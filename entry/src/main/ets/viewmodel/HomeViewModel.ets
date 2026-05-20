import { AnnounceItem, TodoItem, MessageInfo, MsgType, ServiceItem, StatData, TabItem, LoadingState } from '../common/types/ModelTypes';
import { HomeModel } from '../model/HomeModel';
import { LogUtils } from '../common/utils/LogUtils';

const TAG = 'HomeViewModel';

@Observed
export class HomeViewModel {
  @Track currentIndex: number = 0;

  @Track selectedMsgType: MsgType = MsgType.All;

  @Track loadingState: LoadingState = LoadingState.Initial;

  private _tabList: TabItem[] = [];

  private _announceList: AnnounceItem[] = [];

  private _todoList: TodoItem[] = [];

  private _messageList: MessageInfo[] = [];

  private _serviceList: ServiceItem[] = [];

  private _statData: StatData[] = [];

  private static instance: HomeViewModel | null = null;

  private constructor() {
    this.loadData();
  }

  static getInstance(): HomeViewModel {
    if (!HomeViewModel.instance) {
      HomeViewModel.instance = new HomeViewModel();
    }
    return HomeViewModel.instance;
  }

  loadData(): void {
    try {
      this.loadingState = LoadingState.Loading;

      this._tabList = HomeModel.getTabList();
      this._announceList = HomeModel.getAnnounceList();
      this._todoList = HomeModel.getTodoList();
      this._messageList = HomeModel.getMessageList();
      this._serviceList = HomeModel.getServiceList();
      this._statData = HomeModel.getStatData();

      this.loadingState = LoadingState.Success;
      LogUtils.info(TAG, '数据加载成功');
    } catch (error) {
      this.loadingState = LoadingState.Error;
      LogUtils.errorObject(TAG, error);
    }
  }

  refresh(): void {
    this.loadData();
  }

  get tabList(): TabItem[] {
    return this._tabList;
  }

  get announceList(): AnnounceItem[] {
    return this._announceList;
  }

  get todoList(): TodoItem[] {
    return this._todoList;
  }

  get messageList(): MessageInfo[] {
    return this._messageList;
  }

  get serviceList(): ServiceItem[] {
    return this._serviceList;
  }

  get statData(): StatData[] {
    return this._statData;
  }

  getFilteredMessages(): MessageInfo[] {
    if (this.selectedMsgType === MsgType.All) {
      return this._messageList;
    }
    return this._messageList.filter((msg: MessageInfo): boolean => msg.type === this.selectedMsgType);
  }

  switchTab(index: number): void {
    if (index >= 0 && index < this._tabList.length) {
      this.currentIndex = index;
      LogUtils.info(TAG, `切换到Tab: ${index}`);
    }
  }

  switchMsgType(type: MsgType): void {
    this.selectedMsgType = type;
    LogUtils.info(TAG, `切换消息类型: ${type}`);
  }

  markMessageAsRead(messageId: number): void {
    const message = this._messageList.find(msg => msg.id === messageId);
    if (message) {
      message.isUnRead = false;
      LogUtils.info(TAG, `消息已标记为已读: ${messageId}`);
    }
  }

  getUnreadCount(): number {
    return this._messageList.filter(msg => msg.isUnRead).length;
  }
}
