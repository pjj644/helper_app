import { ScheduleEvent, ScheduleEventType, ScheduleUtils } from '../model/ScheduleModel';
import { ThemeManager } from '../common/utils/ThemeManager';

@Component
export struct ScheduleEditor {
  @Prop isEditing: boolean = false;
  @Prop existingEvent: ScheduleEvent | null = null;
  @State title: string = '';
  @State description: string = '';
  @State date: Date = new Date();
  @State selectedTypeIndex: number = 3;
  private typeOptions: SelectOption[] = [
    { value: '考试' },
    { value: '课程' },
    { value: '自定义' },
    { value: '作业' }
  ];

  onSave?: (event: ScheduleEvent) => void;
  onCancel?: () => void;
  onDelete?: (eventId: string) => void;

  aboutToAppear(): void {
    if (this.existingEvent) {
      this.title = this.existingEvent.title;
      this.description = this.existingEvent.description || '';
      const dateStr: string = this.existingEvent.date;
      if (dateStr) {
        const parts = dateStr.split('-').map(Number);
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

  private formatDate(d: Date): string {
    return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`;
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
        Text('日期')
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width(60);
        DatePicker({
          start: new Date('2025-01-01'),
          end: new Date('2027-12-31'),
          selected: this.date
        })
          .onChange((value: DatePickerResult) => {
            this.date = new Date(value.year ?? 2025, (value.month ?? 1), value.day ?? 1);
          })
          .width(180);
      }
      .width('100%');

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
          .borderRadius(12)
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
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
            const event: ScheduleEvent = {
              id: this.existingEvent?.id || ScheduleUtils.generateId(),
              title: this.title.trim(),
              date: this.formatDate(this.date),
              timeRange: this.existingEvent?.timeRange || '',
              location: this.existingEvent?.location || '',
              type: this.getSelectedType(),
              color: ScheduleUtils.getTypeColor(this.getSelectedType()),
              sourceId: this.existingEvent?.sourceId || '',
              description: this.description.trim(),
              createdAt: this.existingEvent?.createdAt || Date.now(),
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
