import { PreferencesUtil, PrefKeys } from './PreferencesUtil';

export enum BlurIntensity {
  CUSTOM = -1,
  THIN = 0,
  REGULAR = 1,
  THICK = 2,
  ULTRA_THICK = 3
}

export enum MaterialStyle {
  STANDARD = 0,
  FROSTED_GLASS = 1,
  MATTE = 2,
  CRYSTAL = 3,
  MIST = 4
}

export enum BorderStyle {
  NONE = 0,
  THIN = 1,
  STANDARD = 2,
  GLOW = 3
}

export class BlurIntensityNames {
  static readonly CUSTOM: string = '自定义';
  static readonly THIN: string = '轻薄';
  static readonly REGULAR: string = '普通';
  static readonly THICK: string = '厚重';
  static readonly ULTRA_THICK: string = '超厚';

  static getName(intensity: BlurIntensity): string {
    switch (intensity) {
      case BlurIntensity.CUSTOM:
        return BlurIntensityNames.CUSTOM;
      case BlurIntensity.THIN:
        return BlurIntensityNames.THIN;
      case BlurIntensity.REGULAR:
        return BlurIntensityNames.REGULAR;
      case BlurIntensity.THICK:
        return BlurIntensityNames.THICK;
      case BlurIntensity.ULTRA_THICK:
        return BlurIntensityNames.ULTRA_THICK;
      default:
        return BlurIntensityNames.REGULAR;
    }
  }
}

export class MaterialStyleNames {
  static readonly STANDARD: string = '标准';
  static readonly FROSTED_GLASS: string = '毛玻璃';
  static readonly MATTE: string = '磨砂';
  static readonly CRYSTAL: string = '晶莹';
  static readonly MIST: string = '雾化';

  static getName(style: MaterialStyle): string {
    switch (style) {
      case MaterialStyle.STANDARD:
        return MaterialStyleNames.STANDARD;
      case MaterialStyle.FROSTED_GLASS:
        return MaterialStyleNames.FROSTED_GLASS;
      case MaterialStyle.MATTE:
        return MaterialStyleNames.MATTE;
      case MaterialStyle.CRYSTAL:
        return MaterialStyleNames.CRYSTAL;
      case MaterialStyle.MIST:
        return MaterialStyleNames.MIST;
      default:
        return MaterialStyleNames.STANDARD;
    }
  }
}

export class BorderStyleNames {
  static readonly NONE: string = '无边框';
  static readonly THIN: string = '细线';
  static readonly STANDARD: string = '标准';
  static readonly GLOW: string = '发光';

  static getName(style: BorderStyle): string {
    switch (style) {
      case BorderStyle.NONE:
        return BorderStyleNames.NONE;
      case BorderStyle.THIN:
        return BorderStyleNames.THIN;
      case BorderStyle.STANDARD:
        return BorderStyleNames.STANDARD;
      case BorderStyle.GLOW:
        return BorderStyleNames.GLOW;
      default:
        return BorderStyleNames.NONE;
    }
  }
}

export class MaterialEffects {
  private static instance: MaterialEffects;

  private _advancedBlurEnabled: boolean = true;

  private _blurIntensity: BlurIntensity = BlurIntensity.REGULAR;

  private _materialStyle: MaterialStyle = MaterialStyle.STANDARD;

  private _borderStyle: BorderStyle = BorderStyle.NONE;

  private _customBlurRadius: number = 20;

  private _saturation: number = 1.0;

  private _brightness: number = 1.0;

  private _backgroundOpacity: number = 0.8;

  private _borderWidth: number = 0.5;

  private _borderOpacity: number = 0.2;

  private _shadowIntensity: number = 10;

  private listeners: (() => void)[] = [];

  private constructor() {
    this.loadSettings();
  }

  static getInstance(): MaterialEffects {
    if (!MaterialEffects.instance) {
      MaterialEffects.instance = new MaterialEffects();
    }
    return MaterialEffects.instance;
  }

