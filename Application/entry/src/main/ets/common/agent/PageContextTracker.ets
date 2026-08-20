/**
 * 页面动作描述符
 */
export interface PageActionDescriptor {
  actionId: string;
  label: string;
  description: string;
}

/**
 * 页面上下文快照
 */
export interface PageSnapshot {
  pageName: string;
  pageTitle: string;
  summaryText: string;
  dataSnapshot: Record<string, Object>;
  availableActions: PageActionDescriptor[];
  updatedAt: number;
}

/**
 * 全局页面感知中心 (PageContextTracker)
 * 供各页面主动上报当前视图、数据及可操作项，供 AI 助手实时感知当前页面并指导/操作
 */
export class PageContextTracker {
  private static instance: PageContextTracker | null = null;
  private currentSnapshot: PageSnapshot = {
    pageName: 'home',
    pageTitle: '首页',
    summaryText: '应用主页',
    dataSnapshot: {},
    availableActions: [],
    updatedAt: Date.now()
  };

  private listeners: ((snapshot: PageSnapshot) => void)[] = [];

  private constructor() {}

  public static getInstance(): PageContextTracker {
    if (!PageContextTracker.instance) {
      PageContextTracker.instance = new PageContextTracker();
    }
    return PageContextTracker.instance;
  }

  /**
   * 上报/更新当前页面上下文
   */
  public updateSnapshot(
    pageName: string,
    pageTitle: string,
    summaryText: string,
    dataSnapshot: Record<string, Object> = {},
    availableActions: PageActionDescriptor[] = []
  ): void {
    this.currentSnapshot = {
      pageName: pageName,
      pageTitle: pageTitle,
      summaryText: summaryText,
      dataSnapshot: dataSnapshot,
      availableActions: availableActions,
      updatedAt: Date.now()
    };

    // 通知监听者
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i](this.currentSnapshot);
      } catch (err) {
        console.error('[PageContextTracker] notify listener error:', JSON.stringify(err));
      }
    }
  }

  /**
   * 获取当前页面快照
   */
  public getSnapshot(): PageSnapshot {
    return this.currentSnapshot;
  }

  /**
   * 获取格式化的 Prompt 上下文字符串
   */
  public getFormattedPromptContext(): string {
    const s = this.currentSnapshot;
    const actionsStr = s.availableActions.length > 0
      ? s.availableActions.map((a: PageActionDescriptor) => `${a.label} (${a.actionId}: ${a.description})`).join(', ')
      : '无特殊页面动作';

    return JSON.stringify({
      currentPage: s.pageName,
      pageTitle: s.pageTitle,
      summary: s.summaryText,
      data: s.dataSnapshot,
      availableActions: actionsStr
    });
  }

  /**
   * 注册快照变化监听器
   */
  public addListener(listener: (snapshot: PageSnapshot) => void): void {
    this.listeners.push(listener);
  }

  /**
   * 移除监听器
   */
  public removeListener(listener: (snapshot: PageSnapshot) => void): void {
    this.listeners = this.listeners.filter((l) => l !== listener);
  }
}
