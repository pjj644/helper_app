import { preferences } from '@kit.ArkData';
import { GradeItem } from '../model/GradeModel';
import { AppConstants } from '../common/constants/AppConstants';

export class GradeRepository {
  static async loadGrades(context: Context): Promise<GradeItem[]> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const jsonStr = pref.getSync(AppConstants.GRADE_DATA_KEY, '[]') as string;
      if (!jsonStr || jsonStr === '[]') {
        return [];
      }
      const parsed: GradeItem[] = JSON.parse(jsonStr) as GradeItem[];
      return parsed;
    } catch (error) {
      console.error('GradeRepository loadGrades error:', JSON.stringify(error));
      return [];
    }
  }

  static async saveGrades(context: Context, grades: GradeItem[]): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.GRADE_DATA_KEY, JSON.stringify(grades));
      pref.flushSync();
    } catch (error) {
      console.error('GradeRepository saveGrades error:', JSON.stringify(error));
    }
  }

  static async clearGrades(context: Context): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.GRADE_DATA_KEY, '[]');
      pref.flushSync();
    } catch (error) {
      console.error('GradeRepository clearGrades error:', JSON.stringify(error));
    }
  }
}
