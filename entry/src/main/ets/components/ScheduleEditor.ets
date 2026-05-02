import { ScheduleEvent, ScheduleEventType, ScheduleUtils } from '../model/ScheduleModel';
import { ThemeManager } from '../common/utils/ThemeManager';

@CustomDialog
export struct ScheduleEditor {
  controller: CustomDialogController = new CustomDialogController({ builder: ScheduleEditor({}) });

  @Prop isEditing: boolean = false;
  @Prop existingEvent: ScheduleEvent | null = null;
  @State title: string = '';
  @State description: string = '';
  @State date: Date = new Date();
  @State selectedTypeIndex: number = 3;
  @State remindMinutes: number = 0;
  @State remindSelectedIndex: number = 0;
  @State startHour: number = 9;
  @State startMinute: number = 0;
  @State endHour: number = 10;
  @State endMinute: number = 0;
  @State showDateDialog: boolean = false;
  private typeOptions: SelectOption[] = [
    { value: '考试' },
    { value: '课程' },
    { value: '自定义' },
    { value: '作业' }
  ];
  private remindOptions: SelectOption[] = [
    { value: '使用默认' },
    { value: '关闭提醒' },
    { value: '5分钟前' },
    { value: '10分钟前' },
    { value: '15分钟前' },
    { value: '30分钟前' },
    { value: '1小时前' }
  ];
  private remindMinutesValues: number[] = [-1, 0, 5, 10, 15, 30, 60];
  private hourOptions: SelectOption[] = this.buildHourOptions();
  private minuteOptions: SelectOption[] = this.buildMinuteOptions();

  onSave?: (event: ScheduleEvent) => void;
  onCancel?: () => void;
  onDelete?: (eventId: string) => void;
  onDialogClose?: () => void;

