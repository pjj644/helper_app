import { ExamItem } from '../../model/classTableModel/ExamModel';
import { DateUtils } from './DateUtils';
import {
  calculateSemesterId,
  detectExamTypeIdFromText,
  getExamTypeLabelById,
  getSemesterLabelById,
  normalizeExamTypeId,
} from '../../model/classTableModel/ExamAccessRules';

export interface ExamInput {
  courseNo?: string;
  courseName?: string;
  examDate?: string;
  examTimeRange?: string;
  examLocation?: string;
  seatNo?: string;
  examStatus?: string;
  examType?: string;
  remark?: string;
  semesterId?: number;
  semesterLabel?: string;
  beginTime?: number;
  endTime?: number;
}

export interface RawExamRow {
  courseNo: string;
  courseName: string;
  examDate: string;
  examTimeRange: string;
  examLocation: string;
  seatNo: string;
  examStatus: string;
  examType: string;
  remark: string;
}

export class ExamUtils {
  static normalizeExam(input: ExamInput): ExamItem {
    const dateText: string = DateUtils.normalizeExamDate(input.examDate || '');
    const timeRange: string = input.examTimeRange || '';
    const parsed = DateUtils.parseDateTime(dateText, timeRange);
    return {
      courseNo: input.courseNo || '',
      courseName: input.courseName || '',
      examDate: dateText,
      examTimeRange: timeRange,
      examLocation: input.examLocation || '',
      seatNo: input.seatNo || '',
      examStatus: input.examStatus || '',
      examType: input.examType || '',
      remark: input.remark || '',
      semesterId: input.semesterId && input.semesterId > 0 ? input.semesterId : 0,
      semesterLabel: input.semesterLabel || '',
      beginTime: input.beginTime && input.beginTime > 0 ? input.beginTime : parsed.begin,
      endTime: input.endTime && input.endTime > 0 ? input.endTime : parsed.end,
    };
  }

  static normalizeStoredExam(item: ExamItem, fallbackSemesterId?: number): ExamItem {
    const semesterId: number = ExamUtils.resolveSemesterId(item, fallbackSemesterId);
    return ExamUtils.normalizeExam({
      courseNo: item.courseNo,
      courseName: item.courseName,
      examDate: item.examDate,
      examTimeRange: item.examTimeRange,
      examLocation: item.examLocation,
      seatNo: item.seatNo,
      examStatus: item.examStatus,
      examType: item.examType,
      remark: item.remark,
      semesterId: semesterId,
      semesterLabel: item.semesterLabel || (semesterId > 0 ? getSemesterLabelById(semesterId) : ''),
      beginTime: item.beginTime,
      endTime: item.endTime,
    });
  }

  static resolveSemesterId(item: ExamItem, fallbackSemesterId?: number): number {
    if (item.semesterId && item.semesterId > 0) {
      return item.semesterId;
    }
    if (item.beginTime > 0) {
      return calculateSemesterId(new Date(item.beginTime));
    }
    const parsedDate: Date | undefined = DateUtils.parseExamDate(item.examDate);
    if (parsedDate) {
      return calculateSemesterId(parsedDate);
    }
    return fallbackSemesterId || 0;
  }

  static resolveExamTypeId(item: ExamItem, fallbackExamTypeId?: number): number {
    const detected: number | undefined = detectExamTypeIdFromText(item.examType || '');
    return detected || fallbackExamTypeId || normalizeExamTypeId(undefined);
  }

  static rowToExam(row: RawExamRow, semesterId: number, examTypeId: number): ExamItem {
    return ExamUtils.normalizeExam({
      courseNo: row.courseNo || '',
      courseName: row.courseName || '',
      examDate: row.examDate || '',
      examTimeRange: row.examTimeRange || '',
      examLocation: row.examLocation || '',
      seatNo: row.seatNo || '',
      examStatus: row.examStatus || '',
      examType: row.examType || getExamTypeLabelById(examTypeId),
      remark: row.remark || '',
      semesterId: semesterId,
      semesterLabel: getSemesterLabelById(semesterId),
    });
  }

  static sortExams(items: ExamItem[]): ExamItem[] {
    const copied: ExamItem[] = [...items];
    copied.sort((a, b) => {
      if (a.beginTime === 0 && b.beginTime === 0) {
        return a.courseName.localeCompare(b.courseName);
      }
      if (a.beginTime === 0) {
        return 1;
      }
      if (b.beginTime === 0) {
        return -1;
      }
      return a.beginTime - b.beginTime;
    });
    return copied;
  }

  static createEmptyExam(): ExamItem {
    return {
      courseNo: '',
      courseName: '',
      examDate: '',
      examTimeRange: '',
      examLocation: '',
      seatNo: '',
      examStatus: '',
      examType: '',
      remark: '',
      semesterId: 0,
      semesterLabel: '',
      beginTime: 0,
      endTime: 0,
    };
  }
}
