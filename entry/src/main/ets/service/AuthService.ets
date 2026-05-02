import { preferences } from '@kit.ArkData';
import { ContextUtils } from '../common/utils/ContextUtils';
import { AppConstants } from '../common/constants/AppConstants';

export interface LoginSession {
  email: string;
  loginAt: number;
}

export class AuthService {
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
  }
}
