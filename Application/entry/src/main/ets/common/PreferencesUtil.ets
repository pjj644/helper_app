import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class PrefKeys {
  static readonly CUSTOM_BACKGROUND_IMAGE: string = 'custom_background_image';
  static readonly CUSTOM_BACKGROUND_ENABLED: string = 'custom_background_enabled';
  static readonly IMMERSIVE_ENABLED: string = 'immersive_enabled';
  static readonly DARK_MODE_TYPE: string = 'dark_mode_type';

  static readonly ANIMATION_SPEED: string = 'animation_speed';
  static readonly ANIMATION_CURVE: string = 'animation_curve';
  static readonly ANIMATION_CARD_ENTER: string = 'animation_card_enter';
  static readonly ANIMATION_PAGE_TRANSITION: string = 'animation_page_transition';
  static readonly ANIMATION_LIST_ITEM: string = 'animation_list_item';
  static readonly ANIMATION_INTENSITY: string = 'animation_intensity';

  static readonly ADVANCED_BLUR_ENABLED: string = 'advanced_blur_enabled';
  static readonly BLUR_INTENSITY: string = 'blur_intensity';
  static readonly MATERIAL_STYLE: string = 'material_style';
  static readonly BORDER_STYLE: string = 'border_style';
  static readonly CUSTOM_BLUR_RADIUS: string = 'custom_blur_radius';
  static readonly MATERIAL_SATURATION: string = 'material_saturation';
  static readonly MATERIAL_BRIGHTNESS: string = 'material_brightness';
  static readonly MATERIAL_BG_OPACITY: string = 'material_bg_opacity';
  static readonly MATERIAL_BORDER_WIDTH: string = 'material_border_width';
  static readonly MATERIAL_BORDER_OPACITY: string = 'material_border_opacity';
  static readonly MATERIAL_SHADOW_INTENSITY: string = 'material_shadow_intensity';
}

export class PreferencesUtil {
  private static instance: PreferencesUtil;
  private preferences: preferences.Preferences | null = null;
  private readonly STORE_NAME: string = 'course_table_local_db';

  private constructor() {}

  static getInstance(): PreferencesUtil {
    if (!PreferencesUtil.instance) {
      PreferencesUtil.instance = new PreferencesUtil();
    }
    return PreferencesUtil.instance;
  }

  init(context: common.UIAbilityContext): void {
    try {
      let options: preferences.Options = { name: this.STORE_NAME };
      this.preferences = preferences.getPreferencesSync(context, options);
      console.info('[PreferencesUtil] 初始化成功');
    } catch (error) {
      this.handleError('初始化失败:', error);
    }
  }

  private ensureInitialized(): boolean {
    if (!this.preferences) {
      console.error('[PreferencesUtil] preferences 未初始化');
      return false;
    }
    return true;
  }

  private handleError(message: string, error: Object): void {
    console.error(`[PreferencesUtil] ${message} ${JSON.stringify(error)}`);
  }

  private putValue(key: string, value: preferences.ValueType): void {
    if (!this.ensureInitialized()) {
      return;
    }
    try {
      this.preferences!.putSync(key, value);
      this.preferences!.flushSync();
    } catch (error) {
      this.handleError(`保存失败 [${key}]:`, error);
    }
  }

  private getValue(key: string, defaultValue: preferences.ValueType): preferences.ValueType {
    if (!this.ensureInitialized()) {
      return defaultValue;
    }
    try {
      return this.preferences!.getSync(key, defaultValue);
    } catch (error) {
      this.handleError(`获取失败 [${key}]:`, error);
      return defaultValue;
    }
  }

  putString(key: string, value: string): void {
    this.putValue(key, value);
  }

  getString(key: string, defaultValue: string = ''): string {
    return this.getValue(key, defaultValue) as string;
  }

  putBoolean(key: string, value: boolean): void {
    this.putValue(key, value);
  }

  getBoolean(key: string, defaultValue: boolean = false): boolean {
    return this.getValue(key, defaultValue) as boolean;
  }

  putNumber(key: string, value: number): void {
    this.putValue(key, value);
  }

  getNumber(key: string, defaultValue: number = 0): number {
    return this.getValue(key, defaultValue) as number;
  }

  hasAgreedPrivacy(): boolean {
    return this.getBoolean('app_privacy_policy_agreed', false);
  }

  setAgreedPrivacy(agreed: boolean): void {
    this.putBoolean('app_privacy_policy_agreed', agreed);
  }

  delete(key: string): void {
    if (!this.ensureInitialized()) {
      return;
    }
    try {
      this.preferences!.deleteSync(key);
      this.preferences!.flushSync();
    } catch (error) {
      this.handleError(`删除失败 [${key}]:`, error);
    }
  }
}
