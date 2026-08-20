import { window, display, promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants, RouterConstants } from '../constants/AppConstants';

export type FloatingWindowMode = 'BALL' | 'PANEL' | 'HIDDEN';

/**
 * 悬浮球与 Mini 助手子窗口管理器 (FloatingWindowManager)
 * 单例模式，负责管理全局 SubWindow 生命周期、窗口尺寸/坐标、吸附与形态切换
 */
export class FloatingWindowManager {
  private static instance: FloatingWindowManager | null = null;
  private windowStage: window.WindowStage | null = null;
  private subWindow: window.Window | null = null;
  private context: Context | null = null;

  // 状态
  private isEnabled: boolean = true;
  private isAssistantPageActive: boolean = false;
  private currentMode: FloatingWindowMode = 'BALL';

  // 坐标与尺寸 (px)
  private screenWidthPx: number = 1080;
  private screenHeightPx: number = 2340;
  private density: number = 3.0;

  private ballSizeVp: number = 60;
  private ballSizePx: number = 180;
  private ballPosX: number = 850;
  private ballPosY: number = 1400;

  private isCreating: boolean = false;

  private constructor() {}

  public static getInstance(): FloatingWindowManager {
    if (!FloatingWindowManager.instance) {
      FloatingWindowManager.instance = new FloatingWindowManager();
    }
    return FloatingWindowManager.instance;
  }

  /**
   * 在 EntryAbility 中初始化
   */
  public init(windowStage: window.WindowStage, context: Context): void {
    this.windowStage = windowStage;
    this.context = context;

    try {
      const disp = display.getDefaultDisplaySync();
      this.screenWidthPx = disp.width;
      this.screenHeightPx = disp.height;
      this.density = disp.densityPixels || 3.0;
      this.ballSizePx = Math.round(this.ballSizeVp * this.density);

      // 默认停靠在右下侧
      this.ballPosX = this.screenWidthPx - this.ballSizePx - Math.round(16 * this.density);
      this.ballPosY = Math.round(this.screenHeightPx * 0.65);
    } catch (e) {
      console.warn('[FloatingWindowManager] get display error:', JSON.stringify(e));
    }

    this.loadEnabledPreference();

    if (this.isEnabled) {
      this.createSubWindowIfNeeded();
    }
  }

