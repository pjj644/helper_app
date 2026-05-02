import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AuthService } from '../service/AuthService';
import { SyncService } from '../service/SyncService';
import { AppConstants } from '../common/constants/AppConstants';
import { ThemeManager } from '../common/utils/ThemeManager';
import { ReminderService } from '../service/ReminderService';
import { BottomTabBar, TabItem } from '../components/BottomTabBar';

@Entry
@Component
struct HomePortalPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State currentTabIndex: number = 1;
  @State syncingToCloud: boolean = false;
  @State downloadingFromCloud: boolean = false;
  @State isLoggedIn: boolean = false;
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  private tabs: TabItem[] = [
    { label: 'Quick' },
    { label: 'Home' },
    { label: 'Class' },
  ];

  private navToQuick(): void {
    router.pushUrl({ url: 'pages/quick/quickIndex' }, router.RouterMode.Standard)
      .catch((error: Error) => console.error('跳转 quick 页面失败:', error));
  }

  private navToHome(): void {
    router.pushUrl({ url: 'pages/home' }, router.RouterMode.Standard)
      .catch((error: Error) => console.error('跳转 home 页面失败:', error));
  }

  private navToClass(): void {
    router.pushUrl({ url: 'pages/classTablePages/Home' }, router.RouterMode.Standard)
      .catch((error: Error) => console.error('跳转 class 页面失败:', error));
  }

  private onTabChange(index: number): void {
    this.currentTabIndex = index;
    if (index === 0) { this.navToQuick(); }
    if (index === 2) { this.navToClass(); }
  }

  onPageShow(): void {
    this.currentTabIndex = 1;
    this.checkLoginStatus();
  }

  private async checkLoginStatus(): Promise<void> {
    try {
      const userId = await AuthService.getLoginUserId(getContext(this));
      this.isLoggedIn = !!userId;
    } catch (error) {
      this.isLoggedIn = false;
    }
  }

  private login(): void {
    router.pushUrl({ url: 'pages/login/loginIndex' })
      .catch((error: Error) => console.error('跳转 login 页面失败:', error));
  }

  private accountManage(): void {
    router.pushUrl({ url: 'pages/login/AccountManage' })
      .catch((error: Error) => console.error('跳转账号管理失败:', error));
  }

  private async syncLocalDataToCloud(): Promise<void> {
    if (this.syncingToCloud) { return; }
    this.syncingToCloud = true;
    try {
      const userId = await AuthService.getLoginUserId(getContext(this));
      if (!userId) {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录后再同步' });
        return;
      }
      const result = await SyncService.syncAllToCloud(getContext(this), userId);
      if (result.courses.success && result.exams.success) {
        const courseCount = result.courses.courseCount || 0;
        const examCount = result.exams.examCount || 0;
        this.getUIContext().getPromptAction().showToast({
          message: `云端同步完成：课表${courseCount}条，考试${examCount}条`
        });
        ReminderService.refreshAllReminders(getContext(this));
      } else {
        const errorMsg = result.courses.error || result.exams.error || '未知错误';
        this.getUIContext().getPromptAction().showToast({ message: `云端同步失败: ${errorMsg}` });
      }
    } catch (error) {
      console.error('云端同步失败:', error);
      this.getUIContext().getPromptAction().showToast({ message: `云端同步失败: ${String(error)}` });
    } finally {
      this.syncingToCloud = false;
    }
  }

  private async downloadFromCloud(): Promise<void> {
    if (this.downloadingFromCloud) { return; }
    this.downloadingFromCloud = true;
    try {
      const userId = await AuthService.getLoginUserId(getContext(this));
      if (!userId) {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录后再下载' });
        return;
      }
      const result = await SyncService.downloadAllFromCloud(getContext(this), userId);
      if (result.courses.success && result.exams.success) {
        const courseCount = result.courses.courseCount || 0;
        const examCount = result.exams.examCount || 0;
        this.getUIContext().getPromptAction().showToast({
          message: `云端下载完成：课表${courseCount}条，考试${examCount}条`
        });
      } else {
        const errorMsg = result.courses.error || result.exams.error || '未知错误';
        this.getUIContext().getPromptAction().showToast({ message: `云端下载失败: ${errorMsg}` });
      }
    } catch (error) {
      console.error('云端下载失败:', error);
      this.getUIContext().getPromptAction().showToast({ message: `云端下载失败: ${String(error)}` });
    } finally {
      this.downloadingFromCloud = false;
    }
  }

  build() {
    Column() {
      Column() {
        Row() {
          Text('UESTC Online')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeManager.getTextPrimaryColor());
          Blank();
          Row({ space: 6 }) {
            if (this.isLoggedIn) {
              Text('账号')
                .fontSize(12)
                .fontColor(ThemeManager.getAccentColor())
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(ThemeManager.getAccentBgColor())
                .borderRadius(14)
                .onClick(() => this.accountManage());

              if (this.syncingToCloud) {
                Text('上传中...')
                  .fontSize(12)
                  .fontColor(ThemeManager.getTextTertiaryColor())
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
                  .borderRadius(14);
              } else {
                Text('上传')
                  .fontSize(12)
                  .fontColor(ThemeManager.getAccentColor())
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(ThemeManager.getAccentBgColor())
                  .borderRadius(14)
                  .onClick(() => this.syncLocalDataToCloud());
              }

              if (this.downloadingFromCloud) {
                Text('下载中...')
                  .fontSize(12)
                  .fontColor(ThemeManager.getTextTertiaryColor())
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
                  .borderRadius(14);
              } else {
                Text('下载')
                  .fontSize(12)
                  .fontColor(ThemeManager.getAccentColor())
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(ThemeManager.getAccentBgColor())
                  .borderRadius(14)
                  .onClick(() => this.downloadFromCloud());
              }
            } else {
              Text('登录')
                .fontSize(12)
                .fontColor(ThemeManager.getAccentColor())
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(ThemeManager.getAccentBgColor())
                .borderRadius(14)
                .onClick(() => this.login());
            }

            Text('刷新')
              .fontSize(12)
              .fontColor(ThemeManager.getAccentColor())
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(ThemeManager.getAccentBgColor())
              .borderRadius(14)
              .onClick(() => this.controller.refresh());
          }
          .alignItems(VerticalAlign.Center);
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 });
      }
      .width('100%')
      .backgroundColor(ThemeManager.getBackgroundColor());

      Web({ src: AppConstants.ONLINE_URL, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .mixedMode(MixedMode.All);

      BottomTabBar({ currentIndex: $currentTabIndex, tabs: this.tabs, onChange: (index: number) => this.onTabChange(index) });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor());
  }
}