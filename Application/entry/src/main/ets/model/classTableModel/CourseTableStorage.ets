import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../../common/constants/AppConstants';

export interface DisplaySettings {
  showToday: boolean;
  showTomorrow: boolean;
  showExamCountdown: boolean;
  examRemindMinutes: number;
  courseRemindMinutes: number;
}

export interface RecentLinkItem {
  title: string;
  url: string;
  visitedAt: number;
}

export interface ExamSelectionPreference {
  examTypeId: number;
  semesterId: number;
}

interface HostContextProvider {
  getHostContext: () => common.UIAbilityContext;
}

export class CourseTableStorage {
  private static getAbilityContext(context: Object): common.UIAbilityContext {
    const contextWithHost = context as HostContextProvider;
    if (contextWithHost && contextWithHost.getHostContext) {
      return contextWithHost.getHostContext();
    }
    return context as common.UIAbilityContext;
  }

  static async saveCourseData(context: Object, courseDataJson: string): Promise<void> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.COURSE_TABLE_DATA_KEY, courseDataJson);
    await pref.flush();
  }

  static async loadCourseData(context: Object): Promise<string> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    return (await pref.get(AppConstants.COURSE_TABLE_DATA_KEY, '')) as string;
  }

  static async hasCourseData(context: Object): Promise<boolean> {
    const courseDataJson: string = await CourseTableStorage.loadCourseData(context);
    return !!courseDataJson;
  }

  static async saveSettings(context: Object, settings: DisplaySettings): Promise<void> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.SETTING_SHOW_TODAY_KEY, settings.showToday);
    await pref.put(AppConstants.SETTING_SHOW_TOMORROW_KEY, settings.showTomorrow);
    await pref.put(AppConstants.SETTING_SHOW_EXAM_KEY, settings.showExamCountdown);
    await pref.put(AppConstants.SETTING_EXAM_REMIND_MINUTES_KEY, settings.examRemindMinutes);
    await pref.put(AppConstants.SETTING_COURSE_REMIND_MINUTES_KEY, settings.courseRemindMinutes);
    await pref.flush();
  }

  static async loadSettings(context: Object): Promise<DisplaySettings> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    return {
      showToday: (await pref.get(AppConstants.SETTING_SHOW_TODAY_KEY, true)) as boolean,
      showTomorrow: (await pref.get(AppConstants.SETTING_SHOW_TOMORROW_KEY, true)) as boolean,
      showExamCountdown: (await pref.get(AppConstants.SETTING_SHOW_EXAM_KEY, true)) as boolean,
      examRemindMinutes: (await pref.get(AppConstants.SETTING_EXAM_REMIND_MINUTES_KEY, 30)) as number,
      courseRemindMinutes: (await pref.get(AppConstants.SETTING_COURSE_REMIND_MINUTES_KEY, 30)) as number,
    };
  }

  static async saveExamData(context: Object, examDataJson: string): Promise<void> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.EXAM_DATA_KEY, examDataJson);
    await pref.flush();
  }

  static async loadExamData(context: Object): Promise<string> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    return (await pref.get(AppConstants.EXAM_DATA_KEY, '')) as string;
  }

  static async saveExamSelectionPreference(context: Object, preference: ExamSelectionPreference): Promise<void> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.EXAM_SELECTED_TYPE_ID_KEY, preference.examTypeId);
    await pref.put(AppConstants.EXAM_SELECTED_SEMESTER_ID_KEY, preference.semesterId);
    await pref.flush();
  }

  static async loadExamSelectionPreference(context: Object): Promise<ExamSelectionPreference> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    return {
      examTypeId: (await pref.get(AppConstants.EXAM_SELECTED_TYPE_ID_KEY, 1)) as number,
      semesterId: (await pref.get(AppConstants.EXAM_SELECTED_SEMESTER_ID_KEY, 0)) as number,
    };
  }

  static async saveRecentLinks(context: Object, links: RecentLinkItem[]): Promise<void> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.RECENT_LINKS_KEY, JSON.stringify(links));
    await pref.flush();
  }

  static async loadRecentLinks(context: Object): Promise<RecentLinkItem[]> {
    const abilityContext: common.UIAbilityContext = CourseTableStorage.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const text: string = (await pref.get(AppConstants.RECENT_LINKS_KEY, '[]')) as string;
    try {
      return JSON.parse(text) as RecentLinkItem[];
    } catch (error) {
      return [];
    }
  }
}
