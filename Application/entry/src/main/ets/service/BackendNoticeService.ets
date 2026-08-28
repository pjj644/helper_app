import { http } from '@kit.NetworkKit';
import { notificationManager } from '@kit.NotificationKit';
import { Context } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { AgentEndpointConfig, AgentEndpoint } from '../common/agent/AgentEndpointConfig';
import { AppConstants } from '../common/constants/AppConstants';
import { PreferencesUtil } from '../common/PreferencesUtil';

/** 后端 /api/v1/notifications 返回的单条通知（与 ai-proxy src/notifications.ts 对齐） */
interface BackendNoticeItem {
  id: number;
  title: string;
  content: string;
  createdAt: string;
}

/** 后端通知列表端点的载荷形态 */
interface BackendNoticePayload {
  ok?: boolean;
  count?: number;
  data?: BackendNoticeItem[];
}

/**
 * 后端简单通知拉取服务（消费设置页「消息通知」开关）。
 *
 * 链路：GET {后端}/api/v1/notifications（经 AgentEndpointConfig 鉴权）
 *       → 与本地 last-seen ID 对比 → notificationManager.publish 系统通知。
 *
 * 策略：
 * - 仅在开关开启且助手后端已配置时拉取；未配置/失败一律静默；
 * - pollIfDue 带 1 小时节流（回前台触发），pollNow 为立即拉取（开关开启时触发）；
 * - 单次最多发布 NOTICE_MAX_PUBLISH_PER_POLL 条，其余直接推进 last-seen，
 *   避免长时间未打开应用后的通知风暴。
 */
export class BackendNoticeService {
  /** 应用回前台调用：开关开启、后端就绪且距上次拉取超过节流间隔才真正拉取 */
  static async pollIfDue(context: Context): Promise<void> {
    await BackendNoticeService.fetchAndPublish(context, false);
  }

  /** 立即拉取（绕过节流间隔），供设置页开启开关时调用 */
  static async pollNow(context: Context): Promise<void> {
    await BackendNoticeService.fetchAndPublish(context, true);
  }

  private static async fetchAndPublish(context: Context, force: boolean): Promise<void> {
    try {
      if (!PreferencesUtil.getInstance().getBoolean(AppConstants.SETTING_SYSTEM_NOTIFICATION_KEY, false)) {
        return;
      }
      const endpoint: AgentEndpoint = await AgentEndpointConfig.resolve(context);
      if (!AgentEndpointConfig.isReady(endpoint)) {
        return;
      }

      const pref = await dataPreferences.getPreferences(context, AppConstants.PREF_COURSE_DB_NAME);
      const lastPollAt = (await pref.get(AppConstants.PREF_NOTICE_LAST_POLL_AT_KEY, 0)) as number;
      const now = Date.now();
      if (!force && lastPollAt > 0 && now - lastPollAt < AppConstants.NOTICE_POLL_MIN_INTERVAL_MS) {
        return;
      }

      const items = await BackendNoticeService.requestNotices(endpoint);
      await pref.put(AppConstants.PREF_NOTICE_LAST_POLL_AT_KEY, now);

      const lastSeenId = (await pref.get(AppConstants.PREF_NOTICE_LAST_SEEN_ID_KEY, 0)) as number;
      let maxId = lastSeenId;
      let published = 0;
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (!item || typeof item.id !== 'number' || item.id <= lastSeenId) {
          continue;
        }
        if (item.id > maxId) {
          maxId = item.id;
        }
        if (published < AppConstants.NOTICE_MAX_PUBLISH_PER_POLL) {
          await BackendNoticeService.publishNotice(item);
          published++;
        }
      }
      if (maxId > lastSeenId) {
        await pref.put(AppConstants.PREF_NOTICE_LAST_SEEN_ID_KEY, maxId);
      }
      await pref.flush();
    } catch (e) {
      console.warn('[BackendNotice] fetchAndPublish error:', String(e));
    }
  }

  /** 请求后端通知列表；网络失败/非 200/载荷非法时返回空数组 */
  private static async requestNotices(endpoint: AgentEndpoint): Promise<BackendNoticeItem[]> {
    const url: string = AgentEndpointConfig.joinUrl(endpoint, AppConstants.BACKEND_NOTIFICATIONS_PATH);
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.GET,
        header: AgentEndpointConfig.buildHeaders(endpoint),
        connectTimeout: 10000,
        readTimeout: 15000
      });
      if (resp.responseCode !== 200) {
        console.warn('[BackendNotice] request failed, code:', JSON.stringify(resp.responseCode));
        return [];
      }
      let payloadText: string = '';
      if (typeof resp.result === 'string') {
        payloadText = resp.result;
      } else if (resp.result) {
        payloadText = JSON.stringify(resp.result);
      }
      if (!payloadText) {
        return [];
      }
      const payload = JSON.parse(payloadText) as BackendNoticePayload;
      if (!payload.ok || !payload.data || !Array.isArray(payload.data)) {
        return [];
      }
      return payload.data;
    } catch (e) {
      console.warn('[BackendNotice] request error:', String(e));
      return [];
    } finally {
      client.destroy();
    }
  }

  /** 发布单条系统通知；未授权通知时抛错由上层静默捕获 */
  private static async publishNotice(item: BackendNoticeItem): Promise<void> {
    const title = item.title && item.title.length > 0 ? item.title : '成电校园助手';
    const text = item.content && item.content.length > 0 ? item.content : title;
    const request: notificationManager.NotificationRequest = {
      id: item.id,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text,
          additionalText: '成电校园助手'
        }
      }
    };
    await notificationManager.publish(request);
  }
}
