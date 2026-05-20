import { hdsMaterial } from '@kit.UIDesignKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { FeatureDetector } from './FeatureDetector';
import { DarkModeType } from './DarkModeType';
import { PreferencesUtil, PrefKeys } from './PreferencesUtil';

export class UISettings {
  private static instance: UISettings;

  private _immersiveEnabled: boolean = true;

  private _materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;

  private _darkModeType: DarkModeType = DarkModeType.FOLLOW_SYSTEM;

  private _isDarkMode: boolean = false;

  private darkModeListeners: ((isDark: boolean) => void)[] = [];
  private darkModeTypeListeners: ((type: DarkModeType) => void)[] = [];
  private immersiveEnabledListeners: ((enabled: boolean) => void)[] = [];

  private featureDetector: FeatureDetector = FeatureDetector.getInstance();

  private _isImmersiveSupported: boolean = false;

  private context: common.UIAbilityContext | null = null;

  private _customBackgroundImage: string = '';

  private _customBackgroundEnabled: boolean = false;

  private customBackgroundListeners: ((imagePath: string) => void)[] = [];
  private customBackgroundEnabledListeners: ((enabled: boolean) => void)[] = [];

  private constructor() {
    this._isImmersiveSupported = this.featureDetector.isImmersiveMaterialSupported();
  }

  static getInstance(): UISettings {
    if (!UISettings.instance) {
      UISettings.instance = new UISettings();
    }
    return UISettings.instance;
  }

  get immersiveEnabled(): boolean {
    return this._immersiveEnabled;
  }

  set immersiveEnabled(value: boolean) {
    if (this._immersiveEnabled !== value) {
      this._immersiveEnabled = value;
      PreferencesUtil.getInstance().putBoolean(PrefKeys.IMMERSIVE_ENABLED, value);
      this.notifyImmersiveEnabledChange(value);
    }
  }

  get isImmersiveSupported(): boolean {
    return this._isImmersiveSupported;
  }

  get materialLevel(): hdsMaterial.MaterialLevel {
    return this._materialLevel;
  }

  set materialLevel(value: hdsMaterial.MaterialLevel) {
    this._materialLevel = value;
  }

  get darkModeType(): DarkModeType {
    return this._darkModeType;
  }

  set darkModeType(value: DarkModeType) {
    if (this._darkModeType !== value) {
      this._darkModeType = value;
      PreferencesUtil.getInstance().putString(PrefKeys.DARK_MODE_TYPE, value as string);
      this.updateActualDarkMode();
      this.notifyDarkModeTypeChange(value);
    }
  }

  get darkMode(): boolean {
    return this._isDarkMode;
  }

  addDarkModeListener(listener: (isDark: boolean) => void): void {
    this.darkModeListeners.push(listener);
  }

  removeDarkModeListener(listener: (isDark: boolean) => void): void {
    const index = this.darkModeListeners.indexOf(listener);
    if (index >= 0) {
      this.darkModeListeners.splice(index, 1);
    }
  }

  addDarkModeTypeListener(listener: (type: DarkModeType) => void): void {
    this.darkModeTypeListeners.push(listener);
  }

  removeDarkModeTypeListener(listener: (type: DarkModeType) => void): void {
    const index = this.darkModeTypeListeners.indexOf(listener);
    if (index >= 0) {
      this.darkModeTypeListeners.splice(index, 1);
    }
  }

  addImmersiveEnabledListener(listener: (enabled: boolean) => void): void {
    this.immersiveEnabledListeners.push(listener);
  }

  removeImmersiveEnabledListener(listener: (enabled: boolean) => void): void {
    const index = this.immersiveEnabledListeners.indexOf(listener);
    if (index >= 0) {
      this.immersiveEnabledListeners.splice(index, 1);
    }
  }

  private notifyDarkModeChange(isDark: boolean): void {
    this.darkModeListeners.forEach(listener => {
      listener(isDark);
    });
  }

  private notifyDarkModeTypeChange(type: DarkModeType): void {
    this.darkModeTypeListeners.forEach(listener => {
      listener(type);
    });
  }

  private notifyImmersiveEnabledChange(enabled: boolean): void {
    this.immersiveEnabledListeners.forEach(listener => {
      listener(enabled);
    });
  }

  get customBackgroundImage(): string {
    return this._customBackgroundImage;
  }

  set customBackgroundImage(value: string) {
    if (this._customBackgroundImage !== value) {
      this._customBackgroundImage = value;
      PreferencesUtil.getInstance().putString(PrefKeys.CUSTOM_BACKGROUND_IMAGE, value);
      this.notifyCustomBackgroundChange(value);
    }
  }

  get customBackgroundEnabled(): boolean {
    return this._customBackgroundEnabled;
  }

  set customBackgroundEnabled(value: boolean) {
    if (this._customBackgroundEnabled !== value) {
      this._customBackgroundEnabled = value;
      PreferencesUtil.getInstance().putBoolean(PrefKeys.CUSTOM_BACKGROUND_ENABLED, value);
      this.notifyCustomBackgroundEnabledChange(value);
    }
  }

