import { promptAction, curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { FloatingWindowManager } from '../../common/agent/FloatingWindowManager';
import { PageContextTracker, PageSnapshot, PageActionDescriptor } from '../../common/agent/PageContextTracker';
import { UIActionDispatcher, GuidanceState } from '../../common/agent/UIActionDispatcher';
import { BackendAgentClient, AgentCallbacks, AgentMessage } from '../../common/agent/BackendAgentClient';
import { ToolExecutor } from '../../common/agent/ToolExecutor';
import { ToolRegistry } from '../../common/agent/ToolRegistry';
import { SpeechRecognizerHelper } from '../../common/speech/SpeechRecognizerHelper';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { ChatSessionRepository, ChatSession, ChatMessage, ChatDisplayMessage } from '../../repository/ChatSessionRepository';
import { MarkdownBubble } from '../../common/agent/MarkdownBubble';

interface MiniDisplayMessage {
  role: 'user' | 'assistant' | 'tool';
  content: string;
  isError?: boolean;
  // 仅内存显示层用于稳定 ForEach key（流式更新不再触发气泡重建），不写入 ChatDisplayMessage
  uid?: number;
}

/** 引导层遮罩底色（挖孔四周半透明黑） */
const GUIDANCE_MASK_COLOR: string = 'rgba(0, 0, 0, 0.55)';

@Entry
@Component
export struct FloatingSubWindowContent {
  @StorageLink(AppConstants.FLOATING_WINDOW_MODE_KEY) windowMode: string = 'BALL';
  @StorageLink('floating_ball_expand_state') expandState: string = 'HALF_HIDDEN';
  @StorageLink('floating_ball_dock_side') dockSide: string = 'RIGHT';
  @StorageLink('floating_ball_reset_timer') @Watch('onResetTimerTriggered') resetTimerTrigger: number = 0;
  @StorageProp(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;

  // 引导聚光灯：目标矩形（vp，主窗口 Index 测量后经 AppStorage 写入）与提示文案
  @StorageLink(AppConstants.GUIDANCE_RECT_X_KEY) guidanceRectX: number = 0;
  @StorageLink(AppConstants.GUIDANCE_RECT_Y_KEY) guidanceRectY: number = 0;
  @StorageLink(AppConstants.GUIDANCE_RECT_W_KEY) guidanceRectW: number = 0;
  @StorageLink(AppConstants.GUIDANCE_RECT_H_KEY) guidanceRectH: number = 0;
  @State guidanceHint: string = '';

  @State breathScale: number = 1.0;
  @State breathOpacity: number = 0.6;
  @State isDragging: boolean = false;

  @State pageSnapshot: PageSnapshot = PageContextTracker.getInstance().getSnapshot();
  @State currentSessionId: string = '';
  @State sessionMessages: ChatMessage[] = [];
  @State messages: MiniDisplayMessage[] = [
    {
      role: 'assistant',
      content: '你好！我是你的 AI 伴随助手。我可以感知当前页面内容，指导操作或代你执行指令。'
    }
  ];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  // 流式尾气泡的内容镜像（tracked 状态）：稳定 uid key 下，ForEach 不会对复用项重新同步 @Prop，
  // chunk 到达时同步本镜像驱动 MarkdownBubble 经 @Prop 增量更新，避免整气泡重建闪烁
  @State streamingContent: string = '';
  @State isRecording: boolean = false;
  @State recordingDuration: number = 0;
  @State currentThinkingHint: string = '正在思考中...';
  @State thinkingElapsedMs: number = 0;
  // T3 中断态：需要展示「重新发送」入口的消息下标（-1 表示无中断）
  @State interruptedMsgIndex: number = -1;
  // 记录本轮载荷与气泡下标，供中断态「重新发送」复用（同一 session_id 幂等续接）
  private lastPromptWithContext: string = '';
  private lastAssistantMsgIndex: number = -1;
  // 消息 uid 递增计数器（uid 仅用于显示层 key 稳定化，不持久化）
  private nextMsgUid: number = 1;

  private scroller: Scroller = new Scroller();
  private speechHelper: SpeechRecognizerHelper = new SpeechRecognizerHelper();
  private currentClient: BackendAgentClient | null = null;
  private breathTimer: number = -1;
  private recordTimer: number = -1;
  private collapseTimer: number = -1;
  private thinkingTimer: number = -1;
  private thinkingStartTime: number = 0;

  // 拖拽累计偏移
  private dragStartX: number = 0;
  private dragStartY: number = 0;

  // 页面快照监听：快照变化即撤除引导，避免高亮滞留指向已失效的元素
  private pageSnapshotListener: (snapshot: PageSnapshot) => void = (snapshot: PageSnapshot): void => {
    this.pageSnapshot = snapshot;
    UIActionDispatcher.getInstance().clearGuidance();
  };

  // 引导状态监听：驱动子窗口进入/退出 GUIDANCE 模式并同步提示文案
  private guidanceStateListener: (state: GuidanceState | null) => void = (state: GuidanceState | null): void => {
    // 守卫：notifyGuidanceChange 线性遍历期间，若坐标解析监听器同步 clearGuidance（先置空再广播），
    // 外层循环随后下发的陈旧 show 通知在此拦截，防止重入把子窗口卡在全屏不可触摸的引导态
    if (state && UIActionDispatcher.getInstance().getGuidanceState() === null) {
      return;
    }
    if (state) {
      FloatingWindowManager.getInstance().switchToGuidanceMode();
      this.guidanceHint = state.hintText;
    } else {
      FloatingWindowManager.getInstance().exitGuidanceMode();
      this.guidanceHint = '';
    }
  };

  aboutToAppear(): void {
    this.initOrLoadSession();

    // 监听页面上下文变化
    PageContextTracker.getInstance().addListener(this.pageSnapshotListener);

    // 监听 AI 引导聚光灯状态（show_guidance / clearGuidance）
    UIActionDispatcher.getInstance().addGuidanceListener(this.guidanceStateListener);

    // 呼吸动画定时器
    this.breathTimer = setInterval(() => {
      animateTo({ duration: 1200, curve: Curve.EaseInOut }, () => {
        this.breathScale = this.breathScale === 1.0 ? 1.12 : 1.0;
        this.breathOpacity = this.breathOpacity === 0.6 ? 0.9 : 0.6;
      });
    }, 1300);
  }

  aboutToDisappear(): void {
    PageContextTracker.getInstance().removeListener(this.pageSnapshotListener);
    UIActionDispatcher.getInstance().removeGuidanceListener(this.guidanceStateListener);
    this.clearCollapseTimer();
    if (this.breathTimer >= 0) {
      clearInterval(this.breathTimer);
      this.breathTimer = -1;
    }
    if (this.recordTimer >= 0) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
    if (this.thinkingTimer >= 0) {
      clearInterval(this.thinkingTimer);
      this.thinkingTimer = -1;
    }
    if (this.currentClient) {
      this.currentClient.cancel();
      this.currentClient = null;
    }
    this.speechHelper.release();
  }

  private onResetTimerTriggered(): void {
    if (this.windowMode === 'BALL' && this.expandState === 'EXPANDED') {
      this.startCollapseTimer();
    }
  }

  private startCollapseTimer(): void {
    this.clearCollapseTimer();
    this.collapseTimer = setTimeout(() => {
      if (this.windowMode === 'BALL' && this.expandState === 'EXPANDED') {
        FloatingWindowManager.getInstance().dockBall();
      }
    }, 3000);
  }

  private clearCollapseTimer(): void {
    if (this.collapseTimer >= 0) {
      clearTimeout(this.collapseTimer);
      this.collapseTimer = -1;
    }
  }

  // === 会话管理逻辑 ===
  private initOrLoadSession(): void {
    try {
      const context = getContext(this);
      const sessions = ChatSessionRepository.getSessions(context);
      if (sessions.length > 0) {
        const latest = sessions[0];
        this.currentSessionId = latest.id;
        this.sessionMessages = [...latest.messages];
        if (latest.displayMessages && latest.displayMessages.length > 0) {
          this.messages = latest.displayMessages.map((d: ChatDisplayMessage): MiniDisplayMessage => ({
            role: (d.role === 'user' ? 'user' : 'assistant') as 'user' | 'assistant' | 'tool',
            content: d.content,
            isError: d.isError,
            uid: this.nextMsgUid++
          }));
        } else {
          this.messages = [
            {
              role: 'assistant',
              content: '你好！我是你的 AI 伴随助手。我可以感知当前页面内容，指导操作或代你执行指令。',
              uid: this.nextMsgUid++
            }
          ];
        }
      } else {
        this.startNewChat(false, false);
      }
    } catch (e) {
      this.startNewChat(false, false);
    }
  }

  private startNewChat(showToast: boolean = true, autoSave: boolean = false): void {
    if (this.currentClient) {
      this.currentClient.cancel();
      this.currentClient = null;
    }
    // 新对话放弃当前轮次：清理中断态与重发上下文
    this.isLoading = false;
    this.interruptedMsgIndex = -1;
    this.lastPromptWithContext = '';
    this.lastAssistantMsgIndex = -1;
    this.streamingContent = '';
    const newSession = ChatSessionRepository.createNewSession();
    this.currentSessionId = newSession.id;
    this.sessionMessages = [];
    this.messages = [
      {
        role: 'assistant',
        content: '你好！我是你的 AI 伴随助手。已开启新对话，我可以感知当前页面内容，指导操作或代你执行指令。',
        uid: this.nextMsgUid++
      }
    ];
    if (autoSave) {
      try {
        const context = getContext(this);
        ChatSessionRepository.saveOrUpdateSession(context, newSession);
      } catch (e) {
        // ignore
      }
    }
    if (showToast) {
      promptAction.showToast({ message: '已开启新对话', duration: 1500 });
    }
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  /**
   * 工具执行确认弹窗（与 AssistantPage.requestConfirmation 同一口径）：
   * 展示工具中文名与参数摘要，高危操作附加警示；拒绝/允许分别 resolve false/true。
   */
  private requestConfirmation(toolName: string, args: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      const displayName: string = ToolRegistry.getDisplayName(toolName);
      const riskLevel: string = ToolRegistry.getRiskLevel(toolName, args);
      let message: string = `AI助手请求执行：${displayName}`;
      if (riskLevel === 'high') {
        message += '\n\n⚠️ 此操作涉及数据变更，请谨慎确认';
      }
      if (args.length > 0) {
        const argsPreview: string = args.length > 300 ? args.substring(0, 300) + '...' : args;
        message += `\n\n参数：${argsPreview}`;
      }
      AlertDialog.show({
        title: '操作确认',
        message: message,
        autoCancel: false,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: '拒绝',
          fontColor: this.isDarkMode ? '#CCCCCC' : '#666666',
          action: () => {
            resolve(false);
          }
        },
        secondaryButton: {
          value: '允许',
          fontColor: riskLevel === 'high' ? '#FF9500' : '#007AFF',
          action: () => {
            resolve(true);
          }
        }
      });
    });
  }

  private persistCurrentSession(context: Context): void {
    const displayList: ChatDisplayMessage[] = this.messages.map((m: MiniDisplayMessage): ChatDisplayMessage => ({
      role: m.role,
      content: m.content,
      isError: !!m.isError
    }));

    let title = '新对话';
    for (let i = 0; i < this.sessionMessages.length; i++) {
      if (this.sessionMessages[i].role === 'user') {
        title = this.sessionMessages[i].content.slice(0, 16);
        break;
      }
    }

    const session: ChatSession = {
      id: this.currentSessionId || `${Date.now()}`,
      title: title,
      messages: [...this.sessionMessages],
      displayMessages: displayList,
      createdAt: Number(this.currentSessionId) || Date.now(),
      updatedAt: Date.now()
    };

    ChatSessionRepository.saveOrUpdateSession(context, session);
  }

  // === 消息发送逻辑 ===
  private async sendMessage(textToSend?: string): Promise<void> {
    const raw = textToSend !== undefined ? textToSend : this.inputText.trim();
    if (raw.length === 0 || this.isLoading) {
      return;
    }

    if (!this.currentSessionId) {
      const newS = ChatSessionRepository.createNewSession();
      this.currentSessionId = newS.id;
    }

    this.inputText = '';
    const userMsg: MiniDisplayMessage = { role: 'user', content: raw, uid: this.nextMsgUid++ };
    this.messages.push(userMsg);

    const assistantMsgIndex = this.messages.length;
    this.messages.push({ role: 'assistant', content: '', uid: this.nextMsgUid++ });
    // 新一轮流式开始：清空内容镜像，先展示思考提示，首个 chunk 到达后再切换为 MarkdownBubble
    this.streamingContent = '';
    this.isLoading = true;
    this.thinkingStartTime = Date.now();
    this.thinkingElapsedMs = 0;
    this.currentThinkingHint = '✨ 正在理解您的问题...';
    if (this.thinkingTimer >= 0) {
      clearInterval(this.thinkingTimer);
    }
    this.thinkingTimer = setInterval(() => {
      this.thinkingElapsedMs = Date.now() - this.thinkingStartTime;
    }, 100);

    // 记录到会话消息
    this.sessionMessages.push({ role: 'user', content: raw });

    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);

    // 注入当前页面上下文
    const tracker = PageContextTracker.getInstance();
    const contextPrompt = tracker.getFormattedPromptContext();
    const promptWithContext = `[系统当前页面信息]:\n${contextPrompt}\n\n[用户指令]:\n${raw}`;

    // 记录本轮载荷与气泡下标，供中断态「重新发送」复用（同一 session_id 幂等续接）
    this.lastPromptWithContext = promptWithContext;
    this.lastAssistantMsgIndex = assistantMsgIndex;

    // 发送前先保存用户消息
    this.persistCurrentSession(getContext(this) as common.UIAbilityContext);

    this.dispatchAgentTurn(promptWithContext, assistantMsgIndex);
  }

  /**
   * 组装回调并发起一次后端请求（新消息与中断重发共用）。
   * 重发时不追加任何用户消息，沿用当前 sessionMessages 与同一 promptWithContext，
   * 由后端 checkpoint 幂等续接，续传内容写回原 assistant 气泡。
   */
  private dispatchAgentTurn(promptWithContext: string, assistantMsgIndex: number): void {
    const context = getContext(this) as common.UIAbilityContext;
    const executor = new ToolExecutor(context);

    const history: AgentMessage[] = [];
    for (let i = 0; i < this.sessionMessages.length - 1; i++) {
      history.push({ role: this.sessionMessages[i].role, content: this.sessionMessages[i].content });
    }
    history.push({ role: 'user', content: promptWithContext });

    const callbacks: AgentCallbacks = {
      onStatusChange: (status: string, message: string) => {
        this.currentThinkingHint = message;
      },
      onThoughtChunk: (chunk: string) => {
        this.currentThinkingHint = '正在深度思考...';
      },
      onToolCallStart: (toolName: string, args: string) => {
        this.currentThinkingHint = `正在调用 ${toolName}...`;
        console.info(`[MiniAssistant] tool call start: ${toolName}`);
      },
      onToolCallResult: (toolName: string, result: string, success: boolean) => {
        this.currentThinkingHint = '正在整理回答...';
        console.info(`[MiniAssistant] tool call result: ${toolName}, success: ${success}`);
      },
      onConfirmationNeeded: (toolName: string, args: string): Promise<boolean> => {
        // 悬浮球与主页面共用同一确认闸门：高危操作必须弹窗确认，不得静默放行
        return this.requestConfirmation(toolName, args);
      },
      onTextChunk: (chunk: string) => {
        if (this.thinkingTimer >= 0) {
          clearInterval(this.thinkingTimer);
          this.thinkingTimer = -1;
        }
        if (this.messages[assistantMsgIndex]) {
          this.messages[assistantMsgIndex].content += chunk;
          // 同步 tracked 镜像，驱动流式气泡经 @Prop 增量刷新（不重建 ListItem / MarkdownBubble）
          this.streamingContent = this.messages[assistantMsgIndex].content;
          this.scroller.scrollEdge(Edge.Bottom);
        }
      },
      onError: (error: string) => {
        if (this.thinkingTimer >= 0) {
          clearInterval(this.thinkingTimer);
          this.thinkingTimer = -1;
        }
        this.isLoading = false;
        this.interruptedMsgIndex = -1;
        if (this.messages[assistantMsgIndex]) {
          if (this.messages[assistantMsgIndex].content.length === 0) {
            this.messages[assistantMsgIndex].content = `⚠️ 请求失败: ${error}`;
          }
          this.messages[assistantMsgIndex].isError = true;
        }
        this.persistCurrentSession(context);
      },
      onComplete: () => {
        if (this.thinkingTimer >= 0) {
          clearInterval(this.thinkingTimer);
          this.thinkingTimer = -1;
        }
        this.isLoading = false;
        this.currentClient = null;
        this.interruptedMsgIndex = -1;
        if (this.messages[assistantMsgIndex]) {
          this.sessionMessages.push({ role: 'assistant', content: this.messages[assistantMsgIndex].content });
        }
        this.persistCurrentSession(context);
      },
      onIncomplete: (message: string) => {
        // 缺 final 帧（completed_with_warning）：轻提示，内容照常展示、不进错误态
        promptAction.showToast({ message: message, duration: 2500 });
      },
      onInterrupted: (message: string) => {
        // 已收到部分内容后流中断：保留已收内容并标记中断态，气泡下方出现「重新发送」入口；
        // 不向 sessionMessages 追加半截回复，重发续接完成后再统一落库
        if (this.thinkingTimer >= 0) {
          clearInterval(this.thinkingTimer);
          this.thinkingTimer = -1;
        }
        this.isLoading = false;
        this.interruptedMsgIndex = assistantMsgIndex;
        console.warn(`[MiniAssistant] stream interrupted: ${message}`);
        this.persistCurrentSession(context);
      }
    };

    const client = new BackendAgentClient(context, executor, callbacks);
    this.currentClient = client;
    client.run(this.currentSessionId, history);
  }

  /**
   * 中断态「重新发送」：复用上一轮的页面上下文载荷与原 assistant 气泡，
   * 不重复入列用户消息，由后端 checkpoint 幂等续接。
   */
  private resendMiniLastMessage(): void {
    if (this.isLoading || this.lastAssistantMsgIndex < 0 || this.lastPromptWithContext.length === 0) {
      return;
    }
    console.info(`[MiniAssistant] resend last message, msgIndex: ${this.lastAssistantMsgIndex}`);
    this.interruptedMsgIndex = -1;
    this.isLoading = true;
    this.thinkingStartTime = Date.now();
    this.thinkingElapsedMs = 0;
    this.currentThinkingHint = '正在重新连接...';
    if (this.thinkingTimer >= 0) {
      clearInterval(this.thinkingTimer);
    }
    this.thinkingTimer = setInterval(() => {
      this.thinkingElapsedMs = Date.now() - this.thinkingStartTime;
    }, 100);
    // 重发复用原气泡（uid 不变）：镜像先回填已收的部分内容，续传 chunk 到达后继续增量刷新
    this.streamingContent = this.messages[this.lastAssistantMsgIndex].content;
    this.dispatchAgentTurn(this.lastPromptWithContext, this.lastAssistantMsgIndex);
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  // === 语音识别控制 ===
  private async startVoiceRecording(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    this.isRecording = true;
    this.recordingDuration = 0;
    this.inputText = '';

    this.recordTimer = setInterval(() => {
      this.recordingDuration += 1;
    }, 1000);

    const ok = await this.speechHelper.startListening(
      context,
      (text: string, isLast: boolean) => {
        this.inputText = text;
        if (isLast) {
          this.stopVoiceRecording(true);
        }
      },
      (err: string) => {
        this.stopVoiceRecording(false);
        promptAction.showToast({ message: err, duration: 2000 });
      }
    );

    if (!ok) {
      this.stopVoiceRecording(false);
    }
  }

  private stopVoiceRecording(autoSend: boolean): void {
    if (!this.isRecording) {
      return;
    }
    this.isRecording = false;
    if (this.recordTimer >= 0) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
    this.speechHelper.stopListening();

    if (autoSend && this.inputText.trim().length > 0) {
      this.sendMessage();
    }
  }

  // === 悬浮球视图 (Ball Mode) ===
  @Builder
  private FloatingBallView(): void {
    Stack({ alignContent: Alignment.Center }) {
      // 外层动态呼吸发光环（仅在全显 EXPANDED 时呼吸）
      Stack()
        .width(58)
        .height(58)
        .borderRadius(29)
        .backgroundColor('rgba(79, 70, 229, 0.22)')
        .opacity(this.expandState === 'EXPANDED' ? this.breathOpacity * 0.4 : 0)
        .scale({ x: this.breathScale, y: this.breathScale })
        .animation({ duration: 250 });

      // 核心圆形球体背景 (纯圆背景 + 居中白色图标 + 圆形阴影)
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.ic_ai_assistant'))
          .width(26)
          .height(26)
          .fillColor(Color.White);
      }
      .width(52)
      .height(52)
      .borderRadius(26)
      .clip(true)
      .backgroundColor('#4F46E5')
      .shadow({
        radius: 8,
        color: 'rgba(79, 70, 229, 0.4)',
        offsetX: 0,
        offsetY: 3
      });
    }
    .width(60)
    .height(60)
    .backgroundColor(Color.Transparent)
    .opacity(this.expandState === 'EXPANDED' ? 1.0 : 0.7)
    .animation({ duration: 250, curve: Curve.EaseOut })
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        PanGesture({ fingers: 1, direction: PanDirection.All })
          .onActionStart((event: GestureEvent) => {
            this.clearCollapseTimer();
            this.isDragging = true;
            FloatingWindowManager.getInstance().startDrag();
          })
          .onActionUpdate((event: GestureEvent) => {
            FloatingWindowManager.getInstance().updateDrag(event.offsetX, event.offsetY);
          })
          .onActionEnd((event: GestureEvent) => {
            this.isDragging = false;
            FloatingWindowManager.getInstance().endDrag(event.offsetX, event.offsetY);
            this.startCollapseTimer();
          }),
        TapGesture({ count: 1 })
          .onAction(() => {
            if (this.isDragging) {
              return;
            }
            if (this.expandState === 'HALF_HIDDEN') {
              // 第一次点击：从半隐藏展开至全显，并启动 3 秒倒计时
              FloatingWindowManager.getInstance().expandBall();
              this.startCollapseTimer();
            } else {
              // 全显状态下在倒计时内再次点击：打开 Mini 助手对话面板
              this.clearCollapseTimer();
              FloatingWindowManager.getInstance().switchToPanelMode();
            }
          })
      )
    );
  }

  // === Mini 助手覆盖层 (Panel Mode) ===
  @Builder
  private MiniAssistantPanelView(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      // 半透明背景遮罩（点击收起为悬浮球）
      Rect()
        .width('100%')
        .height('100%')
        .fill('rgba(0, 0, 0, 0.4)')
        .onClick(() => {
          FloatingWindowManager.getInstance().switchToBallMode();
        });

      // 浮动 Mini 助手主卡片
      Column({ space: 8 }) {
        // 顶部操作栏
        Row() {
          // 左侧：AI 图标与感知到的当前页面胶囊
          Row({ space: 6 }) {
            Image($r('app.media.ic_ai_assistant'))
              .width(22)
              .height(22)
              .fillColor('#6366F1');

            Text('AI 伴随助手')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isDarkMode ? '#F3F4F6' : '#111827');

            // 页面感知标识
            Row({ space: 3 }) {
              Circle({ width: 5, height: 5 }).fill('#10B981');
              Text(this.pageSnapshot.pageTitle || '首页')
                .fontSize(11)
                .fontColor('#10B981')
                .fontWeight(FontWeight.Medium);
            }
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('rgba(16, 185, 129, 0.12)')
            .borderRadius(8);
          }
          .alignItems(VerticalAlign.Center);

          Blank();

          // 右侧：新建对话 [+]、缩小按钮 [-] 与 关闭悬浮球按钮 [X]
          Row({ space: 8 }) {
            // 开启新对话 [+]
            Button() {
              Text('＋')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isDarkMode ? '#D1D5DB' : '#4B5563');
            }
            .width(30)
            .height(30)
            .type(ButtonType.Circle)
            .backgroundColor(this.isDarkMode ? '#374151' : '#F3F4F6')
            .onClick(() => {
              this.startNewChat(true);
            });

            // 缩小为悬浮球 [-]
            Button() {
              Text('－')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isDarkMode ? '#D1D5DB' : '#4B5563');
            }
            .width(30)
            .height(30)
            .type(ButtonType.Circle)
            .backgroundColor(this.isDarkMode ? '#374151' : '#F3F4F6')
            .onClick(() => {
              FloatingWindowManager.getInstance().switchToBallMode();
            });

            // 收起面板并停靠悬浮球（禁用请到设置）
            Button() {
              Text('✕')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#EF4444');
            }
            .width(30)
            .height(30)
            .type(ButtonType.Circle)
            .backgroundColor('rgba(239, 68, 68, 0.1)')
            .onClick(() => {
              // 先把窗口缩回球，再停靠边缘并滑到半隐藏态，功能本身保持开启
              FloatingWindowManager.getInstance().switchToBallMode();
              FloatingWindowManager.getInstance().dockBall();
            });
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 6 });

        // 页面快捷感知与操作胶囊
        Scroll() {
          Row({ space: 8 }) {
            // 胶囊 1: 解析当前页面
            Row({ space: 4 }) {
              Text('🔍').fontSize(12);
              Text(`解析「${this.pageSnapshot.pageTitle || '本页'}」`)
                .fontSize(12)
                .fontColor('#4F46E5');
            }
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor('rgba(79, 70, 229, 0.1)')
            .borderRadius(12)
            .onClick(() => {
              this.sendMessage(`请分析当前【${this.pageSnapshot.pageTitle}】页面的数据与状态，告诉我重点信息或建议。`);
            });

            // 胶囊 2: 指导当前操作
            Row({ space: 4 }) {
              Text('💡').fontSize(12);
              Text('操作指导')
                .fontSize(12)
                .fontColor('#059669');
            }
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor('rgba(5, 150, 105, 0.1)')
            .borderRadius(12)
            .onClick(() => {
              this.sendMessage(`请指导我如何使用当前【${this.pageSnapshot.pageTitle}】页面的功能。`);
            });

            // 若页面有专属动作，展示动态快捷胶囊
            ForEach(this.pageSnapshot.availableActions, (act: PageActionDescriptor) => {
              Row({ space: 4 }) {
                Text('⚡').fontSize(12);
                Text(act.label)
                  .fontSize(12)
                  .fontColor('#D97706');
              }
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('rgba(217, 119, 6, 0.1)')
              .borderRadius(12)
              .onClick(() => {
                // 快捷动作本地直触发，绕过 LLM 转述（actionId 不进自然语言）
                UIActionDispatcher.getInstance().dispatch(act.actionId, {}).then((ok: boolean) => {
                  promptAction.showToast({ message: ok ? `已执行：${act.label}` : '当前页面暂不支持该操作', duration: 1500 });
                });
              });
            });
          }
          .padding({ left: 16, right: 16, bottom: 4 });
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off);

        Divider()
          .color(this.isDarkMode ? '#374151' : '#E5E7EB')
          .strokeWidth(0.5);

        // 简短对话消息流
        List({ scroller: this.scroller }) {
          ForEach(this.messages, (msg: MiniDisplayMessage, index: number) => {
            ListItem() {
              Row() {
                if (msg.role === 'user') {
                  Blank();
                  Text(msg.content)
                    .fontSize(14)
                    .fontColor(Color.White)
                    .backgroundColor('#6366F1')
                    .padding(10)
                    .borderRadius({ topLeft: 14, topRight: 2, bottomLeft: 14, bottomRight: 14 })
                    .constraintSize({ maxWidth: '80%' });
                } else {
                  Row({ space: 8 }) {
                    Stack({ alignContent: Alignment.Center }) {
                      Circle({ width: 24, height: 24 })
                        .fill('#6366F1');
                      Text('🤖')
                        .fontSize(13);
                    }
                    .width(24)
                    .height(24)
                    .alignSelf(ItemAlign.Start);

                    Column() {
                      if (this.isLoading && index === this.messages.length - 1 && this.streamingContent.length === 0) {
                        Row({ space: 6 }) {
                          Text(`${this.currentThinkingHint} (${(this.thinkingElapsedMs / 1000).toFixed(1)}s)`)
                            .fontSize(12)
                            .fontColor(ThemeManager.getTextSecondaryColor());
                        }
                        .padding({ top: 4, bottom: 4 })
                        .alignItems(VerticalAlign.Center);
                      } else {
                        MarkdownBubble({
                          // 流式尾气泡绑定 tracked 镜像（chunk 经 @Prop 增量同步，组件不重建）；
                          // 历史气泡绑定静态 msg.content
                          content: (this.isLoading && index === this.messages.length - 1) ? this.streamingContent : msg.content,
                          isUser: false,
                          isError: msg.isError,
                          isStreaming: (this.isLoading && index === this.messages.length - 1)
                        })
                        .width('100%');
                      }

                      // T3 中断态：保留已收内容并提供「重新发送」入口（同 session_id 幂等续接）
                      if (index === this.interruptedMsgIndex) {
                        Row({ space: 8 }) {
                          Text('⚠️ 连接中断，回复未完成')
                            .fontSize(11)
                            .fontColor('#EF4444');
                          Text('重新发送')
                            .fontSize(12)
                            .fontWeight(FontWeight.Medium)
                            .fontColor('#4F46E5')
                            .onClick(() => {
                              this.resendMiniLastMessage();
                            });
                        }
                        .padding({ top: 4 })
                        .alignItems(VerticalAlign.Center);
                      }
                    }
                    .layoutWeight(1)
                    .padding(10)
                    .backgroundColor(this.isDarkMode ? '#374151' : '#F3F4F6')
                    .borderRadius({ topLeft: 2, topRight: 14, bottomLeft: 14, bottomRight: 14 })
                    .clip(true);
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top);
                }
              }
              .width('100%')
              .margin({ top: 4, bottom: 4 });
            }
          // 稳定 uid key：流式期间 content 变化不再变更 key，气泡实例跨 chunk 复用不重建（配合 streamingContent 镜像增量同步）
          }, (msg: MiniDisplayMessage, index: number) => (msg.uid !== undefined ? String(msg.uid) : `${index}`));
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        .edgeEffect(EdgeEffect.Spring);

        // 录音状态提示条
        if (this.isRecording) {
          Row({ space: 8 }) {
            Circle({ width: 8, height: 8 }).fill('#EF4444');
            Text(`正在聆听语音... ${this.recordingDuration}s`)
              .fontSize(12)
              .fontColor('#EF4444');
          }
          .padding(4);
        }

        // 底部输入区
        Row({ space: 8 }) {
          // 语音按钮
          Button() {
            Image($r('app.media.ic_ai_assistant'))
              .width(18)
              .height(18)
              .fillColor(this.isRecording ? '#EF4444' : (this.isDarkMode ? '#9CA3AF' : '#6B7280'));
          }
          .width(36)
          .height(36)
          .type(ButtonType.Circle)
          .backgroundColor(this.isRecording ? 'rgba(239, 68, 68, 0.15)' : (this.isDarkMode ? '#374151' : '#F3F4F6'))
          // 语音按钮：点击开始录音，再次点击停止并自动发送（去掉长按分支，避免双路径语义重复导致误触）
          .gesture(
            TapGesture()
              .onAction(() => {
                if (this.isRecording) {
                  this.stopVoiceRecording(true);
                } else {
                  this.startVoiceRecording();
                }
              })
          );

          // 文本输入框
          TextInput({ text: this.inputText, placeholder: '询问当前页面或下达指令...' })
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .backgroundColor(this.isDarkMode ? '#374151' : '#F3F4F6')
            .borderRadius(19)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.inputText = value;
            })
            .onSubmit(() => {
              this.sendMessage();
            });

          // 发送按钮
          Button() {
            if (this.isLoading) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(Color.White);
            } else {
              Text('↑')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White);
            }
          }
          .width(36)
          .height(36)
          .type(ButtonType.Circle)
          .backgroundColor(this.inputText.trim().length > 0 ? '#6366F1' : '#A5B4FC')
          .enabled(this.inputText.trim().length > 0 && !this.isLoading)
          .onClick(() => {
            this.sendMessage();
          });
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 4, top: 4 });

        Text('⚠️ AI生成内容仅供参考，以教务处为准')
          .fontSize(10)
          .fontColor(this.isDarkMode ? '#6B7280' : '#9CA3AF')
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ bottom: 8 });
      }
      .width('94%')
      .height(440)
      .margin({ bottom: 20 })
      .backgroundColor(this.isDarkMode ? '#1F2937' : '#FFFFFF')
      .borderRadius(24)
      .shadow({
        radius: 24,
        color: 'rgba(0, 0, 0, 0.25)',
        offsetX: 0,
        offsetY: 8
      });
    }
    .width('100%')
    .height('100%');
  }

  // === 引导聚光灯几何：孔洞 = 目标矩形外扩 8vp（单位 vp） ===
  private guidanceHoleLeft(): number {
    return this.guidanceRectX - AppConstants.GUIDANCE_HOLE_EXPAND_VP;
  }

  private guidanceHoleTop(): number {
    return this.guidanceRectY - AppConstants.GUIDANCE_HOLE_EXPAND_VP;
  }

  private guidanceHoleWidth(): number {
    // 钳制下限为 0，防止坐标解析异常（rect 为 0/负）时渲染负尺寸遮罩与描边环
    return Math.max(this.guidanceRectW + AppConstants.GUIDANCE_HOLE_EXPAND_VP * 2, 0);
  }

  private guidanceHoleHeight(): number {
    return Math.max(this.guidanceRectH + AppConstants.GUIDANCE_HOLE_EXPAND_VP * 2, 0);
  }

  // === 引导聚光灯覆盖层 (GUIDANCE Mode) ===
  @Builder
  private GuidanceOverlayView(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      // 四块遮罩拼出挖孔（中间留白即高亮目标区域）
      Column() {
        Column()
          .width('100%')
          .height(Math.max(this.guidanceHoleTop(), 0))
          .backgroundColor(GUIDANCE_MASK_COLOR);

        Row() {
          Column()
            .width(Math.max(this.guidanceHoleLeft(), 0))
            .height(this.guidanceHoleHeight())
            .backgroundColor(GUIDANCE_MASK_COLOR);

          Column()
            .width(this.guidanceHoleWidth())
            .height(this.guidanceHoleHeight());

          Column()
            .layoutWeight(1)
            .height(this.guidanceHoleHeight())
            .backgroundColor(GUIDANCE_MASK_COLOR);
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);

        Column()
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(GUIDANCE_MASK_COLOR);
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .hitTestBehavior(HitTestMode.None);

      if (this.guidanceHoleWidth() > 0) {
        // 孔洞边缘呼吸描边环（复用 breathScale 呼吸节拍，幅度收敛到约 3%）
        Rect()
          .width(this.guidanceHoleWidth())
          .height(this.guidanceHoleHeight())
          .position({ x: this.guidanceHoleLeft(), y: this.guidanceHoleTop() })
          .radius(AppConstants.GUIDANCE_HOLE_RADIUS_VP)
          .fillOpacity(0)
          .stroke(Color.White)
          .strokeWidth(AppConstants.GUIDANCE_RING_STROKE_VP)
          .strokeOpacity(0.5 + this.breathOpacity * 0.5)
          .scale({
            x: 1 + (this.breathScale - 1) * 0.25,
            y: 1 + (this.breathScale - 1) * 0.25
          })
          .animation({ duration: 250 });
      }

      if (this.guidanceHint.length > 0 && this.guidanceHoleWidth() > 0) {
        if (this.guidanceHoleTop() >= AppConstants.GUIDANCE_HINT_MIN_TOP_VP) {
          // 上方空间充足：气泡贴在孔洞正上方，小三角指向孔洞
          Column() {
            Text(this.guidanceHint)
              .fontSize(13)
              .fontColor(this.isDarkMode ? '#F3F4F6' : '#111827')
              .backgroundColor(this.isDarkMode ? '#1F2937' : '#FFFFFF')
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 14, right: 14, top: 9, bottom: 9 })
              .borderRadius(12)
              .constraintSize({ maxWidth: '78%' });
            Polygon({ width: 12, height: 6 })
              .points([[0, 0], [12, 0], [6, 6]])
              .fill(this.isDarkMode ? '#1F2937' : '#FFFFFF');
          }
          .width('100%')
          .height(this.guidanceHoleTop())
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.None);
        } else {
          // 上方空间不足：气泡放到孔洞下方
          Column() {
            Polygon({ width: 12, height: 6 })
              .points([[0, 6], [6, 0], [12, 6]])
              .fill(this.isDarkMode ? '#1F2937' : '#FFFFFF');
            Text(this.guidanceHint)
              .fontSize(13)
              .fontColor(this.isDarkMode ? '#F3F4F6' : '#111827')
              .backgroundColor(this.isDarkMode ? '#1F2937' : '#FFFFFF')
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 14, right: 14, top: 9, bottom: 9 })
              .borderRadius(12)
              .constraintSize({ maxWidth: '78%' });
          }
          .width('100%')
          .position({ x: 0, y: this.guidanceHoleTop() + this.guidanceHoleHeight() })
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.None);
        }
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.windowMode === 'BALL') {
        this.FloatingBallView();
      } else if (this.windowMode === 'PANEL') {
        this.MiniAssistantPanelView();
      } else if (this.windowMode === 'GUIDANCE') {
        this.GuidanceOverlayView();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent);
  }
}
