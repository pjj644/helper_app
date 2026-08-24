import { preferences } from '@kit.ArkData';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { AppConstants, RouterConstants } from '../../common/constants/AppConstants';
import { ToolRegistry } from '../../common/agent/ToolRegistry';
import { ToolExecutor } from '../../common/agent/ToolExecutor';
import { BackendAgentClient, AgentCallbacks, AgentMessage } from '../../common/agent/BackendAgentClient';
import { AgentEndpointConfig, AgentEndpoint } from '../../common/agent/AgentEndpointConfig';
import { SpeechRecognizerHelper } from '../../common/speech/SpeechRecognizerHelper';
import { VisionScheduleHelper, VisionScheduleResult } from '../../common/agent/VisionScheduleHelper';
import { FloatingWindowManager } from '../../common/agent/FloatingWindowManager';
import { PageContextTracker } from '../../common/agent/PageContextTracker';
import { common } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { ChatSessionRepository, ChatSession, ChatMessage, ChatDisplayMessage, AgentTelemetryInfo } from '../../repository/ChatSessionRepository';
import { MarkdownBubble } from '../../common/agent/MarkdownBubble';

const MAX_HISTORY_ROUNDS: number = 10;

type Message = ChatMessage;
type DisplayMessage = ChatDisplayMessage;

@Entry
@Component
export struct AssistantPage {
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
  @State showToolCalls: boolean = false;
  @State expandedToolIndices: number[] = [];
  @State currentThinkingHint: string = '✨ 正在理解您的问题与上下文...';
  @State thinkingElapsedMs: number = 0;
  @State isThinkingPhase: boolean = false;
  @State activeThought: string = '';
  @State isThoughtExpanded: boolean = true;
  @State expandedThoughtIndices: number[] = [];
  @State pulsePhase: number = 0;
  @StorageLink('floating_ball_enabled') isFloatingBallEnabled: boolean = true;
  @StorageLink(AgentEndpointConfig.STORAGE_KEY_CONFIGURED) @Watch('onConfiguredStateChange') isBackendConfigured: boolean = false;
  @State isRecording: boolean = false;
  @State showBackendGuide: boolean = false;
  @State backendGuideHint: string = '';
  // T3 中断态：需要展示「重新发送」入口的 assistant 气泡下标（-1 表示无中断）
  @State interruptedMsgIndex: number = -1;
  // 澄清提问卡片：输入框草稿（同一时刻至多一张未回答卡片）与最近一次下发的提问参数缓存
  @State clarificationInputText: string = '';
  private lastClarificationArgs: string = '';
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  private scroller: Scroller = new Scroller();
  private dotTimer: number = -1;
  private thinkingStopwatchTimer: number = -1;
  private thinkingStartTime: number = 0;
  private currentClient: BackendAgentClient | null = null;
  // T3 缺 final 帧标记：onIncomplete 时置位，onComplete 时消费并落持久化轻提示
  private pendingIncompleteRound: boolean = false;
  private speechHelper: SpeechRecognizerHelper = new SpeechRecognizerHelper();

