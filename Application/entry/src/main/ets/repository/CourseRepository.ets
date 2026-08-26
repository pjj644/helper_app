import { preferences } from '@kit.ArkData';
import { ContextUtils } from '../common/utils/ContextUtils';
import { AppConstants } from '../common/constants/AppConstants';
import { calculateSemesterId, getSemesterLabelById } from '../model/classTableModel/ExamAccessRules';
import { RawActivity, RawCourseTableData, getCourseBizKey, getCourseContentKey }
  from '../model/classTableModel/CourseModel';

export interface ArchivedSemesterSummary {
  semesterId: number;
  semesterLabel: string;
  courseCount: number;
  hasData: boolean;
}

/** 现存条目的盖章索引记录：内容比较键 + 原时间戳（旧数据无时间戳记 0） */
interface CourseStampRecord {
  contentKey: string;
  updatedAt: number;
}

export class CourseRepository {
  static async saveCourseData(context: Object, courseDataJson: string): Promise<void> {
    const semesterId = calculateSemesterId();
    await CourseRepository.saveCourseDataBySemester(context, semesterId, courseDataJson);
  }

  /**
   * 集中盖章写入（P2-7b）：写盘前读现存 JSON，逐条按业务键比对内容——
   * 内容变化或新增的槽位盖 updatedAt = Date.now()，未变化的保留原时间戳（旧数据无时间戳视为 0）。
   * 所有本地课程写入路径（含 tableUI/Index 手动保存）都经由本方法自动获得时间戳。
   */
  static async saveCourseDataBySemester(context: Object, semesterId: number, courseDataJson: string): Promise<void> {
    const stampedJson = await CourseRepository.stampCourseTimestamps(context, semesterId, courseDataJson);
    await CourseRepository.writeCourseDataBySemester(context, semesterId, stampedJson);
  }

  /**
   * 云同步合并写回专用内部通道（跳过集中盖章）：合并结果中每个条目的 updatedAt
   * 已是双端 LWW 裁决后的时间戳，若再走盖章通道会被「新增/内容变化 → 盖 now」误判，
   * 把裁决保留的历史时间戳全部刷新成本地当前时间，破坏后续轮次的时间戳可比性。
   * 仅限 SyncService 下载合并路径调用。
   */
  static async saveCourseDataBySemesterRaw(context: Object, semesterId: number, courseDataJson: string): Promise<void> {
    await CourseRepository.writeCourseDataBySemester(context, semesterId, courseDataJson);
  }

