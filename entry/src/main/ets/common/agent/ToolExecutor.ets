import { CourseService } from '../../service/CourseService'
import { ExamService } from '../../service/ExamService'
import { GradeService } from '../../service/GradeService'
import { ScheduleService } from '../../service/ScheduleService'
import { SyncService, SyncResult, SyncAllResult, DownloadAllResult } from '../../service/SyncService'
import { AuthService } from '../../service/AuthService'
import { ReminderService } from '../../service/ReminderService'
import { ScheduleEvent, ScheduleUtils, ScheduleEventType } from '../../model/ScheduleModel'
import { Course, SECTION_TIMES } from '../../model/classTableModel/CourseModel'
import { getCurrentWeek } from '../../model/classTableModel/CourseModel'
import { ExamItem } from '../../model/classTableModel/ExamModel'
import { GradeItem } from '../../model/GradeModel'
import { AppConstants, RouterConstants } from '../constants/AppConstants'
import { router } from '@kit.ArkUI'

export interface ToolResult {
  success: boolean
  data: string
}

interface CourseItem {
  name: string
  time: string
  room: string
  teacher: string
}

interface TodayCoursesResult {
  count: number
  courses: CourseItem[]
}

interface WeekCoursesResult {
  week: number
  count: number
  schedule: Record<string, CourseItem[]>
}

interface CurrentWeekResult {
  currentWeek: number
  totalWeeks: number
}

interface NextExamResult {
  courseName: string
  examDate: string
  examTimeRange: string
  examLocation: string
  seatNo: string
  examType: string
  countdown: string
}

interface ExamItemResult {
  courseName: string
  examDate: string
  examTimeRange: string
  examLocation: string
  examType: string
  countdown: string
}

interface AllExamsResult {
  total: number
  upcoming: number
  exams: ExamItemResult[]
}

interface GradeItemResult {
  courseName: string
  credit: number
  totalScore: string
  gradePoint: number
  semesterId: number
}

interface GradesResult {
  overallGPA: string
  totalCourses: number
  grades: GradeItemResult[]
}

interface GpaResult {
  overallGPA: string
  latestSemesterGPA: string
  latestSemesterId: number
  totalCourses: number
}

interface ScheduleItemResult {
  title: string
  date: string
  timeRange: string
  location: string
  type: string
}

interface ScheduleResult {
  count: number
  events: ScheduleItemResult[]
}

interface LoginStatusResult {
  isLoggedIn: boolean
  email: string
}

interface ConflictResult {
  date: string
  timeRange: string
  hasConflict: boolean
}

interface CategorySetting {
  type: string
  enabled: boolean
  remindMinutes: number
}

interface ReminderSettingsResult {
  masterEnabled: boolean
  autoSyncSchedule: boolean
  categories: CategorySetting[]
}

interface HasCourseDataResult {
  hasCourseData: boolean
}

interface CreateScheduleResult {
  message: string
  title: string
  date: string
  timeRange: string
}

interface DeleteScheduleResult {
  message: string
  eventId: string
}

interface SyncResultData {
  message: string
  courseCount: number
}

interface ExamSyncResultData {
  message: string
  examCount: number
}

interface SyncAllResultData {
  message: string
  courseSync: SyncStatusItem
  examSync: SyncStatusItem
}

interface SyncStatusItem {
  success: boolean
  count: number
}

interface DownloadAllResultData {
  message: string
  courseDownload: SyncStatusItem
  examDownload: SyncStatusItem
}

interface ReminderToggleResult {
  message: string
}

interface RemindMinutesResult {
  message: string
}

interface RefreshResult {
  message: string
}

interface NavigateResult {
  message: string
}

export class ToolExecutor {
  private context: Context

  constructor(context: Context) {
    this.context = context
  }

  private getStringArg(args: Record<string, Object>, key: string, defaultValue: string = ''): string {
    const val: Object | undefined = args[key]
    if (val === undefined || val === null) {
      return defaultValue
    }
    return String(val)
  }

  private getNumberArg(args: Record<string, Object>, key: string, defaultValue: number = 0): number {
    const val: Object | undefined = args[key]
    if (val === undefined || val === null) {
      return defaultValue
    }
    return Number(val)
  }

  private getBooleanArg(args: Record<string, Object>, key: string, defaultValue: boolean = false): boolean {
    const val: Object | undefined = args[key]
    if (val === undefined || val === null) {
      return defaultValue
    }
    return Boolean(val)
  }

