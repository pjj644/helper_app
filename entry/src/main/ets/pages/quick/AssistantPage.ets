import { preferences } from '@kit.ArkData';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { AppConstants } from '../../common/constants/AppConstants';
import { ToolRegistry } from '../../common/agent/ToolRegistry';
import { ToolExecutor } from '../../common/agent/ToolExecutor';
import { AgentOrchestrator, AgentCallbacks, AgentMessage } from '../../common/agent/AgentOrchestrator';

const MAX_HISTORY_ROUNDS: number = 10;
const SYSTEM_PROMPT: string =
  '你是"成电校园助手"App的内置AI Agent，专为UESTC(电子科技大学)学生服务。你不仅能回答问题，还能直接执行应用内操作。\n' +
  '本App主要功能：课表查看与导入、考试查询与倒计时、成绩查询与GPA计算、日程管理与提醒、云同步、快捷校园工具、个性化设置。\n\n' +
  '你可以使用以下工具来帮助用户：\n' +
  '查询类工具（无需确认）：\n' +
  '- query_today_courses: 查询今天的课程安排\n' +
  '- query_week_courses: 查询本周课程安排\n' +
  '- query_current_week: 查询当前教学周\n' +
  '- query_next_exam: 查询最近一场考试及倒计时\n' +
  '- query_all_exams: 查询所有考试安排\n' +
  '- query_grades: 查询成绩列表\n' +
  '- query_gpa: 查询GPA\n' +
  '- query_schedule: 查询日程安排\n' +
  '- check_login_status: 检查登录状态\n' +
  '- check_time_conflict: 检查时间冲突\n' +
  '- query_reminder_settings: 查询提醒设置\n' +
  '- has_course_data: 检查是否有课表数据\n\n' +
  '操作类工具（需用户确认）：\n' +
  '- create_schedule: 创建日程\n' +
  '- delete_schedule: 删除日程\n' +
  '- sync_courses_to_cloud: 同步课表到云端\n' +
  '- sync_exams_to_cloud: 同步考试到云端\n' +
  '- sync_all_to_cloud: 全量同步到云端\n' +
  '- download_all_from_cloud: 从云端恢复数据\n' +
  '- set_reminder_enabled: 设置提醒开关\n' +
  '- set_remind_minutes: 设置提醒时间\n' +
  '- refresh_reminders: 刷新提醒\n\n' +
  '导航类工具：\n' +
  '- navigate_to_page: 导航到应用内页面\n\n' +
  '使用原则：\n' +
  '1. 优先使用工具获取实时数据，不要凭记忆回答数据类问题\n' +
  '2. 操作类工具需要用户确认后才会执行\n' +
  '3. 多步骤任务可以连续调用多个工具\n' +
  '4. 如果工具执行失败，向用户说明原因并建议解决方案\n' +
  '5. 只回答与本App相关的问题，非本App问题礼貌拒绝\n' +
  '6. 用中文简洁回答\n' +
  '7. 不透露模型信息';

