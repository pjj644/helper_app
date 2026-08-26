import { ExamItem } from '../model/classTableModel/ExamModel';
import { ExamRepository, ExamSelectionPreference } from '../repository/ExamRepository';
import { ExamUtils } from '../common/utils/ExamUtils';
import { DateUtils } from '../common/utils/DateUtils';
import {
  getExamTypeIdByIndex,
  getExamTypeIndexById,
  normalizeExamTypeId,
} from '../model/classTableModel/ExamAccessRules';

export class ExamService {
  static async loadExams(context: Object): Promise<ExamItem[]> {
    const dataText = await ExamRepository.loadExamData(context);
    console.info(`[ExamDebug] loadExams: rawDataLength=${dataText ? dataText.length : 0}`);
    if (!dataText) {
      console.info('[ExamDebug] loadExams: no exam data in storage, returning empty');
      return [];
    }
    try {
      const parsed = JSON.parse(dataText) as ExamItem[];
      console.info(`[ExamDebug] loadExams: parsedCount=${parsed.length}`);
      const normalized = parsed.map(item => ExamUtils.normalizeStoredExam(item));
      return normalized;
    } catch (error) {
      console.error('[ExamDebug] loadExams parse error:', JSON.stringify(error));
      return [];
    }
  }

  static async saveExams(context: Object, exams: ExamItem[]): Promise<void> {
    const sorted = ExamUtils.sortExams(exams);
    await ExamRepository.saveExamData(context, JSON.stringify(sorted));
  }

  static async clearExamData(context: Object): Promise<void> {
    await ExamRepository.clearExamData(context);
  }

  static filterExams(exams: ExamItem[], examTypeId: number, semesterId: number): ExamItem[] {
    return exams.filter(item => {
      const itemExamTypeId = ExamUtils.resolveExamTypeId(item);
      if (itemExamTypeId !== examTypeId) {
        return false;
      }
      if (semesterId > 0 && item.semesterId !== semesterId) {
        return false;
      }
      return true;
    });
  }

  static sortExams(exams: ExamItem[]): ExamItem[] {
    return ExamUtils.sortExams(exams);
  }

  static getNextExam(exams: ExamItem[], now: number = Date.now()): ExamItem | undefined {
    const sorted = ExamService.sortExams(exams);
    return sorted.find(item => item.beginTime > now);
  }

  static getUpcomingExams(exams: ExamItem[], now: number = Date.now()): ExamItem[] {
    const sorted = ExamService.sortExams(exams);
    return sorted.filter(item => item.beginTime > now);
  }

  static getPastExams(exams: ExamItem[], now: number = Date.now()): ExamItem[] {
    const sorted = ExamService.sortExams(exams);
    return sorted.filter(item => item.beginTime > 0 && item.beginTime <= now);
  }

  static formatCountDown(now: number, beginTime: number): string {
    return DateUtils.formatCountDown(now, beginTime);
  }

  static isSameExam(left: ExamItem, right: ExamItem): boolean {
    return left.courseNo === right.courseNo
      && left.courseName === right.courseName
      && left.examDate === right.examDate
      && left.examTimeRange === right.examTimeRange
      && left.examType === right.examType
      && left.semesterId === right.semesterId;
  }

  static async saveSelectionPreference(context: Object, examTypeId: number, semesterId: number): Promise<void> {
    const preference: ExamSelectionPreference = {
      examTypeId: normalizeExamTypeId(examTypeId),
      semesterId: semesterId,
    };
    await ExamRepository.saveExamSelectionPreference(context, preference);
  }

  static async loadSelectionPreference(context: Object): Promise<ExamSelectionPreference> {
    return await ExamRepository.loadExamSelectionPreference(context);
  }

  static getExamTypeIdByIndex(index: number): number {
    return getExamTypeIdByIndex(index);
  }

  static getExamTypeIndexById(examTypeId: number): number {
    return getExamTypeIndexById(examTypeId);
  }
}
