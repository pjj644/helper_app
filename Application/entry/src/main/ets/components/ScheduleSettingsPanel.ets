import { ThemeManager } from '../common/utils/ThemeManager';
import { ReminderService } from '../service/ReminderService';
import { ScheduleEventType } from '../model/ScheduleModel';

const REMIND_OPTIONS: SelectOption[] = [
  { value: '关闭提醒' },
  { value: '1分钟前' },
  { value: '5分钟前' },
  { value: '10分钟前' },
  { value: '15分钟前' },
  { value: '30分钟前' },
  { value: '1小时前' },
  { value: '2小时前' },
  { value: '1天前' }
];
const REMIND_MINUTES_VALUES: number[] = [0, 1, 5, 10, 15, 30, 60, 120, 1440];

@CustomDialog
export struct ScheduleSettingsPanel {
  controller: CustomDialogController = new CustomDialogController({ builder: ScheduleSettingsPanel({}) });

  @State masterEnabled: boolean = true;
  @State examEnabled: boolean = true;
  @State courseEnabled: boolean = true;
  @State customEnabled: boolean = true;
  @State assignmentEnabled: boolean = true;
  @State examMinutes: number = 30;
  @State courseMinutes: number = 30;
  @State customMinutes: number = 30;
  @State assignmentMinutes: number = 30;
  @State examMinutesIndex: number = 4;
  @State courseMinutesIndex: number = 4;
  @State customMinutesIndex: number = 4;
  @State assignmentMinutesIndex: number = 4;

  onDialogClose?: () => void;

  aboutToAppear(): void {
    this.loadSettings();
  }

  private async loadSettings(): Promise<void> {
    try {
      const context = getContext(this);
      this.masterEnabled = await ReminderService.getGlobalScheduleReminderEnabled(context);
      this.examEnabled = await ReminderService.getCategoryReminderEnabled(context, 'exam');
      this.courseEnabled = await ReminderService.getCategoryReminderEnabled(context, 'course');
      this.customEnabled = await ReminderService.getCategoryReminderEnabled(context, 'custom');
      this.assignmentEnabled = await ReminderService.getCategoryReminderEnabled(context, 'assignment');
      this.examMinutes = await ReminderService.getCategoryRemindMinutes(context, 'exam');
      this.courseMinutes = await ReminderService.getCategoryRemindMinutes(context, 'course');
      this.customMinutes = await ReminderService.getCategoryRemindMinutes(context, 'custom');
      this.assignmentMinutes = await ReminderService.getCategoryRemindMinutes(context, 'assignment');
      this.examMinutesIndex = this.minutesToIndex(this.examMinutes);
      this.courseMinutesIndex = this.minutesToIndex(this.courseMinutes);
      this.customMinutesIndex = this.minutesToIndex(this.customMinutes);
      this.assignmentMinutesIndex = this.minutesToIndex(this.assignmentMinutes);
    } catch (e) {
      console.error('[ScheduleSettingsPanel] loadSettings error:', JSON.stringify(e));
    }
  }

  private minutesToIndex(minutes: number): number {
    for (let i = 0; i < REMIND_MINUTES_VALUES.length; i++) {
      if (REMIND_MINUTES_VALUES[i] === minutes) {
        return i;
      }
    }
    return 4;
  }

  private async onMasterChange(value: boolean): Promise<void> {
    this.masterEnabled = value;
    const context = getContext(this);
    await ReminderService.saveGlobalScheduleReminderEnabled(context, value);
    await ReminderService.refreshScheduleReminders(context);
  }

  private async onCategoryChange(type: ScheduleEventType, value: boolean): Promise<void> {
    switch (type) {
      case 'exam':
        this.examEnabled = value;
        break;
      case 'course':
        this.courseEnabled = value;
        break;
      case 'custom':
        this.customEnabled = value;
        break;
      case 'assignment':
        this.assignmentEnabled = value;
        break;
    }
    const context = getContext(this);
    await ReminderService.saveCategoryReminderEnabled(context, type, value);
    await ReminderService.refreshScheduleReminders(context);
  }