  aboutToAppear(): void {
    FloatingWindowManager.getInstance().setAssistantPageActive(true);
    PageContextTracker.getInstance().updateSnapshot(
      'assistant',
      'AI助手',
      '全屏 AI 智能助手界面',
      {},
      []
    );
    this.dotTimer = setInterval(() => {
      this.streamingDot = !this.streamingDot;
      this.pulsePhase = (this.pulsePhase + 1) % 3;
    }, 400);
    this.loadSessions();
    this.loadToolCallDisplaySetting();
    this.refreshBackendGuide();
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 400);
  }

  aboutToDisappear(): void {
    FloatingWindowManager.getInstance().setAssistantPageActive(false);
    // 离开页面时取消在途请求（首包 watchdog 与重试定时器一并清理）
    if (this.currentClient) {
      this.currentClient.cancel();
      this.currentClient = null;
    }
    this.syncCurrentSession();
    this.saveSessions();
    if (this.dotTimer !== -1) {
      clearInterval(this.dotTimer);
      this.dotTimer = -1;
    }
    this.stopThinkingTimer();
    this.speechHelper.release();
  }

  onPageShow(): void {
    FloatingWindowManager.getInstance().setAssistantPageActive(true);
    this.loadSessions();
    this.loadToolCallDisplaySetting();
    this.refreshBackendGuide();
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 300);
  }

  private onConfiguredStateChange(): void {
    this.refreshBackendGuide();
  }

  // 检查助手后端配置是否齐全，缺失时在会话区顶部展示引导卡片（onPageShow 会复检，从设置返回后自动消失）
  public async refreshBackendGuide(): Promise<void> {
    try {
      const endpoint: AgentEndpoint = await AgentEndpointConfig.resolve(getContext(this));
      const ready: boolean = AgentEndpointConfig.isReady(endpoint);
      this.showBackendGuide = !ready;
      this.backendGuideHint = AgentEndpointConfig.missingHint(endpoint);
      AppStorage.setOrCreate(AgentEndpointConfig.STORAGE_KEY_CONFIGURED, ready);
    } catch (e) {
      this.showBackendGuide = true;
      this.backendGuideHint = '无法读取助手后端配置，请前往设置重新填写。';
    }
  }

  private loadToolCallDisplaySetting(): void {
    try {
      const context = getContext(this);
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      this.showToolCalls = pref.getSync(AppConstants.SETTING_AI_SHOW_TOOL_CALLS_KEY, false) as boolean;
    } catch (error) {
      this.showToolCalls = false;
    }
  }

  private loadSessions(): void {
    console.info('[AssistantPage] loadSessions start');
    try {
      const context = getContext(this);
      this.sessions = ChatSessionRepository.getSessions(context);
    } catch (error) {
      console.error('[AssistantPage] loadSessions error:', JSON.stringify(error));
      this.sessions = [];
    }
    console.info('[AssistantPage] sessions count:', this.sessions.length);
    if (this.sessions.length > 0) {
      this.currentSessionId = this.sessions[0].id;
      this.messages = this.sessions[0].messages;
      this.displayMessages = this.sessions[0].displayMessages;
      console.info('[AssistantPage] restored session:', this.sessions[0].id, 'title:', this.sessions[0].title);
    } else {
      this.messages = [];
      this.displayMessages = [];
      this.createNewChat();
    }
  }

  private saveSessions(): void {
    try {
      const context = getContext(this);
      if (!this.sessions || this.sessions.length === 0) {
        ChatSessionRepository.clearAllSessions(context);
        return;
      }
      const hasAnyMessage = this.sessions.some(s => (s.messages && s.messages.length > 0) || (s.displayMessages && s.displayMessages.length > 0));
      if (!hasAnyMessage && this.sessions.length <= 1) {
        ChatSessionRepository.clearAllSessions(context);
        return;
      }
      ChatSessionRepository.saveSessions(context, this.sessions);
    } catch (error) {
      console.error('[AssistantPage] saveSessions error:', JSON.stringify(error));
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
    // 新建对话视为用户放弃当前轮次：取消在途连接（watchdog/重试一并清理）
    if (this.currentClient) {
      this.currentClient.cancel();
      this.currentClient = null;
      this.isLoading = false;
      this.stopThinkingTimer();
      this.pendingIncompleteRound = false;
      this.interruptedMsgIndex = -1;
    }
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

  private getToolDisplayName(toolName: string): string {
    // 显示名映射已收编至 ToolRegistry（悬浮球确认弹窗共用同一来源）
    return ToolRegistry.getDisplayName(toolName);
  }

  private formatToolResult(toolName: string, result: string): string {
    try {
      switch (toolName) {
        case 'app_data_query':
          return this.formatDataQueryResult(result)
        case 'app_data_mutate':
        case 'app_control':
        case 'app_pipeline':
          return this.formatGenericMessageResult(result)
        case 'query_today_courses':
          return this.formatCourseResult(result)
        case 'query_week_courses':
          return this.formatWeekCourseResult(result)
        case 'query_next_exam':
          return this.formatNextExamResult(result)
        case 'query_all_exams':
          return this.formatAllExamsResult(result)
        case 'query_grades':
          return this.formatGradesResult(result)
        case 'query_gpa':
          return this.formatGpaResult(result)
        case 'query_schedule':
          return this.formatScheduleResult(result)
        default:
          return ''
      }
    } catch (e) {
      return ''
    }
  }

  private formatGenericMessageResult(json: string): string {
    try {
      const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
      if (data['message']) {
        return String(data['message'])
      }
    } catch (e) {
      // ignore
    }
    return ''
  }

  private formatDataQueryResult(json: string): string {
    try {
      const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
      const domain: string = (data['domain'] as string) || ''
      const items: Object[] = (data['items'] as Object[]) || []

      if (domain === 'course') {
        if (items.length === 0) return '未查询到相关课程'
        let text: string = ''
        for (let i = 0; i < items.length; i++) {
          const c: Record<string, Object> = items[i] as Record<string, Object>
          if (i > 0) text += '\n'
          text += `[${String(c['name'])}] ${String(c['dayOfWeekLabel'] || '')} ${String(c['timeRange'] || '')}`
          const room: string = String(c['room'] || '')
          if (room.length > 0 && room !== 'undefined') text += ` · ${room}`
          const teacher: string = String(c['teacher'] || '')
          if (teacher.length > 0 && teacher !== 'undefined') text += ` · ${teacher}`
        }
        return text
      } else if (domain === 'exam') {
        if (items.length === 0) return '未查询到考试安排'
        let text: string = ''
        for (let i = 0; i < items.length; i++) {
          const e: Record<string, Object> = items[i] as Record<string, Object>
          if (i > 0) text += '\n'
          text += `[${String(e['courseName'])}] ${String(e['examDate'])} ${String(e['examTimeRange'])}`
          const loc: string = String(e['examLocation'] || '')
          if (loc.length > 0 && loc !== 'undefined') text += ` · ${loc}`
          const cd: string = String(e['countdown'] || '')
          if (cd.length > 0 && cd !== 'undefined') text += ` (${cd})`
        }
        return text
      } else if (domain === 'grade') {
        let text: string = `总GPA: ${String(data['overallGPA'] || '0.00')}\n`
        for (let i = 0; i < items.length; i++) {
          const g: Record<string, Object> = items[i] as Record<string, Object>
          text += `\n- ${String(g['courseName'])}: 成绩 ${String(g['totalScore'])} · 绩点 ${String(g['gradePoint'])} · 学分 ${String(g['credit'])}`
        }
        return text
      } else if (domain === 'schedule') {
        if (items.length === 0) return '未查询到日程安排'
        let text: string = ''
        for (let i = 0; i < items.length; i++) {
          const e: Record<string, Object> = items[i] as Record<string, Object>
          if (i > 0) text += '\n'
          text += `[${String(e['title'])}] ${String(e['date'])} ${String(e['startTime'])}-${String(e['endTime'])}`
          const loc: string = String(e['location'] || '')
          if (loc.length > 0 && loc !== 'undefined') text += ` · ${loc}`
        }
        return text
      } else if (domain === 'system_info') {
        const sys: Record<string, Object> = (data['data'] as Record<string, Object>) || {}
        return `当前时间: ${String(sys['date'] || '')} ${String(sys['time'] || '')} (${String(sys['dayOfWeekLabel'] || '')}) · 第 ${String(sys['currentWeek'] || '')} 教学周`
      }
    } catch (e) {
      // ignore
    }
    return ''
  }

  private formatCourseResult(json: string): string {
    const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
    const courses: Object[] = data['courses'] as Object[]
    if (!courses || courses.length === 0) {
      return ''
    }
    let text: string = ''
    for (let i = 0; i < courses.length; i++) {
      const c: Record<string, Object> = courses[i] as Record<string, Object>
      if (i > 0) {
        text += '\n'
      }
      text += `📚 ${String(c['name'])}`
      text += `\n   ${String(c['time'])}`
      const room: string = String(c['room'])
      if (room.length > 0 && room !== 'undefined') {
        text += ` · ${room}`
      }
      const teacher: string = String(c['teacher'])
      if (teacher.length > 0 && teacher !== 'undefined') {
        text += ` · ${teacher}`
      }
    }
    return text
  }

  private formatWeekCourseResult(json: string): string {
    const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
    const schedule: Record<string, Object[]> = data['schedule'] as Record<string, Object[]>
    if (!schedule) {
      return ''
    }
    let text: string = ''
    const days: string[] = Object.keys(schedule)
    for (let d = 0; d < days.length; d++) {
      const dayName: string = days[d]
      const courses: Object[] = schedule[dayName]
      if (d > 0) {
        text += '\n'
      }
      text += `📅 ${dayName}`
      for (let i = 0; i < courses.length; i++) {
        const c: Record<string, Object> = courses[i] as Record<string, Object>
        text += `\n   📚 ${String(c['name'])}`
        text += `\n      ${String(c['time'])}`
        const room: string = String(c['room'])
        if (room.length > 0 && room !== 'undefined') {
          text += ` · ${room}`
        }
      }
    }
    return text
  }

  private formatNextExamResult(json: string): string {
    const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
    let text: string = `📝 ${String(data['courseName'])}`
    text += `\n   📅 ${String(data['examDate'])} ${String(data['examTimeRange'])}`
    const location: string = String(data['examLocation'])
    if (location.length > 0 && location !== 'undefined') {
      text += `\n   📍 ${location}`
    }
    const seatNo: string = String(data['seatNo'])
    if (seatNo.length > 0 && seatNo !== 'undefined') {
      text += `\n   💺 座位号: ${seatNo}`
    }
    const countdown: string = String(data['countdown'])
    if (countdown.length > 0 && countdown !== 'undefined') {
      text += `\n   ⏰ 倒计时: ${countdown}`
    }
    return text
  }

  private formatAllExamsResult(json: string): string {
    const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
    const exams: Object[] = data['exams'] as Object[]
    if (!exams || exams.length === 0) {
      return ''
    }
    let text: string = ''
    for (let i = 0; i < exams.length; i++) {
      const e: Record<string, Object> = exams[i] as Record<string, Object>
      if (i > 0) {
        text += '\n'
      }
      text += `📝 ${String(e['courseName'])}`
      text += `\n   📅 ${String(e['examDate'])} ${String(e['examTimeRange'])}`
      const location: string = String(e['examLocation'])
      if (location.length > 0 && location !== 'undefined') {
        text += ` · ${location}`
      }
      const countdown: string = String(e['countdown'])
      if (countdown.length > 0 && countdown !== 'undefined') {
        text += `\n   ⏰ ${countdown}`
      }
    }
    return text
  }

  private formatGradesResult(json: string): string {
    const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
    const grades: Object[] = data['grades'] as Object[]
    if (!grades || grades.length === 0) {
      return ''
    }
    let text: string = `📊 总GPA: ${String(data['overallGPA'])}\n`
    for (let i = 0; i < grades.length; i++) {
      const g: Record<string, Object> = grades[i] as Record<string, Object>
      text += `\n📖 ${String(g['courseName'])}`
      text += `\n   成绩: ${String(g['totalScore'])} · 绩点: ${String(g['gradePoint'])} · 学分: ${String(g['credit'])}`
    }
    return text
  }

  private formatGpaResult(json: string): string {
    const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
    let text: string = `📊 总GPA: ${String(data['overallGPA'])}`
    text += `\n📈 最新学期GPA: ${String(data['latestSemesterGPA'])}`
    text += `\n📚 共修 ${String(data['totalCourses'])} 门课程`
    return text
  }

  private formatScheduleResult(json: string): string {
    const data: Record<string, Object> = JSON.parse(json) as Record<string, Object>
    const events: Object[] = data['events'] as Object[]
    if (!events || events.length === 0) {
      return ''
    }
    let text: string = ''
    for (let i = 0; i < events.length; i++) {
      const e: Record<string, Object> = events[i] as Record<string, Object>
      if (i > 0) {
        text += '\n'
      }
      text += `📌 ${String(e['title'])}`
      text += `\n   📅 ${String(e['date'])} ${String(e['timeRange'])}`
      const location: string = String(e['location'])
      if (location.length > 0 && location !== 'undefined') {
        text += ` · 📍 ${location}`
      }
    }
    return text
  }

  /**
   * 澄清提问卡片入列：以 tool_result 消息形态插入（复用既有持久化结构），
   * toolArgs 携带提问 JSON，toolResult 留空表示未回答；用户作答后回填 toolResult。
   */
  private pushClarificationCard(toolName: string, success: boolean): void {
    const cardMsg: DisplayMessage = {
      role: 'tool_result',
      content: success ? 'AI 助手发起澄清提问' : '澄清提问下发失败',
      isError: !success,
      toolName: toolName,
      toolArgs: this.lastClarificationArgs,
      toolResult: '',
      isToolSuccess: success,
      statusHint: success ? 'await_answer' : ''
    };
    const lastIdx: number = this.displayMessages.length - 1;
    if (lastIdx >= 0 && this.displayMessages[lastIdx].role === 'assistant' && (!this.displayMessages[lastIdx].content || this.displayMessages[lastIdx].content.length === 0)) {
      const updated: DisplayMessage[] = [...this.displayMessages];
      updated.splice(lastIdx, 0, cardMsg);
      this.displayMessages = updated;
    } else {
      this.displayMessages = [...this.displayMessages, cardMsg];
    }
    this.scrollToBottom();
  }

  /** 用户作答（点推荐项或输入提交）：回填卡片为已答态，并把答案作为下一条用户消息发出 */
  private answerClarification(msgIndex: number, answer: string): void {
    const text: string = answer.trim();
    if (text.length === 0 || this.isLoading) {
      return;
    }
    const cur: DisplayMessage = this.displayMessages[msgIndex];
    const updated: DisplayMessage[] = [...this.displayMessages];
    updated[msgIndex] = {
      role: cur.role,
      content: cur.content,
      isError: cur.isError,
      toolName: cur.toolName,
      toolArgs: cur.toolArgs,
      toolResult: text,
      isToolSuccess: cur.isToolSuccess,
      telemetry: cur.telemetry,
      thought: cur.thought,
      thinkingDurationMs: cur.thinkingDurationMs,
      isThoughtExpanded: cur.isThoughtExpanded,
      statusHint: ''
    };
    this.displayMessages = updated;
    this.clarificationInputText = '';
    this.inputText = text;
    this.sendMessage();
  }

  private parseClarificationQuestion(argsJson: string): string {
    try {
      const parsed: Record<string, Object> = JSON.parse(argsJson) as Record<string, Object>
      const q: Object | undefined = parsed['question']
      return typeof q === 'string' ? q : ''
    } catch (e) {
      return ''
    }
  }

  private parseClarificationOptions(argsJson: string): string[] {
    const out: string[] = []
    try {
      const parsed: Record<string, Object> = JSON.parse(argsJson) as Record<string, Object>
      const raw: Object | undefined = parsed['options']
      if (Array.isArray(raw)) {
        for (let i = 0; i < raw.length; i++) {
          if (typeof raw[i] === 'string' && (raw[i] as string).length > 0) {
            out.push(raw[i] as string)
          }
        }
      }
    } catch (e) {
      // 参数缺失/非法时按无推荐项处理
    }
    return out
  }

  private isClarificationFreeInputAllowed(argsJson: string): boolean {
    try {
      const parsed: Record<string, Object> = JSON.parse(argsJson) as Record<string, Object>
      const v: Object | undefined = parsed['allowFreeInput']
      return typeof v === 'boolean' ? v as boolean : true
    } catch (e) {
      return true
    }
  }

  private isClarificationAnswered(msg: DisplayMessage): boolean {
    return msg.toolResult !== undefined && msg.toolResult.length > 0
  }

  /** 澄清提问交互卡片：问题 + 推荐项 chips（有才显示）+ 自由输入框；已答态展示所选答案 */
  @Builder
  private ClarificationCardBuilder(msg: DisplayMessage, index: number): void {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        Text('❓')
          .fontSize(14)
        Text('AI 助手需要补充信息')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#007AFF')
      }

      Text(this.parseClarificationQuestion(msg.toolArgs || ''))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .width('100%')

      if (this.isClarificationAnswered(msg)) {
        Row({ space: 6 }) {
          Text('✅')
            .fontSize(12)
          Text(`已回答：${msg.toolResult}`)
            .fontSize(13)
            .fontColor(ThemeManager.getTextSecondaryColor())
        }
        .padding(10)
        .borderRadius(8)
        .width('100%')
        .backgroundColor(this.isDarkMode ? '#15251B' : '#EAF5EC')
      } else {
        if (this.parseClarificationOptions(msg.toolArgs || '').length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.parseClarificationOptions(msg.toolArgs || ''), (opt: string) => {
              Text(opt)
                .fontSize(13)
                .fontColor('#007AFF')
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .borderRadius(16)
                .border({ width: 1, color: '#007AFF' })
                .backgroundColor(this.isDarkMode ? '#1E2433' : '#F0F6FF')
                .margin({ right: 8, bottom: 8 })
                .opacity(this.isLoading ? 0.5 : 1.0)
                .onClick(() => {
                  this.answerClarification(index, opt);
                })
            }, (opt: string) => opt)
          }
          .width('100%')
        }
        if (this.isClarificationFreeInputAllowed(msg.toolArgs || '')) {
          Row({ space: 8 }) {
            TextInput({ text: this.clarificationInputText, placeholder: '或输入自定义回答...' })
              .fontSize(13)
              .layoutWeight(1)
              .height(38)
              .backgroundColor(this.isDarkMode ? '#1E2433' : '#FFFFFF')
              .onChange((value: string) => {
                this.clarificationInputText = value;
              })
              .onSubmit(() => {
                this.answerClarification(index, this.clarificationInputText);
              })
            Button('发送')
              .fontSize(13)
              .height(38)
              .enabled(!this.isLoading && this.clarificationInputText.trim().length > 0)
              .onClick(() => {
                this.answerClarification(index, this.clarificationInputText);
              })
          }
          .width('100%')
        }
      }
    }
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.isDarkMode ? '#182030' : '#F7FAFF')
    .border({ width: 1, color: this.isDarkMode ? '#2A3B5A' : '#CCE0FF' })
    .width('92%')
    .alignItems(HorizontalAlign.Start)
  }

  private requestConfirmation(toolName: string, args: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      const displayName: string = this.getToolDisplayName(toolName);
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
          action: () => { resolve(false); }
        },
        secondaryButton: {
          value: '允许',
          fontColor: riskLevel === 'high' ? '#FF9500' : '#007AFF',
          action: () => { resolve(true); }
        }
      });
    });
  }

  private startThinkingTimer(): void {
    this.thinkingStartTime = Date.now();
    this.thinkingElapsedMs = 0;
    this.isThinkingPhase = true;
    this.activeThought = '';
    this.isThoughtExpanded = true;
    this.currentThinkingHint = '正在理解您的问题与上下文...';
    if (this.thinkingStopwatchTimer !== -1) {
      clearInterval(this.thinkingStopwatchTimer);
    }
    this.thinkingStopwatchTimer = setInterval(() => {
      const elapsed: number = Date.now() - this.thinkingStartTime;
      this.thinkingElapsedMs = elapsed;
      if (this.isThinkingPhase && (!this.activeThought || this.activeThought.length === 0)) {
        if (elapsed > 4000 && this.currentThinkingHint.indexOf('成电知识库') !== -1) {
          this.currentThinkingHint = '正在梳理最佳解决方案...';
        } else if (elapsed > 1500 && this.currentThinkingHint.indexOf('理解您的问题') !== -1) {
          this.currentThinkingHint = '正在结合成电知识库深入思考...';
        }
      }
    }, 100);
  }

  private stopThinkingTimer(): void {
    if (this.thinkingStopwatchTimer !== -1) {
      clearInterval(this.thinkingStopwatchTimer);
      this.thinkingStopwatchTimer = -1;
    }
    this.isThinkingPhase = false;
  }

  private sendMessage(): void {
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

    this.startThinkingTimer();
    this.displayMessages = [...this.displayMessages, {
      role: 'assistant',
      content: '',
      isError: false,
      thought: '',
      thinkingDurationMs: 0,
      statusHint: this.currentThinkingHint
    }];
    this.scrollToBottom();

    this.dispatchAgentRun();
  }

  /**
   * 组装回调并发起一次后端对话请求。
   * sendMessage（新消息）与 resendLastMessage（中断重发）共用：
   * 重发时不追加用户消息，沿用当前 session_id 与现有历史，由后端 checkpoint 幂等续接，
   * 续传内容写回原 assistant 气泡。
   */
  private dispatchAgentRun(): void {
    this.trimHistory();

    const context: Context = getContext(this);
    const executor: ToolExecutor = new ToolExecutor(context);
    const self = this;

    const callbacks: AgentCallbacks = {
      onStatusChange: (status: string, message: string) => {
        self.currentThinkingHint = message;
        for (let i = self.displayMessages.length - 1; i >= 0; i--) {
          if (self.displayMessages[i].role === 'assistant') {
            const updated: DisplayMessage[] = [...self.displayMessages];
            updated[i] = {
              role: 'assistant',
              content: updated[i].content,
              isError: updated[i].isError,
              thought: updated[i].thought,
              thinkingDurationMs: updated[i].thinkingDurationMs,
              statusHint: message,
              telemetry: updated[i].telemetry
            };
            self.displayMessages = updated;
            break;
          }
        }
      },
      onThoughtChunk: (chunk: string) => {
        self.activeThought += chunk;
        self.currentThinkingHint = '深度思考中...';
        for (let i = self.displayMessages.length - 1; i >= 0; i--) {
          if (self.displayMessages[i].role === 'assistant') {
            const updated: DisplayMessage[] = [...self.displayMessages];
            updated[i] = {
              role: 'assistant',
              content: updated[i].content,
              isError: updated[i].isError,
              thought: self.activeThought,
              thinkingDurationMs: Date.now() - self.thinkingStartTime,
              statusHint: self.currentThinkingHint,
              telemetry: updated[i].telemetry
            };
            self.displayMessages = updated;
            break;
          }
        }
        self.scrollToBottom();
      },
      onToolCallStart: (toolName: string, args: string) => {
        if (toolName === 'ask_user_clarification') {
          // 澄清提问：缓存参数供 onToolCallResult 渲染交互卡片（提问/选项/是否允许自由输入）
          self.lastClarificationArgs = args;
        }
        const displayName: string = self.getToolDisplayName(toolName);
        self.currentThinkingHint = `正在${displayName}...`;
        const newToolCall: DisplayMessage = {
          role: 'tool_call',
          content: `正在${displayName}...`,
          isError: false,
          toolName: toolName,
          toolArgs: args
        };
        const lastIdx: number = self.displayMessages.length - 1;
        if (lastIdx >= 0 && self.displayMessages[lastIdx].role === 'assistant' && (!self.displayMessages[lastIdx].content || self.displayMessages[lastIdx].content.length === 0)) {
          const updated: DisplayMessage[] = [...self.displayMessages];
          updated.splice(lastIdx, 0, newToolCall);
          self.displayMessages = updated;
        } else {
          self.displayMessages = [...self.displayMessages, newToolCall];
        }
        self.scrollToBottom();
      },
      onToolCallResult: (toolName: string, result: string, success: boolean) => {
        if (toolName === 'ask_user_clarification') {
          // 澄清提问不走普通结果 chip，改渲染交互式问答卡片（用户点选项或输入后作为下一条消息发出）
          self.pushClarificationCard(toolName, success);
          return;
        }
        const displayName: string = self.getToolDisplayName(toolName);
        self.currentThinkingHint = success ? '数据已获取，正在提炼回答...' : '正在整理并生成回答...';
        const newToolResult: DisplayMessage = {
          role: 'tool_result',
          content: success ? `${displayName}完成` : `${displayName}失败`,
          isError: !success,
          toolName: toolName,
          toolResult: result,
          isToolSuccess: success
        };
        const lastIdx: number = self.displayMessages.length - 1;
        if (lastIdx >= 0 && self.displayMessages[lastIdx].role === 'assistant' && (!self.displayMessages[lastIdx].content || self.displayMessages[lastIdx].content.length === 0)) {
          const updated: DisplayMessage[] = [...self.displayMessages];
          updated.splice(lastIdx, 0, newToolResult);
          self.displayMessages = updated;
        } else {
          self.displayMessages = [...self.displayMessages, newToolResult];
        }
        self.scrollToBottom();
      },
      onConfirmationNeeded: (toolName: string, args: string): Promise<boolean> => {
        return self.requestConfirmation(toolName, args);
      },
      onTextChunk: (chunk: string) => {
        if (self.isThinkingPhase) {
          self.stopThinkingTimer();
          self.isThoughtExpanded = false;
        }
        const dur: number = self.thinkingElapsedMs > 0 ? self.thinkingElapsedMs : (Date.now() - self.thinkingStartTime);

        let targetIdx: number = -1;
        for (let i = self.displayMessages.length - 1; i >= 0; i--) {
          if (self.displayMessages[i].role === 'assistant') {
            targetIdx = i;
            break;
          }
        }

        if (targetIdx !== -1) {
          const updated: DisplayMessage[] = [...self.displayMessages];
          const cur = updated[targetIdx];
          updated[targetIdx] = {
            role: 'assistant',
            content: cur.content + chunk,
            isError: false,
            thought: self.activeThought.length > 0 ? self.activeThought : cur.thought,
            thinkingDurationMs: cur.thinkingDurationMs && cur.thinkingDurationMs > 0 ? cur.thinkingDurationMs : dur,
            telemetry: cur.telemetry
          };
          self.displayMessages = updated;
        } else {
          self.displayMessages = [...self.displayMessages, {
            role: 'assistant',
            content: chunk,
            isError: false,
            thought: self.activeThought,
            thinkingDurationMs: dur
          }];
        }
        self.scrollToBottom();
      },
      onError: (error: string) => {
        self.stopThinkingTimer();
        self.isLoading = false;
        self.pendingIncompleteRound = false;
        self.interruptedMsgIndex = -1;
        let targetIdx: number = -1;
        for (let i = self.displayMessages.length - 1; i >= 0; i--) {
          if (self.displayMessages[i].role === 'assistant') {
            targetIdx = i;
            break;
          }
        }
        if (targetIdx !== -1) {
          const updated: DisplayMessage[] = [...self.displayMessages];
          updated[targetIdx] = {
            role: 'assistant',
            content: error,
            isError: true,
            thought: self.activeThought,
            thinkingDurationMs: self.thinkingElapsedMs,
            statusHint: ''
          };
          self.displayMessages = updated;
        } else {
          self.displayMessages = [...self.displayMessages, { role: 'assistant', content: error, isError: true, statusHint: '' }];
        }
        self.updateCurrentSessionTimestamp();
        self.syncCurrentSession();
        self.saveSessions();
        self.scrollToBottom();
      },
      onComplete: (telemetry?: AgentTelemetryInfo) => {
        self.stopThinkingTimer();
        self.isLoading = false;
        // 消费缺 final 帧标记：completed_with_warning 时落一条持久化轻提示，其余清空陈旧状态提示
        const wasIncomplete: boolean = self.pendingIncompleteRound;
        self.pendingIncompleteRound = false;
        const lastAssistantMsg: DisplayMessage | undefined = self.findLastAssistantMessage();
        if (lastAssistantMsg && lastAssistantMsg.content.length > 0) {
          self.messages = [...self.messages, { role: 'assistant', content: lastAssistantMsg.content }];
          if (telemetry) {
            const lastIdx: number = self.displayMessages.length - 1;
            for (let i = lastIdx; i >= 0; i--) {
              if (self.displayMessages[i].role === 'assistant') {
                self.displayMessages[i].telemetry = telemetry;
                break;
              }
            }
          }
        }
        for (let i = self.displayMessages.length - 1; i >= 0; i--) {
          if (self.displayMessages[i].role === 'assistant') {
            const refreshed: DisplayMessage[] = [...self.displayMessages];
            refreshed[i] = {
              role: 'assistant',
              content: refreshed[i].content,
              isError: refreshed[i].isError,
              thought: refreshed[i].thought,
              thinkingDurationMs: refreshed[i].thinkingDurationMs,
              statusHint: wasIncomplete ? '⚠️ 回复可能不完整' : '',
              telemetry: refreshed[i].telemetry
            };
            self.displayMessages = refreshed;
            break;
          }
        }
        self.interruptedMsgIndex = -1;
        self.updateCurrentSessionTimestamp();
        self.syncCurrentSession();
        self.saveSessions();
        self.scrollToBottom();
      },
      onIncomplete: (message: string) => {
        // 流干净结束但缺 final 帧（completed_with_warning）：轻提示，内容照常展示、不进错误态
        self.pendingIncompleteRound = true;
        promptAction.showToast({ message: message, duration: 2500 });
      },
      onInterrupted: (message: string) => {
        // 已收到部分内容后流中断：保留已收内容、标记中断态并暴露「重新发送」入口；
        // 不触发消息历史入库，重发续接完成后再统一落库，避免半截回复与续传回复重复
        self.stopThinkingTimer();
        self.isLoading = false;
        let targetIdx: number = -1;
        for (let i = self.displayMessages.length - 1; i >= 0; i--) {
          if (self.displayMessages[i].role === 'assistant') {
            targetIdx = i;
            break;
          }
        }
        if (targetIdx !== -1) {
          const updated: DisplayMessage[] = [...self.displayMessages];
          updated[targetIdx] = {
            role: 'assistant',
            content: updated[targetIdx].content,
            isError: false,
            thought: self.activeThought.length > 0 ? self.activeThought : updated[targetIdx].thought,
            thinkingDurationMs: updated[targetIdx].thinkingDurationMs,
            statusHint: `⚠️ ${message}`,
            telemetry: updated[targetIdx].telemetry
          };
          self.displayMessages = updated;
          self.interruptedMsgIndex = targetIdx;
        }
        self.updateCurrentSessionTimestamp();
        self.syncCurrentSession();
        self.saveSessions();
        self.scrollToBottom();
      }
    };

    const client: BackendAgentClient = new BackendAgentClient(context, executor, callbacks);
    this.currentClient = client;

    const history: AgentMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      history.push({ role: this.messages[i].role, content: this.messages[i].content });
    }

    client.run(this.currentSessionId, history);
  }

  /**
   * 中断态「重新发送」：携带同一 session_id 原样重发用户最后一条消息，
   * 不重复入列用户消息；清除中断标记后复用原 assistant 气泡承接续传内容。
   */
  private resendLastMessage(): void {
    if (this.isLoading || this.interruptedMsgIndex === -1) {
      return;
    }
    let lastUserContent: string = '';
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].role === 'user') {
        lastUserContent = this.messages[i].content;
        break;
      }
    }
    if (lastUserContent.length === 0) {
      this.interruptedMsgIndex = -1;
      return;
    }
    console.info('[AssistantPage] resend last message, session:', this.currentSessionId);

    const idx: number = this.interruptedMsgIndex;
    this.interruptedMsgIndex = -1;
    const updated: DisplayMessage[] = [...this.displayMessages];
    if (idx >= 0 && idx < updated.length && updated[idx].role === 'assistant') {
      updated[idx] = {
        role: 'assistant',
        content: updated[idx].content,
        isError: false,
        thought: '',
        thinkingDurationMs: 0,
        statusHint: '',
        telemetry: updated[idx].telemetry
      };
      this.displayMessages = updated;
    }

    this.isLoading = true;
    this.startThinkingTimer();
    this.scrollToBottom();
    this.dispatchAgentRun();
  }

  private findLastAssistantMessage(): DisplayMessage | undefined {
    for (let i = this.displayMessages.length - 1; i >= 0; i--) {
      if (this.displayMessages[i].role === 'assistant') {
        return this.displayMessages[i];
      }
    }
    return undefined;
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
        console.info('[AssistantPage] side panel open clicked, sessions count:', this.sessions.length);
        this.syncCurrentSession();
        console.info('[AssistantPage] after sync, showSidePanel will be true');
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

      if (msg.role === 'tool_call') {
        Row({ space: 6 }) {
          Circle()
            .width(6)
            .height(6)
            .fill('#007AFF')
          Text(msg.content)
            .fontSize(12)
            .fontColor(ThemeManager.getTextSecondaryColor())
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(8)
        .backgroundColor(this.isDarkMode ? '#1E2433' : '#F2F4F7')
        .border({ width: 0.5, color: this.isDarkMode ? '#2D3748' : '#E2E8F0' })
        .alignItems(VerticalAlign.Center)
      } else if (msg.role === 'tool_result' && msg.toolName === 'ask_user_clarification') {
        this.ClarificationCardBuilder(msg, index)
      } else if (msg.role === 'tool_result') {
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Circle()
              .width(6)
              .height(6)
              .fill(msg.isToolSuccess ? '#34C759' : '#FF3B30')
            Text(msg.content)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(msg.isToolSuccess ? ThemeManager.getTextPrimaryColor() : '#FF3B30')

            if (msg.isToolSuccess && msg.toolResult && msg.toolResult.length > 0 && msg.toolName) {
              Text(this.expandedToolIndices.indexOf(index) !== -1 ? '▾ 收起' : '▸ 查看数据')
                .fontSize(11)
                .fontColor('#007AFF')
                .margin({ left: 4 })
            }
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(8)
          .backgroundColor(this.isDarkMode ? '#1E2433' : '#F4F5F8')
          .border({ width: 0.5, color: this.isDarkMode ? '#2D3748' : '#E2E8F0' })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            if (msg.isToolSuccess && msg.toolResult && msg.toolResult.length > 0) {
              const pos = this.expandedToolIndices.indexOf(index);
              if (pos !== -1) {
                this.expandedToolIndices.splice(pos, 1);
              } else {
                this.expandedToolIndices.push(index);
              }
            }
          })

          if (this.expandedToolIndices.indexOf(index) !== -1 && msg.isToolSuccess && msg.toolResult && msg.toolResult.length > 0 && msg.toolName) {
            Text(this.formatToolResult(msg.toolName, msg.toolResult))
              .fontSize(12)
              .fontColor(ThemeManager.getTextSecondaryColor())
              .padding(8)
              .backgroundColor(this.isDarkMode ? '#141820' : '#EDF0F5')
              .borderRadius(6)
              .margin({ top: 2 })
              .maxLines(15)
              .lineHeight(18)
          }
        }
        .alignItems(HorizontalAlign.Start)
      } else {
        Column({ space: 6 }) {
          if (msg.role === 'assistant') {
            // 1. 思考中状态卡片（当处于加载状态且无正文时）
            if (this.isLoading && index === this.displayMessages.length - 1 && (!msg.content || msg.content.length === 0)) {
              Column({ space: 8 }) {
                // 顶部状态提示行：阶段文案 + 实时秒表
                Row({ space: 8 }) {
                  Text(this.currentThinkingHint)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(ThemeManager.getTextPrimaryColor())
                    .layoutWeight(1)

                  // 实时耗时秒表胶囊
                  Row({ space: 4 }) {
                    Text(`思考中 ${(this.thinkingElapsedMs / 1000).toFixed(1)}s`)
                      .fontSize(11)
                      .fontColor('#007AFF')
                      .fontWeight(FontWeight.Medium)
                  }
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(this.isDarkMode ? 'rgba(0, 122, 255, 0.15)' : 'rgba(0, 122, 255, 0.08)')
                  .borderRadius(10)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                // 呼吸波浪动效条 (三个呼吸微光点)
                Row({ space: 6 }) {
                  Circle({ width: 6, height: 6 })
                    .fill('#007AFF')
                    .opacity(this.pulsePhase === 0 ? 1.0 : 0.3)
                    .scale({ x: this.pulsePhase === 0 ? 1.2 : 0.9, y: this.pulsePhase === 0 ? 1.2 : 0.9 })
                  Circle({ width: 6, height: 6 })
                    .fill('#007AFF')
                    .opacity(this.pulsePhase === 1 ? 1.0 : 0.3)
                    .scale({ x: this.pulsePhase === 1 ? 1.2 : 0.9, y: this.pulsePhase === 1 ? 1.2 : 0.9 })
                  Circle({ width: 6, height: 6 })
                    .fill('#007AFF')
                    .opacity(this.pulsePhase === 2 ? 1.0 : 0.3)
                    .scale({ x: this.pulsePhase === 2 ? 1.2 : 0.9, y: this.pulsePhase === 2 ? 1.2 : 0.9 })

                  Text('AI 正在深度解析与推理中，即将输出解答...')
                    .fontSize(12)
                    .fontColor(ThemeManager.getTextTertiaryColor())
                    .margin({ left: 4 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                // 实时思维链流式展示（若模型输出 thought）
                if (this.activeThought && this.activeThought.length > 0) {
                  Column({ space: 4 }) {
                    Row() {
                      Text('思考过程：')
                        .fontSize(12)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(ThemeManager.getTextSecondaryColor())
                    }
                    .width('100%')

                    Text(this.activeThought)
                      .fontSize(12)
                      .fontFamily('monospace')
                      .fontColor(ThemeManager.getTextSecondaryColor())
                      .lineHeight(17)
                      .maxLines(10)
                  }
                  .width('100%')
                  .padding(8)
                  .backgroundColor(this.isDarkMode ? '#1E2433' : '#EDF0F5')
                  .borderRadius(8)
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.isDarkMode ? 'rgba(30, 36, 51, 0.7)' : 'rgba(240, 243, 249, 0.9)')
              .borderRadius(12)
              .border({ width: 0.5, color: this.isDarkMode ? '#2D3748' : '#D1D9E6' })
            }

            // 2. 思考完成后的思维链折叠栏（当有 thought 且正文已开始输出或生成完毕时）
            if (msg.thought && msg.thought.length > 0 && (msg.content.length > 0 || !this.isLoading)) {
              Column({ space: 6 }) {
                Row({ space: 6 }) {
                  Text(`已深度思考 ${(Number(msg.thinkingDurationMs || 0) / 1000).toFixed(1)}s`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(ThemeManager.getTextSecondaryColor())
                    .layoutWeight(1)

                  Text(this.expandedThoughtIndices.indexOf(index) !== -1 ? '▾ 收起' : '▸ 查看思考过程')
                    .fontSize(11)
                    .fontColor('#007AFF')
                }
                .width('100%')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(this.isDarkMode ? '#1E2433' : '#EDF2F7')
                .borderRadius(8)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  const pos = this.expandedThoughtIndices.indexOf(index);
                  if (pos !== -1) {
                    this.expandedThoughtIndices.splice(pos, 1);
                  } else {
                    this.expandedThoughtIndices.push(index);
                  }
                })

                if (this.expandedThoughtIndices.indexOf(index) !== -1) {
                  Text(msg.thought)
                    .fontSize(12)
                    .fontFamily('monospace')
                    .fontColor(ThemeManager.getTextSecondaryColor())
                    .padding(10)
                    .backgroundColor(this.isDarkMode ? '#141820' : '#F7FAFC')
                    .borderRadius(6)
                    .border({ width: 0.5, color: this.isDarkMode ? '#2D3748' : '#E2E8F0' })
                    .lineHeight(18)
                }
              }
              .width('100%')
              .margin({ bottom: 4 })
            }

            // 3. 正文 Markdown 流式/全量渲染
            if (msg.content && msg.content.length > 0) {
              MarkdownBubble({
                content: msg.content,
                isUser: false,
                isError: msg.isError,
                isStreaming: (this.isLoading && index === this.displayMessages.length - 1)
              })
              .width('100%')
            }

            // 4. 遥测信息 (Tokens / 耗时)
            if (msg.telemetry && msg.telemetry.totalTokens) {
              Row({ space: 4 }) {
                Text(`⚡ ${msg.telemetry.totalTokens} Tokens · ${(Number(msg.telemetry.durationMs || 0) / 1000).toFixed(1)}s${msg.telemetry.ttftMs ? ` (首字 ${(Number(msg.telemetry.ttftMs) / 1000).toFixed(1)}s)` : ''}`)
                  .fontSize(10)
                  .fontColor(ThemeManager.getTextTertiaryColor())
              }
              .margin({ top: 4 })
              .alignSelf(ItemAlign.End)
            }

            // 5. completed_with_warning 持久化轻提示（流干净结束但缺 final 帧）
            if (msg.statusHint && msg.statusHint.indexOf('⚠️') === 0 && index !== this.interruptedMsgIndex) {
              Text(msg.statusHint)
                .fontSize(11)
                .fontColor('#FF9500')
                .margin({ top: 4 })
            }

            // 6. 中断态：保留已收内容并提供「重新发送」入口（同 session_id 借后端 checkpoint 幂等续接）
            if (index === this.interruptedMsgIndex) {
              Row({ space: 10 }) {
                Text(msg.statusHint && msg.statusHint.length > 0 ? msg.statusHint : '⚠️ 连接中断，回复未完成')
                  .fontSize(12)
                  .fontColor('#FF9500')
                  .layoutWeight(1)
                Button('重新发送')
                  .height(28)
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#007AFF')
                  .borderRadius(14)
                  .padding({ left: 12, right: 12 })
                  .onClick(() => {
                    this.resendLastMessage();
                  })
              }
              .width('100%')
              .margin({ top: 6 })
              .alignItems(VerticalAlign.Center)
            }
          } else {
            Text(msg.content)
              .fontSize(15)
              .fontColor('#FFFFFF')
              .maxLines(Number.MAX_SAFE_INTEGER)
              .copyOption(CopyOptions.LocalDevice)
          }
        }
        .layoutWeight(msg.role === 'assistant' ? 1 : undefined)
        .constraintSize({ maxWidth: msg.role === 'user' ? '75%' : '100%' })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(18)
        .backgroundColor(msg.role === 'user' ? '#007AFF' : (this.isDarkMode ? '#2D2D2D' : '#F2F2F7'))
        .alignItems(HorizontalAlign.Start)
        .clip(true)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .justifyContent(msg.role === 'user' ? FlexAlign.End : FlexAlign.Start)
  }

  private async toggleVoiceRecording(): Promise<void> {
    if (this.isRecording) {
      await this.speechHelper.stopListening();
      this.isRecording = false;
      return;
    }

    this.isRecording = true;
    const ok: boolean = await this.speechHelper.startListening(
      getContext(this) as common.UIAbilityContext,
      (text: string, isLast: boolean) => {
        if (text && text.length > 0) {
          this.inputText = text;
        }
        if (isLast) {
          this.isRecording = false;
        }
      },
      (errorMsg: string) => {
        this.isRecording = false;
        promptAction.showToast({ message: errorMsg, duration: 2000 });
      }
    );
    if (!ok) {
      this.isRecording = false;
    }
  }

  private async pickAndParseImageSchedule(): Promise<void> {
    if (this.isLoading) return;
    const photoUri: string | null = await VisionScheduleHelper.pickImage();
    if (!photoUri) return;

    this.isLoading = true;
    const userMsg: Message = { role: 'user', content: '[发送了海报/通知图片]' };
    this.messages = [...this.messages, userMsg];
    this.displayMessages = [...this.displayMessages, {
      role: 'user',
      content: '📷 [海报/通知图片]',
      isError: false
    }, {
      role: 'assistant',
      content: '🔍 正在使用智谱多模态大模型解析海报中的日程信息，请稍候...',
      isError: false
    }];
    this.scrollToBottom();

    try {
      const base64: string | null = await VisionScheduleHelper.convertUriToBase64(photoUri);
      if (!base64) {
        throw new Error('读取图片失败');
      }

      // 先校验后端配置，缺失时直接给出引导文案（不发起无谓请求）
      const agentEndpoint: AgentEndpoint = await AgentEndpointConfig.resolve(getContext(this));
      if (!AgentEndpointConfig.isReady(agentEndpoint)) {
        throw new Error(AgentEndpointConfig.missingHint(agentEndpoint));
      }

      const result: VisionScheduleResult | null = await VisionScheduleHelper.parseScheduleFromImage(getContext(this), base64);
      if (!result) {
        throw new Error('未能从海报中提取到有效日程');
      }

      const formattedResult: string = `🎉 已为您智能识别日程：\n\n` +
        `📌 **标题**：${result.title}\n` +
        `📅 **日期**：${result.date}\n` +
        `⏰ **时间**：${result.startTime} - ${result.endTime}\n` +
        (result.location ? `📍 **地点**：${result.location}\n` : '') +
        (result.description ? `📝 **说明**：${result.description}\n` : '') +
        `\n您可以通过对话回复："帮我把这个日程加到日历" 或 "创建日程"，我将立即为您添加到系统日历！`;

      const lastIdx: number = this.displayMessages.length - 1;
      const updated: DisplayMessage[] = [...this.displayMessages];
      updated[lastIdx] = {
        role: 'assistant',
        content: formattedResult,
        isError: false
      };
      this.displayMessages = updated;
      this.messages = [...this.messages, { role: 'assistant', content: formattedResult }];
      this.updateCurrentSessionTimestamp();
      this.syncCurrentSession();
      this.saveSessions();
    } catch (err) {
      const lastIdx: number = this.displayMessages.length - 1;
      const updated: DisplayMessage[] = [...this.displayMessages];
      updated[lastIdx] = {
        role: 'assistant',
        content: `❌ 解析海报失败：${String((err as Error)?.message || err)}`,
        isError: true
      };
      this.displayMessages = updated;
    } finally {
      this.isLoading = false;
      this.scrollToBottom();
    }
  }

  @Builder
  private InputBarBuilder(): void {
    Column({ space: 6 }) {
      if (this.isRecording) {
        Row({ space: 8 }) {
          Circle()
            .width(10)
            .height(10)
            .fill('#FF3B30')
          Text('正在倾听您的语音，请说话...（点击麦克风停止）')
            .fontSize(12)
            .fontColor('#FF3B30')
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }

      Row({ space: 8 }) {
        Row() {
          Text('📷')
            .fontSize(20)
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .backgroundColor(ThemeManager.getCardColor())
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.pickAndParseImageSchedule();
        })

        Row() {
          Text(this.isRecording ? '🔴' : '🎙️')
            .fontSize(18)
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .backgroundColor(this.isRecording ? 'rgba(255, 59, 48, 0.15)' : ThemeManager.getCardColor())
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.toggleVoiceRecording();
        })

        TextArea({ text: $$this.inputText, placeholder: this.isRecording ? '正在转写语音...' : '输入消息或语音说话...' })
          .layoutWeight(1)
          .maxLines(4)
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .placeholderColor(ThemeManager.getTextTertiaryColor())
          .backgroundColor(ThemeManager.getCardColor())
          .borderRadius(20)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .enabled(!this.isLoading)
          .enterKeyType(EnterKeyType.Send)
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.sendMessage();
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
        .width(60)
        .height(38)
        .borderRadius(19)
        .backgroundColor((this.isLoading || this.inputText.trim().length === 0) ? '#B0C4DE' : '#007AFF')
        .enabled(!this.isLoading && this.inputText.trim().length > 0)
        .onClick(() => {
          this.sendMessage();
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 4 })
      .alignItems(VerticalAlign.Center);

      Text('⚠️ AI 生成内容仅供参考，课程与考试安排请以教务处官方系统为准')
        .fontSize(11)
        .fontColor(ThemeManager.getTextTertiaryColor())
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ bottom: 6 });
    }
    .width('100%')
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
          console.info('[AssistantPage] close side panel clicked');
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
          console.info('[AssistantPage] create new chat from side panel');
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
                  console.info('[AssistantPage] delete session clicked:', session.id);
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
                console.info('[AssistantPage] switch to session:', session.id);
                this.switchToSession(session.id);
              })
            }
          }, (session: ChatSession) => session.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
      }

      Divider().color($r('app.color.divider_color')).strokeWidth(0.5);

      // 助手设置快捷区
      Column({ space: 8 }) {
        Row() {
          Text('开启全局 AI 悬浮球')
            .fontSize(14)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .layoutWeight(1);

          Toggle({ type: ToggleType.Switch, isOn: this.isFloatingBallEnabled })
            .selectedColor($r('app.color.primary_color'))
            .onChange((isOn: boolean) => {
              this.isFloatingBallEnabled = isOn;
              FloatingWindowManager.getInstance().setEnabled(isOn);
            });
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 });

        Row() {
          Text('显示工具调用过程')
            .fontSize(14)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .layoutWeight(1);

          Toggle({ type: ToggleType.Switch, isOn: this.showToolCalls })
            .selectedColor($r('app.color.primary_color'))
            .onChange((isOn: boolean) => {
              this.showToolCalls = isOn;
              try {
                const pref = preferences.getPreferencesSync(getContext(this), { name: AppConstants.COURSE_TABLE_PREF_NAME });
                pref.putSync(AppConstants.SETTING_AI_SHOW_TOOL_CALLS_KEY, isOn);
                pref.flushSync();
              } catch (e) {}
            });
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 });
      }
      .width('100%')
      .backgroundColor(ThemeManager.getCardColor())
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

  @Builder
  private BackendGuideCard(): void {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('⚠️')
          .fontSize(18)
        Text('AI 助手后端尚未配置')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF9500')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.backendGuideHint.length > 0 ? this.backendGuideHint : '请先在「我的 - 应用设置 - 助手后端」填写后端地址与访问密钥，再使用 AI 助手。')
        .fontSize(13)
        .fontColor(ThemeManager.getTextSecondaryColor())
        .width('100%')

      Button('去设置')
        .width('100%')
        .height(36)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor('#007AFF')
        .borderRadius(10)
        .onClick(() => {
          router.pushUrl({ url: RouterConstants.PAGE_SETTINGS }).catch((error: Error) => {
            console.error('[AssistantPage] jump to settings failed:', JSON.stringify(error));
          });
        })
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor(this.isDarkMode ? '#3A2E12' : '#FFF7E6')
    .border({ width: 1, color: this.isDarkMode ? '#8A6D1A' : '#F0D48A' })
  }

  @Builder
  private PromptChipBuilder(label: string, promptText: string): void {
    Button() {
      Text(label)
        .fontSize(13)
        .fontColor('#007AFF')
        .maxLines(1)
    }
    .height(34)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.isDarkMode ? '#1E2433' : '#EFF6FF')
    .borderRadius(17)
    .margin({ right: 8, bottom: 8 })
    .onClick(() => {
      this.inputText = promptText;
      this.sendMessage();
    })
  }

  build() {
    Column() {
      this.TitleBarBuilder()

      List({ space: 0, scroller: this.scroller }) {
        // 后端配置缺失时的引导卡片（配置齐全时不渲染）
        if (this.showBackendGuide) {
          ListItem() {
            this.BackendGuideCard()
          }
          .margin({ left: 16, right: 16, top: 8 })
        }

        ForEach(this.displayMessages, (msg: DisplayMessage, index: number) => {
          ListItem() {
            if (this.showToolCalls || (msg.role !== 'tool_call' && msg.role !== 'tool_result') || (msg.role === 'tool_result' && msg.toolName === 'ask_user_clarification')) {
              this.MessageBubbleBuilder(msg, index as number)
            }
          }
        }, (msg: DisplayMessage, index: number) => `${index}_${msg.role}_${msg.content.length}_${(msg.statusHint && msg.statusHint.length > 0) ? 'h' : 'n'}_${(msg.toolResult && msg.toolResult.length > 0) ? 'a' : 'p'}_${index === this.interruptedMsgIndex ? 'i' : 'n'}`)

        if (this.displayMessages.length === 0) {
          ListItem() {
            Column({ space: 12 }) {
              Image($r('app.media.ic_ai_assistant'))
                .width(56)
                .height(56)
                .margin({ bottom: 4 })

              Text('成电校园智能助手')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeManager.getTextPrimaryColor())

              Text('支持全套教务查询、日程创建、系统日历同步与校园指南')
                .fontSize(13)
                .fontColor(ThemeManager.getTextSecondaryColor())
                .textAlign(TextAlign.Center)

              Column({ space: 8 }) {
                Text('💡 快捷指令推荐')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeManager.getTextTertiaryColor())
                  .alignSelf(ItemAlign.Start)
                  .margin({ left: 4 })

                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  this.PromptChipBuilder('📅 今天有哪些课？', '今天有哪些课？')
                  this.PromptChipBuilder('📝 离我最近的考试', '离我最近的考试安排是什么？')
                  this.PromptChipBuilder('📊 查这学期GPA', '帮我查一下这学期的GPA和成绩')
                  this.PromptChipBuilder('🚌 清水河校车时刻', '查询清水河到沙河校区的校车时刻表')
                  this.PromptChipBuilder('➕ 明天上午自习日程', '帮我明天上午9点到11点创建一个在图书馆自习的日程')
                }
                .width('100%')
              }
              .width('94%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor(ThemeManager.getCardColor())
              .margin({ top: 12 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 40, left: 16, right: 16, bottom: 20 })
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
        console.info('[AssistantPage] side sheet onDisappear');
        this.showSidePanel = false;
      }
    })
    .bindContentCover(this.showDeleteDialog, this.DeleteDialogBuilder(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        console.info('[AssistantPage] delete dialog onDisappear');
        this.showDeleteDialog = false;
        this.pendingDeleteSessionId = '';
      }
    })
  }
}