  private loadSettings(): void {
    const util = PreferencesUtil.getInstance();
    this._advancedBlurEnabled = util.getBoolean(PrefKeys.ADVANCED_BLUR_ENABLED, true);
    this._blurIntensity = util.getNumber(PrefKeys.BLUR_INTENSITY, BlurIntensity.REGULAR) as BlurIntensity;
    this._materialStyle = util.getNumber(PrefKeys.MATERIAL_STYLE, MaterialStyle.STANDARD) as MaterialStyle;
    this._borderStyle = util.getNumber(PrefKeys.BORDER_STYLE, BorderStyle.NONE) as BorderStyle;
    this._customBlurRadius = util.getNumber(PrefKeys.CUSTOM_BLUR_RADIUS, 20);
    this._saturation = util.getNumber(PrefKeys.MATERIAL_SATURATION, 1.0);
    this._brightness = util.getNumber(PrefKeys.MATERIAL_BRIGHTNESS, 1.0);
    this._backgroundOpacity = util.getNumber(PrefKeys.MATERIAL_BG_OPACITY, 0.8);
    this._borderWidth = util.getNumber(PrefKeys.MATERIAL_BORDER_WIDTH, 0.5);
    this._borderOpacity = util.getNumber(PrefKeys.MATERIAL_BORDER_OPACITY, 0.2);
    this._shadowIntensity = util.getNumber(PrefKeys.MATERIAL_SHADOW_INTENSITY, 10);
  }

  private saveSettings(): void {
    const util = PreferencesUtil.getInstance();
    util.putBoolean(PrefKeys.ADVANCED_BLUR_ENABLED, this._advancedBlurEnabled);
    util.putNumber(PrefKeys.BLUR_INTENSITY, this._blurIntensity);
    util.putNumber(PrefKeys.MATERIAL_STYLE, this._materialStyle);
    util.putNumber(PrefKeys.BORDER_STYLE, this._borderStyle);
    util.putNumber(PrefKeys.CUSTOM_BLUR_RADIUS, this._customBlurRadius);
    util.putNumber(PrefKeys.MATERIAL_SATURATION, this._saturation);
    util.putNumber(PrefKeys.MATERIAL_BRIGHTNESS, this._brightness);
    util.putNumber(PrefKeys.MATERIAL_BG_OPACITY, this._backgroundOpacity);
    util.putNumber(PrefKeys.MATERIAL_BORDER_WIDTH, this._borderWidth);
    util.putNumber(PrefKeys.MATERIAL_BORDER_OPACITY, this._borderOpacity);
    util.putNumber(PrefKeys.MATERIAL_SHADOW_INTENSITY, this._shadowIntensity);
    this.notifyChange();
  }

  private notifyChange(): void {
    console.log(`[MaterialEffects] 通知 ${this.listeners.length} 个监听器`);
    this.listeners.forEach((listener: () => void) => {
      listener();
    });
  }

  addListener(listener: () => void): void {
    this.listeners.push(listener);
  }

  removeListener(listener: () => void): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  get advancedBlurEnabled(): boolean {
    return this._advancedBlurEnabled;
  }

  set advancedBlurEnabled(value: boolean) {
    if (this._advancedBlurEnabled !== value) {
      this._advancedBlurEnabled = value;
      this.saveSettings();
    }
  }

  get blurIntensity(): BlurIntensity {
    return this._blurIntensity;
  }

  set blurIntensity(value: BlurIntensity) {
    if (this._blurIntensity !== value) {
      this._blurIntensity = value;
      this.saveSettings();
    }
  }

  get materialStyle(): MaterialStyle {
    return this._materialStyle;
  }

  set materialStyle(value: MaterialStyle) {
    if (this._materialStyle !== value) {
      console.log(`[MaterialEffects] 材质样式改变: ${this._materialStyle} -> ${value}`);
      this._materialStyle = value;
      this.saveSettings();
    }
  }

  get borderStyle(): BorderStyle {
    return this._borderStyle;
  }

  set borderStyle(value: BorderStyle) {
    if (this._borderStyle !== value) {
      this._borderStyle = value;
      this.saveSettings();
    }
  }

  get customBlurRadius(): number {
    return this._customBlurRadius;
  }

  set customBlurRadius(value: number) {
    if (this._customBlurRadius !== value) {
      this._customBlurRadius = value;
      this.saveSettings();
    }
  }

  get saturation(): number {
    return this._saturation;
  }

  set saturation(value: number) {
    if (this._saturation !== value) {
      this._saturation = value;
      this.saveSettings();
    }
  }

