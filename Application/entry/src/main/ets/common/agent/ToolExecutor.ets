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
import { preferences } from '@kit.ArkData'
import { AgentEndpointConfig, AgentEndpoint } from './AgentEndpointConfig'
import { ToolRegistry, LEGACY_TOOL_NAMES } from './ToolRegistry'
import { ScheduleRepository } from '../../repository/ScheduleRepository'
import { DataQueryEngine, QueryFilter } from './DataQueryEngine'
import { PageContextTracker } from './PageContextTracker'
import { UIActionDispatcher } from './UIActionDispatcher'

export interface ToolResult {
  success: boolean
  data: string
}

interface GuideItem {
  id?: string
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
  /** 数据生成时间：后端下发 generatedAt 或内置兜底集标注的生成日期 */
  generatedAt?: string
  /** 数据来源：backend=后端知识库 / cache=进程内缓存 / fallback=内置离线兜底 */
  source?: string
}

interface GuideEnvelope {
  updatedAt: number;
  generatedAt?: string;
  items: GuideItem[];
}

/** 后端 GET /api/v1/knowledge/guides 的响应形状（T6a），data 即 GuideItem 形态 */
interface BackendGuideResponse {
  ok: boolean
  category?: string
  keyword?: string
  count?: number
  generatedAt?: string
  data?: GuideItem[]
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

  /** 执行器全部分发分支名（与 execute() 的 switch 一一对应），供启动自检与注册表键集 diff */
  private static readonly EXECUTOR_TOOL_NAMES: string[] = [
    // === 5 大核心元工具 ===
    'app_data_query',
    'app_data_mutate',
    'app_control',
    'campus_search',
    'app_pipeline',
    // === 智能高阶辅助工具 ===
    'generate_study_plan',
    'get_current_page_context',
    'execute_page_action',
    'ask_user_clarification',
    // === 向后兼容旧工具分发 ===
    'query_today_courses',
    'query_tomorrow_courses',
    'query_week_courses',
    'query_current_week',
    'get_current_datetime',
    'query_courses_by_date',
    'query_course_by_name',
    'query_next_exam',
    'query_all_exams',
    'query_grades',
    'query_gpa',
    'query_schedule',
    'list_calendar_events',
    'query_reminder_settings',
    'check_login_status',
    'has_course_data',
    'create_schedule',
    'delete_schedule',
    'update_schedule',
    'sync_courses_to_cloud',
    'sync_exams_to_cloud',
    'sync_all_to_cloud',
    'download_all_from_cloud',
    'set_reminder_enabled',
    'set_remind_minutes',
    'refresh_reminders',
    'navigate_to_page',
    'query_campus_guide',
    'search_jwc_news'
  ]

