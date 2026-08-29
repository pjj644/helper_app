/**
 * 界面聚光灯/引导状态
 */
export interface GuidanceState {
  targetElementId: string;
  hintText: string;
  durationMs?: number;
}

export type UIActionHandler = (params: Record<string, Object>) => Promise<boolean> | boolean;

/**
 * 界面动作与引导分发器 (UIActionDispatcher)
 * 用于 AI 助手与当前活跃页面之间的 UI 指令通信（如自动切周、高亮按钮、触发导入等）
 */
export class UIActionDispatcher {
  private static instance: UIActionDispatcher | null = null;
  private handlers: Map<string, UIActionHandler[]> = new Map();
  private guidanceListeners: ((state: GuidanceState | null) => void)[] = [];
  private currentGuidance: GuidanceState | null = null;
  private guidanceTimer: number = -1;

  private constructor() {}

  public static getInstance(): UIActionDispatcher {
    if (!UIActionDispatcher.instance) {
      UIActionDispatcher.instance = new UIActionDispatcher();
    }
    return UIActionDispatcher.instance;
  }

  /**
   * 注册页面动作处理器
   * @param action 动作标识，如 'switch_week', 'trigger_import', 'filter_grades', 'scroll_to'
   * @param handler 处理函数
   * @returns 取消注册的清理函数
   */
  public registerHandler(action: string, handler: UIActionHandler): () => void {
    if (!this.handlers.has(action)) {
      this.handlers.set(action, []);
    }
    this.handlers.get(action)?.push(handler);

    return () => {
      const list = this.handlers.get(action);
      if (list) {
        this.handlers.set(action, list.filter((h) => h !== handler));
      }
    };
  }

  /**
   * 分发执行 UI 动作
   */
  public async dispatch(action: string, params: Record<string, Object> = {}): Promise<boolean> {
    console.info(`[UIActionDispatcher] dispatching action: ${action}, params: ${JSON.stringify(params)}`);
    const list = this.handlers.get(action);
    if (!list || list.length === 0) {
      console.warn(`[UIActionDispatcher] no handler registered for action: ${action}`);
      return false;
    }

    let anySuccess = false;
    for (let i = 0; i < list.length; i++) {
      try {
        const result = await list[i](params);
        if (result) {
          anySuccess = true;
        }
      } catch (err) {
        console.error(`[UIActionDispatcher] handler error for ${action}:`, JSON.stringify(err));
      }
    }
    return anySuccess;
  }

  /**
   * 显示/更新 UI 引导聚光灯提示
   */
  public showGuidance(guidance: GuidanceState): void {
    this.currentGuidance = guidance;
    this.notifyGuidanceChange(guidance);

    if (this.guidanceTimer >= 0) {
      clearTimeout(this.guidanceTimer);
      this.guidanceTimer = -1;
    }

    const duration = guidance.durationMs || 5000;
    this.guidanceTimer = setTimeout(() => {
      this.clearGuidance();
    }, duration);
  }

  /**
   * 获取当前引导状态。
   * 供监听器做陈旧通知守卫：clearGuidance 先置空 currentGuidance 再广播，
   * 遍历期间被撤销的 show 通知可用本方法精确识别并忽略，防止重入卡死。
   */
  public getGuidanceState(): GuidanceState | null {
    return this.currentGuidance;
  }

  /**
   * 清除 UI 引导
   */
  public clearGuidance(): void {
    if (this.guidanceTimer >= 0) {
      clearTimeout(this.guidanceTimer);
      this.guidanceTimer = -1;
    }
    this.currentGuidance = null;
    this.notifyGuidanceChange(null);
  }

  /**
   * 监听引导状态变化
   */
  public addGuidanceListener(listener: (state: GuidanceState | null) => void): void {
    this.guidanceListeners.push(listener);
    // 立即通知当前状态
    listener(this.currentGuidance);
  }

  public removeGuidanceListener(listener: (state: GuidanceState | null) => void): void {
    this.guidanceListeners = this.guidanceListeners.filter((l) => l !== listener);
  }

  private notifyGuidanceChange(state: GuidanceState | null): void {
    for (let i = 0; i < this.guidanceListeners.length; i++) {
      try {
        this.guidanceListeners[i](state);
      } catch (err) {
        console.error('[UIActionDispatcher] notifyGuidanceChange error:', JSON.stringify(err));
      }
    }
  }
}