  async execute(toolName: string, args: Record<string, Object>): Promise<ToolResult> {
    try {
      switch (toolName) {
        case 'query_today_courses':
          return await this.queryTodayCourses()
        case 'query_week_courses':
          return await this.queryWeekCourses(args)
        case 'query_current_week':
          return this.queryCurrentWeek()
        case 'query_next_exam':
          return await this.queryNextExam()
        case 'query_all_exams':
          return await this.queryAllExams()
        case 'query_grades':
          return await this.queryGrades()
        case 'query_gpa':
          return await this.queryGpa()
        case 'query_schedule':
          return await this.querySchedule(args)
        case 'check_login_status':
          return await this.checkLoginStatus()
        case 'check_time_conflict':
          return await this.checkTimeConflict(args)
        case 'query_reminder_settings':
          return await this.queryReminderSettings()
        case 'has_course_data':
          return await this.hasCourseData()
        case 'create_schedule':
          return await this.createSchedule(args)
        case 'delete_schedule':
          return await this.deleteSchedule(args)
        case 'sync_courses_to_cloud':
          return await this.syncCoursesToCloud()
        case 'sync_exams_to_cloud':
          return await this.syncExamsToCloud()
        case 'sync_all_to_cloud':
          return await this.syncAllToCloud()
        case 'download_all_from_cloud':
          return await this.downloadAllFromCloud()
        case 'set_reminder_enabled':
          return await this.setReminderEnabled(args)
        case 'set_remind_minutes':
          return await this.setRemindMinutes(args)
        case 'refresh_reminders':
          return await this.refreshReminders()
        case 'navigate_to_page':
          return this.navigateToPage(args)
        default:
          return { success: false, data: `未知工具: ${toolName}` }
      }
    } catch (error) {
      return { success: false, data: `工具执行错误: ${String(error)}` }
    }
  }

  private formatSectionTime(startSection: number, duration: number): string {
    const sectionStr: string = duration > 1
      ? `第${startSection}-${startSection + duration - 1}节`
      : `第${startSection}节`
    const startIdx: number = startSection - 1
    const endIdx: number = startSection + duration - 2
    if (startIdx >= 0 && startIdx < SECTION_TIMES.length && endIdx >= 0 && endIdx < SECTION_TIMES.length) {
      const startTime: string = SECTION_TIMES[startIdx].startTime
      const endTime: string = SECTION_TIMES[endIdx].endTime
      return `${sectionStr} (${startTime}-${endTime})`
    }
    return sectionStr
  }

