import { CourseService } from '../../service/CourseService'
import { ExamService } from '../../service/ExamService'
import { GradeService } from '../../service/GradeService'
import { ScheduleService } from '../../service/ScheduleService'
import { SyncService, SyncResult, DownloadResult } from '../../service/SyncService'
import { AuthService } from '../../service/AuthService'
import { ReminderService } from '../../service/ReminderService'
import { CalendarKitReminderService } from '../../service/CalendarKitReminderService'
import { ScheduleEvent, ScheduleUtils, ScheduleEventType } from '../../model/ScheduleModel'
import { getCurrentWeek } from '../../model/classTableModel/CourseModel'
import { ExamItem } from '../../model/classTableModel/ExamModel'
import { AppConstants, RouterConstants } from '../constants/AppConstants'
import { router } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { http } from '@kit.NetworkKit'
import { SettingsRepository } from '../../repository/SettingsRepository'
import { ScheduleRepository } from '../../repository/ScheduleRepository'
import { DataQueryEngine, QueryFilter } from './DataQueryEngine'
import { PageContextTracker } from './PageContextTracker'
import { UIActionDispatcher } from './UIActionDispatcher'

export interface ToolResult {
  success: boolean
  data: string
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

interface PipelineStepResult {
  stepId: string
  tool: string
  success: boolean
  data: string
}

/**
 * 统一控制引擎端侧执行器（Universal ToolExecutor）
 */
export class ToolExecutor {
  private context: Context
  private queryEngine: DataQueryEngine

