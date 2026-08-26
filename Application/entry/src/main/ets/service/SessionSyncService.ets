import { preferences } from '@kit.ArkData';
import { cloudDatabase } from '@kit.CloudFoundationKit';
import { AppConstants } from '../common/constants/AppConstants';
import { AuthService } from './AuthService';
import { SyncService } from './SyncService';
import { CloudDbRepository } from '../repository/CloudDbRepository';
import { ChatSession, ChatSessionRepository } from '../repository/ChatSessionRepository';
import { ChatSessionRecord } from '../pages/CloudDb/ChatSessionRecord';
import { SessionCryptoUtil } from '../common/utils/SessionCryptoUtil';

// 落盘后的防抖时长：15s 内的连续变更合并为一轮双向同步（独立于课程同步的 30s 防抖）
const SESSION_SYNC_DEBOUNCE_MS: number = 15000;
// 批量 upsert 分片大小与分片间隔（对齐 SyncService 的批量节奏）
const SESSION_UPLOAD_BATCH_SIZE: number = 10;
const SESSION_UPLOAD_BATCH_INTERVAL_MS: number = 500;
// 单会话 JSON 明文超过 1.5MB 则跳过上传（防 AES 输出 base64 后逼近/超过 CloudDB 单记录 2MB 上限）
const SESSION_PAYLOAD_MAX_BYTES: number = 1536 * 1024;

/**
 * AI 会话加密上云同步编排（P2-7d）。
 *
 * - 开关偏好键 SETTING_SESSION_CLOUD_SYNC_KEY（默认关闭），读写自包含在本服务内；
 * - 触发源：ChatSessionRepository.saveSessions 落盘成功后的防抖钩子 + 开关打开时刻的立即触发；
 * - 初次拉取保护：开关打开时刻若本地为空且云端有数据（重装/换机场景），首轮只做下载恢复、
 *   跳过上传与裁剪——否则空本地会把云端全部记录当作「已在别端删除」传播清空（2026-08-26 实测踩坑）；
 * - 每轮执行：重校验登录态 → 网络门控（复用课程同步的 WiFi/以太网/蜂窝判定）→ 上传（幂等 upsert +
 *   删除云端多余记录）→ 下载解密 LWW 合并回写（经不触发钩子的内部通道，防回环）；
 * - 所有云端操作失败软降：try-catch + 日志，不崩溃、不阻塞本地功能
 *   （对象类型尚未在 AGC 控制台创建时同样只记日志）。
 */
export class SessionSyncService {
  private static debounceTimer: number = -1;
  private static syncing: boolean = false;
  /** 开关打开时刻置位：紧随其后的一轮按「初次拉取」处理（本地为空时只恢复不裁剪） */
  private static pendingInitialPull: boolean = false;
  /** 登录态沿袭标记：从已登录变为未登录时清理密钥缓存 */
  private static lastSeenLoggedIn: boolean = false;

