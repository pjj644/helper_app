import { preferences } from '@kit.ArkData';
import { ContextUtils } from '../common/utils/ContextUtils';
import { AppConstants } from '../common/constants/AppConstants';
import { calculateSemesterId } from '../model/classTableModel/ExamAccessRules';

export class CourseRepository {
  static async saveCourseData(context: Object, courseDataJson: string): Promise<void> {
    const semesterId = calculateSemesterId();
    await CourseRepository.saveCourseDataBySemester(context, semesterId, courseDataJson);
  }

  static async saveCourseDataBySemester(context: Object, semesterId: number, courseDataJson: string): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const key = AppConstants.COURSE_TABLE_DATA_KEY_PREFIX + semesterId;
    await pref.put(key, courseDataJson);
    await pref.flush();
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
}