  private loadEnabledPreference(): void {
    if (!this.context) {
      return;
    }
    try {
      const pref = preferences.getPreferencesSync(this.context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      // 默认开启悬浮球
      this.isEnabled = pref.getSync(AppConstants.SETTING_FLOATING_BALL_ENABLED_KEY, true) as boolean;
      AppStorage.setOrCreate('floating_ball_enabled', this.isEnabled);
    } catch (err) {
      this.isEnabled = true;
    }
  }

  public saveEnabledPreference(enabled: boolean): void {
    this.isEnabled = enabled;
    AppStorage.setOrCreate('floating_ball_enabled', enabled);
    if (!this.context) {
      return;
    }
    try {
      const pref = preferences.getPreferencesSync(this.context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SETTING_FLOATING_BALL_ENABLED_KEY, enabled);
      pref.flushSync();
    } catch (err) {
      console.error('[FloatingWindowManager] save preference error:', JSON.stringify(err));
    }
  }

  public getIsEnabled(): boolean {
    return this.isEnabled;
  }

  public getCurrentMode(): FloatingWindowMode {
    return this.currentMode;
  }

  /**
   * 开关控制
   */
  public setEnabled(enabled: boolean): void {
    this.saveEnabledPreference(enabled);
    if (enabled) {
      this.createSubWindowIfNeeded();
      this.show();
    } else {
      this.hide();
    }
  }

  /**
   * 当用户进入全屏 AI 助手页时自动隐藏，离开时自动恢复
   */
  public setAssistantPageActive(isActive: boolean): void {
    this.isAssistantPageActive = isActive;
    if (isActive) {
      // 处于全屏助手界面，避让隐藏
      this.hide();
    } else {
      // 离开全屏助手界面，若开启则恢复
      if (this.isEnabled) {
        this.show();
      }
    }
  }

  /**
   * 创建子窗口
   */
  private createSubWindowIfNeeded(): void {
    if (this.subWindow || this.isCreating || !this.windowStage) {
      return;
    }

    this.isCreating = true;
    this.windowStage.createSubWindow(AppConstants.FLOATING_SUBWINDOW_NAME, (err: BusinessError, win: window.Window) => {
      this.isCreating = false;
      if (err.code) {
        console.error('[FloatingWindowManager] createSubWindow failed:', JSON.stringify(err));
        return;
      }

      this.subWindow = win;

      // 必须先调用 setUIContent，在内容加载完毕后再设置窗口属性与展示
      this.subWindow.setUIContent(RouterConstants.PAGE_FLOATING_SUBWINDOW, (loadErr: BusinessError) => {
        if (loadErr.code) {
          console.error('[FloatingWindowManager] setUIContent failed:', JSON.stringify(loadErr));
          return;
        }

        try {
          this.subWindow?.setWindowBackgroundColor('#00000000');
          this.subWindow?.resize(this.ballSizePx, this.ballSizePx);
          this.subWindow?.moveWindowTo(this.ballPosX, this.ballPosY);

          if (this.isEnabled && !this.isAssistantPageActive) {
            this.subWindow?.showWindow();
            this.currentMode = 'BALL';
            AppStorage.setOrCreate('floating_window_mode', 'BALL');
          }
        } catch (confErr) {
          console.error('[FloatingWindowManager] configure subWindow error:', JSON.stringify(confErr));
        }
      });
    });
  }

  /**
   * 切换到 Mini 助手展开面板模式
   */
  public switchToPanelMode(): void {
    if (!this.subWindow) {
      return;
    }
    try {
      this.currentMode = 'PANEL';
      AppStorage.setOrCreate('floating_window_mode', 'PANEL');

      // 展开为全屏覆盖透明窗口（让 Panel 组件在其内部做半屏或抽屉展示）
      this.subWindow.resize(this.screenWidthPx, this.screenHeightPx);
      this.subWindow.moveWindowTo(0, 0);
    } catch (e) {
      console.error('[FloatingWindowManager] switchToPanelMode error:', JSON.stringify(e));
    }
  }

  /**
   * 切换为悬浮球缩小模式
   */
  public switchToBallMode(): void {
    if (!this.subWindow) {
      return;
    }
    try {
      this.currentMode = 'BALL';
      AppStorage.setOrCreate('floating_window_mode', 'BALL');

      // 缩回球尺寸并移回原位置
      this.subWindow.resize(this.ballSizePx, this.ballSizePx);
      this.subWindow.moveWindowTo(this.ballPosX, this.ballPosY);
    } catch (e) {
      console.error('[FloatingWindowManager] switchToBallMode error:', JSON.stringify(e));
    }
  }

  /**
   * 更新悬浮球拖拽位置（带边缘吸附）
   */
  public updateBallPosition(deltaXPx: number, deltaYPx: number, isEnding: boolean = false): void {
    if (!this.subWindow || this.currentMode !== 'BALL') {
      return;
    }

    let newX = this.ballPosX + deltaXPx;
    let newY = this.ballPosY + deltaYPx;

    const marginPx = Math.round(10 * this.density);
    const topLimitPx = Math.round(80 * this.density);
    const bottomLimitPx = this.screenHeightPx - this.ballSizePx - Math.round(60 * this.density);

    // 边界限制
    newY = Math.max(topLimitPx, Math.min(bottomLimitPx, newY));

    if (isEnding) {
      // 松手时贴靠左右两侧
      const screenMid = this.screenWidthPx / 2;
      if (newX + (this.ballSizePx / 2) < screenMid) {
        newX = marginPx; // 吸附左侧
      } else {
        newX = this.screenWidthPx - this.ballSizePx - marginPx; // 吸附右侧
      }
      this.ballPosX = newX;
      this.ballPosY = newY;
    }

    try {
      this.subWindow.moveWindowTo(newX, newY);
    } catch (e) {
      console.error('[FloatingWindowManager] moveWindowTo error:', JSON.stringify(e));
    }
  }

  public show(): void {
    if (!this.isEnabled || this.isAssistantPageActive) {
      return;
    }
    if (!this.subWindow) {
      this.createSubWindowIfNeeded();
      return;
    }
    try {
      this.subWindow.showWindow();
    } catch (e) {
      console.error('[FloatingWindowManager] showWindow error:', JSON.stringify(e));
    }
  }

  public hide(): void {
    if (!this.subWindow) {
      return;
    }
    try {
      this.subWindow.destroyWindow();
    } catch (e) {
      console.error('[FloatingWindowManager] hide error:', JSON.stringify(e));
    }
    this.subWindow = null;
    this.currentMode = 'BALL';
    AppStorage.setOrCreate('floating_window_mode', 'BALL');
  }

  public destroy(): void {
    if (this.subWindow) {
      try {
        this.subWindow.destroyWindow();
      } catch (e) {
        // ignore
      }
      this.subWindow = null;
    }
  }
}
