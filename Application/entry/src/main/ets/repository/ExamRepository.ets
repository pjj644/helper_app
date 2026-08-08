import { preferences } from '@kit.ArkData';
import { ContextUtils } from '../common/utils/ContextUtils';
import { AppConstants } from '../common/constants/AppConstants';

export interface ExamSelectionPreference {
  examTypeId: number;
  semesterId: number;
}

export class ExamRepository {
  static async saveExamData(context: Object, examDataJson: string): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.EXAM_DATA_KEY, examDataJson);
    await pref.flush();
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
}
