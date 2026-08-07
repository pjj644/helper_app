import { preferences } from '@kit.ArkData';
import { ContextUtils } from '../common/utils/ContextUtils';
import { AppConstants } from '../common/constants/AppConstants';

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

export class SettingsRepository {
  static async saveSettings(context: Object, settings: DisplaySettings): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.SETTING_SHOW_TODAY_KEY, settings.showToday);
    await pref.put(AppConstants.SETTING_SHOW_TOMORROW_KEY, settings.showTomorrow);
    await pref.put(AppConstants.SETTING_SHOW_EXAM_KEY, settings.showExamCountdown);
    await pref.put(AppConstants.SETTING_EXAM_REMIND_MINUTES_KEY, settings.examRemindMinutes);
    await pref.put(AppConstants.SETTING_COURSE_REMIND_MINUTES_KEY, settings.courseRemindMinutes);
    await pref.flush();
  }

  static async loadSettings(context: Object): Promise<DisplaySettings> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    return {
      showToday: (await pref.get(AppConstants.SETTING_SHOW_TODAY_KEY, true)) as boolean,
      showTomorrow: (await pref.get(AppConstants.SETTING_SHOW_TOMORROW_KEY, true)) as boolean,
      showExamCountdown: (await pref.get(AppConstants.SETTING_SHOW_EXAM_KEY, true)) as boolean,
      examRemindMinutes: (await pref.get(AppConstants.SETTING_EXAM_REMIND_MINUTES_KEY, 30)) as number,
      courseRemindMinutes: (await pref.get(AppConstants.SETTING_COURSE_REMIND_MINUTES_KEY, 30)) as number,
    };
  }

  static async saveRecentLinks(context: Object, links: RecentLinkItem[]): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.RECENT_LINKS_KEY, JSON.stringify(links));
    await pref.flush();
  }

  static async loadRecentLinks(context: Object): Promise<RecentLinkItem[]> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const text: string = (await pref.get(AppConstants.RECENT_LINKS_KEY, '[]')) as string;
    try {
      return JSON.parse(text) as RecentLinkItem[];
    } catch (error) {
      return [];
    }
  }

  static async getAgentBackendUrl(context: Object): Promise<string> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    const url: string = (await pref.get(AppConstants.SETTING_AGENT_BACKEND_URL_KEY, AppConstants.AI_AGENT_URL)) as string;
    return url && url.length > 0 ? url : AppConstants.AI_AGENT_URL;
  }

  static async saveAgentBackendUrl(context: Object, url: string): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
    await pref.put(AppConstants.SETTING_AGENT_BACKEND_URL_KEY, url);
    await pref.flush();
  }
}