const APP_KNOWLEDGE: string =
  '【App整体结构】\n' +
  '- 底部4个Tab：首页、课表、发现、我的\n' +
  '- 深色模式支持三种：浅色/深色/跟随系统（在应用设置中切换）\n' +
  '- 登录方式：华为AGConnect邮箱验证码登录\n\n' +

  '【首页Tab】\n' +
  '- 顶部Hero卡片：显示当前教学周数、智能提示语（最近考试提醒/今日课程数/未导入课表引导）\n' +
  '- 快捷统计：今日课程数、待考科目数、本周课程数\n' +
  '- 考试倒计时：显示最近一场考试的实时倒计时（天/时/分/秒），紧急度颜色渐变（3天内红色/7天内橙色/7天以上蓝色）\n' +
  '- 今日/明日课程卡片：课程名、节次时间、教室、教师\n' +
  '- 底部快捷入口：课表详情、考试详情、日程\n\n' +

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
  '- 月历视图：7列月历网格，日期下方彩色圆点标记(蓝=课程/红=考试/橙=自定义/紫=作业)\n' +
  '- 日程CRUD：4种类型(考试/课程/自定义/作业)，支持标题、描述、日期、开始/结束时间、地点\n' +
  '- 提醒设置：每条日程可独立设置提醒时间(5/10/15/30分钟前/1小时前/使用默认/关闭)\n' +
  '- 添加到日历：每条日程可开启"添加到系统日历"开关，同步到手机系统日历\n' +
  '- 冲突检测：自动检测同日时间段重叠，冲突事件显示红色"冲突"标签\n' +
  '- 提醒系统：总开关+四类独立开关(考试/课程/自定义/作业)+每类独立提醒时间\n' +
  '- 双提醒机制：优先使用后台代理提醒(Agent Reminder)，不可用时降级为系统日历(CalendarKit)\n' +
  '- 自动同步：开启时自动将课程和考试同步为日程事件\n' +
  '- 日程设置面板：在日历页面右上角设置图标进入，可配置提醒开关和时间\n\n' +

  '【发现Tab】\n' +
  '- 最近使用：成绩查询、校园日历、图书馆三个快捷入口\n' +
  '- 所有功能网格(11个工具)：\n' +
  '  AI助手、校园地图(gis.uestc.edu.cn)、图书馆(lib.uestc.edu.cn)、\n' +
  '  校园卡(开发中)、计算器(开发中)、天气(开发中)、\n' +
  '  成绩查询、空教室(开发中)、校园日历、清水河畔(bbs.uestc.edu.cn)、一卡通余额\n' +
  '- Web页面工具右上角有刷新按钮\n\n' +

  '【我的Tab】\n' +
  '- 用户卡片：显示头像、登录状态(已登录显示邮箱+绿色标识/未登录显示"未登录，点击登录")\n' +
  '- 未登录点击用户卡片跳转登录页，已登录点击跳转账号管理\n' +
  '- 菜单项：个人信息(开发中)、账号设置(跳转AccountManage)、应用设置(跳转AppSettings)、意见反馈(开发中)、关于应用(开发中)\n\n' +

  '【登录与账号】\n' +
  '- 登录方式：华为AGConnect邮箱验证码登录\n' +
  '- 登录入口：我的Tab用户卡片(未登录时)、应用设置中的账号管理卡片\n' +
  '- 账号管理页：显示登录邮箱、最近登录时间、退出登录按钮\n' +
  '- 登录后自动返回上一页，UI自动刷新登录状态\n\n' +

  '【云同步】\n' +
  '- 上传：课表和考试按学期增量同步到云端(AGConnect CloudDB)，需登录\n' +
  '- 下载：从云端恢复数据到本地，当前学期数据同时写入主存储\n' +
  '- 限流重试：检测限流错误码，指数退避重试\n\n' +

  '【应用设置】(AppSettings页面)\n' +
  '- 账号管理：查看登录状态，登录/管理账号\n' +
  '- 数据同步：上传/下载云端数据\n' +
  '- 沉浸光感效果：启用开关+材质级别(自适应/精致/轻柔/流畅)+高级模糊设置(模糊强度/材质样式/边框样式/饱和度/亮度/透明度/阴影)\n' +
  '- 动画效果：启用开关+速度(快速/标准/慢速)+曲线(线性/平滑/弹性/Q弹)+强度\n' +
  '- 背景图片：自定义背景开关+从相册选择图片+预览+删除\n' +
  '- 显示设置：首页显示今日课程/明日课程/考试倒计时开关+自动创建日程开关\n' +
  '- 其他：消息通知开关+自动更新开关+深色模式(浅色/深色/跟随系统)\n\n' +

  '【功能导航】(FeatureNav页面)\n' +
  '- 最近使用：显示最近访问的功能链接(最多8条)\n' +
  '- 功能链接：教务系统首页、考试信息、图书馆、信息门户、研究生系统、学校官网\n' +
  '- 点击链接通过内嵌WebView打开，非校园网自动启用VPN\n\n' +

  '【数据存储】\n' +
  '- 本地：HarmonyOS Preferences 持久化存储\n' +
  '- 云端：AGConnect CloudDB 增量同步\n' +
  '- 提醒数据：后台代理提醒 + 系统日历事件，日程与系统日历保持一致(先清后建策略)';

const DETAIL_KEYWORDS: string[] = [
  '怎么', '如何', '功能', '课表', '课程', '考试', '成绩', 'GPA', 'gpa',
  '日程', '日历', '导入', '提醒', '同步', '设置', '登录', '深色', '主题',
  '工具', '地图', '图书馆', 'VPN', 'vpn', '教务', '倒计时', '冲突',
  '云', '账号', '邮箱', '颜色', '周', '节', '学分', '绩点',
  '能做', '有什么', '介绍', '帮助', '使用', '操作', '在哪', '哪里',
  '首页', '发现', '我的', '背景', '动画', '模糊', '光感', '材质',
  '日历同步', '系统日历', '通知', '深色模式', '退出', '登出',
  'Hero', '统计', '快捷', '功能导航', '最近使用',
  '今天', '明天', '本周', '下周', '查询', '查看', '帮我', '给我',
  '打开', '跳转', '去', '创建', '添加', '删除', '上传', '下载', '恢复'
];

interface Message {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

interface DisplayMessage {
  role: string;
  content: string;
  isError: boolean;
  toolName?: string;
  toolArgs?: string;
  toolResult?: string;
  isToolSuccess?: boolean;
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
  @State showConfirmDialog: boolean = false;
  @State confirmToolName: string = '';
  @State confirmToolArgs: string = '';
  @State confirmRiskLevel: string = 'low';
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  private scroller: Scroller = new Scroller();
  private dotTimer: number = -1;
  private confirmResolve: ((value: boolean) => void) | null = null;
  private currentOrchestrator: AgentOrchestrator | null = null;

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

