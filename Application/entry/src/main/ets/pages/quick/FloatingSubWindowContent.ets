import { promptAction, curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { FloatingWindowManager } from '../../common/agent/FloatingWindowManager';
import { PageContextTracker, PageSnapshot, PageActionDescriptor } from '../../common/agent/PageContextTracker';
import { UIActionDispatcher } from '../../common/agent/UIActionDispatcher';
import { BackendAgentClient, AgentCallbacks, AgentMessage } from '../../common/agent/BackendAgentClient';
import { ToolExecutor } from '../../common/agent/ToolExecutor';
import { SpeechRecognizerHelper } from '../../common/speech/SpeechRecognizerHelper';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { ChatSessionRepository, ChatSession, ChatMessage, ChatDisplayMessage } from '../../repository/ChatSessionRepository';
import { MarkdownBubble } from '../../common/agent/MarkdownBubble';

interface MiniDisplayMessage {
  role: 'user' | 'assistant' | 'tool';
  content: string;
  isError?: boolean;
}

@Entry
@Component
export struct FloatingSubWindowContent {
  @StorageLink('floating_window_mode') windowMode: string = 'BALL';
  @StorageLink('floating_ball_expand_state') expandState: string = 'HALF_HIDDEN';
  @StorageLink('floating_ball_dock_side') dockSide: string = 'RIGHT';
  @StorageLink('floating_ball_reset_timer') @Watch('onResetTimerTriggered') resetTimerTrigger: number = 0;
  @StorageProp(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;

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
  @State isRecording: boolean = false;
  @State recordingDuration: number = 0;
  @State currentThinkingHint: string = '正在思考中...';
  @State thinkingElapsedMs: number = 0;
  // T3 中断态：需要展示「重新发送」入口的消息下标（-1 表示无中断）
  @State interruptedMsgIndex: number = -1;
  // 记录本轮载荷与气泡下标，供中断态「重新发送」复用（同一 session_id 幂等续接）
  private lastPromptWithContext: string = '';
  private lastAssistantMsgIndex: number = -1;

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

  aboutToAppear(): void {
    this.initOrLoadSession();

    // 监听页面上下文变化
    PageContextTracker.getInstance().addListener((snapshot: PageSnapshot) => {
      this.pageSnapshot = snapshot;
    });

    // 呼吸动画定时器
    this.breathTimer = setInterval(() => {
      animateTo({ duration: 1200, curve: Curve.EaseInOut }, () => {
        this.breathScale = this.breathScale === 1.0 ? 1.12 : 1.0;
        this.breathOpacity = this.breathOpacity === 0.6 ? 0.9 : 0.6;
      });
    }, 1300);
  }

  aboutToDisappear(): void {
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
            isError: d.isError
          }));
        } else {
          this.messages = [
            {
              role: 'assistant',
              content: '你好！我是你的 AI 伴随助手。我可以感知当前页面内容，指导操作或代你执行指令。'
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
    const newSession = ChatSessionRepository.createNewSession();
    this.currentSessionId = newSession.id;
    this.sessionMessages = [];
    this.messages = [
      {
        role: 'assistant',
        content: '你好！我是你的 AI 伴随助手。已开启新对话，我可以感知当前页面内容，指导操作或代你执行指令。'
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
    const userMsg: MiniDisplayMessage = { role: 'user', content: raw };
    this.messages.push(userMsg);

    const assistantMsgIndex = this.messages.length;
    this.messages.push({ role: 'assistant', content: '' });
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
      onConfirmationNeeded: async (toolName: string, args: string): Promise<boolean> => {
        // Mini 浮窗直接确认或简单提示
        return true;
      },
      onTextChunk: (chunk: string) => {
        if (this.thinkingTimer >= 0) {
          clearInterval(this.thinkingTimer);
          this.thinkingTimer = -1;
        }
        if (this.messages[assistantMsgIndex]) {
          this.messages[assistantMsgIndex].content += chunk;
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

            // 取消/关闭悬浮球 [X]
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
              FloatingWindowManager.getInstance().setEnabled(false);
              promptAction.showToast({
                message: 'AI 悬浮球已关闭，可在设置或 AI 助手页重新开启',
                duration: 2000
              });
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
                this.sendMessage(`请帮我执行操作：${act.label} (${act.actionId})`);
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
                      if (this.isLoading && index === this.messages.length - 1 && (!msg.content || msg.content.length === 0)) {
                        Row({ space: 6 }) {
                          Text(`${this.currentThinkingHint} (${(this.thinkingElapsedMs / 1000).toFixed(1)}s)`)
                            .fontSize(12)
                            .fontColor(ThemeManager.getTextSecondaryColor());
                        }
                        .padding({ top: 4, bottom: 4 })
                        .alignItems(VerticalAlign.Center);
                      } else {
                        MarkdownBubble({
                          content: msg.content,
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
          }, (msg: MiniDisplayMessage, index: number) => `${index}_${msg.role}_${msg.content.length}_${index === this.interruptedMsgIndex ? 'i' : 'n'}`);
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
          .gesture(
            GestureGroup(
              GestureMode.Exclusive,
              LongPressGesture({ repeat: false })
                .onAction(() => {
                  this.startVoiceRecording();
                })
                .onActionEnd(() => {
                  this.stopVoiceRecording(true);
                }),
              TapGesture()
                .onAction(() => {
                  if (this.isRecording) {
                    this.stopVoiceRecording(true);
                  } else {
                    this.startVoiceRecording();
                  }
                })
            )
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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.windowMode === 'BALL') {
        this.FloatingBallView();
      } else if (this.windowMode === 'PANEL') {
        this.MiniAssistantPanelView();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent);
  }
}