  private async onMinutesChange(type: ScheduleEventType, index: number): Promise<void> {
    const minutes = REMIND_MINUTES_VALUES[index];
    switch (type) {
      case 'exam':
        this.examMinutesIndex = index;
        this.examMinutes = minutes;
        break;
      case 'course':
        this.courseMinutesIndex = index;
        this.courseMinutes = minutes;
        break;
      case 'custom':
        this.customMinutesIndex = index;
        this.customMinutes = minutes;
        break;
      case 'assignment':
        this.assignmentMinutesIndex = index;
        this.assignmentMinutes = minutes;
        break;
    }
    const context = getContext(this);
    await ReminderService.saveCategoryRemindMinutes(context, type, minutes);
    await ReminderService.refreshScheduleReminders(context);
  }

  @Builder
  private categoryRowBuilder(type: ScheduleEventType, label: string): void {
    Column() {
      Row() {
        Text(label)
          .fontSize(14)
          .fontColor(this.masterEnabled ? ThemeManager.getTextPrimaryColor() : ThemeManager.getTextTertiaryColor())
          .layoutWeight(1);

        Toggle({ type: ToggleType.Switch, isOn: this.getCategoryEnabled(type) })
          .enabled(this.masterEnabled)
          .selectedColor(ThemeManager.getAccentColor())
          .onChange((value: boolean) => {
            this.onCategoryChange(type, value);
          });
      }
      .width('100%');

      Row() {
        Text('提醒时间')
          .fontSize(12)
          .fontColor(ThemeManager.getTextTertiaryColor())
          .width(50);

        Select(REMIND_OPTIONS)
          .selected(this.getMinutesIndex(type))
          .value(String(REMIND_OPTIONS[this.getMinutesIndex(type)].value))
          .enabled(this.masterEnabled && this.getCategoryEnabled(type))
          .onSelect((index: number) => {
            this.onMinutesChange(type, index);
          })
          .width(120)

      }
      .width('100%')
      .margin({ top: 6, bottom: 2 });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 10, bottom: 10 });
  }

  private getCategoryEnabled(type: ScheduleEventType): boolean {
    switch (type) {
      case 'exam':
        return this.examEnabled;
      case 'course':
        return this.courseEnabled;
      case 'custom':
        return this.customEnabled;
      case 'assignment':
        return this.assignmentEnabled;
      default:
        return true;
    }
  }

  private getMinutesIndex(type: ScheduleEventType): number {
    switch (type) {
      case 'exam':
        return this.examMinutesIndex;
      case 'course':
        return this.courseMinutesIndex;
      case 'custom':
        return this.customMinutesIndex;
      case 'assignment':
        return this.assignmentMinutesIndex;
      default:
        return 4;
    }
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Text('日程提醒设置')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .layoutWeight(1);

          Button('关闭')
            .fontSize(13)
            .fontColor(ThemeManager.getAccentColor())
            .backgroundColor('#00000000')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              if (this.onDialogClose) {
                this.onDialogClose();
              }
            });
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 12 });

        Divider()
          .strokeWidth(0.5)
          .color(ThemeManager.getBorderColor());

        Row() {
          Text('启用日程提醒')
            .fontSize(15)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .layoutWeight(1);

          Toggle({ type: ToggleType.Switch, isOn: this.masterEnabled })
            .selectedColor(ThemeManager.getAccentColor())
            .onChange((value: boolean) => {
              this.onMasterChange(value);
            });
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 });

        Divider()
          .strokeWidth(0.5)
          .color(ThemeManager.getBorderColor())
          .margin({ left: 20 });

        this.categoryRowBuilder('exam', '考试提醒');

        Divider()
          .strokeWidth(0.5)
          .color(ThemeManager.getBorderColor())
          .margin({ left: 20 });

        this.categoryRowBuilder('course', '课程提醒');

        Divider()
          .strokeWidth(0.5)
          .color(ThemeManager.getBorderColor())
          .margin({ left: 20 });

        this.categoryRowBuilder('custom', '自定义提醒');

        Divider()
          .strokeWidth(0.5)
          .color(ThemeManager.getBorderColor())
          .margin({ left: 20 });

        this.categoryRowBuilder('assignment', '作业提醒');
      }
      .width('100%')
      .padding({ bottom: 16 });
    }
    .width('100%')
    .constraintSize({ maxHeight: 560 })
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
    .borderRadius(16);
  }
}
