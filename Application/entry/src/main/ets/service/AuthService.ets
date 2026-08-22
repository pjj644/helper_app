import { preferences } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';
import auth from '@hw-agconnect/auth';
import { ContextUtils } from '../common/utils/ContextUtils';
import { AppConstants } from '../common/constants/AppConstants';
import { courseTableModel } from '../model/classTableModel/CourseModel';

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
    const abilityContext = ContextUtils.getAbilityContext(context);
    const pref = await preferences.getPreferences(abilityContext, AppConstants.LOGIN_PREF_NAME);
    const session: LoginSession = {
      email: email,
      loginAt: Date.now(),
    };
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

      // 2. 清理登录凭证
      try {
        await preferences.deletePreferences(abilityContext, AppConstants.LOGIN_PREF_NAME);
      } catch (e) {
        console.warn('[AuthService] delete login pref error:', JSON.stringify(e));
      }

      // 3. 清理课表、考试、成绩、日程等核心本地数据库
      try {
        await preferences.deletePreferences(abilityContext, AppConstants.COURSE_TABLE_PREF_NAME);
      } catch (e) {
        console.warn('[AuthService] delete course table pref error:', JSON.stringify(e));
      }

      // 4. 清理 AI 对话会话与消息数据库
      try {
        await preferences.deletePreferences(abilityContext, 'chat_sessions_db');
        await preferences.deletePreferences(abilityContext, 'chat_messages_db');
      } catch (e) {
        console.warn('[AuthService] delete chat pref error:', JSON.stringify(e));
      }

      // 5. 重置内存运行时数据
      courseTableModel.clear();

      console.info('[AuthService] deleteAccount success, all local user data wiped.');
      return true;
    } catch (e) {
      console.error('[AuthService] deleteAccount critical error:', JSON.stringify(e));
      return false;
    }
  }
}
