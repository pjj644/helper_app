import { parseSemesterIdFromAcademicYear, getGradeSemesterOptions } from './classTableModel/ExamAccessRules';

export interface GradeItem {
  academicYear: string;
  courseCode: string;
  courseSeq: string;
  courseName: string;
  courseCategory: string;
  credit: number;
  finalExamScore: string;
  totalScore: string;
  makeupScore: string;
  finalScore: string;
  gradePoint: number;
  semesterId: number;
}

export interface RawGradeRow {
  academicYear: string;
  courseCode: string;
  courseSeq: string;
  courseName: string;
  courseCategory: string;
  credit: string;
  finalExamScore: string;
  totalScore: string;
  makeupScore: string;
  finalScore: string;
  gradePoint: string;
}

export interface GradeParsePayload {
  grades: RawGradeRow[];
  diagnostics?: GradeDiagnostics;
  error?: string;
}

export interface GradeDiagnostics {
  currentUrl: string;
  pageTitle?: string;
  tableSelector?: string;
  rowCount: number;
  parsedCount: number;
  sampleRow: string;
  allTablesOnPage?: number;
  iframeCount?: number;
  bodyLength?: number;
  bodySnippet?: string;
}

export interface GradeSemesterOption {
  semesterId: number;
  label: string;
}

export class GradeUtils {
  static parseRawGrade(row: RawGradeRow, fallbackSemesterId: number): GradeItem {
    let gradePointNum: number = 0;
    const gp: string = (row.gradePoint || '').trim();
    if (gp && gp !== '--' && gp !== '') {
      const parsed: number = Number.parseFloat(gp);
      if (!Number.isNaN(parsed)) {
        gradePointNum = parsed;
      }
    }
    const creditNum: number = Number.parseFloat(row.credit) || 0;

    let targetSemesterId: number = fallbackSemesterId;
    if (row.academicYear) {
      const parsedId: number | undefined = parseSemesterIdFromAcademicYear(row.academicYear);
      if (parsedId !== undefined && parsedId > 0) {
        targetSemesterId = parsedId;
      }
    }

    return {
      academicYear: row.academicYear,
      courseCode: row.courseCode,
      courseSeq: row.courseSeq,
      courseName: row.courseName,
      courseCategory: row.courseCategory,
      credit: creditNum,
      finalExamScore: row.finalExamScore,
      totalScore: row.totalScore,
      makeupScore: row.makeupScore,
      finalScore: row.finalScore,
      gradePoint: gradePointNum,
      semesterId: targetSemesterId,
    };
  }

  static calculateGPA(grades: GradeItem[]): number {
    let totalGradePoints: number = 0;
    let totalCredits: number = 0;
    for (let i = 0; i < grades.length; i++) {
      const g: GradeItem = grades[i];
      if (g.credit > 0 && typeof g.gradePoint === 'number' && !Number.isNaN(g.gradePoint)) {
        // 包含实际已出分课程（含挂科0绩点），排除未出分或无成绩记录（'--'）的科目
        const hasScore: boolean = (g.totalScore !== undefined && g.totalScore.length > 0 && g.totalScore !== '--') ||
          (g.finalScore !== undefined && g.finalScore.length > 0 && g.finalScore !== '--') ||
          (g.gradePoint > 0);
        if (hasScore) {
          totalGradePoints += g.gradePoint * g.credit;
          totalCredits += g.credit;
        }
      }
    }
    if (totalCredits === 0) {
      return 0;
    }
    return Math.round((totalGradePoints / totalCredits) * 100) / 100;
  }

  static sortGrades(grades: GradeItem[]): GradeItem[] {
    const sorted: GradeItem[] = [...grades];
    sorted.sort((a: GradeItem, b: GradeItem) => {
      if (a.semesterId !== b.semesterId) {
        return b.semesterId - a.semesterId;
      }
      return a.courseCode.localeCompare(b.courseCode);
    });
    return sorted;
  }

  static extractSemesters(grades: GradeItem[]): GradeSemesterOption[] {
    const map: Record<number, string> = {};
    for (let i = 0; i < grades.length; i++) {
      const g: GradeItem = grades[i];
      if (g.semesterId > 0 && !map[g.semesterId]) {
        map[g.semesterId] = g.academicYear;
      }
    }

    const standardOptions = getGradeSemesterOptions();
    const result: GradeSemesterOption[] = [];
    const seenIds = new Set<number>();

    for (let i = 0; i < standardOptions.length; i++) {
      const opt = standardOptions[i];
      result.push({ semesterId: opt.semesterId, label: opt.label });
      seenIds.add(opt.semesterId);
    }

    const allMapKeys = Object.keys(map);
    for (let i = 0; i < allMapKeys.length; i++) {
      const id: number = Number.parseInt(allMapKeys[i], 10);
      if (Number.isFinite(id) && !seenIds.has(id)) {
        result.push({ semesterId: id, label: map[id] || `学期 ${id}` });
      }
    }

    return result;
  }

  static filterBySemester(grades: GradeItem[], semesterId: number): GradeItem[] {
    if (semesterId === 0) {
      return [...grades];
    }
    return grades.filter((g: GradeItem) => g.semesterId === semesterId);
  }

  static getGpaColor(gradePoint: number): string {
    if (gradePoint >= 3.7) {
      return '#4CAF50';
    }
    if (gradePoint >= 2.7) {
      return '#FF9800';
    }
    return '#F44336';
  }

  static getGpaLabel(gradePoint: number): string {
    if (gradePoint >= 3.7) {
      return '优秀';
    }
    if (gradePoint >= 2.7) {
      return '良好';
    }
    if (gradePoint > 0) {
      return '及格';
    }
    return '—';
  }

  static getTotalCredits(grades: GradeItem[]): number {
    let total: number = 0;
    for (let i = 0; i < grades.length; i++) {
      total += grades[i].credit;
    }
    return total;
  }
}
