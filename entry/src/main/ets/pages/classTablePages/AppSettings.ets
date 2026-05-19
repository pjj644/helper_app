import { router } from '@kit.ArkUI';
import { AppSettings } from '../../repository/SettingsRepository';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { SettingsRepository } from '../../repository/SettingsRepository';
import { ReminderService } from '../../service/ReminderService';
import { ScheduleService } from '../../service/ScheduleService';
import { AuthService } from '../../service/AuthService';
import { SyncService } from '../../service/SyncService';
import { LoadingOverlay } from '../../components/LoadingOverlay';
import { Logger } from '../../common/utils/Logger';

const TAG = 'AppSettings';

@Entry
@Component
struct AppSettings {
  @State settings: AppSettings = {
    showToday: true,
    showTomorrow: true,
    showExamCountdown: true,
    examRemindMinutes: 30,
    courseRemindMinutes: 30,
  };
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  @State autoSyncSchedule: boolean = true;
  @State isLoggedIn: boolean = false;
  @State loginEmail: string = '';
  @State syncingToCloud: boolean = false;
  @State downloadingFromCloud: boolean = false;

  aboutToAppear(): void {
    this.loadSettings();
    this.checkLoginStatus();
  }

  private async loadSettings(): Promise<void> {
    try {
      const context = getContext(this);
      this.settings = await SettingsRepository.loadSettings(context);
      this.autoSyncSchedule = await ReminderService.getAutoSyncScheduleEnabled(context);
    } catch (error) {
      const e = error as Error;
      Logger.error(TAG, `加载设置失败: ${e.message || JSON.stringify(error)}`);
    }
  }

  private async checkLoginStatus(): Promise<void> {
    try {
      const userId: string | undefined = await AuthService.getLoginUserId(getContext(this));
      this.isLoggedIn = !!userId;
      this.loginEmail = userId || '';
    } catch (error) {
      this.isLoggedIn = false;
      this.loginEmail = '';
    }
  }

