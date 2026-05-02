import { router } from '@kit.ArkUI';
import { ScheduleEvent, ScheduleUtils, DayInfo, ScheduleEventType } from '../../model/ScheduleModel';
import { ScheduleService } from '../../service/ScheduleService';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { ScheduleEditor } from '../../components/ScheduleEditor';

const WEEK_HEADERS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

@Entry
@Component
struct CalendarPage {
  @State currentYear: number = new Date().getFullYear();
  @State currentMonth: number = new Date().getMonth() + 1;
  @State dayGrid: DayInfo[] = [];
  @State allEvents: ScheduleEvent[] = [];
  @State eventsByDate: Record<string, ScheduleEvent[]> = {};
  @State selectedDate: string = '';
  @State selectedEvents: ScheduleEvent[] = [];
  @State isEditingExisting: boolean = false;
  @State editingEvent: ScheduleEvent = ScheduleUtils.createEmptyEvent();
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;

  private scheduleDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    const today: Date = new Date();
    this.currentYear = today.getFullYear();
    this.currentMonth = today.getMonth() + 1;
    this.selectedDate = ScheduleUtils.formatDate(this.currentYear, this.currentMonth, today.getDate());
    this.loadAllEvents();
  }

  onPageShow(): void {
    this.loadAllEvents();
  }

  private async loadAllEvents(): Promise<void> {
    try {
      const context = getContext(this);
      this.allEvents = await ScheduleService.getAllEvents(context);
      this.eventsByDate = ScheduleUtils.groupByDate(this.allEvents);
      this.buildDayGrid();
      this.updateSelectedEvents();
    } catch (error) {
      console.error('CalendarPage loadAllEvents error:', JSON.stringify(error));
    }
  }

  private buildDayGrid(): void {
    const grid: DayInfo[] = [];
    const firstDay: Date = new Date(this.currentYear, this.currentMonth - 1, 1);
    const startDayOfWeek: number = firstDay.getDay();
    const daysInMonth: number = new Date(this.currentYear, this.currentMonth, 0).getDate();
    const daysInPrevMonth: number = new Date(this.currentYear, this.currentMonth - 1, 0).getDate();
    const today: Date = new Date();
    const todayStr: string = ScheduleUtils.formatDate(today.getFullYear(), today.getMonth() + 1, today.getDate());

    const totalCells: number = 42;
    for (let i = 0; i < totalCells; i++) {
      let day: number;
      let month: number;
      let year: number;
      let isCurrentMonth: boolean;

      if (i < startDayOfWeek) {
        day = daysInPrevMonth - startDayOfWeek + i + 1;
        month = this.currentMonth - 1;
        year = this.currentYear;
        if (month === 0) {
          month = 12;
          year = this.currentYear - 1;
        }
        isCurrentMonth = false;
      } else if (i >= startDayOfWeek + daysInMonth) {
        day = i - startDayOfWeek - daysInMonth + 1;
        month = this.currentMonth + 1;
        year = this.currentYear;
        if (month === 13) {
          month = 1;
          year = this.currentYear + 1;
        }
        isCurrentMonth = false;
      } else {
        day = i - startDayOfWeek + 1;
        month = this.currentMonth;
        year = this.currentYear;
        isCurrentMonth = true;
      }

      const dateStr: string = ScheduleUtils.formatDate(year, month, day);
      const dayInfo: DayInfo = {
        date: dateStr,
        year: year,
        month: month,
        day: day,
        isToday: dateStr === todayStr,
        isCurrentMonth: isCurrentMonth,
        events: this.eventsByDate[dateStr] || [],
        markers: ScheduleUtils.getEventMarkers(this.eventsByDate[dateStr] || []),
      };
      grid.push(dayInfo);
    }
    this.dayGrid = grid;
  }

  private updateSelectedEvents(): void {
    this.selectedEvents = this.eventsByDate[this.selectedDate] || [];
  }

  private prevMonth(): void {
    if (this.currentMonth === 1) {
      this.currentYear--;
      this.currentMonth = 12;
    } else {
      this.currentMonth--;
    }
    this.buildDayGrid();
    this.updateSelectedEvents();
  }

  private nextMonth(): void {
    if (this.currentMonth === 12) {
      this.currentYear++;
      this.currentMonth = 1;
    } else {
      this.currentMonth++;
    }
    this.buildDayGrid();
    this.updateSelectedEvents();
  }

  private goToday(): void {
    const today: Date = new Date();
    this.currentYear = today.getFullYear();
    this.currentMonth = today.getMonth() + 1;
    this.selectedDate = ScheduleUtils.formatDate(this.currentYear, this.currentMonth, today.getDate());
    this.buildDayGrid();
    this.updateSelectedEvents();
  }

  private selectDate(dateStr: string): void {
    this.selectedDate = dateStr;
    this.updateSelectedEvents();
  }

  private openAddEditor(): void {
    this.isEditingExisting = false;
    this.editingEvent = ScheduleUtils.createEmptyEvent();
    const defaultDate = this.selectedDate || ScheduleUtils.formatDate(new Date().getFullYear(), new Date().getMonth() + 1, new Date().getDate());
    this.editingEvent.date = defaultDate;

    this.scheduleDialogController = new CustomDialogController({
      builder: ScheduleEditor({
        existingEvent: this.editingEvent,
        isEditing: false,
        onSave: (evt: ScheduleEvent) => {
          this.onSaveSchedule(evt);
        },
        onDelete: (evtId: string) => {
          this.onDeleteSchedule(evtId);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    });
    this.scheduleDialogController.open();
  }

  private openEditEditor(event: ScheduleEvent): void {
    if (event.type !== 'custom' && event.type !== 'assignment') {
      return;
    }
    this.isEditingExisting = true;
    this.editingEvent = {
      id: event.id,
      title: event.title,
      date: event.date,
      timeRange: event.timeRange,
      location: event.location,
      type: event.type,
      color: event.color,
      sourceId: event.sourceId,
      description: event.description,
      createdAt: event.createdAt,
    };

    this.scheduleDialogController = new CustomDialogController({
      builder: ScheduleEditor({
        existingEvent: this.editingEvent,
        isEditing: true,
        onSave: (evt: ScheduleEvent) => {
          this.onSaveSchedule(evt);
        },
        onDelete: (evtId: string) => {
          this.onDeleteSchedule(evtId);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
    });
    this.scheduleDialogController.open();
  }

  private async onSaveSchedule(event: ScheduleEvent): Promise<void> {
    const context = getContext(this);
    await ScheduleService.saveSchedule(context, event);
    await this.loadAllEvents();
  }

  private async onDeleteSchedule(eventId: string): Promise<void> {
    const context = getContext(this);
    await ScheduleService.deleteSchedule(context, eventId);
    await this.loadAllEvents();
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .fontColor(ThemeManager.getAccentColor())
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => router.back());

        Button('<')
          .fontSize(18)
          .width(36)
          .height(36)
          .backgroundColor('#00000000')
          .onClick(() => this.prevMonth());

        Text(`${this.currentYear}年 ${this.currentMonth}月`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Center);

        Button('>')
          .fontSize(18)
          .width(36)
          .height(36)
          .backgroundColor('#00000000')
          .onClick(() => this.nextMonth());

        Button('今天')
          .fontSize(13)
          .onClick(() => this.goToday());
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 4 });

      Row() {
        ForEach(WEEK_HEADERS, (header: string) => {
          Text(header)
            .width('13.7%')
            .fontSize(12)
            .fontColor('#9E9E9E')
            .textAlign(TextAlign.Center);
        });
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 });

      Grid() {
        ForEach(this.dayGrid, (dayItem: DayInfo) => {
          GridItem() {
            Column() {
              Text(dayItem.day.toString())
                .fontSize(14)
                .fontColor(dayItem.isCurrentMonth
                  ? (dayItem.isToday ? Color.White : ThemeManager.getTextPrimaryColor())
                  : '#C0C0C0')
                .fontWeight(dayItem.isToday ? FontWeight.Bold : FontWeight.Normal)
                .backgroundColor(dayItem.isToday ? '#2196F3' : '#00000000')
                .borderRadius(dayItem.isToday ? 12 : 0)
                .width(dayItem.isToday ? 24 : 'auto')
                .height(dayItem.isToday ? 24 : 'auto')
                .textAlign(TextAlign.Center);

              if (dayItem.events.length > 0) {
                Row({ space: 2 }) {
                  ForEach(dayItem.markers, (type: ScheduleEventType) => {
                    Circle({ width: 5, height: 5 })
                      .fill(ScheduleUtils.getTypeColor(type));
                  });
                }
                .justifyContent(FlexAlign.Center)
                .width('100%')
                .margin({ top: 2 });
              }
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .borderRadius(4)
            .backgroundColor(this.selectedDate === dayItem.date
              ? (ThemeManager.isDarkMode() ? '#1E3A5F' : '#E3F2FD')
              : '#00000000')
            .onClick(() => this.selectDate(dayItem.date));
          }
        });
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsGap(2)
      .columnsGap(2)
      .width('100%')
      .padding({ left: 4, right: 4 });

      Divider().margin({ top: 8, bottom: 4 });

      Text(`${this.selectedDate} 事件`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .width('100%')
        .padding({ left: 16, top: 4 });

      if (this.selectedEvents.length === 0) {
        Text('当天无事件')
          .fontSize(13)
          .fontColor('#BDBDBD')
          .margin({ top: 8 });
      } else {
        List({ space: 6 }) {
          ForEach(this.selectedEvents, (event: ScheduleEvent) => {
            ListItem() {
              Row() {
                Rect()
                  .width(4)
                  .height(36)
                  .fill(event.color)
                  .borderRadius(2);

                Column() {
                  Text(event.title)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(ThemeManager.getTextPrimaryColor());
                  Row({ space: 8 }) {
                    if (event.timeRange) {
                      Text(event.timeRange)
                        .fontSize(11)
                        .fontColor('#9E9E9E');
                    }
                    if (event.location) {
                      Text(event.location)
                        .fontSize(11)
                        .fontColor('#9E9E9E');
                    }
                    Text(ScheduleUtils.getTypeLabel(event.type))
                      .fontSize(10)
                      .fontColor(Color.White)
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .borderRadius(4)
                      .backgroundColor(event.color);
                  }
                  .margin({ top: 2 });
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 8 });

                if (event.type === 'custom' || event.type === 'assignment') {
                  Image($r('app.media.startIcon'))
                    .width(16)
                    .height(16)
                    .fillColor('#9E9E9E')
                    .onClick(() => this.openEditEditor(event));
                }
              }
              .width('100%')
              .padding(10)
              .borderRadius(8)
              .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#FFFFFF');
            }
            .onClick(() => {
              if (event.type === 'custom' || event.type === 'assignment') {
                this.openEditEditor(event);
              }
            });
          });
        }
        .width('92%')
        .layoutWeight(1);
      }

      Button('+')
        .fontSize(24)
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor('#2196F3')
        .fontColor(Color.White)
        .shadow({ radius: 8, color: '#42000000' })
        .margin({ right: 20, bottom: 20 })
        .position({ x: 'calc(100% - 76vp)', y: 'calc(100% - 76vp)' })
        .onClick(() => this.openAddEditor());
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor());
  }
}