  addCustomBackgroundListener(listener: (imagePath: string) => void): void {
    this.customBackgroundListeners.push(listener);
  }

  removeCustomBackgroundListener(listener: (imagePath: string) => void): void {
    const index = this.customBackgroundListeners.indexOf(listener);
    if (index > -1) {
      this.customBackgroundListeners.splice(index, 1);
    }
  }

  addCustomBackgroundEnabledListener(listener: (enabled: boolean) => void): void {
    this.customBackgroundEnabledListeners.push(listener);
  }

  removeCustomBackgroundEnabledListener(listener: (enabled: boolean) => void): void {
    const index = this.customBackgroundEnabledListeners.indexOf(listener);
    if (index > -1) {
      this.customBackgroundEnabledListeners.splice(index, 1);
    }
  }

  private notifyCustomBackgroundChange(imagePath: string): void {
    this.customBackgroundListeners.forEach(listener => {
      listener(imagePath);
    });
  }

  private notifyCustomBackgroundEnabledChange(enabled: boolean): void {
    this.customBackgroundEnabledListeners.forEach(listener => {
      listener(enabled);
    });
  }

  clearCustomBackground(): void {
    this._customBackgroundImage = '';
    this._customBackgroundEnabled = false;
    PreferencesUtil.getInstance().delete(PrefKeys.CUSTOM_BACKGROUND_IMAGE);
    PreferencesUtil.getInstance().putBoolean(PrefKeys.CUSTOM_BACKGROUND_ENABLED, false);
    this.notifyCustomBackgroundChange('');
    this.notifyCustomBackgroundEnabledChange(false);
  }

  private updateActualDarkMode(): void {
    let newIsDark: boolean;

    switch (this._darkModeType) {
      case DarkModeType.DARK:
        newIsDark = true;
        break;
      case DarkModeType.LIGHT:
        newIsDark = false;
        break;
      case DarkModeType.FOLLOW_SYSTEM:
        newIsDark = this.getSystemDarkMode();
        break;
      default:
        newIsDark = false;
    }

    if (this._isDarkMode !== newIsDark) {
      this._isDarkMode = newIsDark;
      this.notifyDarkModeChange(newIsDark);
    }

    this.applyDarkModeToSystem();
  }

  private getSystemDarkMode(): boolean {
    if (this.context) {
      return this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    return false;
  }

  private applyDarkModeToSystem(): void {
    if (!this.context) {
      return;
    }

    try {
      let colorMode: ConfigurationConstant.ColorMode;

      switch (this._darkModeType) {
        case DarkModeType.DARK:
          colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
          break;
        case DarkModeType.LIGHT:
          colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
          break;
        case DarkModeType.FOLLOW_SYSTEM:
          colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
          break;
        default:
          colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      }

      this.context.getApplicationContext().setColorMode(colorMode);
      console.log(`深色模式已应用: ${this._darkModeType}, 颜色模式: ${colorMode}`);
    } catch (error) {
      console.error(`应用深色模式失败: ${JSON.stringify(error)}`);
    }
  }

  getMaterialType(): hdsMaterial.MaterialType {
    if (!this._immersiveEnabled) {
      return hdsMaterial.MaterialType.NONE;
    }
    if (!this._isImmersiveSupported) {
      return hdsMaterial.MaterialType.NONE;
    }
    return hdsMaterial.MaterialType.IMMERSIVE;
  }

  getMaterialLevel(): hdsMaterial.MaterialLevel {
    if (!this._immersiveEnabled) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    if (!this._isImmersiveSupported) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    return this._materialLevel;
  }

  initDarkMode(context: common.UIAbilityContext): void {
    this.context = context;

    PreferencesUtil.getInstance().init(context);

    this._customBackgroundImage = PreferencesUtil.getInstance().getString(PrefKeys.CUSTOM_BACKGROUND_IMAGE, '');
    this._customBackgroundEnabled = PreferencesUtil.getInstance().getBoolean(PrefKeys.CUSTOM_BACKGROUND_ENABLED, false);

    this._immersiveEnabled = PreferencesUtil.getInstance().getBoolean(PrefKeys.IMMERSIVE_ENABLED, true);

    const savedDarkModeTypeStr = PreferencesUtil.getInstance().getString(PrefKeys.DARK_MODE_TYPE, DarkModeType.FOLLOW_SYSTEM);
    if (savedDarkModeTypeStr === DarkModeType.LIGHT) {
      this._darkModeType = DarkModeType.LIGHT;
    } else if (savedDarkModeTypeStr === DarkModeType.DARK) {
      this._darkModeType = DarkModeType.DARK;
    } else {
      this._darkModeType = DarkModeType.FOLLOW_SYSTEM;
    }

    console.info(`[UISettings] 加载设置: 背景图片=${this._customBackgroundImage}, 背景开关=${this._customBackgroundEnabled}, 沉浸光感=${this._immersiveEnabled}, 深色模式=${this._darkModeType}`);

    this.updateActualDarkMode();
  }
}
