import { http } from '@kit.NetworkKit';
import { router } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { AppConstants } from '../../common/constants/AppConstants';

const API_KEY: string = 'sk-742154cb0bd24094bf2c5c81d737c21b';
const API_URL: string = 'https://api.deepseek.com/v1/chat/completions';
const MODEL: string = 'deepseek-chat';
const MAX_HISTORY_ROUNDS: number = 10;
const SYSTEM_PROMPT: string =
  '你是"成电校园助手"App的内置AI助手，专为UESTC(电子科技大学)学生解答本App使用问题。\n' +
  '本App主要功能：课表查看与导入、考试查询与倒计时、成绩查询与GPA计算、日程管理与提醒、云同步、快捷校园工具。\n' +
  '规则：1.只回答与本App相关的问题；2.用中文简洁回答；3.非本App问题礼貌拒绝；4.不透露模型信息。';

const APP_KNOWLEDGE: string =
  '【课表功能】\n' +
  '- 周视图课表：7列×12行网格，支持手势缩放(0.75x~1.4x)，左右/上下滚动\n' +
  '- 首页展示今日/明日课程卡片，含课程名、节次时间、教室、教师\n' +
  '- 支持学期切换，自动计算当前教学周\n' +
  '- 课表导入：内嵌WebView自动登录教务系统(eams.uestc.edu.cn)抓取课表，非校园网自动切换WebVPN\n' +
  '- 课程管理：手动新增/编辑/删除课程，支持"1-16,18"格式周次\n' +
  '- 12种颜色自动分配给不同课程\n\n' +
  '【考试功能】\n' +
  '- 考试列表：按类型(期末/期中/缓补)和学期筛选\n' +
  '- 考试卡片：课程名、日期时间、地点、状态、倒计时，紧急度边框(3天红/7天橙/7天+蓝)\n' +
  '- 考试导入：WebView自动导航教务系统考试页面抓取，支持VPN切换，最多5次重试\n' +
  '- 首页倒计时：显示最近考试倒计时(天/时/分)，每秒刷新\n\n' +
  '【成绩功能】\n' +
  '- GPA展示：按学期/全部计算，颜色分级(≥3.5绿/≥2.5橙/<2.5红)\n' +
  '- 已修学分和课程门数统计，学期筛选\n' +
  '- 成绩导入：WebView自动导航教务系统成绩页面抓取，智能数据轮询等待加载，合并去重\n' +
  '- 绩点标签：≥3.7优秀/≥2.7良好/>0及格\n\n' +
  '【日程/日历功能】\n' +
  '- 月历视图：7列月历网格，日期下方彩色圆点(蓝=课程/红=考试/橙=自定义/紫=作业)\n' +
  '- 日程CRUD：类型(考试/课程/自定义/作业)、标题、描述、日期、时间、提醒设置\n' +
  '- 冲突检测：自动检测同日时间重叠，冲突事件显示红色标签\n' +
  '- 提醒系统：总开关+四类独立开关+独立提醒时间，支持后台代理提醒和系统日历双机制\n' +
  '- 自动同步：开启时自动将课程和考试同步为日程事件\n\n' +
  '【云同步】\n' +
  '- 上传：课表和考试按学期增量同步到云端(AGConnect CloudDB)\n' +
  '- 下载：从云端恢复数据到本地，当前学期数据同时写入主存储\n' +
  '- 限流重试：检测限流错误码，指数退避重试\n\n' +
  '【快捷工具】(发现页)\n' +
  '- AI助手、校园地图(gis.uestc.edu.cn)、图书馆(lib.uestc.edu.cn)\n' +
  '- 成绩查询、校园日历、清水河畔(bbs.uestc.edu.cn)、一卡通余额\n' +
  '- 校园卡/计算器/天气/空教室：开发中\n\n' +
  '【其他】\n' +
  '- 登录：华为AGConnect邮箱验证码登录\n' +
  '- 深色模式：完整深色/浅色双主题，支持跟随系统\n' +
  '- 设置：首页显示选项(今日/明日课程/考试倒计时)、自动创建日程开关\n' +
  '- 数据存储：本地Preferences + 云端CloudDB';

const DETAIL_KEYWORDS: string[] = [
  '怎么', '如何', '功能', '课表', '课程', '考试', '成绩', 'GPA', 'gpa',
  '日程', '日历', '导入', '提醒', '同步', '设置', '登录', '深色', '主题',
  '工具', '地图', '图书馆', 'VPN', 'vpn', '教务', '倒计时', '冲突',
  '云', '账号', '邮箱', '颜色', '周', '节', '学分', '绩点',
  '能做', '有什么', '介绍', '帮助', '使用', '操作', '在哪', '哪里'
];

