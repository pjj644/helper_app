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
        parameters: { 'page': { type: 'string', description: '页面标识：course_table(课表)、exam(考试)、grade(成绩)、schedule(日程)、settings(设置)' } },
        required: ['page'],
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
