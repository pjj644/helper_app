import { window, display, promptAction, router } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants, RouterConstants } from '../constants/AppConstants';
import { UIActionDispatcher } from './UIActionDispatcher';

export type FloatingWindowMode = 'BALL' | 'PANEL' | 'HIDDEN' | 'GUIDANCE';
export type BallExpandState = 'HALF_HIDDEN' | 'EXPANDED';
export type DockSide = 'LEFT' | 'RIGHT';

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
  // 进入 GUIDANCE 引导模式前的窗口模式，退出引导时恢复
  private modeBeforeGuidance: FloatingWindowMode = 'BALL';
  private ballExpandState: BallExpandState = 'HALF_HIDDEN';
  private dockSide: DockSide = 'RIGHT';

  // 坐标与尺寸 (px)
  private screenWidthPx: number = 1080;
  private screenHeightPx: number = 2340;
  private density: number = 3.0;

  private ballSizeVp: number = 60;
  private ballSizePx: number = 180;
  private ballPosX: number = 850;
  private ballPosY: number = 1400;

  // 小窗尺寸与坐标 (px/vp)
  private panelWidthVp: number = 340;
  private panelHeightVp: number = 470;
  private panelWidthPx: number = 1020;
  private panelHeightPx: number = 1410;
  private panelPosX: number = 30;
  private panelPosY: number = 600;

  // 最小尺寸约束 (vp)
  private readonly MIN_PANEL_WIDTH_VP: number = 280;
  private readonly MIN_PANEL_HEIGHT_VP: number = 320;

  // 拖拽小窗手势起始基准坐标 (px)
  private dragStartPanelPosX: number = 0;
  private dragStartPanelPosY: number = 0;

  // 调整小窗尺寸手势起始基准 (px)
  private resizeStartWidthPx: number = 0;
  private resizeStartHeightPx: number = 0;
  private resizeStartPosX: number = 0;
  private resizeStartPosY: number = 0;

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

      // 计算小窗默认尺寸与居中坐标
      const screenWidthVp = this.screenWidthPx / this.density;
      const screenHeightVp = this.screenHeightPx / this.density;
      this.panelWidthVp = Math.min(360, Math.max(280, Math.round(screenWidthVp * 0.90)));
      this.panelHeightVp = Math.min(540, Math.max(400, Math.round(screenHeightVp * 0.52)));

      this.panelWidthPx = Math.round(this.panelWidthVp * this.density);
      this.panelHeightPx = Math.round(this.panelHeightVp * this.density);

      // 默认小窗位置：水平居中，垂直居中偏上（让出底部，避让状态栏）
      this.panelPosX = Math.max(0, Math.round((this.screenWidthPx - this.panelWidthPx) / 2));
      this.panelPosY = Math.max(Math.round(60 * this.density), Math.round((this.screenHeightPx - this.panelHeightPx) * 0.35));

      // 默认停靠在右下侧，初始为半隐藏状态（50% 在屏幕外）
      this.dockSide = 'RIGHT';
      this.ballExpandState = 'HALF_HIDDEN';
      this.ballPosX = this.screenWidthPx - Math.round(this.ballSizePx / 2);
      this.ballPosY = Math.round(this.screenHeightPx * 0.65);
      AppStorage.setOrCreate('floating_ball_dock_side', this.dockSide);
      AppStorage.setOrCreate('floating_ball_expand_state', this.ballExpandState);
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

  public getBallExpandState(): BallExpandState {
    return this.ballExpandState;
  }

  public getDockSide(): DockSide {
    return this.dockSide;
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
            AppStorage.setOrCreate(AppConstants.FLOATING_WINDOW_MODE_KEY, 'BALL');
            AppStorage.setOrCreate('floating_ball_dock_side', this.dockSide);
            AppStorage.setOrCreate('floating_ball_expand_state', this.ballExpandState);
          }
        } catch (confErr) {
          console.error('[FloatingWindowManager] configure subWindow error:', JSON.stringify(confErr));
        }
      });
    });
  }

  /**
   * 切换到 Mini 助手展开小窗模式
   */
  public switchToPanelMode(): void {
    if (!this.subWindow) {
      return;
    }
    try {
      this.currentMode = 'PANEL';
      AppStorage.setOrCreate(AppConstants.FLOATING_WINDOW_MODE_KEY, 'PANEL');

      // 确保小窗处于屏幕安全显示范围内
      this.clampPanelPosition();

      // 调整为小窗独立尺寸与停驻坐标（无全屏遮罩，主窗口可穿透操作）
      this.subWindow.resize(this.panelWidthPx, this.panelHeightPx);
      this.subWindow.moveWindowTo(this.panelPosX, this.panelPosY);
    } catch (e) {
      console.error('[FloatingWindowManager] switchToPanelMode error:', JSON.stringify(e));
    }
  }

  /**
   * 限制小窗坐标在屏幕安全边界内（防滑出屏幕与遮挡顶底状态栏）
   */
  private clampPanelPosition(): void {
    const marginPx = Math.round(8 * this.density);
    const topLimitPx = Math.round(44 * this.density);
    const bottomLimitPx = this.screenHeightPx - this.panelHeightPx - Math.round(36 * this.density);
    const rightLimitPx = this.screenWidthPx - this.panelWidthPx - marginPx;

    const effectiveRight = Math.max(marginPx, rightLimitPx);
    const effectiveBottom = Math.max(topLimitPx, bottomLimitPx);

    this.panelPosX = Math.max(marginPx, Math.min(effectiveRight, this.panelPosX));
    this.panelPosY = Math.max(topLimitPx, Math.min(effectiveBottom, this.panelPosY));
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
      this.ballExpandState = 'EXPANDED';
      AppStorage.setOrCreate(AppConstants.FLOATING_WINDOW_MODE_KEY, 'BALL');
      AppStorage.setOrCreate('floating_ball_expand_state', 'EXPANDED');
      AppStorage.setOrCreate('floating_ball_reset_timer', Date.now());

      const marginPx = Math.round(10 * this.density);
      if (this.dockSide === 'LEFT') {
        this.ballPosX = marginPx;
      } else {
        this.ballPosX = this.screenWidthPx - this.ballSizePx - marginPx;
      }

      // 缩回球尺寸并移回原位置
      this.subWindow.resize(this.ballSizePx, this.ballSizePx);
      this.subWindow.moveWindowTo(this.ballPosX, this.ballPosY);
    } catch (e) {
      console.error('[FloatingWindowManager] switchToBallMode error:', JSON.stringify(e));
    }
  }

  /**
   * 进入引导聚光灯模式：子窗口全屏展示引导层并关闭触摸，
   * 用户可直接点按主窗口中被高亮的目标元素（AI show_guidance 用）
   */
  public switchToGuidanceMode(): void {
    if (!this.subWindow) {
      return;
    }
    try {
      // 重复进入（连续 show_guidance）时保留最初进入前的模式
      if (this.currentMode !== 'GUIDANCE') {
        this.modeBeforeGuidance = this.currentMode;
      }
      this.currentMode = 'GUIDANCE';
      AppStorage.setOrCreate(AppConstants.FLOATING_WINDOW_MODE_KEY, 'GUIDANCE');

      // 展开为全屏覆盖窗口，引导层自行绘制遮罩与挖孔
      this.subWindow.resize(this.screenWidthPx, this.screenHeightPx);
      this.subWindow.moveWindowTo(0, 0);
      // 关闭子窗口触摸，让点击穿透到主窗口（失败仅记日志，引导层 hitTestBehavior 兜底）
      this.subWindow.setWindowTouchable(false).catch((err: BusinessError) => {
        console.error('[FloatingWindowManager] setWindowTouchable(false) error:', JSON.stringify(err));
      });
    } catch (e) {
      console.error('[FloatingWindowManager] switchToGuidanceMode error:', JSON.stringify(e));
    }
  }

  /**
   * 退出引导聚光灯模式：恢复进入前形态并重新开启子窗口触摸
   */
  public exitGuidanceMode(): void {
    // 未处于引导态时直接忽略（含子窗口内容刚挂载收到初始 null 通知的场景）
    if (this.currentMode !== 'GUIDANCE') {
      return;
    }
    if (!this.subWindow) {
      // 窗口已被销毁：仅复位模式状态
      this.currentMode = this.modeBeforeGuidance === 'PANEL' ? 'PANEL' : 'BALL';
      AppStorage.setOrCreate(AppConstants.FLOATING_WINDOW_MODE_KEY, this.currentMode);
      return;
    }
    try {
      if (this.modeBeforeGuidance === 'PANEL') {
        this.switchToPanelMode();
      } else {
        this.switchToBallMode();
      }
      this.subWindow.setWindowTouchable(true).catch((err: BusinessError) => {
        console.error('[FloatingWindowManager] setWindowTouchable(true) error:', JSON.stringify(err));
      });
    } catch (e) {
      console.error('[FloatingWindowManager] exitGuidanceMode error:', JSON.stringify(e));
    }
  }

  /**
   * 将悬浮球从半隐藏滑出至完全显示
   */
  public expandBall(): void {
    if (!this.subWindow || this.currentMode !== 'BALL') {
      return;
    }
    this.ballExpandState = 'EXPANDED';
    AppStorage.setOrCreate('floating_ball_expand_state', 'EXPANDED');
    const marginPx = Math.round(10 * this.density);
    if (this.dockSide === 'LEFT') {
      this.ballPosX = marginPx;
    } else {
      this.ballPosX = this.screenWidthPx - this.ballSizePx - marginPx;
    }
    try {
      this.subWindow.moveWindowTo(this.ballPosX, this.ballPosY);
    } catch (e) {
      console.error('[FloatingWindowManager] expandBall error:', JSON.stringify(e));
    }
  }

  /**
   * 将悬浮球缩回边缘半隐藏（50% 移到屏幕外）
   */
  public dockBall(): void {
    if (!this.subWindow || this.currentMode !== 'BALL') {
      return;
    }
    this.ballExpandState = 'HALF_HIDDEN';
    AppStorage.setOrCreate('floating_ball_expand_state', 'HALF_HIDDEN');
    if (this.dockSide === 'LEFT') {
      this.ballPosX = -Math.round(this.ballSizePx / 2);
    } else {
      this.ballPosX = this.screenWidthPx - Math.round(this.ballSizePx / 2);
    }
    try {
      this.subWindow.moveWindowTo(this.ballPosX, this.ballPosY);
    } catch (e) {
      console.error('[FloatingWindowManager] dockBall error:', JSON.stringify(e));
    }
  }

  /**
   * 关闭面板并直接收缩为贴边半隐藏悬浮球
   */
  public collapseToDockedBall(): void {
    this.switchToBallMode();
    this.dockBall();
  }

  // 拖拽手势起始基准坐标 (px)
  private dragStartBallPosX: number = 0;
  private dragStartBallPosY: number = 0;

  /**
   * 开始拖拽手势：记录当前基准坐标
   */
  public startDrag(): void {
    if (!this.subWindow || this.currentMode !== 'BALL') {
      return;
    }
    this.dragStartBallPosX = this.ballPosX;
    this.dragStartBallPosY = this.ballPosY;
  }

  /**
   * 拖拽手势进行中（无边界限制，1:1 精确跟手）
   * @param offsetXVp PanGesture 的 offsetX (单位: vp)
   * @param offsetYVp PanGesture 的 offsetY (单位: vp)
   */
  public updateDrag(offsetXVp: number, offsetYVp: number): void {
    if (!this.subWindow || this.currentMode !== 'BALL') {
      return;
    }
    const deltaXPx = offsetXVp * this.density;
    const deltaYPx = offsetYVp * this.density;
    const newX = Math.round(this.dragStartBallPosX + deltaXPx);
    const newY = Math.round(this.dragStartBallPosY + deltaYPx);

    try {
      this.subWindow.moveWindowTo(newX, newY);
    } catch (e) {
      console.error('[FloatingWindowManager] updateDrag moveWindowTo error:', JSON.stringify(e));
    }
  }

  /**
   * 拖拽手势结束（松手吸附最近边缘）
   * @param offsetXVp PanGesture 的 offsetX (单位: vp)
   * @param offsetYVp PanGesture 的 offsetY (单位: vp)
   */
  public endDrag(offsetXVp: number, offsetYVp: number): void {
    if (!this.subWindow || this.currentMode !== 'BALL') {
      return;
    }
    const deltaXPx = offsetXVp * this.density;
    const deltaYPx = offsetYVp * this.density;
    const currX = this.dragStartBallPosX + deltaXPx;
    let currY = Math.round(this.dragStartBallPosY + deltaYPx);

    const marginPx = Math.round(10 * this.density);
    const topLimitPx = Math.round(80 * this.density);
    const bottomLimitPx = this.screenHeightPx - this.ballSizePx - Math.round(60 * this.density);

    // 垂直方向限制安全边距（不遮挡状态栏和底部导航栏）
    currY = Math.max(topLimitPx, Math.min(bottomLimitPx, currY));

    // 按松手时球体中心距离屏幕中线的远近，自动吸附到最近边缘
    const ballCenter = currX + (this.ballSizePx / 2);
    const screenMid = this.screenWidthPx / 2;
    if (ballCenter < screenMid) {
      this.dockSide = 'LEFT';
      this.ballPosX = marginPx;
    } else {
      this.dockSide = 'RIGHT';
      this.ballPosX = this.screenWidthPx - this.ballSizePx - marginPx;
    }

    this.ballPosY = currY;
    this.ballExpandState = 'EXPANDED';
    AppStorage.setOrCreate('floating_ball_dock_side', this.dockSide);
    AppStorage.setOrCreate('floating_ball_expand_state', 'EXPANDED');
    AppStorage.setOrCreate('floating_ball_reset_timer', Date.now());

    try {
      this.subWindow.moveWindowTo(this.ballPosX, this.ballPosY);
    } catch (e) {
      console.error('[FloatingWindowManager] endDrag moveWindowTo error:', JSON.stringify(e));
    }
  }

  /**
   * 兼容更新悬浮球拖拽位置
   */
  public updateBallPosition(deltaXPx: number, deltaYPx: number, isEnding: boolean = false): void {
    if (!this.subWindow || this.currentMode !== 'BALL') {
      return;
    }

    if (isEnding) {
      this.endDrag(deltaXPx / this.density, deltaYPx / this.density);
    } else {
      this.updateDrag(deltaXPx / this.density, deltaYPx / this.density);
    }
  }

  // ==================== 小窗平移拖拽与拉伸缩放 API ====================

  /**
   * 开始拖拽小窗整体平移
   */
  public startPanelDrag(): void {
    if (!this.subWindow || this.currentMode !== 'PANEL') {
      return;
    }
    this.dragStartPanelPosX = this.panelPosX;
    this.dragStartPanelPosY = this.panelPosY;
  }

  /**
   * 小窗整体平移拖拽中（1:1 跟手移动物理窗口）
   * @param offsetXVp PanGesture 的 offsetX (单位: vp)
   * @param offsetYVp PanGesture 的 offsetY (单位: vp)
   */
  public updatePanelDrag(offsetXVp: number, offsetYVp: number): void {
    if (!this.subWindow || this.currentMode !== 'PANEL') {
      return;
    }
    const deltaXPx = offsetXVp * this.density;
    const deltaYPx = offsetYVp * this.density;
    const newX = Math.round(this.dragStartPanelPosX + deltaXPx);
    const newY = Math.round(this.dragStartPanelPosY + deltaYPx);

    try {
      this.subWindow.moveWindowTo(newX, newY);
    } catch (e) {
      console.error('[FloatingWindowManager] updatePanelDrag moveWindowTo error:', JSON.stringify(e));
    }
  }

  /**
   * 小窗整体平移拖拽结束（计算最终停驻坐标并应用防溢出保护）
   * @param offsetXVp PanGesture 的 offsetX (单位: vp)
   * @param offsetYVp PanGesture 的 offsetY (单位: vp)
   */
  public endPanelDrag(offsetXVp: number, offsetYVp: number): void {
    if (!this.subWindow || this.currentMode !== 'PANEL') {
      return;
    }
    const deltaXPx = offsetXVp * this.density;
    const deltaYPx = offsetYVp * this.density;
    this.panelPosX = Math.round(this.dragStartPanelPosX + deltaXPx);
    this.panelPosY = Math.round(this.dragStartPanelPosY + deltaYPx);

    this.clampPanelPosition();

    try {
      this.subWindow.moveWindowTo(this.panelPosX, this.panelPosY);
    } catch (e) {
      console.error('[FloatingWindowManager] endPanelDrag moveWindowTo error:', JSON.stringify(e));
    }
  }

  /**
   * 开始调整小窗尺寸手势
   */
  public startPanelResize(): void {
    if (!this.subWindow || this.currentMode !== 'PANEL') {
      return;
    }
    this.resizeStartWidthPx = this.panelWidthPx;
    this.resizeStartHeightPx = this.panelHeightPx;
    this.resizeStartPosX = this.panelPosX;
    this.resizeStartPosY = this.panelPosY;
  }

  /**
   * 调整小窗尺寸中（拖动右下角角标）
   * @param offsetXVp PanGesture 的 offsetX (单位: vp)
   * @param offsetYVp PanGesture 的 offsetY (单位: vp)
   */
  public updatePanelResize(offsetXVp: number, offsetYVp: number): void {
    if (!this.subWindow || this.currentMode !== 'PANEL') {
      return;
    }
    const deltaWPx = offsetXVp * this.density;
    const deltaHPx = offsetYVp * this.density;

    const minWPx = Math.round(this.MIN_PANEL_WIDTH_VP * this.density);
    const minHPx = Math.round(this.MIN_PANEL_HEIGHT_VP * this.density);
    const maxWPx = this.screenWidthPx - Math.round(16 * this.density);
    const maxHPx = this.screenHeightPx - Math.round(90 * this.density);

    const targetW = Math.max(minWPx, Math.min(maxWPx, Math.round(this.resizeStartWidthPx + deltaWPx)));
    const targetH = Math.max(minHPx, Math.min(maxHPx, Math.round(this.resizeStartHeightPx + deltaHPx)));

    // 如果扩展时右边或下边超出屏幕边界，则同步向内推动小窗左/上坐标，保证内容完整展现
    const marginPx = Math.round(8 * this.density);
    const bottomLimitMarginPx = Math.round(36 * this.density);

    let newPosX = this.resizeStartPosX;
    if (newPosX + targetW > this.screenWidthPx - marginPx) {
      newPosX = Math.max(marginPx, this.screenWidthPx - marginPx - targetW);
    }

    let newPosY = this.resizeStartPosY;
    if (newPosY + targetH > this.screenHeightPx - bottomLimitMarginPx) {
      newPosY = Math.max(Math.round(44 * this.density), this.screenHeightPx - bottomLimitMarginPx - targetH);
    }

    this.panelWidthPx = targetW;
    this.panelHeightPx = targetH;
    this.panelWidthVp = targetW / this.density;
    this.panelHeightVp = targetH / this.density;
    this.panelPosX = newPosX;
    this.panelPosY = newPosY;

    try {
      this.subWindow.resize(this.panelWidthPx, this.panelHeightPx);
      this.subWindow.moveWindowTo(this.panelPosX, this.panelPosY);
    } catch (e) {
      console.error('[FloatingWindowManager] updatePanelResize error:', JSON.stringify(e));
    }
  }

  /**
   * 调整小窗尺寸结束
   * @param offsetXVp PanGesture 的 offsetX (单位: vp)
   * @param offsetYVp PanGesture 的 offsetY (单位: vp)
   */
  public endPanelResize(offsetXVp: number, offsetYVp: number): void {
    this.updatePanelResize(offsetXVp, offsetYVp);
  }

  public show(): void {
    if (!this.isEnabled || this.isAssistantPageActive) {
      return;
    }
    if (!this.subWindow) {
      // 重建路径（show / setEnabled(true) 均会走到此分支）：
      // 先清掉残存引导态，避免 8 秒内重建的子窗口内容挂载时通过监听器恢复旧引导
      UIActionDispatcher.getInstance().clearGuidance();
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
    AppStorage.setOrCreate(AppConstants.FLOATING_WINDOW_MODE_KEY, 'BALL');
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

  /**
   * 将主窗口路由导航至指定页面（大屏跳转，确保悬浮窗小屏不受影响）
   * @param url 页面路由（如 RouterConstants.PAGE_TABLE_UI）
   * @param params 附加路由参数
   * @returns 是否成功触发
   */
  public async navigateMainWindow(url: string, params?: Record<string, Object>): Promise<boolean> {
    if (!this.windowStage) {
      console.warn('[FloatingWindowManager] navigateMainWindow: windowStage is not ready');
      return false;
    }
    try {
      const mainWindow = this.windowStage.getMainWindowSync();
      if (!mainWindow) {
        console.warn('[FloatingWindowManager] navigateMainWindow: mainWindow is null');
        return false;
      }
      const mainRouter = mainWindow.getUIContext().getRouter();
      const options: router.RouterOptions = { url: url };
      if (params !== undefined) {
        options.params = params;
      }
      await mainRouter.pushUrl(options);
      console.info(`[FloatingWindowManager] navigateMainWindow to ${url} succeeded`);
      return true;
    } catch (err) {
      console.error(`[FloatingWindowManager] navigateMainWindow error: ${JSON.stringify(err)}`);
      return false;
    }
  }
}