  private async saveSettings(): Promise<void> {
    try {
      const context = getContext(this);
      await SettingsRepository.saveSettings(context, this.settings);
      await ReminderService.saveAutoSyncScheduleEnabled(context, this.autoSyncSchedule);

      if (this.autoSyncSchedule) {
        await ScheduleService.syncCoursesToSchedule(context);
        await ScheduleService.syncExamsToSchedule(context);
      }

      this.getUIContext().getPromptAction().showToast({ message: '设置已保存' });
      router.back();
    } catch (error) {
      const e = error as Error;
      Logger.error(TAG, `保存设置失败: ${e.message || JSON.stringify(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败' });
    }
  }

  private login(): void {
    router.pushUrl({ url: 'pages/login/loginIndex' })
      .catch((error: Error) => console.error('跳转登录页面失败:', error));
  }

  private accountManage(): void {
    router.pushUrl({ url: 'pages/login/AccountManage' })
      .catch((error: Error) => console.error('跳转账号管理失败:', error));
  }

  private async syncLocalDataToCloud(): Promise<void> {
    if (this.syncingToCloud) { return; }
    this.syncingToCloud = true;
    try {
      const userId: string | undefined = await AuthService.getLoginUserId(getContext(this));
      if (!userId) {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录后再同步' });
        return;
      }
      const result = await SyncService.syncAllToCloud(getContext(this), userId);
      if (result.courses.success && result.exams.success) {
        const courseCount: number = result.courses.courseCount || 0;
        const examCount: number = result.exams.examCount || 0;
        this.getUIContext().getPromptAction().showToast({
          message: `云端同步完成：课表${courseCount}条，考试${examCount}条`
        });
        ReminderService.refreshAllReminders(getContext(this));
      } else {
        const errorMsg: string = result.courses.error || result.exams.error || '未知错误';
        this.getUIContext().getPromptAction().showToast({ message: `云端同步失败: ${errorMsg}` });
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `云端同步失败: ${String(error)}` });
    } finally {
      this.syncingToCloud = false;
    }
  }

  private async downloadFromCloud(): Promise<void> {
    if (this.downloadingFromCloud) { return; }
    this.downloadingFromCloud = true;
    try {
      const userId: string | undefined = await AuthService.getLoginUserId(getContext(this));
      if (!userId) {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录后再下载' });
        return;
      }
      const result = await SyncService.downloadAllFromCloud(getContext(this), userId);
      if (result.courses.success && result.exams.success) {
        const courseCount: number = result.courses.courseCount || 0;
        const examCount: number = result.exams.examCount || 0;
        this.getUIContext().getPromptAction().showToast({
          message: `云端下载完成：课表${courseCount}条，考试${examCount}条`
        });
        ReminderService.refreshAllReminders(getContext(this));
      } else {
        const errorMsg: string = result.courses.error || result.exams.error || '未知错误';
        this.getUIContext().getPromptAction().showToast({ message: `云端下载失败: ${errorMsg}` });
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `云端下载失败: ${String(error)}` });
    } finally {
      this.downloadingFromCloud = false;
    }
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('设置')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeManager.getTextPrimaryColor());
          Blank();
          Button('返回')
            .fontColor(ThemeManager.getTextPrimaryColor())
            .backgroundColor(ThemeManager.getCardColor())
            .onClick(() => router.back());
        }
        .width('100%')
        .padding(12);

        Scroll() {
          Column({ space: 16 }) {
            Column({ space: 12 }) {
              Text('账号管理')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeManager.getTextPrimaryColor())
                .width('100%');

              if (this.isLoggedIn) {
                Row() {
                  Column({ space: 4 }) {
                    Text(this.loginEmail)
                      .fontSize(14)
                      .fontColor(ThemeManager.getTextPrimaryColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text('已登录')
                      .fontSize(12)
                      .fontColor('#10B981');
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start);

                  Button('账号管理')
                    .height(32)
                    .fontSize(13)
                    .fontColor(ThemeManager.getAccentColor())
                    .backgroundColor(ThemeManager.getAccentBgColor())
                    .borderRadius(16)
                    .onClick(() => this.accountManage());
                }
                .width('100%')
                .padding(12)
                .borderRadius(10)
                .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#F7F9FB');
              } else {
                Row() {
                  Text('未登录，部分功能不可用')
                    .fontSize(14)
                    .fontColor(ThemeManager.getTextSecondaryColor())
                    .layoutWeight(1);

                  Button('登录')
                    .height(32)
                    .fontSize(13)
                    .fontColor(ThemeManager.getAccentColor())
                    .backgroundColor(ThemeManager.getAccentBgColor())
                    .borderRadius(16)
                    .onClick(() => this.login());
                }
                .width('100%')
                .padding(12)
                .borderRadius(10)
                .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#F7F9FB');
              }
            }
            .width('100%')
            .padding(12)
            .borderRadius(14)
            .backgroundColor(ThemeManager.getCardColor());

            Column({ space: 12 }) {
              Text('数据同步')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeManager.getTextPrimaryColor())
                .width('100%');

              Row({ space: 12 }) {
                Button() {
                  Text(this.syncingToCloud ? '上传中...' : '上传到云端')
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                }
                .layoutWeight(1)
                .height(44)
                .backgroundColor(this.syncingToCloud ? ThemeManager.getTextTertiaryColor() : ThemeManager.getAccentColor())
                .borderRadius(12)
                .enabled(!this.syncingToCloud && !this.downloadingFromCloud)
                .onClick(() => this.syncLocalDataToCloud());

                Button() {
                  Text(this.downloadingFromCloud ? '下载中...' : '从云端下载')
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                }
                .layoutWeight(1)
                .height(44)
                .backgroundColor(this.downloadingFromCloud ? ThemeManager.getTextTertiaryColor() : '#10B981')
                .borderRadius(12)
                .enabled(!this.syncingToCloud && !this.downloadingFromCloud)
                .onClick(() => this.downloadFromCloud());
              }
              .width('100%');
            }
            .width('100%')
            .padding(12)
            .borderRadius(14)
            .backgroundColor(ThemeManager.getCardColor());

            Column({ space: 12 }) {
              Text('显示设置')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeManager.getTextPrimaryColor())
                .width('100%');

              Row() {
                Text('首页显示今日课程')
                  .fontSize(16)
                  .fontColor(ThemeManager.getTextPrimaryColor())
                  .layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: this.settings.showToday })
                  .onChange((value: boolean) => this.settings.showToday = value);
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#F7F9FB');

              Row() {
                Text('首页显示明日课程')
                  .fontSize(16)
                  .fontColor(ThemeManager.getTextPrimaryColor())
                  .layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: this.settings.showTomorrow })
                  .onChange((value: boolean) => this.settings.showTomorrow = value);
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#F7F9FB');

              Row() {
                Text('首页显示考试倒计时')
                  .fontSize(16)
                  .fontColor(ThemeManager.getTextPrimaryColor())
                  .layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: this.settings.showExamCountdown })
                  .onChange((value: boolean) => this.settings.showExamCountdown = value);
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#F7F9FB');

              Row() {
                Text('自动创建相关日程')
                  .fontSize(16)
                  .fontColor(ThemeManager.getTextPrimaryColor())
                  .layoutWeight(1);
                Toggle({ type: ToggleType.Switch, isOn: this.autoSyncSchedule })
                  .onChange((value: boolean) => {
                    this.autoSyncSchedule = value;
                    ReminderService.saveAutoSyncScheduleEnabled(getContext(this), value);
                    if (value) {
                      ScheduleService.syncCoursesToSchedule(getContext(this));
                      ScheduleService.syncExamsToSchedule(getContext(this));
                    } else {
                      ScheduleService.clearAutoGeneratedSchedules(getContext(this));
                    }
                  });
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#F7F9FB');
            }
            .width('100%')
            .padding(12)
            .borderRadius(14)
            .backgroundColor(ThemeManager.getCardColor());

            Button('保存设置')
              .width('92%')
              .height(48)
              .fontSize(16)
              .onClick(() => this.saveSettings());
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 24 });
        }
        .layoutWeight(1)
        .width('100%');
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeManager.getBackgroundSecondaryColor());

      LoadingOverlay({
        isVisible: this.syncingToCloud || this.downloadingFromCloud,
        message: this.syncingToCloud ? '正在上传到云端...' : '正在从云端下载...'
      });
    }
    .width('100%')
    .height('100%');
  }
}
