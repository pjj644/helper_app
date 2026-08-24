import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { AgentEndpointConfig, AgentEndpoint } from '../common/agent/AgentEndpointConfig';
import { AppConstants } from '../common/constants/AppConstants';
import { PreferencesUtil } from '../common/PreferencesUtil';
import {
  BusItem,
  BusScheduleModel,
  BusSchedulePayload,
  NextBusInfo,
  parseBusSchedulePayload
} from '../model/BusScheduleModel';

/** preferences 中持久化的班车 last-good 数据包（本服务自有格式） */
interface BusScheduleEnvelope {
  updatedAt: number;
  generatedAt: string;
  items: BusItem[];
}

/**
 * 班车时刻数据服务（T6a 班车时刻远端化）。
 *
 * 链路：GET knowledge/bus-schedule（经 AgentEndpointConfig 鉴权）
 *       → preferences 存 last-good JSON → 内存缓存 → 页面/提醒消费。
 *
 * 兜底顺序：内存缓存 → preferences 同步读 → BusScheduleModel 内置兜底表
 * （快照随应用版本固化，见 model/BusScheduleModel 头注释）。
 * 拉取失败一律静默保留旧数据；空班次列表视为无效载荷，不覆盖兜底语义。
 */
export class BusDataService {
  /** 进程内内存缓存；null 表示尚未成功加载远端数据 */
  private static memoryList: BusItem[] | null = null;
  private static memoryUpdatedAt: number = 0;

  /**
   * 生效班次列表：远端缓存命中且该方向有数据则用远端，
   * 否则回退内置兜底表。页面渲染与提醒计算统一走此入口。
   */
  static getEffectiveBusList(departure: 'qsh' | 'sh', isWeekend: boolean): BusItem[] {
    const remote: BusItem[] = BusDataService.getRemoteList()
      .filter((bus: BusItem) => bus.departure === departure && bus.isWeekend === isWeekend);
    return remote.length > 0 ? remote : BusScheduleModel.getBusList(departure, isWeekend);
  }

  /** 计算下一班车（列表来源同 getEffectiveBusList，含明日首班的跨日逻辑） */
  static getNextBus(departure: 'qsh' | 'sh', isWeekend: boolean, now: Date = new Date()): NextBusInfo | null {
    const todayList: BusItem[] = BusDataService.getEffectiveBusList(departure, isWeekend);
    const tomorrowIsWeekend = BusScheduleModel.isWeekendDay(new Date(now.getTime() + 24 * 60 * 60 * 1000));
    const tomorrowList: BusItem[] = BusDataService.getEffectiveBusList(departure, tomorrowIsWeekend);
    return BusScheduleModel.getNextBusInfo(todayList, tomorrowList, now);
  }

  /** 是否需要后台刷新：从未加载过，或距上次更新超过最小刷新间隔 */
  static isStale(): boolean {
    if (BusDataService.memoryUpdatedAt === 0) {
      BusDataService.hydrateFromPreferences();
    }
    if (BusDataService.memoryUpdatedAt === 0) {
      return true;
    }
    return Date.now() - BusDataService.memoryUpdatedAt > AppConstants.BUS_SCHEDULE_REFRESH_MIN_INTERVAL_MS;
  }

  /** 过期才拉取的便捷入口；失败静默（内部已捕获），调用方无需处理异常 */
  static async refreshIfNeeded(context: Context): Promise<void> {
    if (!BusDataService.isStale()) {
      return;
    }
    await BusDataService.refreshAsync(context);
  }

  /**
   * 强制拉取最新班车数据并持久化。
   * 未配置后端 / 网络失败 / 非 200 / 载荷非法或为空 → 静默返回 false，旧数据不动。
   */
  static async refreshAsync(context: Context): Promise<boolean> {
    try {
      const endpoint: AgentEndpoint = await AgentEndpointConfig.resolve(context);
      if (!AgentEndpointConfig.isReady(endpoint)) {
        return false;
      }
      const url: string = AgentEndpointConfig.joinUrl(endpoint, AppConstants.KNOWLEDGE_BUS_SCHEDULE_PATH);
      const client: http.HttpRequest = http.createHttp();
      let payloadText: string = '';
      try {
        const resp: http.HttpResponse = await client.request(url, {
          method: http.RequestMethod.GET,
          header: AgentEndpointConfig.buildHeaders(endpoint),
          connectTimeout: 10000,
          readTimeout: 15000
        });
        if (resp.responseCode !== 200) {
          console.warn('[BusDataService] refresh failed, code:', JSON.stringify(resp.responseCode));
          return false;
        }
        // 与 ToolExecutor 同口径的 result 提取：字符串直用，对象序列化
        if (typeof resp.result === 'string') {
          payloadText = resp.result;
        } else if (resp.result) {
          payloadText = JSON.stringify(resp.result);
        }
      } finally {
        client.destroy();
      }

      const payload: BusSchedulePayload | null = parseBusSchedulePayload(payloadText);
      // 空列表不落盘：保护「无数据时回退内置表」的兜底语义
      if (payload === null || payload.items.length === 0) {
        console.warn('[BusDataService] refresh got empty or invalid payload');
        return false;
      }

      BusDataService.persistSync(context, payload.items, payload.generatedAt);
      return true;
    } catch (e) {
      console.warn('[BusDataService] refreshAsync error:', String(e));
      return false;
    }
  }

  /** 远端数据同步读取（内存优先，其次 preferences）；无数据返回空数组 */
  static getRemoteList(): BusItem[] {
    if (BusDataService.memoryList !== null) {
      return BusDataService.memoryList;
    }
    BusDataService.hydrateFromPreferences();
    if (BusDataService.memoryList !== null) {
      return BusDataService.memoryList;
    }
    return [];
  }

  /** 从 preferences 同步载入 last-good 到内存（走 PreferencesUtil 免 Context 通道） */
  private static hydrateFromPreferences(): void {
    try {
      const text: string = PreferencesUtil.getInstance().getString(AppConstants.PREF_BUS_SCHEDULE_JSON_KEY, '');
      if (!text) {
        return;
      }
      const envelope = JSON.parse(text) as BusScheduleEnvelope;
      if (typeof envelope.updatedAt !== 'number' || !envelope.items || !Array.isArray(envelope.items)) {
        return;
      }
      if (envelope.items.length === 0) {
        return;
      }
      BusDataService.memoryList = envelope.items;
      BusDataService.memoryUpdatedAt = envelope.updatedAt;
    } catch (e) {
      console.warn('[BusDataService] hydrate error:', String(e));
    }
  }

  /** 写入 last-good 并更新内存；内容未变化时跳过落盘避免无谓 flush */
  private static persistSync(context: Context, items: BusItem[], generatedAt: string): void {
    const envelope: BusScheduleEnvelope = {
      updatedAt: Date.now(),
      generatedAt: generatedAt,
      items: items
    };
    const text: string = JSON.stringify(envelope);
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const existing: string = pref.getSync(AppConstants.PREF_BUS_SCHEDULE_JSON_KEY, '') as string;
      if (existing !== text) {
        pref.putSync(AppConstants.PREF_BUS_SCHEDULE_JSON_KEY, text);
        pref.flushSync();
      }
    } catch (e) {
      console.warn('[BusDataService] persistSync error:', String(e));
    }
    BusDataService.memoryList = items;
    BusDataService.memoryUpdatedAt = envelope.updatedAt;
  }
}