  private getToolDisplayName(toolName: string): string {
    const nameMap: Record<string, string> = {
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
      'navigate_to_page': '导航到页面'
    };
    return nameMap[toolName] || toolName;
  }

  private formatToolResult(toolName: string, result: string): string {
    try {
      switch (toolName) {
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
      this.confirmToolName = toolName;
      this.confirmToolArgs = args;
      this.confirmRiskLevel = ToolRegistry.getRiskLevel(toolName);
      this.confirmResolve = resolve;
      this.showConfirmDialog = true;
    });
  }

  private onConfirmDialogResult(confirmed: boolean): void {
    this.showConfirmDialog = false;
    if (this.confirmResolve) {
      this.confirmResolve(confirmed);
      this.confirmResolve = null;
    }
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

    let systemContent: string = SYSTEM_PROMPT;
    if (this.needsDetailedContext(userInput)) {
      systemContent = SYSTEM_PROMPT + '\n\n以下是本App详细功能文档，请据此回答：\n' + APP_KNOWLEDGE;
    }

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
          self.scrollToBottom();
        }
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
      onComplete: () => {
        self.isLoading = false;
        const lastAssistantMsg: DisplayMessage | undefined = self.findLastAssistantMessage();
        if (lastAssistantMsg && lastAssistantMsg.content.length > 0) {
          self.messages = [...self.messages, { role: 'assistant', content: lastAssistantMsg.content }];
        }
        self.updateCurrentSessionTimestamp();
        self.syncCurrentSession();
        self.saveSessions();
        self.scrollToBottom();
      }
    };

    const orchestrator: AgentOrchestrator = new AgentOrchestrator(executor, callbacks);
    this.currentOrchestrator = orchestrator;

    const history: AgentMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      history.push({ role: this.messages[i].role, content: this.messages[i].content });
    }

    orchestrator.runStream(systemContent, history);
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
        Column() {
          Row({ space: 6 }) {
            Text('🔧')
              .fontSize(14)
            Text(msg.content)
              .fontSize(13)
              .fontColor(ThemeManager.getTextSecondaryColor())
          }
        }
        .constraintSize({ maxWidth: '85%' })
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(12)
        .backgroundColor(this.isDarkMode ? '#1A2A3A' : '#E8F4FD')
        .alignItems(HorizontalAlign.Start)
      } else if (msg.role === 'tool_result') {
        Column() {
          Row({ space: 6 }) {
            Text(msg.isToolSuccess ? '✅' : '❌')
              .fontSize(14)
            Text(msg.content)
              .fontSize(13)
              .fontColor(msg.isToolSuccess ? ThemeManager.getTextPrimaryColor() : '#FF3B30')
          }
          if (msg.isToolSuccess && msg.toolResult && msg.toolResult.length > 0 && msg.toolName) {
            Text(this.formatToolResult(msg.toolName, msg.toolResult))
              .fontSize(13)
              .fontColor(ThemeManager.getTextSecondaryColor())
              .margin({ top: 6 })
              .maxLines(20)
              .lineHeight(20)
          }
        }
        .constraintSize({ maxWidth: '85%' })
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(12)
        .backgroundColor(msg.isToolSuccess ? (this.isDarkMode ? '#1A2E1A' : '#E8F5E9') : (this.isDarkMode ? '#2E1A1A' : '#FFEBEE'))
        .alignItems(HorizontalAlign.Start)
      } else {
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
      }

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

  @Builder
  private ConfirmDialogBuilder(): void {
    Column() {
      Column() {
        Text('操作确认')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .margin({ bottom: 12 })

        Text(`AI助手请求执行操作：${this.getToolDisplayName(this.confirmToolName)}`)
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .margin({ bottom: 8 })

        if (this.confirmRiskLevel === 'high') {
          Text('⚠️ 此操作涉及数据变更，请谨慎确认')
            .fontSize(13)
            .fontColor('#FF9500')
            .margin({ bottom: 8 })
        }

        if (this.confirmToolArgs.length > 0) {
          Text(this.confirmToolArgs.length > 300 ? this.confirmToolArgs.substring(0, 300) + '...' : this.confirmToolArgs)
            .fontSize(13)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .margin({ bottom: 16 })
            .maxLines(5)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row({ space: 12 }) {
          Button('拒绝')
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .backgroundColor(ThemeManager.getCardColor())
            .borderRadius(12)
            .onClick(() => {
              this.onConfirmDialogResult(false);
            })

          Button('允许')
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor(this.confirmRiskLevel === 'high' ? '#FF9500' : '#007AFF')
            .borderRadius(12)
            .onClick(() => {
              this.onConfirmDialogResult(true);
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .borderRadius(20)
      .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0, 0, 0, 0.4)')
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
    .bindContentCover(this.showConfirmDialog, this.ConfirmDialogBuilder(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        if (this.confirmResolve) {
          this.confirmResolve(false);
          this.confirmResolve = null;
        }
      }
    })
  }
}
