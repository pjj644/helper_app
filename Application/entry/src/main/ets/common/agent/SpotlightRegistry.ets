/**
 * 聚光灯高亮元素契约（SpotlightIds / SpotlightRegistry）
 *
 * 契约约定（show_guidance 能力的唯一真源）：
 * 1. SpotlightIds 中的每个 id 必须与对应页面组件的 `.id()` 标注完全一致，
 *    新增/改名 id 时页面标注与本表必须同步修改，二者缺一不可；
 * 2. 注册表的 pageName 键必须与 PageContextTracker 各页快照上报的 pageName 对齐
 *    （如发现页 Index.ets 上报 'discover'）；
 * 3. execute_page_action 的 show_guidance 只接受本注册表登记过的 id：
 *    模型的 targetElementId 必须取自 get_current_page_context 返回的 highlightableIds，严禁编造，
 *    未登记的 id 会在 ToolExecutor 侧被如实拒绝（success:false 并回带 availableIds）。
 */

/** 可高亮元素 id 常量表（与页面组件 .id() 标注一一对应） */
export class SpotlightIds {
  // === 发现页（pageName='discover'，对应 pages/Index.ets） ===
  /** 「云中成电」Hero 入口卡 */
  static readonly DISCOVER_HERO_CLOUD: string = 'discover_hero_cloud'
  /** 常用服务三卡：成绩查询 */
  static readonly DISCOVER_QUICK_GRADES: string = 'discover_quick_grades'
  /** 常用服务三卡：成电班车 */
  static readonly DISCOVER_QUICK_BUS: string = 'discover_quick_bus'
  /** 常用服务三卡：校园日历 */
  static readonly DISCOVER_QUICK_CALENDAR: string = 'discover_quick_calendar'
  /** 功能九宫格（顺序与 Index.ets tools 数组一致）：云中成电 */
  static readonly DISCOVER_TOOL_CLOUD_PORTAL: string = 'discover_tool_cloud_portal'
  /** 功能九宫格：成电班车 */
  static readonly DISCOVER_TOOL_BUS: string = 'discover_tool_bus'
  /** 功能九宫格：AI 助手 */
  static readonly DISCOVER_TOOL_AI: string = 'discover_tool_ai'
  /** 功能九宫格：成绩查询 */
  static readonly DISCOVER_TOOL_GRADES: string = 'discover_tool_grades'
  /** 功能九宫格：校园地图 */
  static readonly DISCOVER_TOOL_MAP: string = 'discover_tool_map'
  /** 功能九宫格：图书馆 */
  static readonly DISCOVER_TOOL_LIBRARY: string = 'discover_tool_library'
  /** 功能九宫格：校园日历 */
  static readonly DISCOVER_TOOL_CALENDAR: string = 'discover_tool_calendar'
  /** 功能九宫格：清水河畔 */
  static readonly DISCOVER_TOOL_RIVERSIDE: string = 'discover_tool_riverside'
  /** 功能九宫格：一卡通余额 */
  static readonly DISCOVER_TOOL_CARD_BALANCE: string = 'discover_tool_card_balance'
}

/**
 * 聚光灯高亮元素注册表（SpotlightRegistry）
 * 提供「页面 -> 可高亮元素 id 列表」的静态映射，供 ToolExecutor 校验 show_guidance 的
 * targetElementId 是否真实存在，杜绝模型编造元素 id 后谎报「已高亮」。
 */
export class SpotlightRegistry {
  /** 页面 -> 可高亮元素 id 列表（key 与 PageContextTracker 快照的 pageName 对齐） */
  private static pageIds: Map<string, string[]> = SpotlightRegistry.init()

  private static init(): Map<string, string[]> {
    const m: Map<string, string[]> = new Map<string, string[]>()
    // 发现页：云中成电 Hero 卡 + 常用服务三卡 + 功能九宫格（顺序与 Index.ets tools 数组一致）
    m.set('discover', [
      SpotlightIds.DISCOVER_HERO_CLOUD,
      SpotlightIds.DISCOVER_QUICK_GRADES,
      SpotlightIds.DISCOVER_QUICK_BUS,
      SpotlightIds.DISCOVER_QUICK_CALENDAR,
      SpotlightIds.DISCOVER_TOOL_CLOUD_PORTAL,
      SpotlightIds.DISCOVER_TOOL_BUS,
      SpotlightIds.DISCOVER_TOOL_AI,
      SpotlightIds.DISCOVER_TOOL_GRADES,
      SpotlightIds.DISCOVER_TOOL_MAP,
      SpotlightIds.DISCOVER_TOOL_LIBRARY,
      SpotlightIds.DISCOVER_TOOL_CALENDAR,
      SpotlightIds.DISCOVER_TOOL_RIVERSIDE,
      SpotlightIds.DISCOVER_TOOL_CARD_BALANCE
    ])
    return m
  }

  /** 判断 id 是否在任意页面上登记过（跨页全局校验） */
  static isKnownId(id: string): boolean {
    const allIds: string[][] = []
    SpotlightRegistry.pageIds.forEach((ids: string[]) => {
      allIds.push(ids)
    })
    for (let i = 0; i < allIds.length; i++) {
      if (allIds[i].indexOf(id) >= 0) {
        return true
      }
    }
    return false
  }

  /** 判断指定页面是否登记了该可高亮元素（pageName 与快照上报值对齐） */
  static pageHas(pageName: string, id: string): boolean {
    const ids: string[] | undefined = SpotlightRegistry.pageIds.get(pageName)
    if (ids === undefined) {
      return false
    }
    return ids.indexOf(id) >= 0
  }

  /** 获取指定页面的全部可高亮元素 id，未登记的页面返回空数组 */
  static getIdsForPage(pageName: string): string[] {
    const ids: string[] | undefined = SpotlightRegistry.pageIds.get(pageName)
    return ids !== undefined ? ids : []
  }
}
