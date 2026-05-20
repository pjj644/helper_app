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
      console.error(`[PreferencesUtil] 初始化失败: ${JSON.stringify(error)}`);
    }
  }

  putString(key: string, value: string): void {
    if (!this.preferences) {
      console.error('[PreferencesUtil] preferences 未初始化');
      return;
    }
    try {
      this.preferences.putSync(key, value);
      this.preferences.flushSync();
    } catch (error) {
      console.error(`[PreferencesUtil] 保存字符串失败: ${JSON.stringify(error)}`);
    }
  }

  getString(key: string, defaultValue: string = ''): string {
    if (!this.preferences) {
      console.error('[PreferencesUtil] preferences 未初始化');
      return defaultValue;
    }
    try {
      return this.preferences.getSync(key, defaultValue) as string;
    } catch (error) {
      console.error(`[PreferencesUtil] 获取字符串失败: ${JSON.stringify(error)}`);
      return defaultValue;
    }
  }

  putBoolean(key: string, value: boolean): void {
    if (!this.preferences) {
      console.error('[PreferencesUtil] preferences 未初始化');
      return;
    }
    try {
      this.preferences.putSync(key, value);
      this.preferences.flushSync();
    } catch (error) {
      console.error(`[PreferencesUtil] 保存布尔值失败: ${JSON.stringify(error)}`);
    }
  }

  getBoolean(key: string, defaultValue: boolean = false): boolean {
    if (!this.preferences) {
      console.error('[PreferencesUtil] preferences 未初始化');
      return defaultValue;
    }
    try {
      return this.preferences.getSync(key, defaultValue) as boolean;
    } catch (error) {
      console.error(`[PreferencesUtil] 获取布尔值失败: ${JSON.stringify(error)}`);
      return defaultValue;
    }
  }

  delete(key: string): void {
    if (!this.preferences) {
      console.error('[PreferencesUtil] preferences 未初始化');
      return;
    }
    try {
      this.preferences.deleteSync(key);
      this.preferences.flushSync();
    } catch (error) {
      console.error(`[PreferencesUtil] 删除键失败: ${JSON.stringify(error)}`);
    }
  }

  putNumber(key: string, value: number): void {
    if (!this.preferences) {
      console.error('[PreferencesUtil] preferences 未初始化');
      return;
    }
    try {
      this.preferences.putSync(key, value);
      this.preferences.flushSync();
    } catch (error) {
      console.error(`[PreferencesUtil] 保存数字失败: ${JSON.stringify(error)}`);
    }
  }

  getNumber(key: string, defaultValue: number = 0): number {
    if (!this.preferences) {
      console.error('[PreferencesUtil] preferences 未初始化');
      return defaultValue;
    }
    try {
      return this.preferences.getSync(key, defaultValue) as number;
    } catch (error) {
      console.error(`[PreferencesUtil] 获取数字失败: ${JSON.stringify(error)}`);
      return defaultValue;
    }
  }
}
