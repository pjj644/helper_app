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
        name: 'parse_text_to_schedule',
        description: '从文本中提取日程结构',
        parameters: {
          'rawText': { type: 'string', description: '原始文本内容' }
        },
        required: ['rawText'],
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
        description: '在当前页面触发 UI 交互动作（如切换周次、切换Tab、触发导入、显示聚光灯引导等）',
        parameters: {
          'action': { type: 'string', description: '动作类型：switch_week/switch_tab/import_courses/import_grades/import_exams/show_guidance' },
          'params': { type: 'object', description: '动作参数' }
        },
        required: ['action'],
        requiresConfirmation: false,
        riskLevel: 'low'
      },

      // 向后兼容保留
      {
        name: 'query_today_courses',
        description: '查询今天的课程安排',
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
        name: 'navigate_to_page',
        description: '导航到应用内指定页面',
        parameters: { 'page': { type: 'string', description: '页面标识' } },
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
    const tool: ToolDefinition | undefined = ToolRegistry.getToolDefinition(name)
    return tool ? tool.requiresConfirmation : false
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
