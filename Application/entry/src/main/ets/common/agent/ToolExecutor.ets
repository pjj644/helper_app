import { CourseService } from '../../service/CourseService'
import { ExamService } from '../../service/ExamService'
import { GradeService } from '../../service/GradeService'
import { ScheduleService } from '../../service/ScheduleService'
import { SyncService, SyncResult, SyncAllResult, DownloadAllResult } from '../../service/SyncService'
import { AuthService } from '../../service/AuthService'
import { ReminderService } from '../../service/ReminderService'
import { CalendarKitReminderService, CalendarEventSummary } from '../../service/CalendarKitReminderService'
import { ScheduleEvent, ScheduleUtils, ScheduleEventType } from '../../model/ScheduleModel'
import { Course, SECTION_TIMES, getCurrentWeek, getWeekForDate } from '../../model/classTableModel/CourseModel'
import { ExamItem } from '../../model/classTableModel/ExamModel'
import { GradeItem } from '../../model/GradeModel'
import { calculateSemesterId, getSemesterLabelById } from '../../model/classTableModel/ExamAccessRules'
import { AppConstants, RouterConstants } from '../constants/AppConstants'
import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'

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
  id: string
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

interface CurrentDatetimeResult {
  date: string
  time: string
  dayOfWeek: number
  dayOfWeekLabel: string
  currentWeek: number
  totalWeeks: number
  semesterId: number
  semesterLabel: string
}

interface CoursesByDateResult {
  date: string
  dayOfWeek: number
  week: number
  count: number
  courses: CourseItem[]
}

interface CourseSessionItem {
  dayOfWeek: number
  dayLabel: string
  time: string
  room: string
  teacher: string
  weeks: number[]
}

interface CourseByNameResult {
  courseName: string
  matchCount: number
  sessions: CourseSessionItem[]
}

interface CalendarEventItem {
  id: number
  title: string
  startTime: number
  endTime: number
  location: string
}

interface CalendarEventsResult {
  count: number
  events: CalendarEventItem[]
}

interface AddToCalendarResult {
  message: string
  scheduleEventId: string
  calendarEventId: number
  calendarAdded: boolean
}

interface AddExamToCalendarResult {
  message: string
  courseName: string
  examDate: string
  examTimeRange: string
  calendarEventId: number
  calendarAdded: boolean
}

interface AddCourseToCalendarResult {
  message: string
  date: string
  addedCount: number
  calendarEventIds: number[]
}

interface RemoveCalendarEventResult {
  message: string
  calendarEventId: number
}

interface UpdateScheduleResult {
  message: string
  eventId: string
}

interface UpcomingExamStudyItem {
  courseName: string
  date: string
  time: string
  daysLeft: number
  recommendedDailyHours: number
}

interface StudyPlanResultData {
  totalExams: number
  dailyHours: number
  focusCourse: string
  strategy: string
  upcomingExams: UpcomingExamStudyItem[]
}

interface GuideItem {
  title: string
  category: string
  content: string
  details?: string
}

interface GuideResultData {
  category: string
  keyword: string
  count: number
  guides: GuideItem[]
}