  private async queryTodayCourses(): Promise<ToolResult> {
    await CourseService.loadCourses(this.context)
    const dayOfWeek: number = new Date().getDay() || 7
    const weekNumber: number = getCurrentWeek()
    const courses: Course[] = CourseService.getCoursesForDayAndWeek(dayOfWeek, weekNumber)
    if (courses.length === 0) {
      return { success: true, data: '今天没有课程安排' }
    }
    const items: CourseItem[] = []
    for (let i = 0; i < courses.length; i++) {
      const c: Course = courses[i]
      const item: CourseItem = {
        name: c.name,
        time: this.formatSectionTime(c.time.startSection, c.time.duration),
        room: c.roomName,
        teacher: c.teacherName
      }
      items.push(item)
    }
    const result: TodayCoursesResult = { count: courses.length, courses: items }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryWeekCourses(args: Record<string, Object>): Promise<ToolResult> {
    await CourseService.loadCourses(this.context)
    let weekNumber: number = getCurrentWeek()
    const weekArg: Object | undefined = args['weekNumber']
    if (weekArg !== undefined && weekArg !== null) {
      weekNumber = this.getNumberArg(args, 'weekNumber', weekNumber)
    }
    const courses: Course[] = CourseService.getCoursesForWeek(weekNumber)
    if (courses.length === 0) {
      return { success: true, data: `第${weekNumber}周没有课程安排` }
    }
    const grouped: Record<string, CourseItem[]> = {}
    const dayNames: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日']
    for (let i = 0; i < courses.length; i++) {
      const c: Course = courses[i]
      const dayName: string = dayNames[c.time.dayOfWeek] || '未知'
      if (!grouped[dayName]) {
        grouped[dayName] = []
      }
      const item: CourseItem = {
        name: c.name,
        time: this.formatSectionTime(c.time.startSection, c.time.duration),
        room: c.roomName,
        teacher: c.teacherName
      }
      grouped[dayName].push(item)
    }
    const result: WeekCoursesResult = { week: weekNumber, count: courses.length, schedule: grouped }
    return { success: true, data: JSON.stringify(result) }
  }

  private queryCurrentWeek(): ToolResult {
    const weekNumber: number = getCurrentWeek()
    const maxWeek: number = CourseService.getMaxWeekNumber()
    const result: CurrentWeekResult = { currentWeek: weekNumber, totalWeeks: maxWeek }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryNextExam(): Promise<ToolResult> {
    const exams: ExamItem[] = await ExamService.loadExams(this.context)
    const nextExam: ExamItem | undefined = ExamService.getNextExam(exams)
    if (!nextExam) {
      return { success: true, data: '暂无即将到来的考试' }
    }
    const countdown: string = ExamService.formatCountDown(Date.now(), nextExam.beginTime)
    const result: NextExamResult = {
      courseName: nextExam.courseName,
      examDate: nextExam.examDate,
      examTimeRange: nextExam.examTimeRange,
      examLocation: nextExam.examLocation,
      seatNo: nextExam.seatNo,
      examType: nextExam.examType,
      countdown: countdown
    }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryAllExams(): Promise<ToolResult> {
    const exams: ExamItem[] = await ExamService.loadExams(this.context)
    if (exams.length === 0) {
      return { success: true, data: '暂无考试数据' }
    }
    const upcoming: ExamItem[] = ExamService.getUpcomingExams(exams)
    const items: ExamItemResult[] = []
    for (let i = 0; i < upcoming.length; i++) {
      const e: ExamItem = upcoming[i]
      const item: ExamItemResult = {
        courseName: e.courseName,
        examDate: e.examDate,
        examTimeRange: e.examTimeRange,
        examLocation: e.examLocation,
        examType: e.examType,
        countdown: ExamService.formatCountDown(Date.now(), e.beginTime)
      }
      items.push(item)
    }
    const result: AllExamsResult = { total: exams.length, upcoming: items.length, exams: items }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryGrades(): Promise<ToolResult> {
    const grades: GradeItem[] = await GradeService.loadGrades(this.context)
    if (grades.length === 0) {
      return { success: true, data: '暂无成绩数据' }
    }
    const overallGpa: number = GradeService.calculateOverallGPA(grades)
    const items: GradeItemResult[] = []
    for (let i = 0; i < grades.length; i++) {
      const g: GradeItem = grades[i]
      const item: GradeItemResult = {
        courseName: g.courseName,
        credit: g.credit,
        totalScore: g.totalScore,
        gradePoint: g.gradePoint,
        semesterId: g.semesterId
      }
      items.push(item)
    }
    const result: GradesResult = { overallGPA: overallGpa.toFixed(2), totalCourses: grades.length, grades: items }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryGpa(): Promise<ToolResult> {
    const grades: GradeItem[] = await GradeService.loadGrades(this.context)
    if (grades.length === 0) {
      return { success: true, data: '暂无成绩数据，无法计算GPA' }
    }
    const overallGpa: number = GradeService.calculateOverallGPA(grades)
    const latestGpa: number = GradeService.getLatestSemesterGPA(grades)
    const latestId: number = GradeService.getLatestSemesterId(grades)
    const result: GpaResult = {
      overallGPA: overallGpa.toFixed(2),
      latestSemesterGPA: latestGpa.toFixed(2),
      latestSemesterId: latestId,
      totalCourses: grades.length
    }
    return { success: true, data: JSON.stringify(result) }
  }

  private async querySchedule(args: Record<string, Object>): Promise<ToolResult> {
    const allEvents: ScheduleEvent[] = await ScheduleService.getAllEvents(this.context)
    if (allEvents.length === 0) {
      return { success: true, data: '暂无日程安排' }
    }
    let filteredEvents: ScheduleEvent[] = allEvents
    const dateArg: string = this.getStringArg(args, 'date')
    if (dateArg.length > 0) {
      filteredEvents = allEvents.filter((e: ScheduleEvent) => e.date === dateArg)
      if (filteredEvents.length === 0) {
        return { success: true, data: `${dateArg} 没有日程安排` }
      }
    }
    const items: ScheduleItemResult[] = []
    for (let i = 0; i < filteredEvents.length; i++) {
      const evt: ScheduleEvent = filteredEvents[i]
      const item: ScheduleItemResult = {
        title: evt.title,
        date: evt.date,
        timeRange: evt.timeRange || ScheduleUtils.formatTimeRange(evt.startTime || '', evt.endTime || ''),
        location: evt.location,
        type: evt.type
      }
      items.push(item)
    }
    const result: ScheduleResult = { count: items.length, events: items }
    return { success: true, data: JSON.stringify(result) }
  }

  private async checkLoginStatus(): Promise<ToolResult> {
    const loggedIn: boolean = await AuthService.isLoggedIn(this.context)
    if (loggedIn) {
      const userId: string | undefined = await AuthService.getLoginUserId(this.context)
      const result: LoginStatusResult = { isLoggedIn: true, email: userId || '' }
      return { success: true, data: JSON.stringify(result) }
    }
    const result: LoginStatusResult = { isLoggedIn: false, email: '' }
    return { success: true, data: JSON.stringify(result) }
  }

  private async checkTimeConflict(args: Record<string, Object>): Promise<ToolResult> {
    const date: string = this.getStringArg(args, 'date')
    const startTime: string = this.getStringArg(args, 'startTime')
    const endTime: string = this.getStringArg(args, 'endTime')
    const newEvent: ScheduleEvent = ScheduleUtils.createEmptyEvent()
    newEvent.date = date
    newEvent.startTime = startTime
    newEvent.endTime = endTime
    const hasConflict: boolean = await ScheduleService.checkTimeConflict(this.context, newEvent)
    const result: ConflictResult = { date: date, timeRange: `${startTime}-${endTime}`, hasConflict: hasConflict }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryReminderSettings(): Promise<ToolResult> {
    const masterEnabled: boolean = await ReminderService.getGlobalScheduleReminderEnabled(this.context)
    const types: ScheduleEventType[] = ['exam', 'course', 'custom', 'assignment']
    const categories: CategorySetting[] = []
    for (let i = 0; i < types.length; i++) {
      const t: ScheduleEventType = types[i]
      const enabled: boolean = await ReminderService.getCategoryReminderEnabled(this.context, t)
      const minutes: number = await ReminderService.getCategoryRemindMinutes(this.context, t)
      const cat: CategorySetting = { type: t, enabled: enabled, remindMinutes: minutes }
      categories.push(cat)
    }
    const autoSync: boolean = await ReminderService.getAutoSyncScheduleEnabled(this.context)
    const result: ReminderSettingsResult = { masterEnabled: masterEnabled, autoSyncSchedule: autoSync, categories: categories }
    return { success: true, data: JSON.stringify(result) }
  }

  private async hasCourseData(): Promise<ToolResult> {
    const hasData: boolean = await CourseService.hasCourseData(this.context)
    const result: HasCourseDataResult = { hasCourseData: hasData }
    return { success: true, data: JSON.stringify(result) }
  }

  private async createSchedule(args: Record<string, Object>): Promise<ToolResult> {
    const title: string = this.getStringArg(args, 'title')
    const date: string = this.getStringArg(args, 'date')
    const startTime: string = this.getStringArg(args, 'startTime')
    const endTime: string = this.getStringArg(args, 'endTime')
    const location: string = this.getStringArg(args, 'location')
    const description: string = this.getStringArg(args, 'description')
    const typeStr: string = this.getStringArg(args, 'type', 'custom')
    const eventType: ScheduleEventType = (typeStr === 'assignment') ? 'assignment' : 'custom'
    const event: ScheduleEvent = {
      id: '',
      title: title,
      date: date,
      timeRange: `${startTime}-${endTime}`,
      startTime: startTime,
      endTime: endTime,
      location: location,
      type: eventType,
      color: ScheduleUtils.getTypeColor(eventType),
      sourceId: '',
      description: description,
      createdAt: Date.now()
    }
    await ScheduleService.saveSchedule(this.context, event)
    const result: CreateScheduleResult = { message: '日程创建成功', title: title, date: date, timeRange: event.timeRange }
    return { success: true, data: JSON.stringify(result) }
  }

  private async deleteSchedule(args: Record<string, Object>): Promise<ToolResult> {
    const eventId: string = this.getStringArg(args, 'eventId')
    await ScheduleService.deleteSchedule(this.context, eventId)
    const result: DeleteScheduleResult = { message: '日程已删除', eventId: eventId }
    return { success: true, data: JSON.stringify(result) }
  }

  private async syncCoursesToCloud(): Promise<ToolResult> {
    const userId: string | undefined = await AuthService.getLoginUserId(this.context)
    if (!userId) {
      return { success: false, data: '未登录，请先登录后再同步' }
    }
    const syncRes: SyncResult = await SyncService.syncCoursesToCloud(this.context, userId)
    if (syncRes.success) {
      const result: SyncResultData = { message: '课表同步成功', courseCount: syncRes.courseCount || 0 }
      return { success: true, data: JSON.stringify(result) }
    }
    return { success: false, data: `课表同步失败: ${syncRes.error || '未知错误'}` }
  }

  private async syncExamsToCloud(): Promise<ToolResult> {
    const userId: string | undefined = await AuthService.getLoginUserId(this.context)
    if (!userId) {
      return { success: false, data: '未登录，请先登录后再同步' }
    }
    const syncRes: SyncResult = await SyncService.syncExamsToCloud(this.context, userId)
    if (syncRes.success) {
      const result: ExamSyncResultData = { message: '考试同步成功', examCount: syncRes.examCount || 0 }
      return { success: true, data: JSON.stringify(result) }
    }
    return { success: false, data: `考试同步失败: ${syncRes.error || '未知错误'}` }
  }

  private async syncAllToCloud(): Promise<ToolResult> {
    const userId: string | undefined = await AuthService.getLoginUserId(this.context)
    if (!userId) {
      return { success: false, data: '未登录，请先登录后再同步' }
    }
    const syncRes: SyncAllResult = await SyncService.syncAllToCloud(this.context, userId)
    const courseItem: SyncStatusItem = { success: syncRes.courses.success, count: syncRes.courses.courseCount || 0 }
    const examItem: SyncStatusItem = { success: syncRes.exams.success, count: syncRes.exams.examCount || 0 }
    const result: SyncAllResultData = { message: '全量同步完成', courseSync: courseItem, examSync: examItem }
    return { success: true, data: JSON.stringify(result) }
  }

  private async downloadAllFromCloud(): Promise<ToolResult> {
    const userId: string | undefined = await AuthService.getLoginUserId(this.context)
    if (!userId) {
      return { success: false, data: '未登录，请先登录后再恢复数据' }
    }
    const dlRes: DownloadAllResult = await SyncService.downloadAllFromCloud(this.context, userId)
    const courseItem: SyncStatusItem = { success: dlRes.courses.success, count: dlRes.courses.courseCount || 0 }
    const examItem: SyncStatusItem = { success: dlRes.exams.success, count: dlRes.exams.examCount || 0 }
    const result: DownloadAllResultData = { message: '云端数据恢复完成', courseDownload: courseItem, examDownload: examItem }
    return { success: true, data: JSON.stringify(result) }
  }

  private async setReminderEnabled(args: Record<string, Object>): Promise<ToolResult> {
    const typeStr: string = this.getStringArg(args, 'type')
    const enabled: boolean = this.getBooleanArg(args, 'enabled')
    const validTypes: string[] = ['exam', 'course', 'custom', 'assignment']
    if (validTypes.indexOf(typeStr) === -1) {
      return { success: false, data: `无效的类型: ${typeStr}，有效值为: exam, course, custom, assignment` }
    }
    await ReminderService.saveCategoryReminderEnabled(this.context, typeStr as ScheduleEventType, enabled)
    const result: ReminderToggleResult = { message: `${typeStr}提醒已${enabled ? '开启' : '关闭'}` }
    return { success: true, data: JSON.stringify(result) }
  }

  private async setRemindMinutes(args: Record<string, Object>): Promise<ToolResult> {
    const typeStr: string = this.getStringArg(args, 'type')
    const minutes: number = this.getNumberArg(args, 'minutes')
    const validTypes: string[] = ['exam', 'course', 'custom', 'assignment']
    if (validTypes.indexOf(typeStr) === -1) {
      return { success: false, data: `无效的类型: ${typeStr}，有效值为: exam, course, custom, assignment` }
    }
    await ReminderService.saveCategoryRemindMinutes(this.context, typeStr as ScheduleEventType, minutes)
    const result: RemindMinutesResult = { message: `${typeStr}提醒时间已设为提前${minutes}分钟` }
    return { success: true, data: JSON.stringify(result) }
  }

  private async refreshReminders(): Promise<ToolResult> {
    await ReminderService.refreshAllReminders(this.context)
    const result: RefreshResult = { message: '提醒已刷新' }
    return { success: true, data: JSON.stringify(result) }
  }

  private navigateToPage(args: Record<string, Object>): ToolResult {
    const page: string = this.getStringArg(args, 'page')
    let route: string = ''
    switch (page) {
      case 'course_table':
        route = RouterConstants.PAGE_TABLE_UI
        break
      case 'exam':
        route = RouterConstants.PAGE_EXAM
        break
      case 'grade':
        route = RouterConstants.PAGE_GRADE
        break
      case 'schedule':
        route = RouterConstants.PAGE_CALENDAR
        break
      case 'settings':
        route = RouterConstants.PAGE_SETTINGS
        break
      default:
        return { success: false, data: `未知页面: ${page}` }
    }
    router.pushUrl({ url: route })
    const result: NavigateResult = { message: `正在导航到${page}页面` }
    return { success: true, data: JSON.stringify(result) }
  }
}