  static async loadCourseDataBySemester(context: Object, semesterId: number): Promise<string> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const key = AppConstants.COURSE_TABLE_DATA_KEY_PREFIX + semesterId;
    return (await pref.get(key, '')) as string;
  }

  static async loadCourseData(context: Object): Promise<string> {
    const semesterId = calculateSemesterId();
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const key = AppConstants.COURSE_TABLE_DATA_KEY_PREFIX + semesterId;
    const data = (await pref.get(key, '')) as string;
    if (data) {
      return data;
    }
    return (await pref.get(AppConstants.COURSE_TABLE_DATA_KEY, '')) as string;
  }

  static async getStoredSemesterIds(context: Object): Promise<number[]> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const allKeys = await pref.getAll();
    const ids: number[] = [];
    for (const key of Object.keys(allKeys)) {
      if (key.startsWith(AppConstants.COURSE_TABLE_DATA_KEY_PREFIX)) {
        const idStr = key.substring(AppConstants.COURSE_TABLE_DATA_KEY_PREFIX.length);
        const id = Number.parseInt(idStr, 10);
        if (Number.isFinite(id) && id > 0) {
          ids.push(id);
        }
      }
    }
    ids.sort((a, b) => b - a);
    return ids;
  }

  static async getArchivedSemestersSummary(context: Object): Promise<ArchivedSemesterSummary[]> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const storedIds = await CourseRepository.getStoredSemesterIds(context);
    const result: ArchivedSemesterSummary[] = [];

    for (const semId of storedIds) {
      const dataStr = (await pref.get(AppConstants.COURSE_TABLE_DATA_KEY_PREFIX + semId, '')) as string;
      let count = 0;
      if (dataStr) {
        try {
          const parsed = JSON.parse(dataStr) as Record<string, Object>;
          if (parsed && parsed['activities'] && Array.isArray(parsed['activities'])) {
            const courseIds = new Set<string>();
            const activities = parsed['activities'] as Object[][];
            for (const slot of activities) {
              if (Array.isArray(slot)) {
                for (const act of slot) {
                  const actObj = act as Record<string, string>;
                  if (actObj && actObj['courseName']) {
                    courseIds.add(actObj['courseName']);
                  }
                }
              }
            }
            count = courseIds.size;
          }
        } catch (e) {}
      }
      result.push({
        semesterId: semId,
        semesterLabel: getSemesterLabelById(semId),
        courseCount: count,
        hasData: count > 0 || dataStr.length > 0
      });
    }
    return result;
  }

  static async deleteSemesterData(context: Object, semesterId: number): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.delete(AppConstants.COURSE_TABLE_DATA_KEY_PREFIX + semesterId);
    await pref.flush();
  }

  static async hasCourseData(context: Object): Promise<boolean> {
    const courseDataJson: string = await CourseRepository.loadCourseData(context);
    return !!courseDataJson;
  }

  static async clearCourseData(context: Object): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.delete(AppConstants.COURSE_TABLE_DATA_KEY);
    await pref.flush();
  }

  static async clearAllCourseData(context: Object): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const storedIds = await CourseRepository.getStoredSemesterIds(context);
    for (let i = 0; i < storedIds.length; i++) {
      await pref.delete(AppConstants.COURSE_TABLE_DATA_KEY_PREFIX + storedIds[i]);
    }
    await pref.delete(AppConstants.COURSE_TABLE_DATA_KEY);
    await pref.flush();
  }

  /** 底层写盘：put + flush，不含任何盖章逻辑 */
  private static async writeCourseDataBySemester(context: Object, semesterId: number, courseDataJson: string): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const key = AppConstants.COURSE_TABLE_DATA_KEY_PREFIX + semesterId;
    await pref.put(key, courseDataJson);
    await pref.flush();
  }

  /**
   * 集中盖章（P2-7b）：以业务键 (courseId|dayOfWeek|startSection) 对齐现存数据与待写数据，
   * 内容比较维度与 SyncService.courseChanged 对齐（见 getCourseContentKey）。
   * - 双端内容一致 → 继承现存 updatedAt（旧数据无时间戳视为 0 并落盘固化）；
   * - 新增或内容变化 → 盖 Date.now()；
   * - 现存 JSON 解析失败/缺失 → 视为空索引，全部按新增处理；
   * - 待写 JSON 解析失败 → 原样返回（不破坏既有调用方的容错语义）。
   */
  private static async stampCourseTimestamps(context: Object, semesterId: number, courseDataJson: string): Promise<string> {
    let incoming: RawCourseTableData;
    try {
      incoming = JSON.parse(courseDataJson) as RawCourseTableData;
      if (!incoming || !Array.isArray(incoming.activities)) {
        return courseDataJson;
      }
    } catch (e) {
      return courseDataJson;
    }

    // 现存时间戳索引
    const existingMap = new Map<string, CourseStampRecord>();
    try {
      const existingJson = await CourseRepository.loadCourseDataBySemester(context, semesterId);
      if (existingJson) {
        const existing = JSON.parse(existingJson) as RawCourseTableData;
        const oldActivities = existing && Array.isArray(existing.activities) ? existing.activities : [];
        for (let i = 0; i < oldActivities.length; i++) {
          const slot = oldActivities[i];
          if (!Array.isArray(slot)) {
            continue;
          }
          const dayOfWeek = Math.floor(i / 12) + 1;
          const startSection = (i % 12) + 1;
          for (const activity of slot) {
            existingMap.set(
              getCourseBizKey(activity.courseId || '', dayOfWeek, startSection),
              CourseRepository.makeStampRecord(activity)
            );
          }
        }
      }
    } catch (e) {
      console.warn(`[CourseRepository] 读取现存课表用于盖章失败，按全新数据处理: ${String(e)}`);
    }

    const now = Date.now();
    const activities = incoming.activities;
    for (let i = 0; i < activities.length; i++) {
      const slot = activities[i];
      if (!Array.isArray(slot)) {
        continue;
      }
      const dayOfWeek = Math.floor(i / 12) + 1;
      const startSection = (i % 12) + 1;
      for (const activity of slot) {
        const record = existingMap.get(getCourseBizKey(activity.courseId || '', dayOfWeek, startSection));
        if (record && record.contentKey === CourseRepository.contentKeyOf(activity)) {
          activity.updatedAt = record.updatedAt;
        } else {
          activity.updatedAt = now;
        }
      }
    }
    return JSON.stringify(incoming);
  }

  private static makeStampRecord(activity: RawActivity): CourseStampRecord {
    const record: CourseStampRecord = {
      contentKey: CourseRepository.contentKeyOf(activity),
      updatedAt: typeof activity.updatedAt === 'number' ? activity.updatedAt : 0,
    };
    return record;
  }

  private static contentKeyOf(activity: RawActivity): string {
    return getCourseContentKey(
      activity.courseName || '',
      activity.teacherName || '',
      activity.roomName || '',
      activity.vaildWeeks || ''
    );
  }
}
