import { GradeItem, RawGradeRow, GradeUtils, GradeSemesterOption } from '../model/GradeModel';
import { GradeRepository } from '../repository/GradeRepository';

export class GradeService {
  static async loadGrades(context: Context): Promise<GradeItem[]> {
    try {
      const grades: GradeItem[] = await GradeRepository.loadGrades(context);
      return GradeUtils.sortGrades(grades);
    } catch (error) {
      console.error('[GradeService] loadGrades error:', JSON.stringify(error));
      return [];
    }
  }

  static async saveGrades(context: Context, grades: GradeItem[]): Promise<void> {
    try {
      const sorted: GradeItem[] = GradeUtils.sortGrades(grades);
      await GradeRepository.saveGrades(context, sorted);
    } catch (error) {
      console.error('[GradeService] saveGrades error:', JSON.stringify(error));
    }
  }

  static mergeGrades(existing: GradeItem[], imported: GradeItem[]): GradeItem[] {
    const map: Record<string, GradeItem> = {};
    for (let i = 0; i < existing.length; i++) {
      const g: GradeItem = existing[i];
      const key: string = `${g.courseCode}_${g.courseSeq}_${g.academicYear}_${g.courseCategory}`;
      map[key] = g;
    }
    for (let i = 0; i < imported.length; i++) {
      const g: GradeItem = imported[i];
      const key: string = `${g.courseCode}_${g.courseSeq}_${g.academicYear}_${g.courseCategory}`;
      map[key] = g;
    }
    const merged: GradeItem[] = [];
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      merged.push(map[keys[i]]);
    }
    return GradeUtils.sortGrades(merged);
  }

  static getSemesterList(grades: GradeItem[]): GradeSemesterOption[] {
    return GradeUtils.extractSemesters(grades);
  }

  static filterBySemester(grades: GradeItem[], semesterId: number): GradeItem[] {
    return GradeUtils.filterBySemester(grades, semesterId);
  }

  static calculateSemesterGPA(grades: GradeItem[]): number {
    return GradeUtils.calculateGPA(grades);
  }

  static calculateOverallGPA(grades: GradeItem[]): number {
    return GradeUtils.calculateGPA(grades);
  }

  static parseRawGrades(rawGrades: RawGradeRow[], semesterId: number): GradeItem[] {
    const grades: GradeItem[] = [];
    for (let i = 0; i < rawGrades.length; i++) {
      grades.push(GradeUtils.parseRawGrade(rawGrades[i], semesterId));
    }
    return GradeUtils.sortGrades(grades);
  }

  static getLatestSemesterId(grades: GradeItem[]): number {
    if (grades.length === 0) {
      return 0;
    }
    let latest: number = 0;
    for (let i = 0; i < grades.length; i++) {
      if (grades[i].semesterId > latest) {
        latest = grades[i].semesterId;
      }
    }
    return latest;
  }

  static getLatestSemesterGPA(grades: GradeItem[]): number {
    const latestId: number = GradeService.getLatestSemesterId(grades);
    if (latestId === 0) {
      return 0;
    }
    const filtered: GradeItem[] = GradeUtils.filterBySemester(grades, latestId);
    return GradeService.calculateSemesterGPA(filtered);
  }
}