  constructor(context: Context) {
    this.context = context
    this.queryEngine = new DataQueryEngine(context)
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

  private async ensureCalendarPermission(): Promise<boolean> {
    try {
      const uiContext = this.context as common.UIAbilityContext
      if (!uiContext) {
        return false
      }
      return await CalendarKitReminderService.requestCalendarPermission(uiContext)
    } catch (e) {
      console.error('ToolExecutor ensureCalendarPermission error:', JSON.stringify(e))
      return false
    }
  }

  private buildMutateArgs(domain: string, action: string, payload: Record<string, Object>): Record<string, Object> {
    const res: Record<string, Object> = {
      'domain': domain,
      'action': action,
      'payload': payload
    }
    return res
  }

  private buildControlArgs(action: string, syncScope?: string): Record<string, Object> {
    const params: Record<string, Object> = {}
    if (syncScope && syncScope.length > 0) {
      params['syncScope'] = syncScope
    }
    const res: Record<string, Object> = {
      'action': action,
      'params': params
    }
    return res
  }

  async execute(toolName: string, args: Record<string, Object>): Promise<ToolResult> {
    try {
      switch (toolName) {
        // === 5 大核心元工具 ===
        case 'app_data_query':
          return await this.executeDataQuery(args)
        case 'app_data_mutate':
          return await this.executeDataMutate(args)
        case 'app_control':
          return await this.executeAppControl(args)
        case 'campus_search':
          return await this.executeCampusSearch(args)
        case 'app_pipeline':
          return await this.executePipeline(args)

        // === 智能高阶辅助工具 ===
        case 'generate_study_plan':
          return await this.generateStudyPlan(args)
        case 'parse_text_to_schedule':
          return this.parseTextToSchedule(args)
        case 'get_current_page_context':
          return this.getCurrentPageContext()
        case 'execute_page_action':
          return await this.executePageAction(args)

        // === 向后兼容旧工具分发 ===
        case 'query_today_courses':
          return { success: true, data: await this.queryEngine.executeQuery('course', { dayOfWeek: new Date().getDay() || 7, week: getCurrentWeek() }) }
        case 'query_tomorrow_courses':
          return { success: true, data: await this.queryEngine.executeQuery('course', { dayOfWeek: ((new Date().getDay() + 1) % 7) || 7, week: getCurrentWeek() }) }
        case 'query_week_courses':
          return { success: true, data: await this.queryEngine.executeQuery('course', { week: this.getNumberArg(args, 'weekNumber', getCurrentWeek()) }) }
        case 'query_current_week':
        case 'get_current_datetime':
          return { success: true, data: await this.queryEngine.executeQuery('system_info', {}) }
        case 'query_courses_by_date':
          return { success: true, data: await this.queryEngine.executeQuery('course', { date: this.getStringArg(args, 'date') }) }
        case 'query_course_by_name':
          return { success: true, data: await this.queryEngine.executeQuery('course', { keyword: this.getStringArg(args, 'courseName') }) }
        case 'query_next_exam':
          return { success: true, data: await this.queryEngine.executeQuery('exam', { upcomingOnly: true }, 1) }
        case 'query_all_exams':
          return { success: true, data: await this.queryEngine.executeQuery('exam', {}) }
        case 'query_grades':
        case 'query_gpa':
          return { success: true, data: await this.queryEngine.executeQuery('grade', {}) }
        case 'query_schedule':
          return { success: true, data: await this.queryEngine.executeQuery('schedule', { date: this.getStringArg(args, 'date') }) }
        case 'list_calendar_events':
          return { success: true, data: await this.queryEngine.executeQuery('calendar', { startDate: this.getStringArg(args, 'startDate'), endDate: this.getStringArg(args, 'endDate') }) }
        case 'query_reminder_settings':
          return { success: true, data: await this.queryEngine.executeQuery('reminder_setting', {}) }
        case 'check_login_status':
          return await this.checkLoginStatus()
        case 'has_course_data':
          return await this.hasCourseData()
        case 'create_schedule':
          return await this.executeDataMutate(this.buildMutateArgs('schedule', 'create', args))
        case 'delete_schedule':
          return await this.executeDataMutate(this.buildMutateArgs('schedule', 'delete', args))
        case 'update_schedule':
          return await this.executeDataMutate(this.buildMutateArgs('schedule', 'update', args))
        case 'sync_courses_to_cloud':
          return await this.executeAppControl(this.buildControlArgs('sync_cloud', 'courses'))
        case 'sync_exams_to_cloud':
          return await this.executeAppControl(this.buildControlArgs('sync_cloud', 'exams'))
        case 'sync_all_to_cloud':
          return await this.executeAppControl(this.buildControlArgs('sync_cloud', 'all'))
        case 'download_all_from_cloud':
          return await this.executeAppControl(this.buildControlArgs('download_cloud', 'all'))
        case 'set_reminder_enabled':
          return await this.executeDataMutate(this.buildMutateArgs('reminder_setting', 'update', args))
        case 'set_remind_minutes':
          return await this.executeDataMutate(this.buildMutateArgs('reminder_setting', 'update', args))
        case 'refresh_reminders':
          return await this.executeAppControl(this.buildControlArgs('refresh_reminders'))
        case 'navigate_to_page':
          return this.navigateToPage(args)
        case 'query_campus_guide':
          return this.queryCampusGuide(args)
        case 'search_jwc_news':
          return await this.searchJwcNews(args)

        default:
          return { success: false, data: `未知工具: ${toolName}` }
      }
    } catch (error) {
      return { success: false, data: `工具执行错误: ${String(error)}` }
    }
  }

  // === 元工具 1：统一数据查询 ===
  private async executeDataQuery(args: Record<string, Object>): Promise<ToolResult> {
    const domain: string = this.getStringArg(args, 'domain', 'system_info')
    const filterRaw: Object | undefined = args['filter']
    const filter: QueryFilter = (filterRaw && typeof filterRaw === 'object') ? filterRaw as QueryFilter : {}
    const limit: number = this.getNumberArg(args, 'limit', 50)

    const resultStr: string = await this.queryEngine.executeQuery(domain, filter, limit)
    return { success: true, data: resultStr }
  }

  // === 元工具 2：统一数据变更 ===
  private async executeDataMutate(args: Record<string, Object>): Promise<ToolResult> {
    const domain: string = this.getStringArg(args, 'domain', 'schedule')
    const action: string = this.getStringArg(args, 'action', 'create')
    const payloadRaw: Object | undefined = args['payload']
    const payload: Record<string, Object> = (payloadRaw && typeof payloadRaw === 'object')
      ? payloadRaw as Record<string, Object>
      : args

    const syncCalendar: boolean = this.getBooleanArg(args, 'syncCalendar', true)
    const remindMinutesBefore: number = this.getNumberArg(args, 'remindMinutesBefore', 30)

    if (domain === 'schedule') {
      if (action === 'create') {
        const title: string = this.getStringArg(payload, 'title')
        const date: string = this.getStringArg(payload, 'date')
        const startTime: string = this.getStringArg(payload, 'startTime')
        const endTime: string = this.getStringArg(payload, 'endTime')
        const location: string = this.getStringArg(payload, 'location')
        const description: string = this.getStringArg(payload, 'description')
        const typeStr: string = this.getStringArg(payload, 'type', 'custom')

        if (title.length === 0 || date.length === 0) {
          return { success: false, data: '创建日程失败：缺少必要参数 title 或 date' }
        }

        const eventId: string = ScheduleUtils.generateId()
        const event: ScheduleEvent = {
          id: eventId,
          title: title,
          date: date,
          timeRange: (startTime.length > 0 && endTime.length > 0) ? `${startTime}-${endTime}` : (startTime || '全天'),
          startTime: startTime || '09:00',
          endTime: endTime || '10:00',
          location: location,
          type: (typeStr === 'assignment' ? 'assignment' : 'custom') as ScheduleEventType,
          color: ScheduleUtils.getTypeColor(typeStr === 'assignment' ? 'assignment' : 'custom'),
          sourceId: '',
          description: description,
          createdAt: Date.now(),
          remindMinutes: remindMinutesBefore,
          addToCalendar: syncCalendar,
        }

        if (syncCalendar) {
          const hasPerm: boolean = await this.ensureCalendarPermission()
          if (hasPerm) {
            const calId: number = await CalendarKitReminderService.addEventReminder(this.context, event, remindMinutesBefore)
            if (calId >= 0) {
              event.calendarEventId = calId
            }
          }
        }

        await ScheduleService.saveSchedule(this.context, event)
        return {
          success: true,
          data: JSON.stringify({
            message: '日程创建成功',
            eventId: eventId,
            title: title,
            date: date,
            timeRange: event.timeRange,
            calendarSynced: (event.calendarEventId !== undefined && event.calendarEventId > 0)
          })
        }
      } else if (action === 'update') {
        const eventId: string = this.getStringArg(payload, 'eventId')
        if (eventId.length === 0) {
          return { success: false, data: '更新日程失败：缺少 eventId' }
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
          return { success: false, data: `未找到ID为 ${eventId} 的日程` }
        }
        if (payload['title']) target.title = String(payload['title'])
        if (payload['date']) target.date = String(payload['date'])
        if (payload['startTime']) target.startTime = String(payload['startTime'])
        if (payload['endTime']) target.endTime = String(payload['endTime'])
        if (payload['location']) target.location = String(payload['location'])
        if (payload['description']) target.description = String(payload['description'])
        if (target.startTime && target.endTime) {
          target.timeRange = `${target.startTime}-${target.endTime}`
        }

        await ScheduleService.updateSchedule(this.context, target)
        if (target.calendarEventId && target.calendarEventId > 0) {
          const hasPerm: boolean = await this.ensureCalendarPermission()
          if (hasPerm) {
            const newId: number = await CalendarKitReminderService.upsertEventReminder(this.context, target, remindMinutesBefore)
            if (newId >= 0) {
              target.calendarEventId = newId
              await ScheduleService.updateSchedule(this.context, target)
            }
          }
        }
        return { success: true, data: JSON.stringify({ message: '日程已更新', eventId: eventId, title: target.title }) }
      } else if (action === 'delete') {
        const eventId: string = this.getStringArg(payload, 'eventId')
        if (eventId.length === 0) {
          return { success: false, data: '删除日程失败：缺少 eventId' }
        }
        await ScheduleService.deleteSchedule(this.context, eventId)
        return { success: true, data: JSON.stringify({ message: '日程已删除', eventId: eventId }) }
      }
    } else if (domain === 'calendar') {
      if (action === 'delete') {
        const calId: number = this.getNumberArg(payload, 'calendarEventId', -1)
        if (calId < 0) {
          return { success: false, data: '缺少 calendarEventId' }
        }
        const ok: boolean = await CalendarKitReminderService.deleteEvent(this.context, calId)
        // 双向联动：同步从 App 本地数据库中清理绑定此日历事件的日程
        const allSchedules: ScheduleEvent[] = await ScheduleRepository.loadSchedules(this.context)
        const filtered: ScheduleEvent[] = allSchedules.filter((s: ScheduleEvent) => s.calendarEventId !== calId)
        if (filtered.length !== allSchedules.length) {
          await ScheduleRepository.saveSchedules(this.context, filtered)
        }
        return { success: ok, data: JSON.stringify({ message: ok ? '日历事件已删除' : '删除失败', calendarEventId: calId }) }
      }
    } else if (domain === 'reminder_setting') {
      const typeStr: string = this.getStringArg(payload, 'type')
      const minutes: number = this.getNumberArg(payload, 'minutes', 0)

      if (typeStr.length > 0 && minutes > 0) {
        await ReminderService.saveCategoryRemindMinutes(this.context, typeStr as ScheduleEventType, minutes)
        return { success: true, data: JSON.stringify({ message: `提醒时间已更新: ${typeStr} 提前 ${minutes} 分钟` }) }
      }
    }

    return { success: false, data: `未知的变更操作: ${domain} - ${action}` }
  }

  // === 元工具 3：统一应用控制 ===
  private async executeAppControl(args: Record<string, Object>): Promise<ToolResult> {
    const action: string = this.getStringArg(args, 'action', 'navigate')
    const paramsRaw: Object | undefined = args['params']
    const params: Record<string, Object> = (paramsRaw && typeof paramsRaw === 'object')
      ? paramsRaw as Record<string, Object>
      : args

    if (action === 'navigate') {
      return this.navigateToPage(params)
    } else if (action === 'sync_cloud') {
      const userId: string | undefined = await AuthService.getLoginUserId(this.context)
      if (!userId) {
        return { success: false, data: '云同步失败：用户未登录，请先登录账号' }
      }
      const scope: string = this.getStringArg(params, 'syncScope', 'all')
      if (scope === 'courses') {
        const r: SyncResult = await SyncService.syncCoursesToCloud(this.context, userId)
        return { success: r.success, data: JSON.stringify({ message: r.success ? '课表同步成功' : (r.error || '课表同步失败'), courseCount: r.courseCount || 0 }) }
      } else if (scope === 'exams') {
        const r: SyncResult = await SyncService.syncExamsToCloud(this.context, userId)
        return { success: r.success, data: JSON.stringify({ message: r.success ? '考试同步成功' : (r.error || '考试同步失败'), examCount: r.examCount || 0 }) }
      } else {
        const cRes: SyncResult = await SyncService.syncCoursesToCloud(this.context, userId)
        const eRes: SyncResult = await SyncService.syncExamsToCloud(this.context, userId)
        const allOk: boolean = cRes.success && eRes.success
        return { success: allOk, data: JSON.stringify({ message: allOk ? '全量同步成功' : '部分数据同步失败', courses: cRes, exams: eRes }) }
      }
    } else if (action === 'download_cloud') {
      const userId: string | undefined = await AuthService.getLoginUserId(this.context)
      if (!userId) {
        return { success: false, data: '数据恢复失败：用户未登录，请先登录账号' }
      }
      const cRes: DownloadResult = await SyncService.downloadCoursesFromCloud(this.context, userId)
      const eRes: DownloadResult = await SyncService.downloadExamsFromCloud(this.context, userId)
      const allOk: boolean = cRes.success && eRes.success
      return { success: allOk, data: JSON.stringify({ message: allOk ? '全量数据恢复成功' : '数据恢复失败', courses: cRes, exams: eRes }) }
    } else if (action === 'refresh_reminders') {
      await ReminderService.refreshAllReminders(this.context)
      return { success: true, data: JSON.stringify({ message: '全部日程与系统日历提醒已刷新重建' }) }
    }

    return { success: false, data: `未知的应用控制动作: ${action}` }
  }

  // === 元工具 4：统一校园检索 ===
  private async executeCampusSearch(args: Record<string, Object>): Promise<ToolResult> {
    const query: string = this.getStringArg(args, 'query', '')
    const source: string = this.getStringArg(args, 'source', 'auto')
    const category: string = this.getStringArg(args, 'category', 'all')

    if (source === 'jwc_news') {
      return await this.searchJwcNews({ 'keyword': query, 'category': category })
    }

    // 默认本地知识库检索
    const localRes: ToolResult = this.queryCampusGuide({ 'keyword': query, 'category': category })
    try {
      const data = JSON.parse(localRes.data) as GuideResultData
      if (data.count > 0 || source === 'guide') {
        return localRes
      }
    } catch (e) {
      // ignore
    }

    // 若本地未匹配到且为 auto 模式，自动尝试检索教务处
    return await this.searchJwcNews({ 'keyword': query, 'category': category })
  }

  // === 元工具 5：声明式复合流水线批处理 ===
  private async executePipeline(args: Record<string, Object>): Promise<ToolResult> {
    const stepsRaw: Object[] | undefined = args['steps'] as Object[]
    if (!stepsRaw || stepsRaw.length === 0) {
      return { success: false, data: '流水线执行失败：步骤列表为空' }
    }

    const stepResults: PipelineStepResult[] = []
    let allSuccess: boolean = true

    for (let i = 0; i < stepsRaw.length; i++) {
      const s: Record<string, Object> = stepsRaw[i] as Record<string, Object>
      const stepId: string = (s['stepId'] as string) || `step_${i + 1}`
      const tool: string = (s['tool'] as string) || ''
      const stepArgs: Record<string, Object> = (s['args'] as Record<string, Object>) || {}

      const res: ToolResult = await this.execute(tool, stepArgs)
      stepResults.push({
        stepId: stepId,
        tool: tool,
        success: res.success,
        data: res.data
      })

      if (!res.success) {
        allSuccess = false
        break
      }
    }

    return {
      success: allSuccess,
      data: JSON.stringify({
        pipelineSuccess: allSuccess,
        totalSteps: stepsRaw.length,
        executedSteps: stepResults.length,
        results: stepResults
      })
    }
  }

  // === 基础状态与导航辅助 ===
  private async checkLoginStatus(): Promise<ToolResult> {
    const isLoggedIn: boolean = await AuthService.isLoggedIn(this.context)
    let email: string = ''
    if (isLoggedIn) {
      const userId = await AuthService.getLoginUserId(this.context)
      email = userId || ''
    }
    return { success: true, data: JSON.stringify({ isLoggedIn: isLoggedIn, email: email }) }
  }

  private async hasCourseData(): Promise<ToolResult> {
    const hasData: boolean = await CourseService.hasCourseData(this.context)
    return { success: true, data: JSON.stringify({ hasCourseData: hasData }) }
  }

  private navigateToPage(args: Record<string, Object>): ToolResult {
    const page: string = this.getStringArg(args, 'page')
    const pageMap: Record<string, string> = {
      'course_table': RouterConstants.PAGE_TABLE_UI,
      'exam': RouterConstants.PAGE_EXAM,
      'grade': RouterConstants.PAGE_GRADE,
      'schedule': RouterConstants.PAGE_CALENDAR,
      'settings': RouterConstants.PAGE_SETTINGS,
      'course_import': RouterConstants.PAGE_COURSE_IMPORT,
      'exam_import': RouterConstants.PAGE_EXAM_IMPORT,
      'grade_import': RouterConstants.PAGE_GRADE_IMPORT,
      'assistant': RouterConstants.PAGE_ASSISTANT,
      'home': RouterConstants.PAGE_INDEX
    }
    const url: string = pageMap[page] || ''
    if (url.length === 0) {
      return { success: false, data: `未知页面: ${page}` }
    }
    router.pushUrl({ url: url }).catch((err: Error) => {
      console.error(`ToolExecutor navigate error: ${String(err)}`)
    })
    return { success: true, data: JSON.stringify({ message: `已导航到 ${page} 页面` }) }
  }

  // === 校园指南本地库 ===
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
      matched = matched.filter((g: GuideItem) => g.category === category)
    }
    if (keyword.length > 0) {
      matched = matched.filter((g: GuideItem) => g.title.toLowerCase().includes(keyword) || g.content.toLowerCase().includes(keyword) || (g.details !== undefined && g.details.toLowerCase().includes(keyword)))
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
    return {
      success: true,
      data: JSON.stringify({
        status: 'ready_for_extraction',
        rawLength: rawText.length,
        hint: '请助手根据此文本提取日程详情（标题、日期YYYY-MM-DD、开始时间HH:mm、结束时间HH:mm、地点、描述），并调用 app_data_mutate 创建日程'
      })
    }
  }

