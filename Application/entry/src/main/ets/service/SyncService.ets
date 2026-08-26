import { connection } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { Course, RawActivity, RawCourseTableData } from '../model/classTableModel/CourseModel';
import { ExamItem } from '../model/classTableModel/ExamModel';
import { CloudDbRepository } from '../repository/CloudDbRepository';
import { CourseRepository } from '../repository/CourseRepository';
import { ExamRepository } from '../repository/ExamRepository';
import { ClassCourse } from '../pages/CloudDb/ClassCourse';
import { ClassExam } from '../pages/CloudDb/ClassExam';
import { calculateSemesterId, getSemesterLabelById } from '../model/classTableModel/ExamAccessRules';
import { AppConstants } from '../common/constants/AppConstants';
import { AuthService } from './AuthService';
import { ReminderService } from './ReminderService';

export interface SyncResult {
  success: boolean;
  courseCount?: number;
  examCount?: number;
  error?: string;
}

export interface DownloadResult {
  success: boolean;
  courseCount?: number;
  examCount?: number;
  error?: string;
}

export interface SyncAllResult {
  courses: SyncResult;
  exams: SyncResult;
}

export interface DownloadAllResult {
  courses: DownloadResult;
  exams: DownloadResult;
}

/** 云端自动同步运行状态（持久化于 CLOUD_AUTO_SYNC_STATE_JSON_KEY） */
export interface CloudAutoSyncState {
  /** 上次成功全量同步的时间戳（毫秒），0 表示从未成功 */
  lastSuccessAtMs: number;
  /** 是否存在待补传的变更 */
  pending: boolean;
  /** 连续失败次数（成功后清零），驱动指数退避 */
  attempts: number;
  /** 下次允许自动重试的时间戳（毫秒），退避/频率窗口的到点时间 */
  nextAttemptAtMs: number;
}

// 数据落盘后的防抖时长：30s 内的连续变更合并为一轮上传
const AUTO_SYNC_DEBOUNCE_MS: number = 30000;
// 频率上限：距上次成功全量同步不足 5 分钟则跳过（手动同步不受限）
const CLOUD_SYNC_MIN_INTERVAL_MS: number = 5 * 60 * 1000;
// 失败指数退避：30s 起步，逐次翻倍
const CLOUD_SYNC_BACKOFF_BASE_MS: number = 30000;
// 退避上限 30 分钟
const CLOUD_SYNC_BACKOFF_MAX_MS: number = 30 * 60 * 1000;
// 网络条件不满足时的短暂重试间隔（不计入失败退避）
const CLOUD_SYNC_NETWORK_WAIT_MS: number = 60000;

export class SyncService {
  static async initCloudDB(): Promise<void> {
    await CloudDbRepository.initCloudDB();
  }