  /** AI 会话云同步开关（默认关闭） */
  static async getSessionCloudSyncEnabled(context: Context): Promise<boolean> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const value = pref.getSync(AppConstants.SETTING_SESSION_CLOUD_SYNC_KEY, false);
      return value === true;
    } catch (e) {
      console.warn(`[SessionSync] 读取AI会话云同步开关失败: ${String(e)}`);
      return false;
    }
  }

  static async setSessionCloudSyncEnabled(context: Context, enabled: boolean): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SETTING_SESSION_CLOUD_SYNC_KEY, enabled);
      pref.flushSync();
    } catch (e) {
      console.warn(`[SessionSync] 写入AI会话云同步开关失败: ${String(e)}`);
      return;
    }
    if (!enabled) {
      // 关闭时取消挂起的防抖任务，避免关掉后仍补跑一轮
      SessionSyncService.cancelPendingDebounce();
      return;
    }
    // 开关打开的那一刻立即触发一轮（不走 15s 防抖），并标记为初次拉取：
    // 本地可能为空（重装/换机），首轮需保护云端数据不被裁剪清空
    SessionSyncService.pendingInitialPull = true;
    SessionSyncService.scheduleRun(context, 0);
  }

  /**
   * ChatSessionRepository.saveSessions 落盘成功后的入口：15s 防抖后执行一轮双向同步。
   * 开关/登录态/网络条件的校验都延迟到定时器触发时进行。
   */
  static triggerSessionSyncIfEnabled(context: Context): void {
    SessionSyncService.scheduleRun(context, SESSION_SYNC_DEBOUNCE_MS);
  }

  /**
   * 登出/注销流程调用：取消挂起定时器并清除派生密钥缓存。
   * （当前 AccountManage 的登出路径不在本任务可改动领地内，故另有两层兜底：
   * 密钥缓存按 UID 自动失效 + 每轮同步开始时检测登出态主动清理。）
   */
  static stopAndClear(_context: Context): void {
    SessionSyncService.cancelPendingDebounce();
    SessionCryptoUtil.clearKeyCache();
    SessionSyncService.lastSeenLoggedIn = false;
    console.info('[SessionSync] stopAndClear：已取消挂起定时器并清除密钥缓存');
  }

  private static cancelPendingDebounce(): void {
    if (SessionSyncService.debounceTimer >= 0) {
      clearTimeout(SessionSyncService.debounceTimer);
      SessionSyncService.debounceTimer = -1;
    }
  }

  private static scheduleRun(context: Context, delayMs: number): void {
    if (SessionSyncService.debounceTimer >= 0) {
      clearTimeout(SessionSyncService.debounceTimer);
    }
    SessionSyncService.debounceTimer = setTimeout(() => {
      SessionSyncService.debounceTimer = -1;
      SessionSyncService.runSyncRound(context);
    }, delayMs);
  }

  /** 一轮双向同步：登录态 → 网络 → 上传 → 云端裁剪 → 下载合并。全程软降。 */
  private static async runSyncRound(context: Context): Promise<void> {
    if (SessionSyncService.syncing) {
      return;
    }
    SessionSyncService.syncing = true;
    try {
      const enabled = await SessionSyncService.getSessionCloudSyncEnabled(context);
      if (!enabled) {
        return;
      }
      // 每轮同步开始时重新校验登录态
      const userId = await AuthService.getLoginUserId(context);
      if (!userId) {
        if (SessionSyncService.lastSeenLoggedIn) {
          console.info('[SessionSync] 检测到已登出，清理派生密钥缓存');
          SessionCryptoUtil.clearKeyCache();
          SessionSyncService.lastSeenLoggedIn = false;
        }
        return;
      }
      SessionSyncService.lastSeenLoggedIn = true;

      // 网络门控：复用课程同步的 WiFi/蜂窝判定
      const networkOk = await SyncService.isCloudAutoSyncNetworkAllowed(context);
      if (!networkOk) {
        console.info('[SessionSync] 网络条件不满足（非 WiFi 且未允许蜂窝同步），本轮跳过');
        return;
      }

      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }

      const isInitialPull = SessionSyncService.pendingInitialPull;
      SessionSyncService.pendingInitialPull = false;

      const sessions = ChatSessionRepository.getSessions(context);

      // 初次拉取保护：开关刚打开且本地为空（重装/换机），只做下载恢复，跳过上传与裁剪
      if (isInitialPull && sessions.length === 0) {
        const cloudRecords = await SessionSyncService.queryAllByUser(userId);
        if (cloudRecords.length > 0) {
          await SessionSyncService.downloadMerge(context, userId, cloudRecords, new Set<string>());
          console.info(`[SessionSync] 初次拉取完成：从云端恢复 ${cloudRecords.length} 条会话，已跳过上传与裁剪`);
        } else {
          console.info('[SessionSync] 初次拉取：云端无历史会话');
        }
        return;
      }

      await SessionSyncService.uploadLocalSessions(userId, sessions);

      // 查询云端该用户全部记录，删除与下载合并复用同一份查询结果
      const cloudRecords = await SessionSyncService.queryAllByUser(userId);

      const localIds = new Set<string>();
      for (const s of sessions) {
        if (s && s.id) {
          localIds.add(s.id);
        }
      }
      // 如果是初次拉取但本地非空（例如本地已有新会话），也不裁剪云端旧会话，直接双向合并
      let removedIds: Set<string>;
      if (isInitialPull) {
        removedIds = new Set<string>();
        console.info('[SessionSync] 初次拉取（本地非空）：跳过云端裁剪，执行双向合并');
      } else {
        removedIds = await SessionSyncService.pruneCloudStale(cloudRecords, localIds);
      }
      await SessionSyncService.downloadMerge(context, userId, cloudRecords, removedIds);
      console.info('[SessionSync] 双向同步完成');
    } catch (e) {
      console.warn(`[SessionSync] 同步轮次失败（软降，不影响本地功能）: ${String(e)}`);
    } finally {
      SessionSyncService.syncing = false;
    }
  }

  /**
   * 上传：逐会话构造 ChatSessionRecord（payload=AES-GCM 加密的整会话 JSON）批量幂等 upsert。
   * 超过 1.5MB 明文的会话跳过并记日志。
   */
  private static async uploadLocalSessions(userId: string, sessions: ChatSession[]): Promise<void> {
    const zone = CloudDbRepository.getZone();
    if (!zone) {
      throw new Error('CloudDB zone not initialized');
    }
    const records: ChatSessionRecord[] = [];
    for (const s of sessions) {
      if (!s || !s.id) {
        continue;
      }
      const plain = JSON.stringify(s);
      if (SessionSyncService.utf8ByteLength(plain) > SESSION_PAYLOAD_MAX_BYTES) {
        console.warn(`[SessionSync] 会话 ${s.id} 明文超过1.5MB，跳过上传（防超CloudDB单记录上限）`);
        continue;
      }
      const encrypted = await SessionCryptoUtil.encrypt(userId, plain);
      const record = new ChatSessionRecord();
      record.id = s.id;
      record.userId = userId;
      record.payload = encrypted;
      record.payloadVersion = 1;
      record.updatedAt =
        new Date(typeof s.updatedAt === 'number' && s.updatedAt > 0 ? s.updatedAt : Date.now());
      records.push(record);
    }

    for (let i = 0; i < records.length; i += SESSION_UPLOAD_BATCH_SIZE) {
      const batch = records.slice(i, i + SESSION_UPLOAD_BATCH_SIZE);
      await zone.upsert(batch);
      if (i + SESSION_UPLOAD_BATCH_SIZE < records.length) {
        await SessionSyncService.delay(SESSION_UPLOAD_BATCH_INTERVAL_MS);
      }
    }
    console.info(`[SessionSync] 上传完成：${records.length}/${sessions.length} 条会话`);
  }

  /** 查询云端该 userId 全部会话记录 */
  private static async queryAllByUser(userId: string): Promise<ChatSessionRecord[]> {
    const zone = CloudDbRepository.getZone();
    if (!zone) {
      throw new Error('CloudDB zone not initialized');
    }
    const query = new cloudDatabase.DatabaseQuery(ChatSessionRecord);
    query.equalTo('userId', userId);
    return await zone.query(query);
  }

  /**
   * 删除「本地已不存在」的云端记录（裁剪语义尽力传播）。
   * 返回被删 id 集合，供下载合并阶段排除（防止刚删除的记录又被当作「仅云端有」复活回本地）。
   */
  private static async pruneCloudStale(
    cloudRecords: ChatSessionRecord[],
    localIds: Set<string>
  ): Promise<Set<string>> {
    const removedIds = new Set<string>();
    const zone = CloudDbRepository.getZone();
    if (!zone) {
      throw new Error('CloudDB zone not initialized');
    }
    const stale: ChatSessionRecord[] = [];
    for (const cr of cloudRecords) {
      if (cr && cr.id && !localIds.has(cr.id)) {
        stale.push(cr);
        removedIds.add(cr.id);
      }
    }
    if (stale.length > 0) {
      await zone.delete(stale);
      console.info(`[SessionSync] 已裁剪云端不存在于本地的会话记录 ${stale.length} 条`);
    }
    return removedIds;
  }

  /**
   * 下载合并：解密云端记录 → 按 session.id 去重并入本地列表，双端都有时按
   * updatedAt 毫秒 LWW 裁决（完全相等时云端胜，与课程/考试一致）；损坏记录跳过并记日志。
   * 结果按 MAX_SESSIONS 裁剪后经「不触发同步钩子」的内部通道写回本地，防止回写再触发上传循环。
   */
  private static async downloadMerge(
    context: Context,
    userId: string,
    cloudRecords: ChatSessionRecord[],
    excludedIds: Set<string>
  ): Promise<void> {
    const localSessions = ChatSessionRepository.getSessions(context);
    const mergedMap = new Map<string, ChatSession>();
    const orderedIds: string[] = [];
    for (const s of localSessions) {
      if (!s || !s.id || mergedMap.has(s.id)) {
        continue;
      }
      mergedMap.set(s.id, s);
      orderedIds.push(s.id);
    }

    let adoptedCount = 0;
    for (const cr of cloudRecords) {
      if (!cr || !cr.id || !cr.payload || excludedIds.has(cr.id)) {
        continue;
      }
      let cs: ChatSession;
      try {
        const plain = await SessionCryptoUtil.decrypt(userId, cr.payload);
        cs = JSON.parse(plain) as ChatSession;
      } catch (e) {
        console.warn(`[SessionSync] 云端会话 ${cr.id} 解密/解析失败，跳过: ${String(e)}`);
        continue;
      }
      if (!cs || !cs.id) {
        console.warn(`[SessionSync] 云端会话 ${cr.id} 内容非法（缺少 id），跳过`);
        continue;
      }
      const local = mergedMap.get(cs.id);
      if (!local) {
        mergedMap.set(cs.id, cs);
        continue;
      }
      const localTs = SessionSyncService.updatedAtMsOf(local);
      const cloudTs = SessionSyncService.updatedAtMsOf(cs);
      if (cloudTs >= localTs) {
        // 相等时云端胜（与课程/考试 LWW 口径一致）
        mergedMap.set(cs.id, cs);
        adoptedCount++;
      }
    }

    // 重组列表：保持本地原有顺序，仅云端有的会话按 updatedAt 倒序追加在尾部
    const mergedList: ChatSession[] = [];
    for (const id of orderedIds) {
      const value = mergedMap.get(id);
      if (value) {
        mergedList.push(value);
      }
    }
    const appended: ChatSession[] = [];
    mergedMap.forEach((value: ChatSession) => {
      if (orderedIds.indexOf(value.id) < 0) {
        appended.push(value);
      }
    });
    appended.sort((a: ChatSession, b: ChatSession): number =>
      SessionSyncService.updatedAtMsOf(b) - SessionSyncService.updatedAtMsOf(a));
    for (const item of appended) {
      mergedList.push(item);
    }

    // 与仓库写入通道一致的 MAX_SESSIONS 裁剪
    const trimmed = mergedList.slice(0, AppConstants.AI_CHAT_MAX_SESSIONS);
    const changed = adoptedCount > 0 || appended.length > 0 || trimmed.length !== localSessions.length;
    if (!changed) {
      console.info('[SessionSync] 下载合并：无差异，无需写回');
      return;
    }
    ChatSessionRepository.saveSessionsRaw(context, trimmed);
    console.info(
      `[SessionSync] 下载合并完成：采纳云端更新 ${adoptedCount} 条，新增 ${appended.length} 条，共 ${trimmed.length} 条`
    );
  }

  private static updatedAtMsOf(session: ChatSession): number {
    return typeof session.updatedAt === 'number' ? session.updatedAt : 0;
  }

  /** UTF-8 字节长度估算（含中文/代理对），用于 1.5MB 上限判断 */
  private static utf8ByteLength(text: string): number {
    let bytes = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if (code >= 0xD800 && code <= 0xDBFF) {
        // 代理对：一个码点占 4 字节，消费低位代理
        bytes += 4;
        i++;
      } else if (code < 0x80) {
        bytes += 1;
      } else if (code < 0x800) {
        bytes += 2;
      } else {
        bytes += 3;
      }
    }
    return bytes;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), ms));
  }
}