interface Message {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

interface DisplayMessage {
  role: string;
  content: string;
  isError: boolean;
}

interface ChatSession {
  id: string;
  title: string;
  messages: Message[];
  displayMessages: DisplayMessage[];
  createdAt: number;
  updatedAt: number;
}

@Entry
@Component
struct AssistantPage {
  @State sessions: ChatSession[] = [];
  @State currentSessionId: string = '';
  @State messages: Message[] = [];
  @State displayMessages: DisplayMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State streamingDot: boolean = false;
  @State showSidePanel: boolean = false;
  @State showDeleteDialog: boolean = false;
  @State pendingDeleteSessionId: string = '';
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  private scroller: Scroller = new Scroller();
  private dotTimer: number = -1;

  aboutToAppear(): void {
    this.dotTimer = setInterval(() => {
      this.streamingDot = !this.streamingDot;
    }, 500);
    this.loadSessions();
  }

  aboutToDisappear(): void {
    this.syncCurrentSession();
    this.saveSessions();
    if (this.dotTimer !== -1) {
      clearInterval(this.dotTimer);
      this.dotTimer = -1;
    }
  }

  private loadSessions(): void {
    console.info('[AI Debug] loadSessions start');
    try {
      const context = getContext(this);
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const jsonStr: string = pref.getSync(AppConstants.AI_CHAT_SESSIONS_KEY, '[]') as string;
      console.info('[AI Debug] loaded sessions json length:', jsonStr.length);
      if (jsonStr && jsonStr !== '[]') {
        this.sessions = JSON.parse(jsonStr) as ChatSession[];
      }
    } catch (error) {
      console.error('[AI Debug] loadSessions error:', JSON.stringify(error));
      this.sessions = [];
    }
    console.info('[AI Debug] sessions count:', this.sessions.length);
    if (this.sessions.length > 0) {
      this.currentSessionId = this.sessions[0].id;
      this.messages = this.sessions[0].messages;
      this.displayMessages = this.sessions[0].displayMessages;
      console.info('[AI Debug] restored session:', this.sessions[0].id, 'title:', this.sessions[0].title);
    } else {
      this.createNewChat();
    }
  }

  private saveSessions(): void {
    try {
      const context = getContext(this);
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.AI_CHAT_SESSIONS_KEY, JSON.stringify(this.sessions));
      pref.flushSync();
    } catch (error) {
      console.error('saveSessions error:', JSON.stringify(error));
    }
  }