  static async syncCoursesToCloud(context: Object, userId: string): Promise<SyncResult> {
    try {
      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }
      const semesterIds = await CourseRepository.getStoredSemesterIds(context);
      let totalCourseCount = 0;

      for (const semesterId of semesterIds) {
        const courseJson = await CourseRepository.loadCourseDataBySemester(context, semesterId);
        if (!courseJson) {
          continue;
        }

        const rawData: RawCourseTableData = JSON.parse(courseJson);
        const semesterLabel = getSemesterLabelById(semesterId);

        const courses = SyncService.extractCoursesFromRawData(rawData);
        const cloudCourses: ClassCourse[] = [];

        for (const course of courses) {
          const record = SyncService.toCloudCourse(course, userId, semesterId, semesterLabel);
          cloudCourses.push(record);
        }

        const existingCourses = await CloudDbRepository.queryCourses(userId, semesterId);
        const existingMap = new Map<number, ClassCourse>();
        for (const ec of existingCourses) {
          existingMap.set(ec.id, ec);
        }

        const toUpsert: ClassCourse[] = [];
        for (const cc of cloudCourses) {
          const existing = existingMap.get(cc.id);
          if (!existing || SyncService.courseChanged(existing, cc)) {
            toUpsert.push(cc);
          }
        }

        if (toUpsert.length > 0) {
          await SyncService.upsertCoursesInBatches(toUpsert);
          totalCourseCount += toUpsert.length;
        }
      }

      if (semesterIds.length === 0) {
        const courseJson = await CourseRepository.loadCourseData(context);
        if (courseJson) {
          const rawData: RawCourseTableData = JSON.parse(courseJson);
          const semesterId = calculateSemesterId();
          const semesterLabel = getSemesterLabelById(semesterId);

          const courses = SyncService.extractCoursesFromRawData(rawData);
          const cloudCourses: ClassCourse[] = [];

          for (const course of courses) {
            const record = SyncService.toCloudCourse(course, userId, semesterId, semesterLabel);
            cloudCourses.push(record);
          }

          const existingCourses = await CloudDbRepository.queryCourses(userId, semesterId);
          const existingMap = new Map<number, ClassCourse>();
          for (const ec of existingCourses) {
            existingMap.set(ec.id, ec);
          }

          const toUpsert: ClassCourse[] = [];
          for (const cc of cloudCourses) {
            const existing = existingMap.get(cc.id);
            if (!existing || SyncService.courseChanged(existing, cc)) {
              toUpsert.push(cc);
            }
          }

          if (toUpsert.length > 0) {
            await SyncService.upsertCoursesInBatches(toUpsert);
            totalCourseCount += toUpsert.length;
          }
        }
      }

      const result: SyncResult = {
        success: true,
        courseCount: totalCourseCount
      };
      return result;
    } catch (error) {
      console.error('[SyncService] 同步课表到云端失败:', error);
      const result: SyncResult = {
        success: false,
        error: String(error)
      };
      return result;
    }
  }

  static async downloadCoursesFromCloud(context: Object, userId: string): Promise<DownloadResult> {
    try {
      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }
      const cloudCourses = await CloudDbRepository.queryAllCourses(userId);

      if (cloudCourses.length === 0) {
        const result: DownloadResult = { success: true, courseCount: 0 };
        return result;
      }

      const bySemester = new Map<number, ClassCourse[]>();
      for (const cc of cloudCourses) {
        const sid = cc.semesterId || 0;
        if (!bySemester.has(sid)) {
          bySemester.set(sid, []);
        }
        bySemester.get(sid)!.push(cc);
      }

      const semesterIds = Array.from(bySemester.keys());
      for (let i = 0; i < semesterIds.length; i++) {
        const semesterId = semesterIds[i];
        const courses = bySemester.get(semesterId);
        if (!courses) {
          continue;
        }
        const rawData = SyncService.cloudCoursesToRawData(courses);
        await CourseRepository.saveCourseDataBySemester(context, semesterId, JSON.stringify(rawData));
      }

      const currentSemesterId = calculateSemesterId();
      const currentCourses = bySemester.get(currentSemesterId);
      if (currentCourses && currentCourses.length > 0) {
        const rawData = SyncService.cloudCoursesToRawData(currentCourses);
        await CourseRepository.saveCourseData(context, JSON.stringify(rawData));
      }

      const result: DownloadResult = {
        success: true,
        courseCount: cloudCourses.length
      };
      return result;
    } catch (error) {
      console.error('[SyncService] 从云端下载课表失败:', error);
      const result: DownloadResult = {
        success: false,
        error: String(error)
      };
      return result;
    }
  }

  static async syncExamsToCloud(context: Object, userId: string): Promise<SyncResult> {
    try {
      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }
      const examJson = await ExamRepository.loadExamData(context);
      if (!examJson) {
        const result: SyncResult = { success: true, examCount: 0 };
        return result;
      }

      const exams: ExamItem[] = JSON.parse(examJson);

      const bySemester = new Map<number, ExamItem[]>();
      for (const item of exams) {
        const semesterId = item.semesterId > 0 ? item.semesterId : calculateSemesterId();
        if (!bySemester.has(semesterId)) {
          bySemester.set(semesterId, []);
        }
        bySemester.get(semesterId)!.push(item);
      }

      let totalExamCount = 0;
      const semesterIdList = Array.from(bySemester.keys());
      for (let i = 0; i < semesterIdList.length; i++) {
        const semesterId = semesterIdList[i];
        const semesterExams = bySemester.get(semesterId);
        if (!semesterExams) {
          continue;
        }
        const cloudExams: ClassExam[] = [];
        for (const item of semesterExams) {
          const record = SyncService.toCloudExam(item, userId);
          cloudExams.push(record);
        }

        const existingExams = await CloudDbRepository.queryExams(userId, semesterId);
        const existingMap = new Map<number, ClassExam>();
        for (const ee of existingExams) {
          existingMap.set(ee.id, ee);
        }

        const toUpsert: ClassExam[] = [];
        for (const ce of cloudExams) {
          const existing = existingMap.get(ce.id);
          if (!existing || SyncService.examChanged(existing, ce)) {
            toUpsert.push(ce);
          }
        }

        if (toUpsert.length > 0) {
          await SyncService.upsertExamsInBatches(toUpsert);
          totalExamCount += toUpsert.length;
        }
      }

      const result: SyncResult = {
        success: true,
        examCount: totalExamCount
      };
      return result;
    } catch (error) {
      console.error('[SyncService] 同步考试到云端失败:', error);
      const result: SyncResult = {
        success: false,
        error: String(error)
      };
      return result;
    }
  }

  static async downloadExamsFromCloud(context: Object, userId: string): Promise<DownloadResult> {
    try {
      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }
      const cloudExams = await CloudDbRepository.queryAllExams(userId);

      if (cloudExams.length === 0) {
        const result: DownloadResult = { success: true, examCount: 0 };
        return result;
      }

      const examItems: ExamItem[] = [];
      for (const ce of cloudExams) {
        const item: ExamItem = {
          courseNo: ce.courseNo || '',
          courseName: ce.courseName || '',
          examDate: ce.examDate || '',
          examTimeRange: ce.examTimeRange || '',
          examLocation: ce.examLocation || '',
          seatNo: ce.seatNo || '',
          examStatus: ce.examStatus || '',
          examType: ce.examType || '',
          remark: ce.remark || '',
          semesterId: ce.semesterId || 0,
          semesterLabel: ce.semesterLabel || '',
          beginTime: ce.beginTime ? ce.beginTime.getTime() : 0,
          endTime: ce.endTime ? ce.endTime.getTime() : 0,
        };
        examItems.push(item);
      }

      await ExamRepository.saveExamData(context, JSON.stringify(examItems));

      const result: DownloadResult = {
        success: true,
        examCount: cloudExams.length
      };
      return result;
    } catch (error) {
      console.error('[SyncService] 从云端下载考试失败:', error);
      const result: DownloadResult = {
        success: false,
        error: String(error)
      };
      return result;
    }
  }

  private static async upsertCoursesInBatches(courses: ClassCourse[]): Promise<void> {
    const BATCH_SIZE = 50;
    for (let i = 0; i < courses.length; i += BATCH_SIZE) {
      const batch = courses.slice(i, i + BATCH_SIZE);
      await SyncService.retryOperation(() => CloudDbRepository.upsertCourses(batch));
      if (i + BATCH_SIZE < courses.length) {
        await SyncService.delay(500);
      }
    }
  }

  private static async upsertExamsInBatches(exams: ClassExam[]): Promise<void> {
    const BATCH_SIZE = 50;
    for (let i = 0; i < exams.length; i += BATCH_SIZE) {
      const batch = exams.slice(i, i + BATCH_SIZE);
      await SyncService.retryOperation(() => CloudDbRepository.upsertExams(batch));
      if (i + BATCH_SIZE < exams.length) {
        await SyncService.delay(500);
      }
    }
  }

  static async syncAllToCloud(context: Object, userId: string): Promise<SyncAllResult> {
    await SyncService.initCloudDB();
    const courses = await SyncService.syncCoursesToCloud(context, userId);
    await SyncService.delay(500);
    const exams = await SyncService.syncExamsToCloud(context, userId);
    const result: SyncAllResult = { courses, exams };
    return result;
  }

  static async downloadAllFromCloud(context: Object, userId: string): Promise<DownloadAllResult> {
    await SyncService.initCloudDB();
    const courses = await SyncService.downloadCoursesFromCloud(context, userId);
    await SyncService.delay(500);
    const exams = await SyncService.downloadExamsFromCloud(context, userId);
    const result: DownloadAllResult = { courses, exams };
    return result;
  }

  private static autoSyncDebounceTimer: number = -1;
  private static autoSyncRetryTimer: number = -1;
  private static autoSyncRunning: boolean = false;

  private static emptyCloudAutoSyncState(): CloudAutoSyncState {
    const state: CloudAutoSyncState = { lastSuccessAtMs: 0, pending: false, attempts: 0, nextAttemptAtMs: 0 };
    return state;
  }

  private static async loadCloudAutoSyncState(context: Context): Promise<CloudAutoSyncState> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const raw = pref.getSync(AppConstants.CLOUD_AUTO_SYNC_STATE_JSON_KEY, '') as string;
      if (!raw) {
        return SyncService.emptyCloudAutoSyncState();
      }
      const parsed = JSON.parse(raw) as CloudAutoSyncState;
      const state: CloudAutoSyncState = {
        lastSuccessAtMs: parsed.lastSuccessAtMs || 0,
        pending: parsed.pending === true,
        attempts: parsed.attempts || 0,
        nextAttemptAtMs: parsed.nextAttemptAtMs || 0,
      };
      return state;
    } catch (e) {
      console.warn(`[SyncService] 读取云端自动同步状态失败: ${String(e)}`);
      return SyncService.emptyCloudAutoSyncState();
    }
  }

  private static async saveCloudAutoSyncState(context: Context, state: CloudAutoSyncState): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.CLOUD_AUTO_SYNC_STATE_JSON_KEY, JSON.stringify(state));
      pref.flushSync();
    } catch (e) {
      console.warn(`[SyncService] 持久化云端自动同步状态失败: ${String(e)}`);
    }
  }

  /**
   * 网络门控：WiFi 直接放行；蜂窝仅在「允许蜂窝网络同步」副开关开启时放行；
   * 无网络或其他承载类型不满足。拿不到网络状态时保守视为不满足并记录日志。
   */
  private static async isCloudAutoSyncNetworkAllowed(context: Context): Promise<boolean> {
    try {
      const netHandle = await connection.getDefaultNet();
      if (!netHandle || netHandle.netId === 0) {
        console.info('[SyncService] 自动同步网络检查：无可用默认网络，暂缓上传');
        return false;
      }
      const capabilities = await connection.getNetCapabilities(netHandle);
      const bearerTypes: connection.NetBearType[] = capabilities ? capabilities.bearerTypes : [];
      if (bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
        return true;
      }
      if (bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) {
        const cellularAllowed = await ReminderService.getCloudSyncCellularEnabled(context);
        if (!cellularAllowed) {
          console.info('[SyncService] 自动同步网络检查：当前为蜂窝网络且未开启允许蜂窝同步，跳过');
        }
        return cellularAllowed;
      }
      console.info('[SyncService] 自动同步网络检查：当前承载非 WiFi/蜂窝，保守跳过');
      return false;
    } catch (e) {
      console.warn(`[SyncService] 自动同步网络检查失败，保守视为不满足: ${String(e)}`);
      return false;
    }
  }

  /**
   * 课程/考试数据落盘后的防抖自动同步入口（P2-7a）。
   * 仅受「云端自动同步」开关控制（与本地日历/日程自动同步的 SETTING_AUTO_SYNC_SCHEDULE_KEY 互不相干），
   * 手动「上传到云端」不受任何频率限制。
   */
  static triggerAutoSyncIfEnabled(context: Context): void {
    if (SyncService.autoSyncDebounceTimer >= 0) {
      clearTimeout(SyncService.autoSyncDebounceTimer);
    }
    SyncService.autoSyncDebounceTimer = setTimeout(async () => {
      SyncService.autoSyncDebounceTimer = -1;
      try {
        const enabled = await ReminderService.getCloudAutoSyncEnabled(context);
        if (!enabled) {
          return;
        }
        const userId = await AuthService.getLoginUserId(context);
        if (!userId) {
          return;
        }
        const state = await SyncService.loadCloudAutoSyncState(context);
        const now = Date.now();

        // 频率上限：距上次成功全量同步不足 5 分钟则记待同步，顺延到窗口结束再传
        if (state.lastSuccessAtMs > 0 && now - state.lastSuccessAtMs < CLOUD_SYNC_MIN_INTERVAL_MS) {
          state.pending = true;
          state.nextAttemptAtMs =
            Math.max(state.nextAttemptAtMs, state.lastSuccessAtMs + CLOUD_SYNC_MIN_INTERVAL_MS);
          await SyncService.saveCloudAutoSyncState(context, state);
          console.info('[SyncService] 距上次自动同步不足5分钟，本轮记为待同步');
          return;
        }

        // 失败退避未到点：记待同步，等补偿触发或到点定时器重试
        if (state.attempts > 0 && now < state.nextAttemptAtMs) {
          state.pending = true;
          await SyncService.saveCloudAutoSyncState(context, state);
          console.info('[SyncService] 处于失败退避期，本轮记为待同步');
          return;
        }

        await SyncService.runCloudAutoSync(context, userId, state);
      } catch (e) {
        console.warn(`[SyncService] 自动同步异常: ${String(e)}`);
      }
    }, AUTO_SYNC_DEBOUNCE_MS);
  }

  /** 实际执行一轮云端自动同步：网络门控 → 全量 diff 上传 → 更新状态与退避 */
  private static async runCloudAutoSync(context: Context, userId: string, state: CloudAutoSyncState): Promise<void> {
    if (SyncService.autoSyncRunning) {
      return;
    }
    SyncService.autoSyncRunning = true;
    try {
      const networkOk = await SyncService.isCloudAutoSyncNetworkAllowed(context);
      if (!networkOk) {
        // 无网/网络不满足不算失败，短间隔后可再试
        state.pending = true;
        state.nextAttemptAtMs = Date.now() + CLOUD_SYNC_NETWORK_WAIT_MS;
        await SyncService.saveCloudAutoSyncState(context, state);
        return;
      }
      console.info('[SyncService] 云端自动同步开始...');
      const result = await SyncService.syncAllToCloud(context, userId);
      if (result.courses.success && result.exams.success) {
        state.pending = false;
        state.attempts = 0;
        state.nextAttemptAtMs = 0;
        state.lastSuccessAtMs = Date.now();
        await SyncService.saveCloudAutoSyncState(context, state);
        console.info('[SyncService] 云端自动同步完成');
      } else {
        const errorMsg: string = result.courses.error || result.exams.error || '未知错误';
        await SyncService.recordCloudAutoSyncFailure(context, state, errorMsg);
      }
    } catch (e) {
      await SyncService.recordCloudAutoSyncFailure(context, state, String(e));
    } finally {
      SyncService.autoSyncRunning = false;
    }
  }

  private static async recordCloudAutoSyncFailure(
    context: Context,
    state: CloudAutoSyncState,
    message: string
  ): Promise<void> {
    state.pending = true;
    state.attempts += 1;
    const backoffMs: number =
      Math.min(CLOUD_SYNC_BACKOFF_BASE_MS * Math.pow(2, state.attempts - 1), CLOUD_SYNC_BACKOFF_MAX_MS);
    state.nextAttemptAtMs = Date.now() + backoffMs;
    await SyncService.saveCloudAutoSyncState(context, state);
    console.warn(`[SyncService] 云端自动同步失败(${message})，第${state.attempts}次退避 ${backoffMs}ms`);
    SyncService.scheduleBackoffRetry(context, backoffMs);
  }

  /** 退避到点后若应用仍存活则自动补传一次 */
  private static scheduleBackoffRetry(context: Context, delayMs: number): void {
    if (SyncService.autoSyncRetryTimer >= 0) {
      clearTimeout(SyncService.autoSyncRetryTimer);
    }
    SyncService.autoSyncRetryTimer = setTimeout(() => {
      SyncService.autoSyncRetryTimer = -1;
      SyncService.flushPendingAutoSync(context);
    }, delayMs);
  }

  /**
   * 启动/回前台时的补偿触发（P2-7a）：存在待同步条目且已过退避/频率窗口时补传一次。
   * 开关关闭、未登录或未到重试时间点时静默返回；手动同步不受影响。
   */
  static async flushPendingAutoSync(context: Context): Promise<void> {
    try {
      const enabled = await ReminderService.getCloudAutoSyncEnabled(context);
      if (!enabled) {
        return;
      }
      const userId = await AuthService.getLoginUserId(context);
      if (!userId) {
        return;
      }
      const state = await SyncService.loadCloudAutoSyncState(context);
      if (!state.pending) {
        return;
      }
      const now = Date.now();
      if (now < state.nextAttemptAtMs) {
        return;
      }
      // 补偿同样遵守频率上限：仍在成功窗口内则顺延到窗口结束
      if (state.lastSuccessAtMs > 0 && now - state.lastSuccessAtMs < CLOUD_SYNC_MIN_INTERVAL_MS) {
        state.nextAttemptAtMs =
          Math.max(state.nextAttemptAtMs, state.lastSuccessAtMs + CLOUD_SYNC_MIN_INTERVAL_MS);
        await SyncService.saveCloudAutoSyncState(context, state);
        return;
      }
      await SyncService.runCloudAutoSync(context, userId, state);
    } catch (e) {
      console.warn(`[SyncService] 补偿自动同步异常: ${String(e)}`);
    }
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), ms));
  }

  private static async retryOperation<T>(
    operation: () => Promise<T>,
    maxRetries: number = 3,
    baseDelay: number = 2000
  ): Promise<T> {
    let lastError: Error | null = null;
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error as Error;
        const errorStr = String(error);
        if (errorStr.includes('1004007') && attempt < maxRetries) {
          const delayMs = baseDelay * Math.pow(2, attempt);
          console.warn(`[SyncService] 请求被限流，${delayMs}ms后重试 (${attempt + 1}/${maxRetries})`);
          await SyncService.delay(delayMs);
        } else {
          throw new Error(String(error));
        }
      }
    }
    throw lastError!;
  }

  private static courseChanged(existing: ClassCourse, current: ClassCourse): boolean {
    return existing.courseName !== current.courseName ||
           existing.teacherName !== current.teacherName ||
           existing.roomName !== current.roomName ||
           existing.validWeeks !== current.validWeeks ||
           existing.dayOfWeek !== current.dayOfWeek ||
           existing.startSection !== current.startSection ||
           existing.duration !== current.duration;
  }

  private static examChanged(existing: ClassExam, current: ClassExam): boolean {
    return existing.examDate !== current.examDate ||
           existing.examTimeRange !== current.examTimeRange ||
           existing.examLocation !== current.examLocation ||
           existing.seatNo !== current.seatNo ||
           existing.examStatus !== current.examStatus;
  }

  /**
   * 【ID 治理 · P2-7c】确定性哈希 ID 设计说明（决策：维持现状，不迁移）
   *
   * - 幂等设计意图：以「userId|学期|业务键」做确定性哈希，同一门课/同一场考试
   *   无论重复上传多少次、在哪个设备上传，恒得到同一个云端 Integer 主键。
   *   因此 upsert 天然是「覆盖更新」而非「插入重复」，双端写同一实体无需发号即可收敛；
   * - 碰撞概率量级：碰撞仅发生在「不同业务键哈希出同一值」。云 ID 空间约 21 亿
   *   （buildId 取模 20 亿再 +1），单用户课程+考试仅数百条规模，生日悖论估算下
   *   用户内碰撞概率约十万分之一量级；即便发生碰撞，条目级 LWW 合并仍可正常裁决，
   *   风险可接受，不值得为此迁移存量数据；
   * - id-generator 云函数已退役：其实现仅为返回 crypto.randomUUID()，无号段分配，
   *   「集中发号」无实质增益。保留在仓库（CloudProgram/cloudfunctions/id-generator）但
   *   不部署、不接入任何调用链。本轮及后续新增实体一律采用 String 主键 + 端侧
   *   util.generateRandomUUID()（见 PHASE2_PLAN.md P2-7d）。
   */
  private static buildId(seed: string): number {
    let hash: number = 0;
    for (let i = 0; i < seed.length; i++) {
      hash = ((hash << 5) - hash) + seed.charCodeAt(i);
      hash |= 0;
    }
    const value: number = Math.abs(hash % 2000000000);
    return value + 1;
  }

  private static toCloudCourse(course: Course, userId: string, semesterId: number, semesterLabel: string): ClassCourse {
    const record = new ClassCourse();
    record.id = SyncService.buildId(`${userId}|${semesterId}|${course.id}|${course.time.dayOfWeek}|${course.time.startSection}|${course.validWeeks}`);
    record.userId = userId;
    record.semesterId = semesterId;
    record.semesterLabel = semesterLabel;
    record.courseId = course.id;
    record.courseName = course.name;
    record.teacherName = course.teacherName || '';
    record.roomName = course.roomName || '';
    record.dayOfWeek = Number(course.time.dayOfWeek) || 1;
    record.startSection = Number(course.time.startSection) || 1;
    record.duration = Number(course.time.duration) || 1;
    record.validWeeks = course.validWeeks || '';
    record.colorIndex = Number(course.colorIndex) || 0;
    record.updatedAt = new Date();
    return record;
  }

  private static toCloudExam(item: ExamItem, userId: string): ClassExam {
    const semesterId: number = item.semesterId > 0 ? item.semesterId : calculateSemesterId();
    const semesterLabel: string = item.semesterLabel || getSemesterLabelById(semesterId);
    const record = new ClassExam();
    record.id = SyncService.buildId(`${userId}|${semesterId}|${item.courseNo}|${item.courseName}|${item.examDate}|${item.examTimeRange}|${item.examType}`);
    record.userId = userId;
    record.semesterId = semesterId;
    record.semesterLabel = semesterLabel;
    record.courseNo = item.courseNo;
    record.courseName = item.courseName;
    record.examDate = item.examDate;
    record.examTimeRange = item.examTimeRange;
    record.examLocation = item.examLocation;
    record.seatNo = item.seatNo;
    record.examStatus = item.examStatus;
    record.examType = item.examType;
    record.remark = item.remark;
    if (item.beginTime > 0) {
      record.beginTime = new Date(item.beginTime);
    }
    if (item.endTime > 0) {
      record.endTime = new Date(item.endTime);
    }
    record.updatedAt = new Date();
    return record;
  }

  private static extractCoursesFromRawData(rawData: RawCourseTableData): Course[] {
    const courses: Course[] = [];
    const activities = rawData.activities;

    if (!activities || !Array.isArray(activities)) {
      return courses;
    }

    const processed = new Set<string>();

    for (let i = 0; i < activities.length; i++) {
      const slotActivities = activities[i];
      if (!slotActivities || slotActivities.length === 0) {
        continue;
      }

      const dayOfWeek = Math.floor(i / 12) + 1;
      const startSection = (i % 12) + 1;

      for (const rawActivity of slotActivities) {
        const key = `${rawActivity.courseId}_${rawActivity.courseName}_${dayOfWeek}_${startSection}_${rawActivity.vaildWeeks}`;
        if (processed.has(key)) {
          continue;
        }

        const course: Course = {
          id: rawActivity.courseId || '',
          name: rawActivity.courseName,
          teacherName: rawActivity.teacherName || '',
          roomName: rawActivity.roomName || '',
          time: {
            dayOfWeek,
            startSection,
            duration: 1,
          },
          validWeeks: rawActivity.vaildWeeks || '',
          colorIndex: 0,
        };

        courses.push(course);
        processed.add(key);
      }
    }

    return courses;
  }

  private static cloudCoursesToRawData(cloudCourses: ClassCourse[]): RawCourseTableData {
    const rawActivities: RawActivity[][] = [];
    for (let i = 0; i < 84; i++) {
      rawActivities.push([]);
    }

    for (const cc of cloudCourses) {
      const dayIndex = (cc.dayOfWeek || 1) - 1;
      const sectionIndex = (cc.startSection || 1) - 1;
      const slotIndex = dayIndex * 12 + sectionIndex;
      if (slotIndex >= 0 && slotIndex < 84) {
        const activity: RawActivity = {
          teacherId: '',
          teacherName: cc.teacherName || '',
          courseId: cc.courseId || '',
          courseName: cc.courseName || '',
          roomId: '',
          roomName: cc.roomName || '',
          vaildWeeks: cc.validWeeks || '',
        };
        rawActivities[slotIndex].push(activity);
      }

      const dur = cc.duration || 1;
      for (let d = 1; d < dur; d++) {
        const extraIndex = dayIndex * 12 + sectionIndex + d;
        if (extraIndex < 84) {
          const activity: RawActivity = {
            teacherId: '',
            teacherName: cc.teacherName || '',
            courseId: cc.courseId || '',
            courseName: cc.courseName || '',
            roomId: '',
            roomName: cc.roomName || '',
            vaildWeeks: cc.validWeeks || '',
          };
          rawActivities[extraIndex].push(activity);
        }
      }
    }

    const result: RawCourseTableData = {
      unitCounts: 12,
      activities: rawActivities,
    };
    return result;
  }
}