interface ParseResultData {
  status: string
  rawLength: number
  hint: string
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
        case 'get_current_datetime':
          return await this.getCurrentDatetime()
        case 'query_courses_by_date':
          return await this.queryCoursesByDate(args)
        case 'query_tomorrow_courses':
          return await this.queryTomorrowCourses()
        case 'query_course_by_name':
          return await this.queryCourseByName(args)
        case 'list_calendar_events':
          return await this.listCalendarEvents(args)
        case 'add_to_calendar':
          return await this.addToCalendar(args)
        case 'add_exam_to_calendar':
          return await this.addExamToCalendar(args)
        case 'add_course_to_calendar':
          return await this.addCourseToCalendar(args)
        case 'remove_calendar_event':
          return await this.removeCalendarEvent(args)
        case 'update_schedule':
          return await this.updateSchedule(args)
        case 'generate_study_plan':
          return await this.generateStudyPlan(args)
        case 'query_campus_guide':
          return this.queryCampusGuide(args)
        case 'parse_text_to_schedule':
          return this.parseTextToSchedule(args)
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
        id: evt.id,
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
      case 'course_import':
        route = RouterConstants.PAGE_COURSE_IMPORT
        break
      case 'exam_import':
        route = RouterConstants.PAGE_EXAM_IMPORT
        break
      case 'grade_import':
        route = 'pages/gradePages/GradeImport'
        break
      case 'assistant':
        route = RouterConstants.PAGE_ASSISTANT
        break
      case 'home':
        route = RouterConstants.PAGE_INDEX
        break
      default:
        return { success: false, data: `未知页面: ${page}` }
    }
    router.pushUrl({ url: route })
    const result: NavigateResult = { message: `正在导航到${page}页面` }
    return { success: true, data: JSON.stringify(result) }
  }

  private dayLabel(dayOfWeek: number): string {
    const labels: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日']
    return labels[dayOfWeek] || '未知'
  }

  private parseDate(dateStr: string): Date | null {
    const parts: string[] = dateStr.split('-')
    if (parts.length !== 3) {
      return null
    }
    return new Date(
      Number.parseInt(parts[0], 10),
      Number.parseInt(parts[1], 10) - 1,
      Number.parseInt(parts[2], 10)
    )
  }

  private async ensureCalendarPermission(): Promise<boolean> {
    const uiContext: common.UIAbilityContext = this.context as common.UIAbilityContext
    const granted: boolean = await CalendarKitReminderService.checkCalendarPermission(uiContext)
    if (granted) {
      return true
    }
    return await CalendarKitReminderService.requestCalendarPermission(uiContext)
  }

  private async getCurrentDatetime(): Promise<ToolResult> {
    const now: Date = new Date()
    const date: string = ScheduleUtils.formatDate(now.getFullYear(), now.getMonth() + 1, now.getDate())
    const time: string = `${ScheduleUtils.twoDigit(now.getHours())}:${ScheduleUtils.twoDigit(now.getMinutes())}`
    const dayOfWeek: number = now.getDay() || 7
    const currentWeek: number = getCurrentWeek()
    await CourseService.loadCourses(this.context)
    const totalWeeks: number = CourseService.getMaxWeekNumber()
    const semesterId: number = calculateSemesterId()
    const semesterLabel: string = getSemesterLabelById(semesterId)
    const result: CurrentDatetimeResult = {
      date: date,
      time: time,
      dayOfWeek: dayOfWeek,
      dayOfWeekLabel: this.dayLabel(dayOfWeek),
      currentWeek: currentWeek,
      totalWeeks: totalWeeks,
      semesterId: semesterId,
      semesterLabel: semesterLabel,
    }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryCoursesByDate(args: Record<string, Object>): Promise<ToolResult> {
    const dateStr: string = this.getStringArg(args, 'date')
    if (dateStr.length === 0) {
      return { success: false, data: '缺少date参数，格式YYYY-MM-DD' }
    }
    const target: Date | null = this.parseDate(dateStr)
    if (!target) {
      return { success: false, data: `日期格式错误: ${dateStr}，应为YYYY-MM-DD` }
    }
    const dayOfWeek: number = target.getDay() || 7
    const weekNumber: number = getWeekForDate(target)
    await CourseService.loadCourses(this.context)
    const courses: Course[] = CourseService.getCoursesForDayAndWeek(dayOfWeek, weekNumber)
    if (courses.length === 0) {
      return { success: true, data: `${dateStr}（第${weekNumber}周 ${this.dayLabel(dayOfWeek)}）没有课程安排` }
    }
    const items: CourseItem[] = []
    for (let i = 0; i < courses.length; i++) {
      const c: Course = courses[i]
      items.push({
        name: c.name,
        time: this.formatSectionTime(c.time.startSection, c.time.duration),
        room: c.roomName,
        teacher: c.teacherName,
      })
    }
    const result: CoursesByDateResult = {
      date: dateStr,
      dayOfWeek: dayOfWeek,
      week: weekNumber,
      count: courses.length,
      courses: items,
    }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryTomorrowCourses(): Promise<ToolResult> {
    const tomorrow: Date = new Date()
    tomorrow.setDate(tomorrow.getDate() + 1)
    const dayOfWeek: number = tomorrow.getDay() || 7
    const weekNumber: number = getWeekForDate(tomorrow)
    const dateStr: string = ScheduleUtils.formatDate(tomorrow.getFullYear(), tomorrow.getMonth() + 1, tomorrow.getDate())
    await CourseService.loadCourses(this.context)
    const courses: Course[] = CourseService.getCoursesForDayAndWeek(dayOfWeek, weekNumber)
    if (courses.length === 0) {
      return { success: true, data: `明天(${dateStr} 第${weekNumber}周 ${this.dayLabel(dayOfWeek)})没有课程安排` }
    }
    const items: CourseItem[] = []
    for (let i = 0; i < courses.length; i++) {
      const c: Course = courses[i]
      items.push({
        name: c.name,
        time: this.formatSectionTime(c.time.startSection, c.time.duration),
        room: c.roomName,
        teacher: c.teacherName,
      })
    }
    const result: CoursesByDateResult = {
      date: dateStr,
      dayOfWeek: dayOfWeek,
      week: weekNumber,
      count: courses.length,
      courses: items,
    }
    return { success: true, data: JSON.stringify(result) }
  }

  private async queryCourseByName(args: Record<string, Object>): Promise<ToolResult> {
    const courseName: string = this.getStringArg(args, 'courseName')
    if (courseName.length === 0) {
      return { success: false, data: '缺少courseName参数' }
    }
    const allCourses: Course[] = await CourseService.loadCourses(this.context)
    const keyword: string = courseName.toLowerCase()
    const matched: Course[] = []
    for (let i = 0; i < allCourses.length; i++) {
      if (allCourses[i].name.toLowerCase().includes(keyword)) {
        matched.push(allCourses[i])
      }
    }
    if (matched.length === 0) {
      return { success: true, data: `未找到包含"${courseName}"的课程` }
    }
    const sessions: CourseSessionItem[] = []
    for (let i = 0; i < matched.length; i++) {
      const c: Course = matched[i]
      const weeks: number[] = []
      const vw: string = c.validWeeks || ''
      for (let w = 1; w < vw.length; w++) {
        if (vw.charAt(w) === '1') {
          weeks.push(w)
        }
      }
      sessions.push({
        dayOfWeek: c.time.dayOfWeek,
        dayLabel: this.dayLabel(c.time.dayOfWeek),
        time: this.formatSectionTime(c.time.startSection, c.time.duration),
        room: c.roomName,
        teacher: c.teacherName,
        weeks: weeks,
      })
    }
    const result: CourseByNameResult = {
      courseName: courseName,
      matchCount: matched.length,
      sessions: sessions,
    }
    return { success: true, data: JSON.stringify(result) }
  }

  private async listCalendarEvents(args: Record<string, Object>): Promise<ToolResult> {
    const now: Date = new Date()
    const todayStart: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const startStr: string = this.getStringArg(args, 'startDate')
    const endStr: string = this.getStringArg(args, 'endDate')
    let startMs: number = todayStart
    let endMs: number = todayStart + 30 * 24 * 60 * 60 * 1000
    if (startStr.length > 0) {
      const d: Date | null = this.parseDate(startStr)
      if (d) {
        startMs = d.getTime()
      }
    }
    if (endStr.length > 0) {
      const d: Date | null = this.parseDate(endStr)
      if (d) {
        endMs = d.getTime()
      }
    }
    const hasPerm: boolean = await this.ensureCalendarPermission()
    if (!hasPerm) {
      return { success: false, data: '未授予日历权限，无法读取系统日历' }
    }
    const events: CalendarEventSummary[] = await CalendarKitReminderService.listEvents(this.context, startMs, endMs)
    const items: CalendarEventItem[] = []
    for (let i = 0; i < events.length; i++) {
      items.push({
        id: events[i].id,
        title: events[i].title,
        startTime: events[i].startTime,
        endTime: events[i].endTime,
        location: events[i].location,
      })
    }
    const result: CalendarEventsResult = { count: items.length, events: items }
    return { success: true, data: JSON.stringify(result) }
  }

  private async addToCalendar(args: Record<string, Object>): Promise<ToolResult> {
    const title: string = this.getStringArg(args, 'title')
    const date: string = this.getStringArg(args, 'date')
    const startTime: string = this.getStringArg(args, 'startTime')
    const endTime: string = this.getStringArg(args, 'endTime')
    if (title.length === 0 || date.length === 0 || startTime.length === 0 || endTime.length === 0) {
      return { success: false, data: '缺少必要参数：title/date/startTime/endTime' }
    }
    const remindMinutes: number = this.getNumberArg(args, 'remindMinutesBefore', 30)
    const location: string = this.getStringArg(args, 'location')
    const description: string = this.getStringArg(args, 'description')
    const typeStr: string = this.getStringArg(args, 'type', 'custom')
    const eventType: ScheduleEventType = typeStr === 'assignment' ? 'assignment' : 'custom'
    const existingEvents: ScheduleEvent[] = await ScheduleService.loadCustomSchedules(this.context)
    let existing: ScheduleEvent | undefined
    for (let i = 0; i < existingEvents.length; i++) {
      const ex: ScheduleEvent = existingEvents[i]
      if (ex.title === title && ex.date === date && ex.startTime === startTime && ex.endTime === endTime) {
        existing = ex
        break
      }
    }
    const event: ScheduleEvent = {
      id: existing ? existing.id : '',
      title: title,
      date: date,
      timeRange: `${startTime}-${endTime}`,
      startTime: startTime,
      endTime: endTime,
      location: location,
      type: eventType,
      color: ScheduleUtils.getTypeColor(eventType),
      sourceId: existing ? existing.sourceId : '',
      description: description,
      createdAt: existing ? existing.createdAt : Date.now(),
      remindMinutes: remindMinutes,
      addToCalendar: true,
      calendarEventId: existing ? existing.calendarEventId || 0 : 0,
    }
    await ScheduleService.saveSchedule(this.context, event)
    const hasPerm: boolean = await this.ensureCalendarPermission()
    let calendarAdded: boolean = false
    let calendarEventId: number = -1
    if (hasPerm) {
      calendarEventId = await CalendarKitReminderService.addEventReminder(this.context, event, remindMinutes)
      if (calendarEventId >= 0) {
        calendarAdded = true
        event.calendarEventId = calendarEventId
        await ScheduleService.updateSchedule(this.context, event)
      }
    }
    const result: AddToCalendarResult = {
      message: calendarAdded
        ? '日程已创建并写入系统日历'
        : (hasPerm ? '日程已创建，但写入系统日历失败' : '日程已创建，但未授予日历权限，未写入系统日历'),
      scheduleEventId: event.id,
      calendarEventId: calendarEventId,
      calendarAdded: calendarAdded,
    }
    return { success: calendarAdded, data: JSON.stringify(result) }
  }

  private async addExamToCalendar(args: Record<string, Object>): Promise<ToolResult> {
    const courseName: string = this.getStringArg(args, 'courseName')
    const remindMinutes: number = this.getNumberArg(args, 'remindMinutesBefore', 30)
    const exams: ExamItem[] = await ExamService.loadExams(this.context)
    if (exams.length === 0) {
      return { success: false, data: '暂无考试数据' }
    }
    let target: ExamItem | undefined
    if (courseName.length === 0) {
      target = ExamService.getNextExam(exams)
    } else {
      const keyword: string = courseName.toLowerCase()
      const upcoming: ExamItem[] = ExamService.getUpcomingExams(exams)
      for (let i = 0; i < upcoming.length; i++) {
        if (upcoming[i].courseName.toLowerCase().includes(keyword)) {
          target = upcoming[i]
          break
        }
      }
      if (!target) {
        for (let i = 0; i < exams.length; i++) {
          if (exams[i].courseName.toLowerCase().includes(keyword)) {
            target = exams[i]
            break
          }
        }
      }
    }
    if (!target) {
      return { success: false, data: courseName.length > 0 ? `未找到包含"${courseName}"的考试` : '暂无即将到来的考试' }
    }
    const hasPerm: boolean = await this.ensureCalendarPermission()
    if (!hasPerm) {
      return { success: false, data: '未授予日历权限，无法写入系统日历' }
    }
    const startPart: string = target.examTimeRange && target.examTimeRange.length > 0
      ? target.examTimeRange.split('-')[0].trim()
      : '9:00'
    const event: ScheduleEvent = {
      id: '',
      title: `${target.courseName} 考试`,
      date: target.examDate,
      timeRange: target.examTimeRange,
      startTime: startPart,
      endTime: '',
      location: target.examLocation,
      type: 'exam' as ScheduleEventType,
      color: ScheduleUtils.getTypeColor('exam'),
      sourceId: target.courseNo,
      description: target.seatNo || '',
      createdAt: Date.now(),
      remindMinutes: remindMinutes,
      addToCalendar: true,
    }
    const calendarEventId: number = await CalendarKitReminderService.addEventReminder(this.context, event, remindMinutes)
    const calendarAdded: boolean = calendarEventId >= 0
    const result: AddExamToCalendarResult = {
      message: calendarAdded ? '考试已写入系统日历' : '写入系统日历失败',
      courseName: target.courseName,
      examDate: target.examDate,
      examTimeRange: target.examTimeRange,
      calendarEventId: calendarEventId,
      calendarAdded: calendarAdded,
    }
    return { success: calendarAdded, data: JSON.stringify(result) }
  }

  private async addCourseToCalendar(args: Record<string, Object>): Promise<ToolResult> {
    const courseName: string = this.getStringArg(args, 'courseName')
    const dateStr: string = this.getStringArg(args, 'date')
    const remindMinutes: number = this.getNumberArg(args, 'remindMinutesBefore', 15)
    const now: Date = new Date()
    let target: Date
    if (dateStr.length > 0) {
      const parsed: Date | null = this.parseDate(dateStr)
      if (!parsed) {
        return { success: false, data: `日期格式错误: ${dateStr}，应为YYYY-MM-DD` }
      }
      target = parsed
    } else {
      target = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    }
    const dayOfWeek: number = target.getDay() || 7
    const weekNumber: number = getWeekForDate(target)
    const usedDateStr: string = ScheduleUtils.formatDate(target.getFullYear(), target.getMonth() + 1, target.getDate())
    await CourseService.loadCourses(this.context)
    let courses: Course[] = CourseService.getCoursesForDayAndWeek(dayOfWeek, weekNumber)
    if (courseName.length > 0) {
      const keyword: string = courseName.toLowerCase()
      const filtered: Course[] = []
      for (let i = 0; i < courses.length; i++) {
        if (courses[i].name.toLowerCase().includes(keyword)) {
          filtered.push(courses[i])
        }
      }
      courses = filtered
    }
    if (courses.length === 0) {
      return { success: true, data: `${usedDateStr} 没有匹配的课程` }
    }
    const hasPerm: boolean = await this.ensureCalendarPermission()
    if (!hasPerm) {
      return { success: false, data: '未授予日历权限，无法写入系统日历' }
    }
    const calendarEventIds: number[] = []
    for (let i = 0; i < courses.length; i++) {
      const c: Course = courses[i]
      const endSection: number = c.time.startSection + c.time.duration - 1
      const startTime: string = SECTION_TIMES[c.time.startSection - 1]?.startTime || '8:30'
      const endTime: string = SECTION_TIMES[endSection - 1]?.endTime || '9:15'
      const event: ScheduleEvent = {
        id: '',
        title: c.name,
        date: usedDateStr,
        timeRange: `${startTime}-${endTime}`,
        startTime: startTime,
        endTime: endTime,
        location: c.roomName,
        type: 'course' as ScheduleEventType,
        color: ScheduleUtils.getTypeColor('course'),
        sourceId: c.id,
        description: c.teacherName || '',
        createdAt: Date.now(),
        remindMinutes: remindMinutes,
        addToCalendar: true,
      }
      const calId: number = await CalendarKitReminderService.addEventReminder(this.context, event, remindMinutes)
      if (calId >= 0) {
        calendarEventIds.push(calId)
      }
    }
    const result: AddCourseToCalendarResult = {
      message: `已将${calendarEventIds.length}门课程写入系统日历`,
      date: usedDateStr,
      addedCount: calendarEventIds.length,
      calendarEventIds: calendarEventIds,
    }
    return { success: calendarEventIds.length > 0, data: JSON.stringify(result) }
  }

  private async removeCalendarEvent(args: Record<string, Object>): Promise<ToolResult> {
    const calendarEventId: number = this.getNumberArg(args, 'calendarEventId', -1)
    if (calendarEventId < 0) {
      return { success: false, data: '缺少calendarEventId参数' }
    }
    const ok: boolean = await CalendarKitReminderService.deleteEvent(this.context, calendarEventId)
    // 同步清理应用内日程里指向该日历事件的引用
    try {
      const allEvents: ScheduleEvent[] = await ScheduleService.loadCustomSchedules(this.context)
      for (let i = 0; i < allEvents.length; i++) {
        if (allEvents[i].calendarEventId === calendarEventId) {
          allEvents[i].calendarEventId = 0
          await ScheduleService.updateSchedule(this.context, allEvents[i])
        }
      }
    } catch (e) {
      // ignore cleanup errors
    }
    const result: RemoveCalendarEventResult = {
      message: ok ? '已从系统日历移除' : '移除失败（事件可能已不存在）',
      calendarEventId: calendarEventId,
    }
    return { success: ok, data: JSON.stringify(result) }
  }

  private async updateSchedule(args: Record<string, Object>): Promise<ToolResult> {
    const eventId: string = this.getStringArg(args, 'eventId')
    if (eventId.length === 0) {
      return { success: false, data: '缺少eventId参数' }
    }
    const allEvents: ScheduleEvent[] = await ScheduleService.loadCustomSchedules(this.context)
    let target: ScheduleEvent | undefined
    for (let i = 0; i < allEvents.length; i++) {
      if (allEvents[i].id === eventId) {
        target = allEvents[i]
        break
      }
    }
    if (!target) {
      return { success: false, data: `未找到ID为${eventId}的日程` }
    }
    const evt: ScheduleEvent = target
    const title: string = this.getStringArg(args, 'title')
    if (title.length > 0) evt.title = title
    const date: string = this.getStringArg(args, 'date')
    if (date.length > 0) evt.date = date
    const startTime: string = this.getStringArg(args, 'startTime')
    if (startTime.length > 0) evt.startTime = startTime
    const endTime: string = this.getStringArg(args, 'endTime')
    if (endTime.length > 0) evt.endTime = endTime
    if (startTime.length > 0 || endTime.length > 0) {
      const s: string = evt.startTime || ''
      const e: string = evt.endTime || ''
      if (s.length > 0 && e.length > 0) {
        evt.timeRange = `${s}-${e}`
      }
    }
    const location: string = this.getStringArg(args, 'location')
    if (location.length > 0) evt.location = location
    const description: string = this.getStringArg(args, 'description')
    if (description.length > 0) evt.description = description
    const typeStr: string = this.getStringArg(args, 'type')
    if (typeStr === 'custom' || typeStr === 'assignment') {
      evt.type = typeStr as ScheduleEventType
      evt.color = ScheduleUtils.getTypeColor(typeStr as ScheduleEventType)
    }
    await ScheduleService.updateSchedule(this.context, evt)
    // 若已关联系统日历事件，同步更新日历
    if (evt.calendarEventId && evt.calendarEventId > 0) {
      const hasPerm: boolean = await this.ensureCalendarPermission()
      if (hasPerm) {
        const remindMinutes: number = await ReminderService.getEffectiveRemindMinutes(this.context, evt)
        const newId: number = await CalendarKitReminderService.upsertEventReminder(this.context, evt, remindMinutes)
        if (newId >= 0) {
          evt.calendarEventId = newId
          await ScheduleService.updateSchedule(this.context, evt)
        }
      }
    }
    const result: UpdateScheduleResult = { message: '日程已更新', eventId: eventId }
    return { success: true, data: JSON.stringify(result) }
  }

  private async generateStudyPlan(args: Record<string, Object>): Promise<ToolResult> {
    const exams: ExamItem[] = await ExamService.loadExams(this.context)
    if (!exams || exams.length === 0) {
      return { success: false, data: '当前暂无考试安排，无需生成复习计划' }
    }
    const dailyHours: number = this.getNumberArg(args, 'dailyHours', 4)
    const focusCourse: string = this.getStringArg(args, 'focusCourse', '')

    const now: number = Date.now()
    const upcoming: ExamItem[] = []
    for (let i = 0; i < exams.length; i++) {
      const e: ExamItem = exams[i]
      if (e.beginTime > now) {
        upcoming.push(e)
      }
    }

    if (upcoming.length === 0) {
      return { success: false, data: '所有考试均已结束，当前暂无未来考试安排' }
    }

    upcoming.sort((a: ExamItem, b: ExamItem) => a.beginTime - b.beginTime)

    const upcomingExams: UpcomingExamStudyItem[] = []
    for (let i = 0; i < upcoming.length; i++) {
      const e: ExamItem = upcoming[i]
      const days: number = Math.max(1, Math.ceil((e.beginTime - now) / (1000 * 3600 * 24)))
      let allocatedHours: number = Math.round((dailyHours / upcoming.length) * 10) / 10
      if (focusCourse.length > 0 && e.courseName.includes(focusCourse)) {
        allocatedHours = Math.round((dailyHours * 0.5) * 10) / 10
      }
      upcomingExams.push({
        courseName: e.courseName,
        date: e.examDate,
        time: e.examTimeRange,
        daysLeft: days,
        recommendedDailyHours: allocatedHours
      })
    }

    const planData: StudyPlanResultData = {
      totalExams: upcoming.length,
      dailyHours: dailyHours,
      focusCourse: focusCourse,
      strategy: '按考试紧急程度与倒计时天数加权分配，最近科目优先突破，每天合理规划时间。',
      upcomingExams: upcomingExams
    }
    return { success: true, data: JSON.stringify(planData) }
  }

  private queryCampusGuide(args: Record<string, Object>): ToolResult {
    const category: string = this.getStringArg(args, 'category', 'all')
    const keyword: string = this.getStringArg(args, 'keyword', '').toLowerCase()

    const allGuides: GuideItem[] = [
      {
        title: '清水河 ⇋ 沙河 校车时刻表',
        category: 'bus',
        content: '工作日班次：07:00, 08:30, 10:00, 12:00, 13:30, 15:00, 16:30, 18:00, 21:00。周末与节假日班次有所减少。',
        details: '清水河上车点：主楼东侧班车站；沙河上车点：东门班车站。乘车请出示校园卡或成电码。'
      },
      {
        title: '期末缓考与补考规定',
        category: 'academic_policy',
        content: '必修课期末不及格通常在开学前一周安排补考；因病等不可抗力无法应考须在考试前在教务系统提交缓考申请及医院证明。',
        details: '缓考成绩按正常考试计分；缺考或作弊者取消补考资格。'
      },
      {
        title: '保研与推免学分绩点计算',
        category: 'academic_policy',
        content: '保研推免绩点主要计算培养方案规定内的所有必修课和限选课加权平均成绩（GPA），通识选修与重修初修记录按学院细则执行。',
        details: '学术科研、学科竞赛获奖及综合素质测评加分按学院当年推免方案折算。'
      },
      {
        title: '清水河与沙河校医院就医流程',
        category: 'hospital',
        content: '校医院工作时间：周一至周日全天 24 小时急诊值班；门诊常规接诊 08:30-12:00, 14:00-17:30。',
        details: '清水河校医院位于商业街西侧，就医请带校园卡或身份证。学生享受成都市大学生医保门诊报销。'
      },
      {
        title: '清水河图书馆与自习室指南',
        category: 'facilities',
        content: '清水河主图书馆开放时间 08:00 - 22:30。一至四楼设有静音自习区、研讨室及电子阅览室。',
        details: '研修间与研讨室可在"成电移动校园"或图书馆官网提前预约；入馆需刷校园卡或电子校园卡。'
      },
      {
        title: '体育场馆与游泳馆开放时间',
        category: 'facilities',
        content: '综合体育馆、羽毛球馆、网球场与游泳馆面向全校师生开放，一般开放时间为 12:00 - 21:30。',
        details: '部分场馆周末需通过成电移动校园-场馆预约系统提前订场。'
      }
    ]

    let matched: GuideItem[] = allGuides
    if (category !== 'all') {
      matched = matched.filter(g => g.category === category)
    }
    if (keyword.length > 0) {
      matched = matched.filter(g => g.title.toLowerCase().includes(keyword) || g.content.toLowerCase().includes(keyword) || (g.details !== undefined && g.details.toLowerCase().includes(keyword)))
    }

    const guideResult: GuideResultData = {
      category: category,
      keyword: keyword,
      count: matched.length,
      guides: matched
    }
    return { success: true, data: JSON.stringify(guideResult) }
  }

  private parseTextToSchedule(args: Record<string, Object>): ToolResult {
    const rawText: string = this.getStringArg(args, 'rawText', '')
    if (rawText.length === 0) {
      return { success: false, data: '提供的文本内容为空，无法解析' }
    }
    const parseResult: ParseResultData = {
      status: 'ready_for_extraction',
      rawLength: rawText.length,
      hint: '请助手根据此文本提取日程详情（标题、日期YYYY-MM-DD、开始时间HH:mm、结束时间HH:mm、地点、描述），并向用户确认或直接调用 create_schedule / add_to_calendar'
    }
    return { success: true, data: JSON.stringify(parseResult) }
  }
}

