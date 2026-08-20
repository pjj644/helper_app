import { CourseService } from '../../service/CourseService'
import { ExamService } from '../../service/ExamService'
import { GradeService } from '../../service/GradeService'
import { ScheduleService } from '../../service/ScheduleService'
import { ReminderService } from '../../service/ReminderService'
import { CalendarKitReminderService, CalendarEventSummary } from '../../service/CalendarKitReminderService'
import { Course, SECTION_TIMES, getCurrentWeek, getWeekForDate } from '../../model/classTableModel/CourseModel'
import { ExamItem } from '../../model/classTableModel/ExamModel'
import { GradeItem } from '../../model/GradeModel'
import { ScheduleEvent, ScheduleUtils, ScheduleEventType } from '../../model/ScheduleModel'
import { calculateSemesterId, getSemesterLabelById } from '../../model/classTableModel/ExamAccessRules'
import { common } from '@kit.AbilityKit'

export interface QueryFilter {
  date?: string
  week?: number
  dayOfWeek?: number
  keyword?: string
  teacher?: string
  room?: string
  upcomingOnly?: boolean
  semesterId?: number
  minGpa?: number
  maxGpa?: number
  type?: string
  startDate?: string
  endDate?: string
}

export class DataQueryEngine {
  private context: Context

  constructor(context: Context) {
    this.context = context
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

  async executeQuery(domain: string, filter: QueryFilter = {}, limit: number = 50): Promise<string> {
    switch (domain) {
      case 'system_info':
        return this.querySystemInfo()
      case 'course':
        return await this.queryCourses(filter, limit)
      case 'exam':
        return await this.queryExams(filter, limit)
      case 'grade':
        return await this.queryGrades(filter, limit)
      case 'schedule':
        return await this.querySchedules(filter, limit)
      case 'calendar':
        return await this.queryCalendar(filter, limit)
      case 'reminder_setting':
        return await this.queryReminderSettings()
      default:
        return JSON.stringify({ domain: domain, count: 0, error: `不支持的数据领域: ${domain}` })
    }
  }

  private querySystemInfo(): string {
    const now: Date = new Date()
    const year: number = now.getFullYear()
    const month: string = String(now.getMonth() + 1).padStart(2, '0')
    const day: string = String(now.getDate()).padStart(2, '0')
    const hours: string = String(now.getHours()).padStart(2, '0')
    const minutes: string = String(now.getMinutes()).padStart(2, '0')
    const dayOfWeek: number = now.getDay() || 7
    const dayLabels: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日']
    const currentWeek: number = getCurrentWeek()
    const totalWeeks: number = CourseService.getMaxWeekNumber()
    const semesterId: number = calculateSemesterId(now)
    const semesterLabel: string = getSemesterLabelById(semesterId)

    const res: Record<string, Object> = {
      'date': `${year}-${month}-${day}`,
      'time': `${hours}:${minutes}`,
      'dayOfWeek': dayOfWeek,
      'dayOfWeekLabel': dayLabels[dayOfWeek] || '未知',
      'currentWeek': currentWeek,
      'totalWeeks': totalWeeks,
      'semesterId': semesterId,
      'semesterLabel': semesterLabel
    }
    return JSON.stringify({ domain: 'system_info', count: 1, data: res })
  }

  private async queryCourses(filter: QueryFilter, limit: number): Promise<string> {
    await CourseService.loadCourses(this.context)
    let targetWeek: number | undefined = filter.week
    let targetDayOfWeek: number | undefined = filter.dayOfWeek

    if (filter.date && filter.date.length > 0) {
      const parts: string[] = filter.date.split('-')
      if (parts.length === 3) {
        const d: Date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
        if (!isNaN(d.getTime())) {
          targetWeek = getWeekForDate(d)
          targetDayOfWeek = d.getDay() || 7
        }
      }
    }

    let courses: Course[] = CourseService.getAllCourses()

    if (targetWeek !== undefined && targetWeek > 0) {
      courses = CourseService.getCoursesForWeek(targetWeek)
    }

    if (targetDayOfWeek !== undefined && targetDayOfWeek > 0) {
      courses = courses.filter((c: Course) => c.time.dayOfWeek === targetDayOfWeek)
    }

    if (filter.keyword && filter.keyword.length > 0) {
      const kw: string = filter.keyword.toLowerCase()
      courses = courses.filter((c: Course) =>
        c.name.toLowerCase().includes(kw) ||
        (c.roomName && c.roomName.toLowerCase().includes(kw)) ||
        (c.teacherName && c.teacherName.toLowerCase().includes(kw))
      )
    }

    if (filter.teacher && filter.teacher.length > 0) {
      const t: string = filter.teacher.toLowerCase()
      courses = courses.filter((c: Course) => c.teacherName && c.teacherName.toLowerCase().includes(t))
    }

    if (filter.room && filter.room.length > 0) {
      const r: string = filter.room.toLowerCase()
      courses = courses.filter((c: Course) => c.roomName && c.roomName.toLowerCase().includes(r))
    }

    const dayLabels: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日']
    const items: Record<string, Object>[] = []
    const count: number = Math.min(courses.length, limit > 0 ? limit : 50)
    for (let i = 0; i < count; i++) {
      const c: Course = courses[i]
      const item: Record<string, Object> = {
        'id': c.id,
        'name': c.name,
        'teacher': c.teacherName,
        'room': c.roomName,
        'dayOfWeek': c.time.dayOfWeek,
        'dayOfWeekLabel': dayLabels[c.time.dayOfWeek] || '',
        'section': `第${c.time.startSection}-${c.time.startSection + c.time.duration - 1}节`,
        'timeRange': this.formatSectionTime(c.time.startSection, c.time.duration),
        'validWeeks': c.validWeeks
      }
      items.push(item)
    }

    return JSON.stringify({
      domain: 'course',
      count: courses.length,
      targetWeek: targetWeek || getCurrentWeek(),
      items: items
    })
  }

  private async queryExams(filter: QueryFilter, limit: number): Promise<string> {
    const allExams: ExamItem[] = await ExamService.loadExams(this.context)
    if (allExams.length === 0) {
      return JSON.stringify({ domain: 'exam', count: 0, items: [] })
    }

    let list: ExamItem[] = filter.upcomingOnly ? ExamService.getUpcomingExams(allExams) : allExams

    if (filter.semesterId && filter.semesterId > 0) {
      list = list.filter((e: ExamItem) => e.semesterId === filter.semesterId)
    }

    if (filter.keyword && filter.keyword.length > 0) {
      const kw: string = filter.keyword.toLowerCase()
      list = list.filter((e: ExamItem) =>
        e.courseName.toLowerCase().includes(kw) ||
        (e.examLocation && e.examLocation.toLowerCase().includes(kw))
      )
    }

    const items: Record<string, Object>[] = []
    const count: number = Math.min(list.length, limit > 0 ? limit : 50)
    for (let i = 0; i < count; i++) {
      const e: ExamItem = list[i]
      const item: Record<string, Object> = {
        'courseName': e.courseName,
        'examDate': e.examDate,
        'examTimeRange': e.examTimeRange,
        'examLocation': e.examLocation,
        'seatNo': e.seatNo,
        'examType': e.examType,
        'semesterId': e.semesterId,
        'countdown': ExamService.formatCountDown(Date.now(), e.beginTime)
      }
      items.push(item)
    }

    return JSON.stringify({ domain: 'exam', count: list.length, items: items })
  }

  private async queryGrades(filter: QueryFilter, limit: number): Promise<string> {
    const allGrades: GradeItem[] = await GradeService.loadGrades(this.context)
    if (allGrades.length === 0) {
      return JSON.stringify({ domain: 'grade', count: 0, overallGPA: '0.00', items: [] })
    }

    let list: GradeItem[] = allGrades
    if (filter.semesterId && filter.semesterId > 0) {
      list = list.filter((g: GradeItem) => g.semesterId === filter.semesterId)
    }

    if (filter.minGpa !== undefined) {
      list = list.filter((g: GradeItem) => g.gradePoint >= filter.minGpa!)
    }
    if (filter.maxGpa !== undefined) {
      list = list.filter((g: GradeItem) => g.gradePoint <= filter.maxGpa!)
    }

    if (filter.keyword && filter.keyword.length > 0) {
      const kw: string = filter.keyword.toLowerCase()
      list = list.filter((g: GradeItem) => g.courseName.toLowerCase().includes(kw))
    }

    const overallGpa: number = GradeService.calculateOverallGPA(allGrades)
    const latestGpa: number = GradeService.getLatestSemesterGPA(allGrades)
    const latestId: number = GradeService.getLatestSemesterId(allGrades)

    const items: Record<string, Object>[] = []
    const count: number = Math.min(list.length, limit > 0 ? limit : 100)
    for (let i = 0; i < count; i++) {
      const g: GradeItem = list[i]
      const item: Record<string, Object> = {
        'courseName': g.courseName,
        'credit': g.credit,
        'totalScore': g.totalScore,
        'gradePoint': g.gradePoint,
        'semesterId': g.semesterId
      }
      items.push(item)
    }

    return JSON.stringify({
      domain: 'grade',
      count: list.length,
      overallGPA: overallGpa.toFixed(2),
      latestSemesterGPA: latestGpa.toFixed(2),
      latestSemesterId: latestId,
      totalCourses: allGrades.length,
      items: items
    })
  }

  private async querySchedules(filter: QueryFilter, limit: number): Promise<string> {
    const allEvents: ScheduleEvent[] = await ScheduleService.getAllEvents(this.context)
    if (allEvents.length === 0) {
      return JSON.stringify({ domain: 'schedule', count: 0, items: [] })
    }

    let list: ScheduleEvent[] = allEvents
    if (filter.date && filter.date.length > 0) {
      list = list.filter((e: ScheduleEvent) => e.date === filter.date)
    }
    if (filter.startDate && filter.startDate.length > 0) {
      list = list.filter((e: ScheduleEvent) => e.date >= filter.startDate!)
    }
    if (filter.endDate && filter.endDate.length > 0) {
      list = list.filter((e: ScheduleEvent) => e.date <= filter.endDate!)
    }
    if (filter.type && filter.type.length > 0) {
      list = list.filter((e: ScheduleEvent) => e.type === filter.type)
    }
    if (filter.keyword && filter.keyword.length > 0) {
      const kw: string = filter.keyword.toLowerCase()
      list = list.filter((e: ScheduleEvent) =>
        e.title.toLowerCase().includes(kw) ||
        (e.location && e.location.toLowerCase().includes(kw)) ||
        (e.description && e.description.toLowerCase().includes(kw))
      )
    }

    const items: Record<string, Object>[] = []
    const count: number = Math.min(list.length, limit > 0 ? limit : 50)
    for (let i = 0; i < count; i++) {
      const evt: ScheduleEvent = list[i]
      const item: Record<string, Object> = {
        'id': evt.id,
        'title': evt.title,
        'date': evt.date,
        'timeRange': evt.timeRange || ScheduleUtils.formatTimeRange(evt.startTime || '', evt.endTime || ''),
        'location': evt.location,
        'type': evt.type,
        'description': evt.description || '',
        'calendarEventId': evt.calendarEventId || 0
      }
      items.push(item)
    }

    return JSON.stringify({ domain: 'schedule', count: list.length, items: items })
  }

  private async queryCalendar(filter: QueryFilter, limit: number): Promise<string> {
    const uiContext = this.context as common.UIAbilityContext
    const hasPerm: boolean = uiContext ? await CalendarKitReminderService.checkCalendarPermission(uiContext) : false
    if (!hasPerm) {
      return JSON.stringify({ domain: 'calendar', count: 0, message: '日历权限未开启' })
    }

    let startMs: number = Date.now()
    let endMs: number = Date.now() + 30 * 24 * 3600 * 1000

    if (filter.startDate && filter.startDate.length > 0) {
      const d: Date = new Date(filter.startDate + 'T00:00:00')
      if (!isNaN(d.getTime())) {
        startMs = d.getTime()
      }
    }
    if (filter.endDate && filter.endDate.length > 0) {
      const d: Date = new Date(filter.endDate + 'T23:59:59')
      if (!isNaN(d.getTime())) {
        endMs = d.getTime()
      }
    }

    const events: CalendarEventSummary[] = await CalendarKitReminderService.listEvents(this.context, startMs, endMs)
    let list: CalendarEventSummary[] = events
    if (filter.keyword && filter.keyword.length > 0) {
      const kw: string = filter.keyword.toLowerCase()
      list = list.filter((e: CalendarEventSummary) =>
        e.title.toLowerCase().includes(kw) ||
        (e.location && e.location.toLowerCase().includes(kw))
      )
    }

    const items: Record<string, Object>[] = []
    const count: number = Math.min(list.length, limit > 0 ? limit : 50)
    for (let i = 0; i < count; i++) {
      const e: CalendarEventSummary = list[i]
      const item: Record<string, Object> = {
        'id': e.id,
        'title': e.title,
        'startTime': e.startTime,
        'endTime': e.endTime,
        'location': e.location
      }
      items.push(item)
    }

    return JSON.stringify({ domain: 'calendar', count: list.length, items: items })
  }

  private async queryReminderSettings(): Promise<string> {
    const autoSync: boolean = await ReminderService.getAutoSyncScheduleEnabled(this.context)
    const examMin: number = await ReminderService.getCategoryRemindMinutes(this.context, 'exam' as ScheduleEventType)
    const courseMin: number = await ReminderService.getCategoryRemindMinutes(this.context, 'course' as ScheduleEventType)
    const customMin: number = await ReminderService.getCategoryRemindMinutes(this.context, 'custom' as ScheduleEventType)
    const assignmentMin: number = await ReminderService.getCategoryRemindMinutes(this.context, 'assignment' as ScheduleEventType)

    const cats: Record<string, Object>[] = [
      { 'type': 'exam', 'remindMinutes': examMin },
      { 'type': 'course', 'remindMinutes': courseMin },
      { 'type': 'custom', 'remindMinutes': customMin },
      { 'type': 'assignment', 'remindMinutes': assignmentMin }
    ]
    const res: Record<string, Object> = {
      'autoSyncSchedule': autoSync,
      'categories': cats
    }
    return JSON.stringify({ domain: 'reminder_setting', count: 1, data: res })
  }
}
