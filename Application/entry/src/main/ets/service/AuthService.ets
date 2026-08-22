import { preferences } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';
import auth from '@hw-agconnect/auth';
import { ContextUtils } from '../common/utils/ContextUtils';
import { AppConstants } from '../common/constants/AppConstants';
import { courseTableModel } from '../model/classTableModel/CourseModel';
import { ChatSessionRepository } from '../repository/ChatSessionRepository';
import { ScheduleRepository } from '../repository/ScheduleRepository';
import { CourseRepository } from '../repository/CourseRepository';
import { CalendarKitReminderService } from './CalendarKitReminderService';

export interface LoginSession {
  email: string;
  loginAt: number;
}

export class AuthService {
  private static sdkInitialized: boolean = false;

  /**
   * 延迟初始化 AGC Auth SDK（仅在用户同意隐私政策后调用）
   */
  static initSDK(context: Object): boolean {
    if (AuthService.sdkInitialized) {
      return true;
    }
    try {
      const abilityContext = ContextUtils.getAbilityContext(context);
      const file = abilityContext.resourceManager.getRawFileContentSync('agconnect-services.json');
      const jsonConfig: string = buffer.from(file.buffer).toString();
      auth.init(abilityContext, jsonConfig);
      AuthService.sdkInitialized = true;
      console.info('[AuthService] AGC Auth SDK 初始化成功');
      return true;
    } catch (err) {
      console.error('[AuthService] AGC Auth SDK 初始化失败:', JSON.stringify(err));
      return false;
    }
  }

  static isSDKInitialized(): boolean {
    return AuthService.sdkInitialized;
  }

  static async getLoginUserId(context: Object): Promise<string | undefined> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.LOGIN_PREF_NAME);
    const text = (await pref.get(AppConstants.LOGIN_SESSION_KEY, '')) as string;
    if (!text) {
      return undefined;
    }
    const session = JSON.parse(text) as LoginSession;
    if (!session.email) {
      return undefined;
    }
    return session.email;
  }

  static async getLoginSession(context: Object): Promise<LoginSession | undefined> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.LOGIN_PREF_NAME);
    const text = (await pref.get(AppConstants.LOGIN_SESSION_KEY, '')) as string;
    if (!text) {
      return undefined;
    }
    const session = JSON.parse(text) as LoginSession;
    if (!session.email) {
      return undefined;
    }
    return session;
  }

  static async isLoggedIn(context: Object): Promise<boolean> {
    const userId = await AuthService.getLoginUserId(context);
    return !!userId;
  }

  static async saveSession(context: Object, email: string): Promise<void> {
    const session: LoginSession = {
      email: email,
      loginAt: Date.now()
    };
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.LOGIN_PREF_NAME);
    await pref.put(AppConstants.LOGIN_SESSION_KEY, JSON.stringify(session));
    await pref.flush();
  }

  static async clearSession(context: Object): Promise<void> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.LOGIN_PREF_NAME);
    await pref.delete(AppConstants.LOGIN_SESSION_KEY);
    await pref.flush();
    if (AuthService.sdkInitialized) {
      try {
        await auth.signOut();
      } catch (e) {
        console.warn('[AuthService] signOut error:', JSON.stringify(e));
      }
    }
  }

  static async logout(context: Object): Promise<void> {
    await AuthService.clearSession(context);
  }

  /**
   * 账号注销：清除云端账号并彻底清空本地所有持久化数据库与内存缓存
   */
  static async deleteAccount(context: Object): Promise<boolean> {
    const abilityContext = ContextUtils.getAbilityContext(context);
    try {
      // 1. 登出云端账号
      if (AuthService.sdkInitialized) {
        try {
          await auth.signOut();
        } catch (e) {
          console.warn('[AuthService] AGC signOut error:', JSON.stringify(e));
        }
      }

      // 2. 清空 AI 对话记录
      try {
        ChatSessionRepository.clearAllSessions(abilityContext);
      } catch (e) {
        console.warn('[AuthService] clearAllSessions error:', JSON.stringify(e));
      }

      // 3. 清空日程记录
      try {
        await ScheduleRepository.clearSchedules(abilityContext);
      } catch (e) {
        console.warn('[AuthService] clearSchedules error:', JSON.stringify(e));
      }

      // 4. 清空多学期课表数据
      try {
        await CourseRepository.clearAllCourseData(abilityContext);
      } catch (e) {
        console.warn('[AuthService] clearAllCourseData error:', JSON.stringify(e));
      }

      // 5. 清空系统日历事件
      try {
        await CalendarKitReminderService.clearAllEvents(abilityContext);
      } catch (e) {
        console.warn('[AuthService] clearAllEvents error:', JSON.stringify(e));
      }

      // 6. 深度清空核心数据库 Preferences（先清空内存键再持久化删除并清理运行时缓存）
      try {
        const coursePref = await preferences.getPreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
        await coursePref.clear();
        await coursePref.flush();
        await preferences.deletePreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
        try {
          preferences.removePreferencesFromCache(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
        } catch (_e) {}
      } catch (e) {
        console.warn('[AuthService] delete course table pref error:', JSON.stringify(e));
      }

      // 7. 清理登录凭证
      try {
        const loginPref = await preferences.getPreferences(abilityContext, AppConstants.LOGIN_PREF_NAME);
        await loginPref.clear();
        await loginPref.flush();
        await preferences.deletePreferences(abilityContext, AppConstants.LOGIN_PREF_NAME);
        try {
          preferences.removePreferencesFromCache(abilityContext, AppConstants.LOGIN_PREF_NAME);
        } catch (_e) {}
      } catch (e) {
        console.warn('[AuthService] delete login pref error:', JSON.stringify(e));
      }

      // 8. 清理其他可能存在的历史数据库
      const legacyDbs = ['chat_sessions_db', 'chat_messages_db', 'schedule_db', 'exam_db'];
      for (let i = 0; i < legacyDbs.length; i++) {
        try {
          const p = await preferences.getPreferences(abilityContext, legacyDbs[i]);
          await p.clear();
          await p.flush();
          await preferences.deletePreferences(abilityContext, legacyDbs[i]);
          try {
            preferences.removePreferencesFromCache(abilityContext, legacyDbs[i]);
          } catch (_e) {}
        } catch (_e) {}
      }

      // 9. 重置内存运行时数据与全局状态
      courseTableModel.clear();
      AppStorage.delete('pendingCourseData');
      AppStorage.delete('pendingCourseSemesterId');
      AppStorage.setOrCreate('account_wipe_timestamp', Date.now());

      console.info('[AuthService] deleteAccount success, all local user data wiped.');
      return true;
    } catch (e) {
      console.error('[AuthService] deleteAccount critical error:', JSON.stringify(e));
      return false;
    }
  }
}