  private buildHourOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < 24; i++) {
      options.push({ value: `${i}` });
    }
    return options;
  }

  private buildMinuteOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < 60; i++) {
      options.push({ value: `${i}` });
    }
    return options;
  }

  aboutToAppear(): void {
    if (this.existingEvent) {
      this.title = this.existingEvent.title;
      this.description = this.existingEvent.description || '';
      const dateStr: string = this.existingEvent.date;
      if (dateStr) {
        const parts: number[] = dateStr.split('-').map(Number);
        this.date = new Date(parts[0], parts[1] - 1, parts[2]);
      }
      switch (this.existingEvent.type) {
        case 'exam':
          this.selectedTypeIndex = 0;
          break;
        case 'course':
          this.selectedTypeIndex = 1;
          break;
        case 'custom':
          this.selectedTypeIndex = 2;
          break;
        case 'assignment':
          this.selectedTypeIndex = 3;
          break;
      }
      this.remindMinutes = this.existingEvent.remindMinutes || 0;
      this.remindSelectedIndex = this.getRemindSelectedIndex();

      if (this.existingEvent.startTime) {
        const timeParts: string[] = this.existingEvent.startTime.split(':');
        this.startHour = timeParts[0] ? parseInt(timeParts[0]) : 9;
        this.startMinute = timeParts[1] ? parseInt(timeParts[1]) : 0;
      } else if (this.existingEvent.endTime) {
        const timeParts: string[] = this.existingEvent.endTime.split(':');
        this.endHour = timeParts[0] ? parseInt(timeParts[0]) : 10;
        this.endMinute = timeParts[1] ? parseInt(timeParts[1]) : 0;
      } else if (this.existingEvent.timeRange) {
        const parts: string[] = this.existingEvent.timeRange.split('-');
        if (parts.length === 2) {
          const startParts: string[] = parts[0].split(':');
          const endParts: string[] = parts[1].split(':');
          this.startHour = startParts[0] ? parseInt(startParts[0]) : 9;
          this.startMinute = startParts[1] ? parseInt(startParts[1]) : 0;
          this.endHour = endParts[0] ? parseInt(endParts[0]) : 10;
          this.endMinute = endParts[1] ? parseInt(endParts[1]) : 0;
        }
      }
    }
  }

  private getTypeLabel(): string {
    return String(this.typeOptions[this.selectedTypeIndex].value);
  }

  private getSelectedType(): ScheduleEventType {
    switch (this.selectedTypeIndex) {
      case 0:
        return 'exam' as ScheduleEventType;
      case 1:
        return 'course' as ScheduleEventType;
      case 2:
        return 'custom' as ScheduleEventType;
      case 3:
        return 'assignment' as ScheduleEventType;
      default:
        return 'custom' as ScheduleEventType;
    }
  }

  private getRemindSelectedIndex(): number {
    for (let i = 0; i < this.remindMinutesValues.length; i++) {
      if (this.remindMinutesValues[i] === this.remindMinutes) {
        return i;
      }
    }
    return 0;
  }

  private formatDate(d: Date): string {
    return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`;
  }

  private twoDigit(n: number): string {
    return n.toString().padStart(2, '0');
  }

  build() {
    Column({ space: 16 }) {
      Text(this.isEditing ? '编辑日程' : '添加日程')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .width('100%')
        .textAlign(TextAlign.Center);

      Row() {
        Text('类型')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width(60);
        Select(this.typeOptions)
          .selected(this.selectedTypeIndex)
          .onSelect((index: number) => {
            this.selectedTypeIndex = index;
          })
          .width(120);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row() {
        Text('标题')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width(60);
        TextInput({ text: this.title, placeholder: '日程标题' })
          .onChange((value: string) => {
            this.title = value;
          })
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .backgroundColor(ThemeManager.getCardColor())
          .borderRadius(8);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row() {
        Text('描述')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width(60);
        TextInput({ text: this.description, placeholder: '日程描述' })
          .onChange((value: string) => {
            this.description = value;
          })
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .backgroundColor(ThemeManager.getCardColor())
          .borderRadius(8)
          .maxLines(3);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row() {
        Text('提醒')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width(60);
        Select(this.remindOptions)
          .selected(this.remindSelectedIndex)
          .onSelect((index: number) => {
            this.remindSelectedIndex = index;
            this.remindMinutes = this.remindMinutesValues[index];
          })
          .width(130);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row() {
        Text('日期')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width(60);
        Text(this.formatDate(this.date))
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .onClick(() => {
            this.showDateDialog = true;
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row() {
        Text('开始时间')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width(60);
        Select(this.hourOptions)
          .selected(this.startHour)
          .onSelect((index: number) => {
            this.startHour = index;
          })
          .width(70);
        Text(':')
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor());
        Select(this.minuteOptions)
          .selected(this.startMinute)
          .onSelect((index: number) => {
            this.startMinute = index;
          })
          .width(70);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row() {
        Text('结束时间')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width(60);
        Select(this.hourOptions)
          .selected(this.endHour)
          .onSelect((index: number) => {
            this.endHour = index;
          })
          .width(70);
        Text(':')
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor());
        Select(this.minuteOptions)
          .selected(this.endMinute)
          .onSelect((index: number) => {
            this.endMinute = index;
          })
          .width(70);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
          .borderRadius(12)
          .onClick(() => {
            if (this.onDialogClose) {
              this.onDialogClose();
            }
          });

        Button('保存')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeManager.getAccentColor())
          .borderRadius(12)
          .onClick(() => {
            if (!this.title.trim()) {
              return;
            }
            const startTime: string = `${this.twoDigit(this.startHour)}:${this.twoDigit(this.startMinute)}`;
            const endTime: string = `${this.twoDigit(this.endHour)}:${this.twoDigit(this.endMinute)}`;
            const timeRange: string = `${startTime}-${endTime}`;
            const event: ScheduleEvent = {
              id: this.existingEvent?.id || ScheduleUtils.generateId(),
              title: this.title.trim(),
              date: this.formatDate(this.date),
              timeRange: timeRange,
              startTime: startTime,
              endTime: endTime,
              location: this.existingEvent?.location || '',
              type: this.getSelectedType(),
              color: ScheduleUtils.getTypeColor(this.getSelectedType()),
              sourceId: this.existingEvent?.sourceId || '',
              description: this.description.trim(),
              createdAt: this.existingEvent?.createdAt || Date.now(),
              remindMinutes: this.remindMinutesValues[this.remindSelectedIndex],
            };
            if (this.onSave) {
              this.onSave(event);
            }
          });
      }
      .width('100%');
    }
    .width('100%')
    .padding(20)
    .backgroundColor(ThemeManager.getBackgroundColor())
    .borderRadius(16);
  }
}