  private async searchJwcNews(args: Record<string, Object>): Promise<ToolResult> {
    const keyword = this.getStringArg(args, 'keyword', '')
    const category = this.getStringArg(args, 'category', 'all')
    let backendUrl = AppConstants.AI_AGENT_URL
    try {
      backendUrl = await SettingsRepository.getAgentBackendUrl(this.context)
    } catch (e) {
      // ignore
    }

    const endpoint = `${backendUrl.replace(/\/+$/, '')}/api/jwc/search?keyword=${encodeURIComponent(keyword)}&category=${encodeURIComponent(category)}&limit=6`
    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(endpoint, {
        method: http.RequestMethod.GET,
        header: {
          'x-proxy-key': 'uestc-helper-proxy-key-change-me'
        },
        readTimeout: 10000,
        connectTimeout: 5000
      })

      if (response.responseCode === 200 && response.result) {
        let resStr = response.result as string
        if (typeof resStr !== 'string') {
          resStr = JSON.stringify(response.result)
        }
        return { success: true, data: resStr }
      }
      return { success: false, data: `教务处检索服务异常: HTTP ${response.responseCode}` }
    } catch (err) {
      return { success: false, data: `连接教务处检索服务失败: ${String(err)}` }
    } finally {
      httpRequest.destroy()
    }
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