  /** 校园指南进程内缓存：key = `${category}|${keyword}`，仅保留最近成功结果；持久化缓存见阻塞表 B-03 */
  private static readonly guideCache: Map<string, GuideResultData> = new Map<string, GuideResultData>()
  /** 缓存条目上限，超出后整体清空（查询基数低，简化处理即可） */
  private static readonly GUIDE_CACHE_MAX_ENTRIES: number = 32
  /** 内置离线兜底集的生成日期标注 */
  private static readonly BUILTIN_GUIDES_GENERATED_AT: string = '2026-08-24'
  /** 内置最小离线兜底集（校车+缓考）：离线兜底，完整数据由后端知识库下发 */
  private static readonly builtinGuides: GuideItem[] = [
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
    }
  ]

  /** 启动自检只执行一次的标记 */
  private static selfCheckDone: boolean = false

  constructor(context: Context) {
    this.context = context
    this.queryEngine = new DataQueryEngine(context)
    ToolExecutor.checkRegistrySync()
  }

  /**
   * T2 启动自检：比对执行器分发分支名与 ToolRegistry 注册键集，
   * 任一侧存在对方没有的工具名（含 LEGACY_TOOL_NAMES 漂移）即 console.warn 列出差异，
   * 防止再次出现「执行器可执行但注册表未登记」的确认弹窗旁路缺口。
   * 仅在发现漂移时告警，正常情况下零日志噪音。
   */
  private static checkRegistrySync(): void {
    if (ToolExecutor.selfCheckDone) {
      return
    }
    ToolExecutor.selfCheckDone = true
    const executorNames: string[] = ToolExecutor.EXECUTOR_TOOL_NAMES
    const registryNames: string[] = ToolRegistry.getRegisteredToolNames()

    const missingInRegistry: string[] = []
    for (let i = 0; i < executorNames.length; i++) {
      if (registryNames.indexOf(executorNames[i]) < 0) {
        missingInRegistry.push(executorNames[i])
      }
    }
    const unknownToExecutor: string[] = []
    for (let i = 0; i < registryNames.length; i++) {
      if (executorNames.indexOf(registryNames[i]) < 0) {
        unknownToExecutor.push(registryNames[i])
      }
    }
    // LEGACY_TOOL_NAMES 与执行器分支的双向一致性（常量被两侧共用的漂移防线）
    const staleLegacyNames: string[] = []
    for (let i = 0; i < LEGACY_TOOL_NAMES.length; i++) {
      if (executorNames.indexOf(LEGACY_TOOL_NAMES[i]) < 0) {
        staleLegacyNames.push(LEGACY_TOOL_NAMES[i])
      }
    }

    if (missingInRegistry.length > 0 || unknownToExecutor.length > 0 || staleLegacyNames.length > 0) {
      console.warn(`[ToolExecutor][自检] 执行器与工具注册表存在漂移 -> 仅执行器可执行: [${missingInRegistry.join(', ')}]; 仅注册表登记: [${unknownToExecutor.join(', ')}]; LEGACY_TOOL_NAMES 中已失效: [${staleLegacyNames.join(', ')}]`)
    }
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
      console.error('[ToolExecutor] ensureCalendarPermission error:', JSON.stringify(e))
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
        // 注：空壳工具 parse_text_to_schedule 已随 T7 移除（后端 schema/toolMeta 同步删除），
        // 旧会话回放命中该名称时走 default 分支返回「未知工具」即可，无需兼容层。
        case 'generate_study_plan':
          return await this.generateStudyPlan(args)
        case 'get_current_page_context':
          return this.getCurrentPageContext()
        case 'execute_page_action':
          return await this.executePageAction(args)
        case 'ask_user_clarification':
          return this.askUserClarification(args)

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
          return await this.navigateToPage(args)
        case 'query_campus_guide':
          return await this.queryCampusGuide(args)
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
      if (typeStr.length === 0) {
        return { success: false, data: '更新提醒配置失败：缺少必要参数 type' }
      }
      const categoryType = typeStr as ScheduleEventType
      const key = ReminderService.getCategoryReminderKey(categoryType)
      if (!key) {
        return { success: false, data: `未知提醒类别: ${typeStr}，支持类型：course/exam/custom/assignment` }
      }
      const hasEnabled: boolean = payload['enabled'] !== undefined
      const enabled: boolean = hasEnabled ? this.getBooleanArg(payload, 'enabled', true) : true
      const hasMinutes: boolean = payload['minutes'] !== undefined
      const minutes: number = this.getNumberArg(payload, 'minutes', 0)

      if (hasEnabled) {
        await ReminderService.saveCategoryReminderEnabled(this.context, categoryType, enabled)
      }
      if (enabled && hasMinutes && minutes > 0) {
        await ReminderService.saveCategoryRemindMinutes(this.context, categoryType, minutes)
      }

      try {
        await ReminderService.refreshScheduleReminders(this.context)
      } catch (e) {
        console.warn(`[ToolExecutor] refreshScheduleReminders after mutate error: ${String(e)}`)
      }

      const statusDesc: string = enabled ? `已开启${minutes > 0 ? `（提前 ${minutes} 分钟）` : ''}` : '已关闭'
      return {
        success: true,
        data: JSON.stringify({
          message: `提醒配置已更新: ${typeStr} 提醒${statusDesc}`,
          type: typeStr,
          enabled: enabled,
          minutes: (enabled && minutes > 0) ? minutes : undefined
        })
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
      return await this.navigateToPage(params)
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

    // 默认走后端校园指南知识库（含缓存与内置兜底降级）
    const localRes: ToolResult = await this.queryCampusGuide({ 'keyword': query, 'category': category })
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

  private async navigateToPage(args: Record<string, Object>): Promise<ToolResult> {
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
    // T4：pushUrl 的失败必须捕获并如实回传 success:false，让模型能向用户解释跳转未发生
    try {
      await router.pushUrl({ url: url })
      return { success: true, data: JSON.stringify({ message: `已导航到 ${page} 页面` }) }
    } catch (err) {
      console.error(`[ToolExecutor] navigate error: ${String(err)}`)
      const detail: string = this.extractErrorMessage(err as Object)
      return {
        success: false,
        data: JSON.stringify({ message: `跳转到 ${page} 页面失败`, error: detail })
      }
    }
  }

  /** 从路由/网络异常对象中尽量提取可读的 message，取不到时退化为 String() 形式 */
  private extractErrorMessage(err: Object): string {
    try {
      const rec = err as Record<string, Object>
      const msg = rec['message']
      if (msg !== undefined && msg !== null && String(msg).length > 0) {
        return String(msg)
      }
    } catch (e) {
      // ignore
    }
    return String(err)
  }

  // === 校园指南检索（T6a/P2-1a：四级降级：后端 -> 内存 -> Preferences last-good -> 内置最小离线兜底） ===
  private async queryCampusGuide(args: Record<string, Object>): Promise<ToolResult> {
    const category: string = this.getStringArg(args, 'category', 'all')
    const keyword: string = this.getStringArg(args, 'keyword', '').toLowerCase()
    const cacheKey: string = `${category}|${keyword}`

    // 1) 后端检索：地址与请求头统一经 AgentEndpointConfig（与 searchJwcNews 同一口径）
    const endpoint: AgentEndpoint = await AgentEndpointConfig.resolve(this.context)
    if (AgentEndpointConfig.isReady(endpoint)) {
      // 约定：category=all 时传空串表示全量
      const categoryParam: string = (category === 'all') ? '' : category
      const requestUrl: string = AgentEndpointConfig.joinUrl(endpoint, `api/v1/knowledge/guides?category=${encodeURIComponent(categoryParam)}&keyword=${encodeURIComponent(keyword)}`)
      const httpRequest = http.createHttp()
      try {
        const response = await httpRequest.request(requestUrl, {
          method: http.RequestMethod.GET,
          header: AgentEndpointConfig.buildHeaders(endpoint),
          readTimeout: 10000,
          connectTimeout: 5000
        })
        if (response.responseCode === 200 && response.result) {
          let resStr = response.result as string
          if (typeof resStr !== 'string') {
            resStr = JSON.stringify(response.result)
          }
          const parsed = JSON.parse(resStr) as BackendGuideResponse
          if (parsed.ok && parsed.data && parsed.data.length > 0) {
            const resultData: GuideResultData = {
              category: category,
              keyword: keyword,
              count: parsed.data.length,
              guides: parsed.data,
              generatedAt: parsed.generatedAt,
              source: 'backend'
            }
            ToolExecutor.cacheGuideResult(cacheKey, resultData)
            const isFullDataset: boolean = (category === 'all' || category === '') && keyword.length === 0
            this.persistGuidesLastGood(parsed.data, parsed.generatedAt, isFullDataset)
            return { success: true, data: JSON.stringify(resultData) }
          }
        } else {
          console.error(`[ToolExecutor] 校园指南后端检索异常: HTTP ${response.responseCode}`)
        }
      } catch (err) {
        console.error(`[ToolExecutor] 连接校园指南服务失败: ${String(err)}`)
      } finally {
        httpRequest.destroy()
      }
    }

    // 2) 降级一：复用进程内缓存的上次成功结果
    const cached: GuideResultData | undefined = ToolExecutor.guideCache.get(cacheKey)
    if (cached !== undefined) {
      const cachedResult: GuideResultData = {
        category: cached.category,
        keyword: cached.keyword,
        count: cached.count,
        guides: cached.guides,
        generatedAt: cached.generatedAt,
        source: 'cache'
      }
      console.warn(`[ToolExecutor] 校园指南后端不可用，命中进程内缓存（source=cache, count=${cached.count}）`)
      return { success: true, data: JSON.stringify(cachedResult) }
    }

    // 3) 降级二：从 preferences 读取持久化 last-good 缓存（P2-1a 清偿 B-03）
    const lastGood = this.loadGuidesLastGood()
    if (lastGood !== null) {
      let matched: GuideItem[] = lastGood.items
      if (category !== 'all') {
        matched = matched.filter((g: GuideItem) => g.category === category)
      }
      if (keyword.length > 0) {
        matched = matched.filter((g: GuideItem) => g.title.toLowerCase().includes(keyword) || g.content.toLowerCase().includes(keyword) || (g.details !== undefined && g.details.toLowerCase().includes(keyword)))
      }
      if (matched.length > 0) {
        const lastGoodData: GuideResultData = {
          category: category,
          keyword: keyword,
          count: matched.length,
          guides: matched,
          generatedAt: lastGood.generatedAt,
          source: 'last_good'
        }
        console.warn(`[ToolExecutor] 校园指南后端不可用，命中 preferences last-good 缓存（source=last_good, count=${matched.length}）`)
        return { success: true, data: JSON.stringify(lastGoodData) }
      }
    }

    // 4) 降级三：内置最小离线兜底集（离线兜底，完整数据由后端下发）
    let matched: GuideItem[] = ToolExecutor.builtinGuides
    if (category !== 'all') {
      matched = matched.filter((g: GuideItem) => g.category === category)
    }
    if (keyword.length > 0) {
      matched = matched.filter((g: GuideItem) => g.title.toLowerCase().includes(keyword) || g.content.toLowerCase().includes(keyword) || (g.details !== undefined && g.details.toLowerCase().includes(keyword)))
    }
    const fallbackData: GuideResultData = {
      category: category,
      keyword: keyword,
      count: matched.length,
      guides: matched,
      generatedAt: ToolExecutor.BUILTIN_GUIDES_GENERATED_AT,
      source: 'fallback'
    }
    console.warn(`[ToolExecutor] 校园指南无缓存可用，返回内置离线兜底集（source=fallback, count=${matched.length}）`)
    return { success: true, data: JSON.stringify(fallbackData) }
  }

  /** 写入指南进程内缓存；超过容量上限时整体清空（查询基数低，简化处理即可） */
  private static cacheGuideResult(key: string, value: GuideResultData): void {
    if (!ToolExecutor.guideCache.has(key) && ToolExecutor.guideCache.size >= ToolExecutor.GUIDE_CACHE_MAX_ENTRIES) {
      ToolExecutor.guideCache.clear()
    }
    ToolExecutor.guideCache.set(key, value)
  }

  /** 写入校园指南 last-good 到 Preferences（P2-1a：支持全量与增量合并） */
  private persistGuidesLastGood(items: GuideItem[], generatedAt?: string, isFullDataset: boolean = false): void {
    try {
      let finalItems: GuideItem[] = items
      if (!isFullDataset) {
        const existing = this.loadGuidesLastGood()
        if (existing && Array.isArray(existing.items) && existing.items.length > 0) {
          const itemMap = new Map<string, GuideItem>()
          for (let i = 0; i < existing.items.length; i++) {
            const it = existing.items[i]
            const key = it.id ? it.id : (it.category + ':' + it.title)
            itemMap.set(key, it)
          }
          for (let i = 0; i < items.length; i++) {
            const it = items[i]
            const key = it.id ? it.id : (it.category + ':' + it.title)
            itemMap.set(key, it)
          }
          const merged: GuideItem[] = []
          itemMap.forEach((val: GuideItem) => {
            merged.push(val)
          })
          finalItems = merged
        }
      }
      const envelope: GuideEnvelope = {
        updatedAt: Date.now(),
        generatedAt: generatedAt,
        items: finalItems
      }
      const text: string = JSON.stringify(envelope)
      const pref = preferences.getPreferencesSync(this.context, { name: AppConstants.COURSE_TABLE_PREF_NAME })
      const existing: string = pref.getSync(AppConstants.PREF_CAMPUS_GUIDES_JSON_KEY, '') as string
      if (existing !== text) {
        pref.putSync(AppConstants.PREF_CAMPUS_GUIDES_JSON_KEY, text)
        pref.flushSync()
      }
    } catch (e) {
      console.warn(`[ToolExecutor] persistGuidesLastGood error: ${String(e)}`)
    }
  }

  /** 从 Preferences 读取校园指南 last-good 缓存（P2-1a） */
  private loadGuidesLastGood(): GuideEnvelope | null {
    try {
      const pref = preferences.getPreferencesSync(this.context, { name: AppConstants.COURSE_TABLE_PREF_NAME })
      const text: string = pref.getSync(AppConstants.PREF_CAMPUS_GUIDES_JSON_KEY, '') as string
      if (!text) {
        return null
      }
      const envelope = JSON.parse(text) as GuideEnvelope
      if (envelope && Array.isArray(envelope.items) && envelope.items.length > 0) {
        return envelope
      }
    } catch (e) {
      console.warn(`[ToolExecutor] loadGuidesLastGood error: ${String(e)}`)
    }
    return null
  }

  private async searchJwcNews(args: Record<string, Object>): Promise<ToolResult> {
    const keyword = this.getStringArg(args, 'keyword', '')
    const category = this.getStringArg(args, 'category', 'all')
    // 后端地址与密钥统一从设置读取，未配置时直接返回引导提示（不崩溃）
    const agentEndpoint: AgentEndpoint = await AgentEndpointConfig.resolve(this.context)
    if (!AgentEndpointConfig.isReady(agentEndpoint)) {
      return { success: false, data: AgentEndpointConfig.missingHint(agentEndpoint) }
    }

    const query = `keyword=${encodeURIComponent(keyword)}&category=${encodeURIComponent(category)}&limit=6`
    const requestUrl = AgentEndpointConfig.joinUrl(agentEndpoint, `api/jwc/search?${query}`)
    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(requestUrl, {
        method: http.RequestMethod.GET,
        header: AgentEndpointConfig.buildHeaders(agentEndpoint),
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

  /**
   * 澄清反问工具：后端 LLM 在意图模糊/信息不足时下发问题与可选快捷项。
   * 问题文案由模型随后以正文形式展示给用户（端侧无需弹 UI），
   * 这里只需如实回报「已转达」，让后端图正常收束到等待用户下一条消息回答；
   * 若缺实现会被判执行失败，在气泡上标红「ask_user_clarification失败」（U2 复测发现的缺口）。
   */
  private askUserClarification(args: Record<string, Object>): ToolResult {
    const question: string = this.getStringArg(args, 'question')
    if (question.length === 0) {
      return { success: false, data: '缺少 question 参数，无法向用户转达澄清问题' }
    }
    return { success: true, data: '澄清问题已展示给用户，用户将在下一条消息中回答' }
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
