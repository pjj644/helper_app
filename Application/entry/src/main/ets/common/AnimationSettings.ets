import { PreferencesUtil, PrefKeys } from './PreferencesUtil';
import { curves } from '@kit.ArkUI';

export enum AnimationSpeed {
  FAST = 0,
  NORMAL = 1,
  SLOW = 2
}

export enum AnimationCurveType {
  LINEAR = 0,
  SMOOTH = 1,
  BOUNCY = 2,
  SPRING = 3
}

export interface CardEnterParams {
  duration: number;
  curve: ICurve;
}

export class AnimationSettings {
  private static instance: AnimationSettings;

  private _speed: AnimationSpeed = AnimationSpeed.NORMAL;

  private _curve: AnimationCurveType = AnimationCurveType.SMOOTH;

  private _cardEnterEnabled: boolean = true;

  private _pageTransitionEnabled: boolean = true;

  private _listItemAnimationEnabled: boolean = true;

  private _intensity: number = 1.0;

  private listeners: (() => void)[] = [];

  private constructor() {
    this.loadSettings();
  }

  static getInstance(): AnimationSettings {
    if (!AnimationSettings.instance) {
      AnimationSettings.instance = new AnimationSettings();
    }
    return AnimationSettings.instance;
  }

  private loadSettings(): void {
    const util = PreferencesUtil.getInstance();
    this._speed = util.getNumber(PrefKeys.ANIMATION_SPEED, AnimationSpeed.NORMAL) as AnimationSpeed;
    this._curve = util.getNumber(PrefKeys.ANIMATION_CURVE, AnimationCurveType.SMOOTH) as AnimationCurveType;
    this._cardEnterEnabled = util.getBoolean(PrefKeys.ANIMATION_CARD_ENTER, true);
    this._pageTransitionEnabled = util.getBoolean(PrefKeys.ANIMATION_PAGE_TRANSITION, true);
    this._listItemAnimationEnabled = util.getBoolean(PrefKeys.ANIMATION_LIST_ITEM, true);
    this._intensity = util.getNumber(PrefKeys.ANIMATION_INTENSITY, 1.0);
  }

  private saveSettings(): void {
    const util = PreferencesUtil.getInstance();
    util.putNumber(PrefKeys.ANIMATION_SPEED, this._speed);
    util.putNumber(PrefKeys.ANIMATION_CURVE, this._curve);
    util.putBoolean(PrefKeys.ANIMATION_CARD_ENTER, this._cardEnterEnabled);
    util.putBoolean(PrefKeys.ANIMATION_PAGE_TRANSITION, this._pageTransitionEnabled);
    util.putBoolean(PrefKeys.ANIMATION_LIST_ITEM, this._listItemAnimationEnabled);
    util.putNumber(PrefKeys.ANIMATION_INTENSITY, this._intensity);
    this.notifyChange();
  }

  private notifyChange(): void {
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

  get speed(): AnimationSpeed {
    return this._speed;
  }

  set speed(value: AnimationSpeed) {
    if (this._speed !== value) {
      this._speed = value;
      this.saveSettings();
    }
  }

  get curve(): AnimationCurveType {
    return this._curve;
  }

  set curve(value: AnimationCurveType) {
    if (this._curve !== value) {
      this._curve = value;
      this.saveSettings();
    }
  }

  get cardEnterEnabled(): boolean {
    return this._cardEnterEnabled;
  }

  set cardEnterEnabled(value: boolean) {
    if (this._cardEnterEnabled !== value) {
      this._cardEnterEnabled = value;
      this.saveSettings();
    }
  }

  get pageTransitionEnabled(): boolean {
    return this._pageTransitionEnabled;
  }

  set pageTransitionEnabled(value: boolean) {
    if (this._pageTransitionEnabled !== value) {
      this._pageTransitionEnabled = value;
      this.saveSettings();
    }
  }

  get listItemAnimationEnabled(): boolean {
    return this._listItemAnimationEnabled;
  }

  set listItemAnimationEnabled(value: boolean) {
    if (this._listItemAnimationEnabled !== value) {
      this._listItemAnimationEnabled = value;
      this.saveSettings();
    }
  }

  get intensity(): number {
    return this._intensity;
  }

  set intensity(value: number) {
    const clampedValue = Math.max(0.5, Math.min(2.0, value));
    if (this._intensity !== clampedValue) {
      this._intensity = clampedValue;
      this.saveSettings();
    }
  }

  getBaseDuration(): number {
    const baseDuration = 300;
    switch (this._speed) {
      case AnimationSpeed.FAST:
        return baseDuration * 0.6;
      case AnimationSpeed.NORMAL:
        return baseDuration;
      case AnimationSpeed.SLOW:
        return baseDuration * 1.5;
      default:
        return baseDuration;
    }
  }

  getSpringCurve(): ICurve {
    return curves.springCurve(0, 1, 228, 30);
  }

  getSmoothEnterCurve(): ICurve {
    return curves.cubicBezierCurve(0.25, 0.1, 0.25, 1);
  }

  getBouncyExitCurve(): ICurve {
    return curves.cubicBezierCurve(0.55, 0, 1, 0.45);
  }

  getEnterDuration(): number {
    return this.getBaseDuration() * 0.7 * this._intensity;
  }

  getCardEnterParams(): CardEnterParams {
    return {
      duration: this.getEnterDuration(),
      curve: this.getSpringCurve()
    };
  }

  getListItemParams(): CardEnterParams {
    return {
      duration: this.getEnterDuration() * 0.6,
      curve: this.getSmoothEnterCurve()
    };
  }

  getPageTransitionParams(): CardEnterParams {
    return {
      duration: this.getBaseDuration() * 0.5,
      curve: this.getSmoothEnterCurve()
    };
  }
}

export class AnimationCurveNames {
  static readonly LINEAR: string = '线性';
  static readonly SMOOTH: string = '平滑';
  static readonly BOUNCY: string = '弹性';
  static readonly SPRING: string = 'Q弹';

  static getName(type: AnimationCurveType): string {
    switch (type) {
      case AnimationCurveType.LINEAR:
        return AnimationCurveNames.LINEAR;
      case AnimationCurveType.SMOOTH:
        return AnimationCurveNames.SMOOTH;
      case AnimationCurveType.BOUNCY:
        return AnimationCurveNames.BOUNCY;
      case AnimationCurveType.SPRING:
        return AnimationCurveNames.SPRING;
      default:
        return AnimationCurveNames.SMOOTH;
    }
  }
}

export class AnimationSpeedNames {
  static readonly FAST: string = '快速';
  static readonly NORMAL: string = '标准';
  static readonly SLOW: string = '慢速';

  static getName(speed: AnimationSpeed): string {
    switch (speed) {
      case AnimationSpeed.FAST:
        return AnimationSpeedNames.FAST;
      case AnimationSpeed.NORMAL:
        return AnimationSpeedNames.NORMAL;
      case AnimationSpeed.SLOW:
        return AnimationSpeedNames.SLOW;
      default:
        return AnimationSpeedNames.NORMAL;
    }
  }
}