  get brightness(): number {
    return this._brightness;
  }

  set brightness(value: number) {
    if (this._brightness !== value) {
      this._brightness = value;
      this.saveSettings();
    }
  }

  get backgroundOpacity(): number {
    return this._backgroundOpacity;
  }

  set backgroundOpacity(value: number) {
    if (this._backgroundOpacity !== value) {
      this._backgroundOpacity = value;
      this.saveSettings();
    }
  }

  get borderWidth(): number {
    return this._borderWidth;
  }

  set borderWidth(value: number) {
    if (this._borderWidth !== value) {
      this._borderWidth = value;
      this.saveSettings();
    }
  }

  get borderOpacity(): number {
    return this._borderOpacity;
  }

  set borderOpacity(value: number) {
    if (this._borderOpacity !== value) {
      this._borderOpacity = value;
      this.saveSettings();
    }
  }

  get shadowIntensity(): number {
    return this._shadowIntensity;
  }

  set shadowIntensity(value: number) {
    if (this._shadowIntensity !== value) {
      this._shadowIntensity = value;
      this.saveSettings();
    }
  }

  getBlurRadius(): number {
    if (this._blurIntensity === BlurIntensity.CUSTOM) {
      return this._customBlurRadius;
    }

    switch (this._blurIntensity) {
      case BlurIntensity.THIN:
        return 10;
      case BlurIntensity.REGULAR:
        return 20;
      case BlurIntensity.THICK:
        return 35;
      case BlurIntensity.ULTRA_THICK:
        return 50;
      default:
        return 20;
    }
  }

  getStyleAdjustedParams(): MaterialParams {
    const baseRadius = this.getBlurRadius();

    switch (this._materialStyle) {
      case MaterialStyle.FROSTED_GLASS:
        return {
          radius: baseRadius * 1.3,
          saturation: this._saturation * 1.2,
          brightness: this._brightness * 0.95,
          opacity: this._backgroundOpacity * 0.7,
          borderOpacity: this._borderOpacity * 1.5
        };
      case MaterialStyle.MATTE:
        return {
          radius: baseRadius * 0.8,
          saturation: this._saturation * 0.8,
          brightness: this._brightness * 1.05,
          opacity: this._backgroundOpacity * 0.9,
          borderOpacity: this._borderOpacity * 0.8
        };
      case MaterialStyle.CRYSTAL:
        return {
          radius: baseRadius * 1.1,
          saturation: this._saturation * 1.1,
          brightness: this._brightness * 1.15,
          opacity: this._backgroundOpacity * 0.5,
          borderOpacity: this._borderOpacity * 0.6
        };
      case MaterialStyle.MIST:
        return {
          radius: baseRadius * 1.5,
          saturation: this._saturation * 0.7,
          brightness: this._brightness * 1.0,
          opacity: this._backgroundOpacity * 0.6,
          borderOpacity: this._borderOpacity * 0.4
        };
      default:
        return {
          radius: baseRadius,
          saturation: this._saturation,
          brightness: this._brightness,
          opacity: this._backgroundOpacity,
          borderOpacity: this._borderOpacity
        };
    }
  }

  getBorderWidth(): number {
    switch (this._borderStyle) {
      case BorderStyle.NONE:
        return 0;
      case BorderStyle.THIN:
        return 0.5;
      case BorderStyle.STANDARD:
        return 1;
      case BorderStyle.GLOW:
        return 2;
      default:
        return 0;
    }
  }

  isGlowBorder(): boolean {
    return this._borderStyle === BorderStyle.GLOW;
  }

  resetToDefaults(): void {
    this._advancedBlurEnabled = true;
    this._blurIntensity = BlurIntensity.REGULAR;
    this._materialStyle = MaterialStyle.STANDARD;
    this._borderStyle = BorderStyle.NONE;
    this._customBlurRadius = 20;
    this._saturation = 1.0;
    this._brightness = 1.0;
    this._backgroundOpacity = 0.8;
    this._borderWidth = 0.5;
    this._borderOpacity = 0.2;
    this._shadowIntensity = 10;
    this.saveSettings();
  }
}

export interface MaterialParams {
  radius: number;
  saturation: number;
  brightness: number;
  opacity: number;
  borderOpacity: number;
}
