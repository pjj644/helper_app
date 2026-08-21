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

  private scroller: Scroller = new Scroller();
  private speechHelper: SpeechRecognizerHelper = new SpeechRecognizerHelper();
  private currentClient: BackendAgentClient | null = null;
  private breathTimer: number = -1;
  private recordTimer: number = -1;

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
    if (this.breathTimer >= 0) {
      clearInterval(this.breathTimer);
      this.breathTimer = -1;
    }
    if (this.recordTimer >= 0) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
    if (this.currentClient) {
      this.currentClient.cancel();
      this.currentClient = null;
    }
    this.speechHelper.release();
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
        }
      } else {
        this.startNewChat(false);
      }
    } catch (e) {
      this.startNewChat(false);
    }
  }

  private startNewChat(showToast: boolean = true): void {
    if (this.currentClient) {
      this.currentClient.cancel();
      this.currentClient = null;
    }
    this.isLoading = false;
    const newSession = ChatSessionRepository.createNewSession();
    this.currentSessionId = newSession.id;
    this.sessionMessages = [];
    this.messages = [
      {
        role: 'assistant',
        content: '你好！我是你的 AI 伴随助手。已开启新对话，我可以感知当前页面内容，指导操作或代你执行指令。'
      }
    ];
    try {
      const context = getContext(this);
      ChatSessionRepository.saveOrUpdateSession(context, newSession);
    } catch (e) {
      // ignore
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

    // 记录到会话消息
    this.sessionMessages.push({ role: 'user', content: raw });

    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);

    // 注入当前页面上下文
    const tracker = PageContextTracker.getInstance();
    const contextPrompt = tracker.getFormattedPromptContext();
    const promptWithContext = `[系统当前页面信息]:\n${contextPrompt}\n\n[用户指令]:\n${raw}`;

    const history: AgentMessage[] = [];
    for (let i = 0; i < this.sessionMessages.length - 1; i++) {
      history.push({ role: this.sessionMessages[i].role, content: this.sessionMessages[i].content });
    }
    history.push({ role: 'user', content: promptWithContext });

    const context = getContext(this) as common.UIAbilityContext;
    const executor = new ToolExecutor(context);

    // 发送前先保存用户消息
    this.persistCurrentSession(context);

    const callbacks: AgentCallbacks = {
      onToolCallStart: (toolName: string, args: string) => {
        console.info(`[MiniAssistant] tool call start: ${toolName}`);
      },
      onToolCallResult: (toolName: string, result: string, success: boolean) => {
        console.info(`[MiniAssistant] tool call result: ${toolName}, success: ${success}`);
      },
      onConfirmationNeeded: async (toolName: string, args: string): Promise<boolean> => {
        // Mini 浮窗直接确认或简单提示
        return true;
      },
      onTextChunk: (chunk: string) => {
        if (this.messages[assistantMsgIndex]) {
          this.messages[assistantMsgIndex].content += chunk;
          this.scroller.scrollEdge(Edge.Bottom);
        }
      },
      onError: (error: string) => {
        this.isLoading = false;
        if (this.messages[assistantMsgIndex]) {
          if (this.messages[assistantMsgIndex].content.length === 0) {
            this.messages[assistantMsgIndex].content = `⚠️ 请求失败: ${error}`;
          }
          this.messages[assistantMsgIndex].isError = true;
        }
        this.persistCurrentSession(context);
      },
      onComplete: () => {
        this.isLoading = false;
        this.currentClient = null;
        if (this.messages[assistantMsgIndex]) {
          this.sessionMessages.push({ role: 'assistant', content: this.messages[assistantMsgIndex].content });
        }
        this.persistCurrentSession(context);
      }
    };

    const client = new BackendAgentClient(context, executor, callbacks);
    this.currentClient = client;
    await client.run(this.currentSessionId, history);
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
      // 外层动态呼吸发光环
      Circle()
        .width(60)
        .height(60)
        .fill('#4F46E5')
        .opacity(this.breathOpacity * 0.4)
        .scale({ x: this.breathScale, y: this.breathScale });

      // 核心球体
      Circle()
        .width(52)
        .height(52)
        .fill('#4F46E5')
        .shadow({
          radius: 12,
          color: 'rgba(79, 70, 229, 0.45)',
          offsetX: 0,
          offsetY: 4
        });

      // 机器人图标
      Column() {
        Image($r('app.media.ic_ai_assistant'))
          .width(28)
          .height(28)
          .fillColor(Color.White);
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);
    }
    .width(60)
    .height(60)
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        PanGesture({ fingers: 1, direction: PanDirection.All })
          .onActionStart((event: GestureEvent) => {
            this.isDragging = true;
            this.dragStartX = event.offsetX;
            this.dragStartY = event.offsetY;
          })
          .onActionUpdate((event: GestureEvent) => {
            FloatingWindowManager.getInstance().updateBallPosition(event.offsetX, event.offsetY, false);
          })
          .onActionEnd((event: GestureEvent) => {
            this.isDragging = false;
            FloatingWindowManager.getInstance().updateBallPosition(event.offsetX, event.offsetY, true);
          }),
        TapGesture({ count: 1 })
          .onAction(() => {
            if (!this.isDragging) {
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
          ForEach(this.messages, (msg: MiniDisplayMessage) => {
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
                      if (this.isLoading && (!msg.content || msg.content.length === 0)) {
                        Text('正在思考中...')
                          .fontSize(13)
                          .fontColor(ThemeManager.getTextSecondaryColor());
                      } else {
                        MarkdownBubble({
                          content: msg.content,
                          isUser: false,
                          isError: msg.isError
                        })
                        .width('100%');
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
          });
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
        .padding({ left: 14, right: 14, bottom: 14, top: 4 });
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
    .height('100%');
  }
}