  private syncCurrentSession(): void {
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === this.currentSessionId) {
        this.sessions[i] = {
          id: this.sessions[i].id,
          title: this.sessions[i].title,
          messages: [...this.messages],
          displayMessages: [...this.displayMessages],
          createdAt: this.sessions[i].createdAt,
          updatedAt: this.sessions[i].updatedAt
        };
        break;
      }
    }
  }

  private createNewChat(): void {
    this.syncCurrentSession();
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].messages.length === 0) {
        this.currentSessionId = this.sessions[i].id;
        this.messages = [];
        this.displayMessages = [];
        this.saveSessions();
        return;
      }
    }
    const newSession: ChatSession = {
      id: `${Date.now()}`,
      title: '新对话',
      messages: [],
      displayMessages: [],
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
    this.sessions = [newSession, ...this.sessions];
    this.currentSessionId = newSession.id;
    this.messages = [];
    this.displayMessages = [];
    this.trimSessions();
    this.saveSessions();
  }

  private switchToSession(sessionId: string): void {
    if (sessionId === this.currentSessionId) {
      this.showSidePanel = false;
      return;
    }
    this.syncCurrentSession();
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === sessionId) {
        this.currentSessionId = sessionId;
        this.messages = [...this.sessions[i].messages];
        this.displayMessages = [...this.sessions[i].displayMessages];
        break;
      }
    }
    this.showSidePanel = false;
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  private deleteSession(sessionId: string): void {
    const remaining: ChatSession[] = this.sessions.filter((s: ChatSession) => s.id !== sessionId);
    this.sessions = remaining;
    if (sessionId === this.currentSessionId) {
      if (remaining.length > 0) {
        this.currentSessionId = remaining[0].id;
        this.messages = [...remaining[0].messages];
        this.displayMessages = [...remaining[0].displayMessages];
      } else {
        this.createNewChat();
        return;
      }
    }
    this.saveSessions();
  }

  private trimSessions(): void {
    if (this.sessions.length > AppConstants.AI_CHAT_MAX_SESSIONS) {
      this.sessions = this.sessions.slice(0, AppConstants.AI_CHAT_MAX_SESSIONS);
    }
  }

  private generateTitle(userInput: string): string {
    const trimmed: string = userInput.replace(/\n/g, ' ').trim();
    return trimmed.length > 20 ? trimmed.substring(0, 20) + '...' : trimmed;
  }

  private formatRelativeTime(timestamp: number): string {
    const now: number = Date.now();
    const diff: number = now - timestamp;
    const minutes: number = Math.floor(diff / 60000);
    if (minutes < 1) {
      return '刚刚';
    }
    if (minutes < 60) {
      return `${minutes}分钟前`;
    }
    const hours: number = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours}小时前`;
    }
    const days: number = Math.floor(hours / 24);
    if (days === 1) {
      return '昨天';
    }
    if (days < 30) {
      return `${days}天前`;
    }
    const date: Date = new Date(timestamp);
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  private trimHistory(): void {
    const maxPairs: number = MAX_HISTORY_ROUNDS * 2;
    if (this.messages.length > maxPairs) {
      this.messages = this.messages.slice(this.messages.length - maxPairs);
    }
  }

  private needsDetailedContext(userInput: string): boolean {
    const input: string = userInput.toLowerCase();
    for (let i = 0; i < DETAIL_KEYWORDS.length; i++) {
      if (input.indexOf(DETAIL_KEYWORDS[i].toLowerCase()) !== -1) {
        return true;
      }
    }
    return false;
  }

  private handleError(err: Error): string {
    const msg: string = err.message || '';
    if (msg.indexOf('timeout') !== -1 || msg.indexOf('超时') !== -1) {
      return '网络超时，请检查连接后重试';
    }
    if (msg.indexOf('401') !== -1) {
      return 'API Key 无效，请检查配置';
    }
    if (msg.indexOf('429') !== -1) {
      return '请求太频繁，请稍后再试';
    }
    if (msg.indexOf('500') !== -1 || msg.indexOf('502') !== -1) {
      return '服务暂时不可用，请稍后再试';
    }
    return '出现未知错误，请重试';
  }

  private async callDeepSeekAPI(userInput: string): Promise<string> {
    let systemContent: string = SYSTEM_PROMPT;
    if (this.needsDetailedContext(userInput)) {
      systemContent = SYSTEM_PROMPT + '\n\n以下是本App详细功能文档，请据此回答：\n' + APP_KNOWLEDGE;
    }
    const systemMsg: Message = { role: 'system', content: systemContent };
    const messagesWithSystem: Message[] = [systemMsg, ...this.messages];

    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(API_URL, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${API_KEY}`,
          'Accept': 'application/json'
        },
        extraData: JSON.stringify({
          model: MODEL,
          messages: messagesWithSystem,
          max_tokens: 2048,
          temperature: 0.7,
          stream: false
        }),
        connectTimeout: 10000,
        readTimeout: 60000
      });

      httpRequest.destroy();

      if (response.responseCode === 200) {
        const result: string = typeof response.result === 'string'
          ? response.result
          : JSON.stringify(response.result);
        const data: Record<string, Object> = JSON.parse(result) as Record<string, Object>;
        const choices: Object[] = data['choices'] as Object[];
        if (choices && choices.length > 0) {
          const firstChoice: Record<string, Object> = choices[0] as Record<string, Object>;
          const message: Record<string, string> = firstChoice['message'] as Record<string, string>;
          return message['content'] || '';
        }
        throw new Error('响应格式异常');
      } else {
        throw new Error(`${response.responseCode}`);
      }
    } catch (err) {
      httpRequest.destroy();
      throw new Error(String(err));
    }
  }

  private async sendMessage(): Promise<void> {
    const userInput: string = this.inputText.trim();
    if (userInput.length === 0 || this.isLoading) {
      return;
    }

    this.displayMessages = [...this.displayMessages, { role: 'user', content: userInput, isError: false }];
    this.messages = [...this.messages, { role: 'user', content: userInput }];
    this.inputText = '';
    this.isLoading = true;

    const isFirstMessage: boolean = this.messages.length === 1;
    if (isFirstMessage) {
      this.updateCurrentSessionTitle(this.generateTitle(userInput));
    }

    this.displayMessages = [...this.displayMessages, { role: 'assistant', content: '', isError: false }];
    this.scrollToBottom();

    try {
      this.trimHistory();
      const reply: string = await this.callDeepSeekAPI(userInput);
      const lastIndex: number = this.displayMessages.length - 1;
      const updated: DisplayMessage[] = [...this.displayMessages];
      updated[lastIndex] = { role: 'assistant', content: reply, isError: false };
      this.displayMessages = updated;
      this.messages = [...this.messages, { role: 'assistant', content: reply }];
    } catch (err) {
      const errorMsg: string = this.handleError(err as Error);
      const lastIndex: number = this.displayMessages.length - 1;
      const updated: DisplayMessage[] = [...this.displayMessages];
      updated[lastIndex] = { role: 'assistant', content: errorMsg, isError: true };
      this.displayMessages = updated;
    } finally {
      this.isLoading = false;
      this.updateCurrentSessionTimestamp();
      this.syncCurrentSession();
      this.saveSessions();
      this.scrollToBottom();
    }
  }

  private updateCurrentSessionTitle(title: string): void {
    const updated: ChatSession[] = [...this.sessions];
    for (let i = 0; i < updated.length; i++) {
      if (updated[i].id === this.currentSessionId) {
        updated[i] = {
          id: updated[i].id,
          title: title,
          messages: updated[i].messages,
          displayMessages: updated[i].displayMessages,
          createdAt: updated[i].createdAt,
          updatedAt: updated[i].updatedAt
        };
        break;
      }
    }
    this.sessions = updated;
  }

  private updateCurrentSessionTimestamp(): void {
    const updated: ChatSession[] = [...this.sessions];
    for (let i = 0; i < updated.length; i++) {
      if (updated[i].id === this.currentSessionId) {
        updated[i] = {
          id: updated[i].id,
          title: updated[i].title,
          messages: updated[i].messages,
          displayMessages: updated[i].displayMessages,
          createdAt: updated[i].createdAt,
          updatedAt: Date.now()
        };
        break;
      }
    }
    this.sessions = updated;
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  @Builder
  private TitleBarBuilder(): void {
    Row() {
      Row() {
        Text('☰')
          .fontSize(20)
          .fontColor(ThemeManager.getTextPrimaryColor())
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(ThemeManager.getCardColor())
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        console.info('[AI Debug] side panel open clicked, sessions count:', this.sessions.length);
        this.syncCurrentSession();
        console.info('[AI Debug] after sync, showSidePanel will be true');
        this.showSidePanel = true;
      })

      Text('AI 助手')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Row() {
        Text('+')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#007AFF')
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(ThemeManager.getCardColor())
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.createNewChat();
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private MessageBubbleBuilder(msg: DisplayMessage, index: number): void {
    Row() {
      if (msg.role === 'user') {
        Blank()
      }

      Column() {
        Text(msg.content)
          .fontSize(15)
          .fontColor(msg.role === 'user' ? '#FFFFFF' : (msg.isError ? '#FF3B30' : ThemeManager.getTextPrimaryColor()))
          .maxLines(Number.MAX_SAFE_INTEGER)
          .copyOption(CopyOptions.LocalDevice)

        if (msg.role === 'assistant' && this.isLoading && index === this.displayMessages.length - 1 && msg.content.length === 0) {
          Text(this.streamingDot ? '▌' : ' ')
            .fontSize(15)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .margin({ top: 2 })
        }
      }
      .constraintSize({ maxWidth: '75%' })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .borderRadius(18)
      .backgroundColor(msg.role === 'user' ? '#007AFF' : (this.isDarkMode ? '#2D2D2D' : '#F2F2F7'))
      .alignItems(HorizontalAlign.Start)

      if (msg.role === 'assistant') {
        Blank()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .justifyContent(msg.role === 'user' ? FlexAlign.End : FlexAlign.Start)
  }

  @Builder
  private InputBarBuilder(): void {
    Row({ space: 10 }) {
      TextArea({ text: $$this.inputText, placeholder: '输入消息...' })
        .layoutWeight(1)
        .maxLines(4)
        .fontSize(15)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .placeholderColor(ThemeManager.getTextTertiaryColor())
        .backgroundColor(ThemeManager.getCardColor())
        .borderRadius(20)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .enabled(!this.isLoading)
        .onChange((value: string) => {
          this.inputText = value;
        })

      Button() {
        if (this.isLoading) {
          Text('●●●')
            .fontSize(14)
            .fontColor('#FFFFFF')
        } else {
          Text('发送')
            .fontSize(14)
            .fontColor('#FFFFFF')
        }
      }
      .width(64)
      .height(40)
      .borderRadius(20)
      .backgroundColor((this.isLoading || this.inputText.trim().length === 0) ? '#B0C4DE' : '#007AFF')
      .enabled(!this.isLoading && this.inputText.trim().length > 0)
      .onClick(() => {
        this.sendMessage();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private SidePanelBuilder(): void {
    Column() {
      Row() {
        Text('对话历史')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .layoutWeight(1)

        Row() {
          Text('✕')
            .fontSize(18)
            .fontColor(ThemeManager.getTextSecondaryColor())
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(ThemeManager.getCardColor())
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          console.info('[AI Debug] close side panel clicked');
          this.showSidePanel = false;
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)

      Button('+ 新建对话')
        .width('90%')
        .height(44)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .backgroundColor('#007AFF')
        .borderRadius(12)
        .margin({ bottom: 12 })
        .onClick(() => {
          console.info('[AI Debug] create new chat from side panel');
          this.createNewChat();
          this.showSidePanel = false;
        })

      if (this.sessions.length === 0) {
        Column() {
          Text('暂无对话记录')
            .fontSize(14)
            .fontColor(ThemeManager.getTextTertiaryColor())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.sessions, (session: ChatSession) => {
            ListItem() {
              Row() {
                Column() {
                  Text(session.title)
                    .fontSize(15)
                    .fontColor(session.id === this.currentSessionId ? '#007AFF' : ThemeManager.getTextPrimaryColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')

                  Text(this.formatRelativeTime(session.updatedAt))
                    .fontSize(12)
                    .fontColor(ThemeManager.getTextTertiaryColor())
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Row() {
                  Image($r('app.media.ic_public_delete'))
                    .width(18)
                    .height(18)
                    .fillColor(ThemeManager.getTextTertiaryColor())
                }
                .width(32)
                .height(32)
                .borderRadius(16)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  console.info('[AI Debug] delete session clicked:', session.id);
                  this.pendingDeleteSessionId = session.id;
                  this.showDeleteDialog = true;
                })
              }
              .width('100%')
              .padding({ left: 16, right: 12, top: 10, bottom: 10 })
              .borderRadius(12)
              .backgroundColor(session.id === this.currentSessionId
                ? (this.isDarkMode ? '#1A3A6B' : '#EBF5FF')
                : ThemeManager.getCardColor())
              .onClick(() => {
                console.info('[AI Debug] switch to session:', session.id);
                this.switchToSession(session.id);
              })
            }
          }, (session: ChatSession) => session.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundColor())
  }

  @Builder
  private DeleteDialogBuilder(): void {
    Column() {
      Column() {
        Text('删除对话')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .margin({ bottom: 12 })

        Text('确定要删除这个对话吗？此操作不可撤销。')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .margin({ bottom: 24 })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .backgroundColor(ThemeManager.getCardColor())
            .borderRadius(12)
            .onClick(() => {
              this.showDeleteDialog = false;
              this.pendingDeleteSessionId = '';
            })

          Button('删除')
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor('#FF3B30')
            .borderRadius(12)
            .onClick(() => {
              this.deleteSession(this.pendingDeleteSessionId);
              this.showDeleteDialog = false;
              this.pendingDeleteSessionId = '';
            })
        }
        .width('100%')
      }
      .width('80%')
      .padding(24)
      .borderRadius(20)
      .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0, 0, 0, 0.4)')
    .onClick(() => {
      this.showDeleteDialog = false;
      this.pendingDeleteSessionId = '';
    })
  }

  build() {
    Column() {
      this.TitleBarBuilder()

      List({ space: 0, scroller: this.scroller }) {
        ForEach(this.displayMessages, (msg: DisplayMessage, index: number) => {
          ListItem() {
            this.MessageBubbleBuilder(msg, index as number)
          }
        }, (msg: DisplayMessage, index: number) => `${index}_${msg.role}_${msg.content.length}`)

        if (this.displayMessages.length === 0) {
          ListItem() {
            Column() {
              Image($r('app.media.ic_ai_assistant'))
                .width(64)
                .height(64)
                .margin({ bottom: 16 })

              Text('你好，我是成电校园助手')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeManager.getTextPrimaryColor())
                .margin({ bottom: 8 })

              Text('可以回答关于本App的任何使用问题')
                .fontSize(14)
                .fontColor(ThemeManager.getTextSecondaryColor())
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 120 })
          }
        }
      }
      .layoutWeight(1)
      .width('100%')

      this.InputBarBuilder()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundColor())
    .bindSheet(this.showSidePanel, this.SidePanelBuilder(), {
      height: SheetSize.FIT_CONTENT,
      showClose: false,
      dragBar: false,
      onDisappear: () => {
        console.info('[AI Debug] side sheet onDisappear');
        this.showSidePanel = false;
      }
    })
    .bindContentCover(this.showDeleteDialog, this.DeleteDialogBuilder(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        console.info('[AI Debug] delete dialog onDisappear');
        this.showDeleteDialog = false;
        this.pendingDeleteSessionId = '';
      }
    })
  }
}
