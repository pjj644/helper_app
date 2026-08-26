import { preferences } from '@kit.ArkData';
import { ContextUtils } from '../common/utils/ContextUtils';
import { AppConstants } from '../common/constants/AppConstants';
import { ExamItem, getExamBizKey, getExamContentKey } from '../model/classTableModel/ExamModel';

export interface ExamSelectionPreference {
  examTypeId: number;
  semesterId: number;
}

/** 现存条目的盖章索引记录：内容比较键 + 原时间戳（旧数据无时间戳记 0） */
interface ExamStampRecord {
  contentKey: string;
  updatedAt: number;
}

export class ExamRepository {
  /**
   * 集中盖章写入（P2-7b）：写盘前读现存 JSON，逐条按业务键比对内容——
   * 内容变化或新增的条目盖 updatedAt = Date.now()，未变化的保留原时间戳（旧数据无时间戳视为 0）。
   */
  static async saveExamData(context: Object, examDataJson: string): Promise<void> {
    const stampedJson = await ExamRepository.stampExamTimestamps(context, examDataJson);
    await ExamRepository.writeExamData(context, stampedJson);
  }

  /**
   * 云同步合并写回专用内部通道（跳过集中盖章）：合并结果中每个条目的 updatedAt
   * 已是双端 LWW 裁决后的时间戳，再盖章会把裁决保留的历史时间戳误刷新成本地当前时间。
   * 仅限 SyncService 下载合并路径调用。
   */
  static async saveExamDataRaw(context: Object, examDataJson: string): Promise<void> {
    await ExamRepository.writeExamData(context, examDataJson);
  }

  static async loadExamData(context: Object): Promise<string> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    return (await pref.get(AppConstants.EXAM_DATA_KEY, '')) as string;
  }

  static async saveExamSelectionPreference(context: Object, preference: ExamSelectionPreference): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.EXAM_SELECTED_TYPE_ID_KEY, preference.examTypeId);
    await pref.put(AppConstants.EXAM_SELECTED_SEMESTER_ID_KEY, preference.semesterId);
    await pref.flush();
  }

  static async loadExamSelectionPreference(context: Object): Promise<ExamSelectionPreference> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    return {
      examTypeId: (await pref.get(AppConstants.EXAM_SELECTED_TYPE_ID_KEY, 1)) as number,
      semesterId: (await pref.get(AppConstants.EXAM_SELECTED_SEMESTER_ID_KEY, 0)) as number,
    };
  }

  static async clearExamData(context: Object): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.delete(AppConstants.EXAM_DATA_KEY);
    await pref.flush();
  }

  /** 底层写盘：put + flush，不含任何盖章逻辑 */
  private static async writeExamData(context: Object, examDataJson: string): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.EXAM_DATA_KEY, examDataJson);
    await pref.flush();
  }

  /**
   * 集中盖章（P2-7b）：以考试业务键对齐现存数据与待写数据（见 getExamBizKey，
   * 含学期维度），内容比较维度见 getExamContentKey。
   * - 双端内容一致 → 继承现存 updatedAt（旧数据无时间戳视为 0 并落盘固化）；
   * - 新增或内容变化 → 盖 Date.now()；
   * - 现存 JSON 解析失败/缺失 → 视为空索引，全部按新增处理；
   * - 待写 JSON 解析失败 → 原样返回（不破坏既有调用方的容错语义）。
   */
  private static async stampExamTimestamps(context: Object, examDataJson: string): Promise<string> {
    let incoming: ExamItem[];
    try {
      incoming = JSON.parse(examDataJson) as ExamItem[];
      if (!Array.isArray(incoming)) {
        return examDataJson;
      }
    } catch (e) {
      return examDataJson;
    }

    const existingMap = new Map<string, ExamStampRecord>();
    try {
      const existingJson = await ExamRepository.loadExamData(context);
      if (existingJson) {
        const existingItems = JSON.parse(existingJson) as ExamItem[];
        if (Array.isArray(existingItems)) {
          for (const item of existingItems) {
            const key = ExamRepository.bizKeyOf(item);
            const record: ExamStampRecord = {
              contentKey: ExamRepository.contentKeyOf(item),
              updatedAt: typeof item.updatedAt === 'number' ? item.updatedAt : 0,
            };
            existingMap.set(key, record);
          }
        }
      }
    } catch (e) {
      console.warn(`[ExamRepository] 读取现存考试用于盖章失败，按全新数据处理: ${String(e)}`);
    }

    const now = Date.now();
    for (const item of incoming) {
      const record = existingMap.get(ExamRepository.bizKeyOf(item));
      if (record && record.contentKey === ExamRepository.contentKeyOf(item)) {
        item.updatedAt = record.updatedAt;
      } else {
        item.updatedAt = now;
      }
    }
    return JSON.stringify(incoming);
  }

  private static bizKeyOf(item: ExamItem): string {
    return getExamBizKey(
      item.semesterId > 0 ? item.semesterId : 0,
      item.courseNo || '',
      item.examDate || '',
      item.examTimeRange || '',
      item.examType || ''
    );
  }

  private static contentKeyOf(item: ExamItem): string {
    return getExamContentKey(
      item.courseName || '',
      item.examLocation || '',
      item.seatNo || '',
      item.examStatus || '',
      item.remark || ''
    );
  }
}
