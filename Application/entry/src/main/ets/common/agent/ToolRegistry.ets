export interface ToolParamDef {
  type: string
  description: string
}

export interface ToolDefinition {
  name: string
  description: string
  parameters: Record<string, ToolParamDef>
  required: string[]
  requiresConfirmation: boolean
  riskLevel: 'low' | 'medium' | 'high'
}

/**
 * 旧版别名工具名清单（T2）。
 * 与 ToolExecutor 分发分支中的「向后兼容旧工具分发」段一一对应，
 * 供本文件注册登记与 ToolExecutor 启动自检共用；
 * 任一侧增删工具时必须同步维护此常量，否则启动自检会 console.warn 漂移差异。
 */
export const LEGACY_TOOL_NAMES: string[] = [
  // 查询类（免确认）
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
  'query_campus_guide',
  'search_jwc_news',
  'navigate_to_page',
  // 日程/提醒变更类（需确认）
  'create_schedule',
  'delete_schedule',
  'update_schedule',
  'set_reminder_enabled',
  'set_remind_minutes',
  // 云端同步/恢复、提醒重建类（高危需确认）
  'sync_courses_to_cloud',
  'sync_exams_to_cloud',
  'sync_all_to_cloud',
  'download_all_from_cloud',
  'refresh_reminders'
]

export class ToolRegistry {
  private static tools: ToolDefinition[] = ToolRegistry.initTools()

