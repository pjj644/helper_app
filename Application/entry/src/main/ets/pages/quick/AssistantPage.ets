import { preferences } from '@kit.ArkData';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { AppConstants } from '../../common/constants/AppConstants';
import { ToolRegistry } from '../../common/agent/ToolRegistry';
import { ToolExecutor } from '../../common/agent/ToolExecutor';
import { BackendAgentClient, AgentCallbacks, AgentMessage } from '../../common/agent/BackendAgentClient';
import { SpeechRecognizerHelper } from '../../common/speech/SpeechRecognizerHelper';
import { VisionScheduleHelper, VisionScheduleResult } from '../../common/agent/VisionScheduleHelper';
import { SettingsRepository } from '../../repository/SettingsRepository';
import { FloatingWindowManager } from '../../common/agent/FloatingWindowManager';
import { PageContextTracker } from '../../common/agent/PageContextTracker';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
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
  @StorageLink('floating_ball_enabled') isFloatingBallEnabled: boolean = true;
  @State isRecording: boolean = false;
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  private scroller: Scroller = new Scroller();
  private dotTimer: number = -1;
  private currentClient: BackendAgentClient | null = null;
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
    }, 500);
    this.loadSessions();
    this.loadToolCallDisplaySetting();
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 400);
  }

  aboutToDisappear(): void {
    FloatingWindowManager.getInstance().setAssistantPageActive(false);
    this.syncCurrentSession();
    this.saveSessions();
    if (this.dotTimer !== -1) {
      clearInterval(this.dotTimer);
      this.dotTimer = -1;
    }
    this.speechHelper.release();
  }

  onPageShow(): void {
    FloatingWindowManager.getInstance().setAssistantPageActive(true);
    this.loadSessions();
    this.loadToolCallDisplaySetting();
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 300);
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
    console.info('[AI Debug] loadSessions start');
    try {
      const context = getContext(this);
      this.sessions = ChatSessionRepository.getSessions(context);
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
      ChatSessionRepository.saveSessions(context, this.sessions);
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

  private getToolDisplayName(toolName: string): string {
    const nameMap: Record<string, string> = {
      'app_data_query': '查询应用数据',
      'app_data_mutate': '变更应用数据',
      'app_control': '应用系统控制',
      'campus_search': '检索校园信息',
      'app_pipeline': '执行复合流水线',
      'query_today_courses': '查询今日课程',
      'query_week_courses': '查询本周课程',
      'query_current_week': '查询当前周',
      'query_next_exam': '查询最近考试',
      'query_all_exams': '查询所有考试',
      'query_grades': '查询成绩',
      'query_gpa': '查询GPA',
      'query_schedule': '查询日程',
      'check_login_status': '检查登录状态',
      'check_time_conflict': '检查时间冲突',
      'query_reminder_settings': '查询提醒设置',
      'has_course_data': '检查课表数据',
      'create_schedule': '创建日程',
      'delete_schedule': '删除日程',
      'sync_courses_to_cloud': '同步课表到云端',
      'sync_exams_to_cloud': '同步考试到云端',
      'sync_all_to_cloud': '全量同步到云端',
      'download_all_from_cloud': '从云端恢复数据',
      'set_reminder_enabled': '设置提醒开关',
      'set_remind_minutes': '设置提醒时间',
      'refresh_reminders': '刷新提醒',
      'navigate_to_page': '导航到页面',
      'query_campus_guide': '查询成电指南',
      'generate_study_plan': '生成突击规划',
      'parse_text_to_schedule': '解析日程文本',
      'search_jwc_news': '检索教务处官网'
    };
    return nameMap[toolName] || toolName;
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

    this.displayMessages = [...this.displayMessages, { role: 'assistant', content: '', isError: false }];
    this.scrollToBottom();

    this.trimHistory();

    const context: Context = getContext(this);
    const executor: ToolExecutor = new ToolExecutor(context);
    const self = this;

    const callbacks: AgentCallbacks = {
      onToolCallStart: (toolName: string, args: string) => {
        const displayName: string = self.getToolDisplayName(toolName);
        self.displayMessages = [...self.displayMessages, {
          role: 'tool_call',
          content: `正在${displayName}...`,
          isError: false,
          toolName: toolName,
          toolArgs: args
        }];
        self.scrollToBottom();
      },
      onToolCallResult: (toolName: string, result: string, success: boolean) => {
        const displayName: string = self.getToolDisplayName(toolName);
        self.displayMessages = [...self.displayMessages, {
          role: 'tool_result',
          content: success ? `${displayName}完成` : `${displayName}失败`,
          isError: !success,
          toolName: toolName,
          toolResult: result,
          isToolSuccess: success
        }];
        self.scrollToBottom();
      },
      onConfirmationNeeded: (toolName: string, args: string): Promise<boolean> => {
        return self.requestConfirmation(toolName, args);
      },
      onTextChunk: (chunk: string) => {
        const lastIndex: number = self.displayMessages.length - 1;
        if (lastIndex >= 0 && self.displayMessages[lastIndex].role === 'assistant') {
          const updated: DisplayMessage[] = [...self.displayMessages];
          updated[lastIndex] = {
            role: 'assistant',
            content: updated[lastIndex].content + chunk,
            isError: false
          };
          self.displayMessages = updated;
        } else {
          self.displayMessages = [...self.displayMessages, { role: 'assistant', content: chunk, isError: false }];
        }
        self.scrollToBottom();
      },
      onError: (error: string) => {
        self.isLoading = false;
        const lastIndex: number = self.displayMessages.length - 1;
        if (lastIndex >= 0 && self.displayMessages[lastIndex].role === 'assistant') {
          const updated: DisplayMessage[] = [...self.displayMessages];
          updated[lastIndex] = { role: 'assistant', content: error, isError: true };
          self.displayMessages = updated;
        } else {
          self.displayMessages = [...self.displayMessages, { role: 'assistant', content: error, isError: true }];
        }
        self.updateCurrentSessionTimestamp();
        self.syncCurrentSession();
        self.saveSessions();
        self.scrollToBottom();
      },
      onComplete: (telemetry?: AgentTelemetryInfo) => {
        self.isLoading = false;
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
        Column({ space: 4 }) {
          if (msg.role === 'assistant') {
            MarkdownBubble({
              content: msg.content,
              isUser: false,
              isError: msg.isError
            })
          } else {
            Text(msg.content)
              .fontSize(15)
              .fontColor('#FFFFFF')
              .maxLines(Number.MAX_SAFE_INTEGER)
              .copyOption(CopyOptions.LocalDevice)
          }

          if (msg.role === 'assistant' && this.isLoading && index === this.displayMessages.length - 1 && msg.content.length === 0) {
            Text(this.streamingDot ? '▌' : ' ')
              .fontSize(15)
              .fontColor(ThemeManager.getTextPrimaryColor())
              .margin({ top: 2 })
          }

          if (msg.role === 'assistant' && msg.telemetry && msg.telemetry.totalTokens) {
            Row({ space: 4 }) {
              Text(`⚡ ${msg.telemetry.totalTokens} Tokens · ${(Number(msg.telemetry.durationMs || 0) / 1000).toFixed(1)}s`)
                .fontSize(10)
                .fontColor(ThemeManager.getTextTertiaryColor())
            }
            .margin({ top: 4 })
            .alignSelf(ItemAlign.End)
          }
        }
        .constraintSize({ maxWidth: msg.role === 'user' ? '75%' : '88%' })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(18)
        .backgroundColor(msg.role === 'user' ? '#007AFF' : (this.isDarkMode ? '#2D2D2D' : '#F2F2F7'))
        .alignItems(HorizontalAlign.Start)
      }

      if (msg.role === 'assistant') {
        Blank()
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

      let backendUrl: string = AppConstants.AI_AGENT_URL;
      try {
        backendUrl = await SettingsRepository.getAgentBackendUrl(getContext(this));
      } catch (e) {}

      const result: VisionScheduleResult | null = await VisionScheduleHelper.parseScheduleFromImage(backendUrl, base64);
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
      .padding({ left: 12, right: 12, top: 6, bottom: 10 })
      .alignItems(VerticalAlign.Center)
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

  build() {
    Column() {
      this.TitleBarBuilder()

      List({ space: 0, scroller: this.scroller }) {
        ForEach(this.displayMessages, (msg: DisplayMessage, index: number) => {
          ListItem() {
            if (this.showToolCalls || (msg.role !== 'tool_call' && msg.role !== 'tool_result')) {
              this.MessageBubbleBuilder(msg, index as number)
            }
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

              Text('我可以回答问题，也能帮你执行操作\n如：查询课表、同步数据、创建日程等')
                .fontSize(14)
                .fontColor(ThemeManager.getTextSecondaryColor())
                .textAlign(TextAlign.Center)
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
