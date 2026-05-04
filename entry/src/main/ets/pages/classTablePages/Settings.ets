import { router } from '@kit.ArkUI';
import { AppSettings } from '../../repository/SettingsRepository';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { SettingsRepository } from '../../repository/SettingsRepository';
import { ReminderService } from '../../service/ReminderService';
import { ScheduleService } from '../../service/ScheduleService';
import { Logger } from '../../common/utils/Logger';

const TAG = 'Settings';

@Entry
@Component
struct Settings {
  @State settings: AppSettings = {
    themeDark: false,
    showToday: true,
    showTomorrow: true,
    showExamCountdown: true,
    examRemindMinutes: 30,
    courseRemindMinutes: 30,
  };
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  @State autoSyncSchedule: boolean = true;

  aboutToAppear(): void {
    this.loadSettings();
  }

  private async loadSettings(): Promise<void> {
    try {
      const context = getContext(this);
      this.settings = await SettingsRepository.loadSettings(context);
      this.isDarkMode = this.settings.themeDark;
      this.autoSyncSchedule = await ReminderService.getAutoSyncScheduleEnabled(context);
    } catch (error) {
      const e = error as Error;
      Logger.error(TAG, `加载设置失败: ${e.message || JSON.stringify(error)}`);
    }
  }

  private async saveSettings(): Promise<void> {
    try {
      const context = getContext(this);
      await SettingsRepository.saveSettings(context, this.settings);
      ThemeManager.setDarkMode(this.settings.themeDark);
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

  private onThemeChange(isDark: boolean): void {
    this.settings.themeDark = isDark;
    this.isDarkMode = isDark;
    ThemeManager.setDarkMode(isDark);
  }

  build() {
    Column() {
      Row() {
        Text('基础设置')
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

      Column({ space: 12 }) {
        Row() {
          Text('深色主题')
            .fontSize(16)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .layoutWeight(1);
          Toggle({ type: ToggleType.Switch, isOn: this.settings.themeDark })
            .onChange((value: boolean) => this.onThemeChange(value));
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#F7F9FB');

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
      .padding({ left: 12, right: 12, top: 8 });

      Button('保存设置')
        .width('92%')
        .margin({ top: 24 })
        .onClick(() => this.saveSettings());

      Blank();
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor());
  }
}