  private static initTools(): ToolDefinition[] {
    const emptyParams: Record<string, ToolParamDef> = {}
    const tools: ToolDefinition[] = [
      // 5 大核心元工具
      {
        name: 'app_data_query',
        description: '统一查询 App 内所有核心数据（课表、考试、成绩/GPA、日程、系统日历、提醒配置、系统时间与教学周）',
        parameters: {
          'domain': { type: 'string', description: '数据领域：course/exam/grade/schedule/calendar/reminder_setting/system_info' },
          'filter': { type: 'object', description: '动态多维度过滤条件' },
          'limit': { type: 'number', description: '最大记录数限制' }
        },
        required: ['domain'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'app_data_mutate',
        description: '创建、修改或删除日程、日历事件及提醒配置',
        parameters: {
          'domain': { type: 'string', description: '变更的数据领域：schedule/calendar/reminder_setting' },
          'action': { type: 'string', description: '操作类型：create/update/delete' },
          'payload': { type: 'object', description: '变更载荷数据' },
          'syncCalendar': { type: 'boolean', description: '是否同步写入系统日历' },
          'remindMinutesBefore': { type: 'number', description: '提前提醒分钟数' }
        },
        required: ['domain', 'action', 'payload'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'app_control',
        description: '控制页面路由跳转、云端同步/恢复、提醒数据全量刷新',
        parameters: {
          'action': { type: 'string', description: '控制指令：navigate/sync_cloud/download_cloud/refresh_reminders' },
          'params': { type: 'object', description: '附加参数' }
        },
        required: ['action'],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'campus_search',
        description: '检索成电校园生活指南及教务处官网公告新闻',
        parameters: {
          'query': { type: 'string', description: '检索关键词或问题' },
          'source': { type: 'string', description: '检索来源：guide/jwc_news/auto' },
          'category': { type: 'string', description: '指南分类' }
        },
        required: ['query'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'app_pipeline',
        description: '声明式复合流水线批处理，单次下发多步原子动作在端侧顺序执行',
        parameters: {
          'steps': { type: 'array', description: '顺序执行的步骤数组' }
        },
        required: ['steps'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },

      // 智能辅助工具
      {
        name: 'generate_study_plan',
        description: '分析所有即将到来的考试科目，生成考前每日复习冲刺任务计划',
        parameters: {
          'dailyHours': { type: 'number', description: '每日可用复习小时数' },
          'focusCourse': { type: 'string', description: '重点突击课程名' }
        },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'get_current_page_context',
        description: '获取用户手机当前所在的页面名称、数据概览及可用操作集合',
        parameters: {},
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'execute_page_action',
        description: '在当前页面触发 UI 交互动作（如切换周次、切换Tab、触发导入、打开外部网页、显示聚光灯高亮引导等）或指导用户操作。注意：聚光灯高亮仅支持 get_current_page_context 返回的 highlightableIds 中列出的元素，其余 id 一律会被端侧拒绝。',
        parameters: {
          'action': { type: 'string', description: '动作类型：switch_week(切换周次), switch_tab(切换Tab), import_courses(导入课表), import_grades(导入成绩), import_exams(导入考试), web(打开外部网页,需params.url), show_guidance(聚光灯高亮引导)' },
          'params': { type: 'object', description: '动作参数，如 { week: 5 }, { url: "https://...", title: "校园地图" }, { targetElementId: "<必须取自 get_current_page_context 返回的 highlightableIds>", hintText: "点击这里" }，show_guidance 的 targetElementId 严禁编造' }
        },
        required: ['action'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'ask_user_clarification',
        description: '意图模糊或缺少关键信息时向用户反问（问题由模型正文展示，端侧仅确认已转达）',
        parameters: {
          'question': { type: 'string', description: '向用户反问的具体问题' },
          'options': { type: 'object', description: '快捷选择候选项列表（可选）' },
          'allowFreeInput': { type: 'boolean', description: '是否允许自由文本补充，默认 true（可选）' }
        },
        required: ['question'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },

      // 向后兼容保留（别名工具，名称清单见 LEGACY_TOOL_NAMES，风险等级继承所委托的元工具）
      {
        name: 'query_today_courses',
        description: '查询今天的课程安排',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_tomorrow_courses',
        description: '查询明天的课程安排',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_week_courses',
        description: '查询指定周的课程安排',
        parameters: { 'weekNumber': { type: 'number', description: '教学周数' } },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_current_week',
        description: '查询当前是第几教学周',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'get_current_datetime',
        description: '查询当前系统时间与教学周信息',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_courses_by_date',
        description: '查询指定日期的课程安排',
        parameters: { 'date': { type: 'string', description: '日期（YYYY-MM-DD）' } },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_course_by_name',
        description: '按课程名称关键词查询课程信息',
        parameters: { 'courseName': { type: 'string', description: '课程名称关键词' } },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_next_exam',
        description: '查询最近一场即将到来的考试',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_all_exams',
        description: '查询所有考试安排',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_grades',
        description: '查询成绩列表和GPA信息',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_gpa',
        description: '查询GPA',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_schedule',
        description: '查询日程安排',
        parameters: { 'date': { type: 'string', description: '日期' } },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'list_calendar_events',
        description: '查询系统日历中指定时间范围内的事件',
        parameters: {
          'startDate': { type: 'string', description: '起始日期' },
          'endDate': { type: 'string', description: '结束日期' }
        },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_reminder_settings',
        description: '查询各类日程的提醒配置',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'check_login_status',
        description: '检查用户登录状态并返回账号信息',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'has_course_data',
        description: '检查本地是否已导入课程数据',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_campus_guide',
        description: '按关键词与分类检索校园生活指南',
        parameters: {
          'keyword': { type: 'string', description: '检索关键词' },
          'category': { type: 'string', description: '指南分类' }
        },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'search_jwc_news',
        description: '检索教务处官网公告新闻',
        parameters: {
          'keyword': { type: 'string', description: '检索关键词' },
          'category': { type: 'string', description: '公告分类' }
        },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'navigate_to_page',
        description: '导航到应用内指定页面',
        parameters: { 'page': { type: 'string', description: '页面标识' } },
        required: ['page'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'create_schedule',
        description: '创建一条自定义日程',
        parameters: {
          'title': { type: 'string', description: '标题' },
          'date': { type: 'string', description: '日期' },
          'startTime': { type: 'string', description: '开始时间' },
          'endTime': { type: 'string', description: '结束时间' }
        },
        required: ['title', 'date', 'startTime', 'endTime'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'delete_schedule',
        description: '删除指定ID的日程',
        parameters: { 'eventId': { type: 'string', description: '日程ID' } },
        required: ['eventId'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'update_schedule',
        description: '更新指定ID的日程内容',
        parameters: {
          'eventId': { type: 'string', description: '日程ID' },
          'title': { type: 'string', description: '标题' },
          'date': { type: 'string', description: '日期' },
          'startTime': { type: 'string', description: '开始时间' },
          'endTime': { type: 'string', description: '结束时间' },
          'location': { type: 'string', description: '地点' },
          'description': { type: 'string', description: '描述' }
        },
        required: ['eventId'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'set_reminder_enabled',
        description: '更新指定类型日程的提醒开关与提前提醒时长',
        parameters: {
          'type': { type: 'string', description: '日程类型：course/exam/custom/assignment' },
          'enabled': { type: 'boolean', description: '是否开启该类日程提醒（默认 true）' },
          'minutes': { type: 'number', description: '提前提醒分钟数（可选）' }
        },
        required: ['type'],
        requiresConfirmation: true,
        riskLevel: 'low'
      },
      {
        name: 'set_remind_minutes',
        description: '更新指定类型日程的提前提醒分钟数',
        parameters: {
          'type': { type: 'string', description: '日程类型：custom/exam/assignment 等' },
          'minutes': { type: 'number', description: '提前提醒分钟数' }
        },
        required: [],
        requiresConfirmation: true,
        riskLevel: 'low'
      },
      {
        name: 'sync_courses_to_cloud',
        description: '同步课表数据到云端',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'sync_exams_to_cloud',
        description: '同步考试安排到云端',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'sync_all_to_cloud',
        description: '全量同步到云端',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'download_all_from_cloud',
        description: '从云端恢复数据',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'refresh_reminders',
        description: '全量刷新重建日程与系统日历提醒',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      }
    ]

    // 注册侧自检（T2）：LEGACY_TOOL_NAMES 中每个别名都必须已注册，防止常量与注册表再次漂移
    for (let i = 0; i < LEGACY_TOOL_NAMES.length; i++) {
      let found: boolean = false
      for (let j = 0; j < tools.length; j++) {
        if (tools[j].name === LEGACY_TOOL_NAMES[i]) {
          found = true
          break
        }
      }
      if (!found) {
        console.warn(`[ToolRegistry] 注册表自检失败：LEGACY_TOOL_NAMES 中的工具未注册: ${LEGACY_TOOL_NAMES[i]}`)
      }
    }

    return tools
  }

  /**
   * 按名称查找工具定义。
   * T2 fail-closed：未命中时不再返回 undefined，而是返回「高危且需确认」的哨兵定义，
   * 堵住「查不到定义 → 默认低风险放行」的确认弹窗旁路；哨兵沿用入参作为 name，便于日志定位。
   */
  static getToolDefinition(name: string): ToolDefinition | undefined {
    for (let i = 0; i < ToolRegistry.tools.length; i++) {
      if (ToolRegistry.tools[i].name === name) {
        return ToolRegistry.tools[i]
      }
    }
    console.warn(`[ToolRegistry] 工具 "${name}" 未注册，已按 fail-closed 哨兵定义处理（riskLevel=high，需确认）`)
    const sentinel: ToolDefinition = {
      name: name,
      description: `未注册工具（fail-closed 哨兵定义）: ${name}`,
      parameters: {},
      required: [],
      requiresConfirmation: true,
      riskLevel: 'high'
    }
    return sentinel
  }

  /** 返回当前已注册的全部工具名（供 ToolExecutor 启动自检做键集 diff） */
  static getRegisteredToolNames(): string[] {
    const names: string[] = []
    for (let i = 0; i < ToolRegistry.tools.length; i++) {
      names.push(ToolRegistry.tools[i].name)
    }
    return names
  }

  static requiresConfirmation(name: string, argsStr?: string): boolean {
    if (name === 'app_control' && argsStr) {
      try {
        const parsed: Record<string, Object> = JSON.parse(argsStr) as Record<string, Object>
        if (parsed['action'] === 'navigate') {
          return false
        }
      } catch (e) {
        // ignore
      }
    }
    // 未注册工具经哨兵定义走 high 需确认；兜底分支同样取 true 保持 fail-closed 口径
    const tool: ToolDefinition | undefined = ToolRegistry.getToolDefinition(name)
    return tool ? tool.requiresConfirmation : true
  }

  /** 工具显示名映射（单一来源）：确认弹窗与工具调用卡片共用，未收录时原样返回工具名 */
  private static readonly TOOL_DISPLAY_NAMES: Record<string, string> = {
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
    'update_schedule': '修改日程',
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
    'search_jwc_news': '检索教务处官网'
  }

  /** 取工具中文显示名（AssistantPage 与悬浮球浮窗共用，避免映射多处漂移） */
  static getDisplayName(name: string): string {
    const display: string | undefined = ToolRegistry.TOOL_DISPLAY_NAMES[name]
    return display !== undefined ? display : name
  }

  static getRiskLevel(name: string, argsStr?: string): string {
    if (name === 'app_control' && argsStr) {
      try {
        const parsed: Record<string, Object> = JSON.parse(argsStr) as Record<string, Object>
        if (parsed['action'] === 'navigate') {
          return 'low'
        }
      } catch (e) {
        // ignore
      }
    }
    // 未注册工具返回 high（fail-closed），确认弹窗将展示高危警示样式
    const tool: ToolDefinition | undefined = ToolRegistry.getToolDefinition(name)
    return tool ? tool.riskLevel : 'high'
  }

  static getToolDescriptions(): string {
    let result: string = ''
    for (let i = 0; i < ToolRegistry.tools.length; i++) {
      const tool: ToolDefinition = ToolRegistry.tools[i]
      result += `- ${tool.name}: ${tool.description}\n`
    }
    return result
  }
}
