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

interface ToolFunctionDef {
  name: string
  description: string
  parameters: ToolParametersDef
}

interface ToolParametersDef {
  type: string
  properties: Record<string, ToolParamDef>
  required: string[]
}

interface ToolSchemaItem {
  type: string
  function: ToolFunctionDef
}

export class ToolRegistry {
  private static tools: ToolDefinition[] = ToolRegistry.initTools()

  private static initTools(): ToolDefinition[] {
    const emptyParams: Record<string, ToolParamDef> = {}
    const tools: ToolDefinition[] = [
      {
        name: 'query_today_courses',
        description: '查询今天的课程安排，返回课程名称、时间、教室、教师等信息',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_week_courses',
        description: '查询指定周的课程安排，不传weekNumber则查询本周',
        parameters: { 'weekNumber': { type: 'number', description: '教学周数，如1-20，不传则查询当前周' } },
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
        name: 'query_next_exam',
        description: '查询最近一场即将到来的考试，包含倒计时信息',
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
        description: '查询GPA（总评绩点和最新学期绩点）',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_schedule',
        description: '查询日程安排，可指定日期筛选',
        parameters: { 'date': { type: 'string', description: '日期，格式YYYY-MM-DD，不传则查询所有日程' } },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'check_login_status',
        description: '检查用户是否已登录，返回登录状态和用户邮箱',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'check_time_conflict',
        description: '检查指定日期和时间段是否有日程冲突',
        parameters: {
          'date': { type: 'string', description: '日期，格式YYYY-MM-DD' },
          'startTime': { type: 'string', description: '开始时间，格式HH:mm' },
          'endTime': { type: 'string', description: '结束时间，格式HH:mm' }
        },
        required: ['date', 'startTime', 'endTime'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_reminder_settings',
        description: '查询当前的提醒设置，包括总开关、各分类开关和提醒时间',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'has_course_data',
        description: '检查是否有课表数据',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'create_schedule',
        description: '创建一条自定义日程，需要提供标题、日期和时间',
        parameters: {
          'title': { type: 'string', description: '日程标题' },
          'date': { type: 'string', description: '日期，格式YYYY-MM-DD' },
          'startTime': { type: 'string', description: '开始时间，格式HH:mm' },
          'endTime': { type: 'string', description: '结束时间，格式HH:mm' },
          'location': { type: 'string', description: '地点，可选' },
          'description': { type: 'string', description: '描述，可选' },
          'type': { type: 'string', description: '类型：custom(自定义)或assignment(作业)，默认custom' }
        },
        required: ['title', 'date', 'startTime', 'endTime'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'delete_schedule',
        description: '删除指定ID的日程',
        parameters: { 'eventId': { type: 'string', description: '要删除的日程ID' } },
        required: ['eventId'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'sync_courses_to_cloud',
        description: '将本地课表数据同步到云端，需要用户已登录',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'sync_exams_to_cloud',
        description: '将本地考试数据同步到云端，需要用户已登录',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'sync_all_to_cloud',
        description: '将本地全部数据（课表+考试）同步到云端，需要用户已登录',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'download_all_from_cloud',
        description: '从云端恢复全部数据到本地，需要用户已登录',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'high'
      },
      {
        name: 'set_reminder_enabled',
        description: '设置某类日程的提醒开关',
        parameters: {
          'type': { type: 'string', description: '类型：exam/course/custom/assignment' },
          'enabled': { type: 'boolean', description: '是否启用' }
        },
        required: ['type', 'enabled'],
        requiresConfirmation: true,
        riskLevel: 'low'
      },
      {
        name: 'set_remind_minutes',
        description: '设置某类日程的提醒提前时间',
        parameters: {
          'type': { type: 'string', description: '类型：exam/course/custom/assignment' },
          'minutes': { type: 'number', description: '提前提醒的分钟数' }
        },
        required: ['type', 'minutes'],
        requiresConfirmation: true,
        riskLevel: 'low'
      },
      {
        name: 'refresh_reminders',
        description: '刷新全部提醒，重新同步课程和考试到日程并重建提醒',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: true,
        riskLevel: 'low'
      },
      {
        name: 'navigate_to_page',
        description: '导航到应用内指定页面',
        parameters: { 'page': { type: 'string', description: '页面标识：course_table(课表)、exam(考试)、grade(成绩)、schedule(日程)、settings(设置)、course_import(导入课表)、exam_import(导入考试)、grade_import(导入成绩)、assistant(AI助手)、home(首页)' } },
        required: ['page'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'get_current_datetime',
        description: '获取当前日期、时间、星期几、第几教学周、当前学期等基础时间信息。涉及"今天/明天/本周/这学期"等相对时间时务必先调用此工具。',
        parameters: emptyParams,
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_courses_by_date',
        description: '查询指定日期的课程安排（自动换算教学周与星期）',
        parameters: { 'date': { type: 'string', description: '日期，格式YYYY-MM-DD' } },
        required: ['date'],
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
        name: 'query_course_by_name',
        description: '按课程名查询上课时间、教室、教师及生效周次（支持模糊匹配）',
        parameters: { 'courseName': { type: 'string', description: '课程名称或关键词' } },
        required: ['courseName'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'list_calendar_events',
        description: '列出已写入系统日历的本应用事件，默认查询未来30天',
        parameters: {
          'startDate': { type: 'string', description: '起始日期YYYY-MM-DD，默认今天' },
          'endDate': { type: 'string', description: '结束日期YYYY-MM-DD，默认今天+30天' }
        },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'add_to_calendar',
        description: '创建一条日程并写入系统日历，可设置提前若干分钟提醒',
        parameters: {
          'title': { type: 'string', description: '日程标题' },
          'date': { type: 'string', description: '日期，格式YYYY-MM-DD' },
          'startTime': { type: 'string', description: '开始时间，格式HH:mm' },
          'endTime': { type: 'string', description: '结束时间，格式HH:mm' },
          'remindMinutesBefore': { type: 'number', description: '提前提醒的分钟数，默认30' },
          'location': { type: 'string', description: '地点，可选' },
          'description': { type: 'string', description: '描述，可选' },
          'type': { type: 'string', description: '类型：custom(自定义)或assignment(作业)，默认custom' }
        },
        required: ['title', 'date', 'startTime', 'endTime'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'add_exam_to_calendar',
        description: '把一场考试写入系统日历并设置提前提醒。不传courseName则取最近一场即将到来的考试。',
        parameters: {
          'courseName': { type: 'string', description: '课程名称或关键词，不传则取最近一场考试' },
          'remindMinutesBefore': { type: 'number', description: '提前提醒的分钟数，默认30' }
        },
        required: [],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'add_course_to_calendar',
        description: '把课程写入系统日历并设置提前提醒。不传courseName则添加当天全部课程。',
        parameters: {
          'courseName': { type: 'string', description: '课程名称或关键词，不传则添加当天全部课程' },
          'date': { type: 'string', description: '日期YYYY-MM-DD，默认今天' },
          'remindMinutesBefore': { type: 'number', description: '提前提醒的分钟数，默认15' }
        },
        required: [],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'remove_calendar_event',
        description: '从系统日历移除指定事件（按系统日历事件ID）',
        parameters: { 'calendarEventId': { type: 'number', description: '系统日历事件ID，可通过list_calendar_events获取' } },
        required: ['calendarEventId'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'update_schedule',
        description: '编辑已有的应用内日程，修改其字段。若已关联系统日历事件，会同步更新日历。',
        parameters: {
          'eventId': { type: 'string', description: '要编辑的日程ID' },
          'title': { type: 'string', description: '新标题' },
          'date': { type: 'string', description: '新日期YYYY-MM-DD' },
          'startTime': { type: 'string', description: '新开始时间HH:mm' },
          'endTime': { type: 'string', description: '新结束时间HH:mm' },
          'location': { type: 'string', description: '新地点' },
          'description': { type: 'string', description: '新描述' },
          'type': { type: 'string', description: '新类型：custom或assignment' }
        },
        required: ['eventId'],
        requiresConfirmation: true,
        riskLevel: 'medium'
      },
      {
        name: 'generate_study_plan',
        description: '分析所有即将到来的考试，结合剩余天数自动生成每日考前复习计划',
        parameters: {
          'dailyHours': { type: 'number', description: '每日复习小时数，默认4' },
          'focusCourse': { type: 'string', description: '重点复习课程名称，可选' }
        },
        required: [],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'query_campus_guide',
        description: '查询电子科技大学校园生活指南与政策（校车时刻/免修/保研政策/场馆）',
        parameters: {
          'category': { type: 'string', description: '分类：bus/academic_policy/hospital/facilities/all' },
          'keyword': { type: 'string', description: '关键词' }
        },
        required: ['category'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'parse_text_to_schedule',
        description: '从通知公告等文本中智能解析日程（标题/时间/地点）',
        parameters: {
          'rawText': { type: 'string', description: '原始文本' }
        },
        required: ['rawText'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },
      {
        name: 'search_jwc_news',
        description: '从电子科技大学教务处官网(www.jwc.uestc.edu.cn)实时检索最新教务通知、考试公告、选拔公示与新闻',
        parameters: {
          'keyword': { type: 'string', description: '检索关键词' },
          'category': { type: 'string', description: '分类：all(全部)、jxtz(教学通知)、kwtz(考务通知)、sjjx(实践教学)、xjgl(学籍管理)' }
        },
        required: ['keyword'],
        requiresConfirmation: false,
        riskLevel: 'low'
      }
    ]
    return tools
  }

  static getToolDefinition(name: string): ToolDefinition | undefined {
    for (let i = 0; i < ToolRegistry.tools.length; i++) {
      if (ToolRegistry.tools[i].name === name) {
        return ToolRegistry.tools[i]
      }
    }
    return undefined
  }

  static requiresConfirmation(name: string): boolean {
    const tool: ToolDefinition | undefined = ToolRegistry.getToolDefinition(name)
    return tool ? tool.requiresConfirmation : false
  }

  static getRiskLevel(name: string): string {
    const tool: ToolDefinition | undefined = ToolRegistry.getToolDefinition(name)
    return tool ? tool.riskLevel : 'low'
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