  // === 页面感知与 UI 操作工具 ===
  private getCurrentPageContext(): ToolResult {
    const snapshot = PageContextTracker.getInstance().getSnapshot()
    return {
      success: true,
      data: JSON.stringify(snapshot)
    }
  }

  private async executePageAction(args: Record<string, Object>): Promise<ToolResult> {
    const action: string = this.getStringArg(args, 'action')
    const paramsRaw: Object | undefined = args['params']
    const params: Record<string, Object> = (paramsRaw && typeof paramsRaw === 'object')
      ? paramsRaw as Record<string, Object>
      : args

    if (action === 'show_guidance') {
      const targetElementId: string = this.getStringArg(params, 'targetElementId')
      const hintText: string = this.getStringArg(params, 'hintText')
      const durationMs: number = this.getNumberArg(params, 'durationMs', 5000)
      UIActionDispatcher.getInstance().showGuidance({
        targetElementId: targetElementId,
        hintText: hintText,
        durationMs: durationMs
      })
      return { success: true, data: JSON.stringify({ message: `已显示引导提示：${hintText}` }) }
    }

    const ok: boolean = await UIActionDispatcher.getInstance().dispatch(action, params)
    return {
      success: ok,
      data: JSON.stringify({
        action: action,
        dispatched: ok,
        message: ok ? `页面动作 [${action}] 执行成功` : `当前页面未响应动作 [${action}]，可能不支持或未在该页面`
      })
    }
  }
}
