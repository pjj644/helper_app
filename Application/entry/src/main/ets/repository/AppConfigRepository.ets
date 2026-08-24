import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { AgentEndpointConfig, AgentEndpoint } from '../common/agent/AgentEndpointConfig';
import { AppConstants } from '../common/constants/AppConstants';
import { PreferencesUtil } from '../common/PreferencesUtil';
import {
  FALLBACK_SEMESTER_CONFIG,
  SemesterConfigData,
  parseSemesterConfigJson
} from '../model/SemesterConfig';

/**
 * 应用级云端配置仓库（T5a 学期参数云端化）。
 *
 * 链路：启动预热 warmUp → GET app-config（经 AgentEndpointConfig 鉴权）
 *       → preferences 存 last-good JSON（含 fetchedAt）→ 内存单例；
 * 读取：getConfig() 同步返回，永不抛出、永不返回空 —— 内存 → preferences 同步读（getSync）→ 内置兜底。
 *
 * 同步读取方案说明：
 * - 项目 targetSdkVersion 为 6.0.2(22)，@kit.ArkData preferences 的
 *   getPreferencesSync / getSync / putSync / flushSync 均自 API 11 起可用，
 *   且工程内已有三处成熟先例（EntryFormAbility、PreferencesUtil、FloatingWindowManager），
 *   故直接采用「同步读取路径」而非异步预热内存单例方案；
 * - 模型层调用方（CourseModel.getCurrentWeek 等高频同步路径）无 Context，
 *   因此同步读优先走 PreferencesUtil 单例通道（其已在 EntryAbility.onCreate 完成同步初始化，
 *   与本仓库写入使用同一个 course_table_local_db 偏好实例）；未初始化场景
 *   （如独立卡片进程、预览器）自然降级为内置兜底值，行为与历史硬编码一致。
 */
export class AppConfigRepository {
  /** 进程内内存缓存；null 表示尚未从偏好加载成功 */
  private static memoryConfig: SemesterConfigData | null = null;
  /** warmUp 幂等标记（每进程仅拉取一次） */
  private static warmedUp: boolean = false;

  /**
   * 同步读取生效配置：内存 → preferences 同步读 → 内置兜底。
   * 供模型层高频调用（周次换算、学期 ID 推算），必须保持零阻塞、零异常。
   */
  static getConfig(): SemesterConfigData {
    if (AppConfigRepository.memoryConfig !== null) {
      return AppConfigRepository.memoryConfig;
    }
    const cached: SemesterConfigData | null = AppConfigRepository.readCachedViaPreferencesUtil();
    if (cached !== null) {
      AppConfigRepository.memoryConfig = cached;
      return cached;
    }
    return FALLBACK_SEMESTER_CONFIG;
  }

  /** 启动预热：幂等。先同步载入 last-good，再异步拉取远端刷新（失败静默）。 */
  static warmUp(context: Context): void {
    if (AppConfigRepository.warmedUp) {
      return;
    }
    AppConfigRepository.warmedUp = true;
    AppConfigRepository.hydrateSync(context);
    AppConfigRepository.refreshAsync(context).catch(() => {
      // 静默失败：last-good 或兜底继续生效，不打断启动流程
    });
  }

  /** 用传入 Context 同步载入 last-good 到内存（适用于能拿到 Context 的进程，如卡片进程） */
  static hydrateSync(context: Context): void {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const text: string = pref.getSync(AppConstants.PREF_APP_CONFIG_JSON_KEY, '') as string;
      const parsed: SemesterConfigData | null = parseSemesterConfigJson(text);
      if (parsed !== null) {
        AppConfigRepository.memoryConfig = parsed;
      }
    } catch (e) {
      console.warn('[AppConfigRepository] hydrateSync error:', String(e));
    }
  }

  /**
   * 异步拉取最新配置并持久化。任何失败（未配置后端、网络错误、非 200、数据非法）
   * 均静默返回 false，保留既有 last-good / 内置兜底不动。
   */
  static async refreshAsync(context: Context): Promise<boolean> {
    try {
      const endpoint: AgentEndpoint = await AgentEndpointConfig.resolve(context);
      if (!AgentEndpointConfig.isReady(endpoint)) {
        return false;
      }
      const url: string = AgentEndpointConfig.joinUrl(endpoint, AppConstants.APP_CONFIG_PATH);
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
          console.warn('[AppConfigRepository] refresh failed, code:', JSON.stringify(resp.responseCode));
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

      const parsed: SemesterConfigData | null = parseSemesterConfigJson(payloadText);
      if (parsed === null) {
        console.warn('[AppConfigRepository] refresh got invalid payload');
        return false;
      }

      AppConfigRepository.persistSync(context, parsed);
      return true;
    } catch (e) {
      console.warn('[AppConfigRepository] refreshAsync error:', String(e));
      return false;
    }
  }

  /** 无 Context 的同步读取桥：走 PreferencesUtil 单例（主进程内与本仓库同一偏好实例） */
  private static readCachedViaPreferencesUtil(): SemesterConfigData | null {
    try {
      const text: string = PreferencesUtil.getInstance()
        .getString(AppConstants.PREF_APP_CONFIG_JSON_KEY, '');
      return parseSemesterConfigJson(text);
    } catch (e) {
      console.warn('[AppConfigRepository] readCached error:', String(e));
      return null;
    }
  }

  /** 写入 last-good 并更新内存；内容未变化时跳过落盘避免无谓 flush */
  private static persistSync(context: Context, config: SemesterConfigData): void {
    const text: string = JSON.stringify(config);
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const existing: string = pref.getSync(AppConstants.PREF_APP_CONFIG_JSON_KEY, '') as string;
      if (existing !== text) {
        pref.putSync(AppConstants.PREF_APP_CONFIG_JSON_KEY, text);
        pref.flushSync();
      }
    } catch (e) {
      console.warn('[AppConfigRepository] persistSync error:', String(e));
    }
    AppConfigRepository.memoryConfig = config;
  }
}
