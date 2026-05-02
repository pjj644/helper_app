import { router } from '@kit.ArkUI';
import { ScheduleEvent, ScheduleUtils, DayInfo, ScheduleEventType } from '../../model/ScheduleModel';
import { ScheduleService } from '../../service/ScheduleService';
import { ReminderService } from '../../service/ReminderService';
import { CourseService } from '../../service/CourseService';
import { ExamService } from '../../service/ExamService';
import { Course } from '../../model/classTableModel/CourseModel';
import { ExamItem } from '../../model/classTableModel/ExamModel';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { ScheduleEditor } from '../../components/ScheduleEditor';
import { ScheduleSettingsPanel } from '../../components/ScheduleSettingsPanel';

const WEEK_HEADERS: string[] = ['日', '一', '二', '三', '四', '五', '六'];
const TOTAL_GRID_CELLS: number = 42;

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
  @State isLoading: boolean = false;
  @State loadingError: string = '';
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  private dialogController: CustomDialogController | null = null;
  private settingsDialogController: CustomDialogController | null = null;

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
    this.isLoading = true;
    this.loadingError = '';

    try {
      const context = getContext(this);

      const courseEventsPromise = this.buildCourseEventsForView(context, this.currentYear, this.currentMonth);
      const examEventsPromise = this.buildExamEventsForView(context);
      const customEventsPromise = this.loadCustomEvents(context);

      const allResults = await Promise.all([
        courseEventsPromise,
        examEventsPromise,
        customEventsPromise,
      ]);
      const courseEvents: ScheduleEvent[] = allResults[0];
      const examEvents: ScheduleEvent[] = allResults[1];
      const customEvents: ScheduleEvent[] = allResults[2];

      const all: ScheduleEvent[] = [];
      for (let i = 0; i < courseEvents.length; i++) {
        all.push(courseEvents[i]);
      }
      for (let i = 0; i < examEvents.length; i++) {
        all.push(examEvents[i]);
      }
      for (let i = 0; i < customEvents.length; i++) {
        all.push(customEvents[i]);
      }

      this.allEvents = all;
      this.eventsByDate = ScheduleUtils.groupByDate(this.allEvents);
      this.buildDayGrid();
      this.updateSelectedEvents();
    } catch (error) {
      console.error('CalendarPage loadAllEvents error:', JSON.stringify(error));
      this.loadingError = '加载日程失败';
    } finally {
      this.isLoading = false;
    }
  }

  private async buildCourseEventsForView(ctx: Context, year: number, month: number): Promise<ScheduleEvent[]> {
    const events: ScheduleEvent[] = [];
    try {
      const courses: Course[] = await CourseService.loadCourses(ctx);
      if (courses.length === 0) {
        return events;
      }

      const firstDay: Date = new Date(year, month - 1, 1);
      const startDayOfWeek: number = firstDay.getDay();
      const viewStart: Date = new Date(year, month - 1, 1);
      viewStart.setDate(viewStart.getDate() - startDayOfWeek);

      const current: Date = new Date(viewStart);
      for (let cellIdx = 0; cellIdx < TOTAL_GRID_CELLS; cellIdx++) {
        const currentDayOfWeek: number = current.getDay();
        const mappedDow: number = currentDayOfWeek === 0 ? 7 : currentDayOfWeek;

        for (let ci = 0; ci < courses.length; ci++) {
          const course: Course = courses[ci];
          if (course.time.dayOfWeek !== mappedDow) {
            continue;
          }

          const dateStr: string = ScheduleUtils.formatDate(current.getFullYear(), current.getMonth() + 1, current.getDate());
          const sectionMins: number = (course.time.startSection - 1) * 45 + Math.floor((course.time.startSection - 1) / 2) * 10;
          const startMins: number = 8 * 60 + sectionMins;
          const startHour: number = Math.floor(startMins / 60);
          const startMin: number = startMins % 60;
          const durationSections: number = course.time.duration;
          const endMins: number = startMins + durationSections * 45 + Math.floor(durationSections / 2) * 10;
          const endHour: number = Math.floor(endMins / 60);
          const endMin: number = endMins % 60;
          const timeRange: string = `${ScheduleUtils.twoDigit(startHour)}:${ScheduleUtils.twoDigit(startMin)}-${ScheduleUtils.twoDigit(endHour)}:${ScheduleUtils.twoDigit(endMin)}`;

          const evt: ScheduleEvent = {
            id: 'course_' + course.id + '_' + dateStr,
            title: course.name,
            date: dateStr,
            timeRange: timeRange,
            startTime: `${ScheduleUtils.twoDigit(startHour)}:${ScheduleUtils.twoDigit(startMin)}`,
            endTime: `${ScheduleUtils.twoDigit(endHour)}:${ScheduleUtils.twoDigit(endMin)}`,
            location: course.roomName,
            type: 'course' as ScheduleEventType,
            color: '#2196F3',
            sourceId: course.id,
            description: course.teacherName || '',
            createdAt: Date.now(),
          };
          events.push(evt);
        }

        current.setDate(current.getDate() + 1);
      }
    } catch (error) {
      console.error('CalendarPage buildCourseEventsForView error:', JSON.stringify(error));
    }
    return events;
  }

  private async buildExamEventsForView(ctx: Context): Promise<ScheduleEvent[]> {
    const events: ScheduleEvent[] = [];
    try {
      const exams: ExamItem[] = await ExamService.loadExams(ctx);
      for (let i = 0; i < exams.length; i++) {
        const exam: ExamItem = exams[i];
        if (exam.beginTime <= 0) {
          continue;
        }
        const examDate: Date = new Date(exam.beginTime);
        let examStartTime: string | undefined = undefined;
        let examEndTime: string | undefined = undefined;
        if (exam.examTimeRange && exam.examTimeRange.includes('-')) {
          const parts = exam.examTimeRange.split('-');
          examStartTime = parts[0].trim();
          examEndTime = parts[1].trim();
        }
        const evt: ScheduleEvent = {
          id: 'exam_' + exam.courseNo + '_' + exam.beginTime,
          title: exam.courseName + ' 考试',
          date: ScheduleUtils.formatDate(examDate.getFullYear(), examDate.getMonth() + 1, examDate.getDate()),
          timeRange: exam.examTimeRange,
          startTime: examStartTime,
          endTime: examEndTime,
          location: exam.examLocation,
          type: 'exam' as ScheduleEventType,
          color: '#F44336',
          sourceId: exam.courseNo,
          description: exam.seatNo || '',
          createdAt: Date.now(),
        };
        events.push(evt);
      }
    } catch (error) {
      console.error('CalendarPage buildExamEventsForView error:', JSON.stringify(error));
    }
    return events;
  }

  private async loadCustomEvents(ctx: Context): Promise<ScheduleEvent[]> {
    try {
      return await ScheduleService.loadCustomSchedules(ctx);
    } catch (error) {
      console.error('CalendarPage loadCustomEvents error:', JSON.stringify(error));
      return [];
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

    for (let i = 0; i < TOTAL_GRID_CELLS; i++) {
      let day: number;
      let month: number;
      let yearVal: number;
      let isCurrentMonth: boolean;

      if (i < startDayOfWeek) {
        day = daysInPrevMonth - startDayOfWeek + i + 1;
        month = this.currentMonth - 1;
        yearVal = this.currentYear;
        if (month === 0) {
          month = 12;
          yearVal = this.currentYear - 1;
        }
        isCurrentMonth = false;
      } else if (i >= startDayOfWeek + daysInMonth) {
        day = i - startDayOfWeek - daysInMonth + 1;
        month = this.currentMonth + 1;
        yearVal = this.currentYear;
        if (month === 13) {
          month = 1;
          yearVal = this.currentYear + 1;
        }
        isCurrentMonth = false;
      } else {
        day = i - startDayOfWeek + 1;
        month = this.currentMonth;
        yearVal = this.currentYear;
        isCurrentMonth = true;
      }

      const dateStr: string = ScheduleUtils.formatDate(yearVal, month, day);
      const dayEvents: ScheduleEvent[] = this.eventsByDate[dateStr] || [];
      const dayInfo: DayInfo = {
        date: dateStr,
        year: yearVal,
        month: month,
        day: day,
        isToday: dateStr === todayStr,
        isCurrentMonth: isCurrentMonth,
        events: dayEvents,
        markers: ScheduleUtils.getEventMarkers(dayEvents),
      };
      grid.push(dayInfo);
    }
    this.dayGrid = grid;
  }

  private updateSelectedEvents(): void {
    const filtered: ScheduleEvent[] = [];
    for (let i = 0; i < this.allEvents.length; i++) {
      if (this.allEvents[i].date === this.selectedDate) {
        filtered.push(this.allEvents[i]);
      }
    }
    this.selectedEvents = filtered;
  }

  private async prevMonth(): Promise<void> {
    if (this.currentMonth === 1) {
      this.currentYear--;
      this.currentMonth = 12;
    } else {
      this.currentMonth--;
    }
    await this.loadAllEvents();
  }

  private async nextMonth(): Promise<void> {
    if (this.currentMonth === 12) {
      this.currentYear++;
      this.currentMonth = 1;
    } else {
      this.currentMonth++;
    }
    await this.loadAllEvents();
  }

  private async goToday(): Promise<void> {
    const today: Date = new Date();
    const newYear: number = today.getFullYear();
    const newMonth: number = today.getMonth() + 1;
    const newDateStr: string = ScheduleUtils.formatDate(newYear, newMonth, today.getDate());

    if (this.currentYear === newYear && this.currentMonth === newMonth && this.selectedDate === newDateStr) {
      this.loadAllEvents();
      return;
    }

    this.currentYear = newYear;
    this.currentMonth = newMonth;
    this.selectedDate = newDateStr;
    await this.loadAllEvents();
  }

  private selectDate(dateStr: string): void {
    this.selectedDate = dateStr;
    this.updateSelectedEvents();
  }

  private prepareAddEvent(): void {
    this.isEditingExisting = false;
    this.editingEvent = ScheduleUtils.createEmptyEvent();
    const defaultDate = this.selectedDate || ScheduleUtils.formatDate(new Date().getFullYear(), new Date().getMonth() + 1, new Date().getDate());
    this.editingEvent.date = defaultDate;

    this.dialogController = new CustomDialogController({
      builder: () => { this.scheduleAddBuilder(); },
      autoCancel: true,
      alignment: DialogAlignment.Center,
    });
    this.dialogController.open();
  }

  private prepareEditEvent(event: ScheduleEvent): void {
    this.isEditingExisting = true;
    this.editingEvent = {
      id: event.id,
      title: event.title,
      date: event.date,
      timeRange: event.timeRange,
      startTime: event.startTime,
      endTime: event.endTime,
      location: event.location,
      type: event.type,
      color: event.color,
      sourceId: event.sourceId,
      description: event.description,
      createdAt: event.createdAt,
      remindMinutes: event.remindMinutes || 0,
    };

    this.dialogController = new CustomDialogController({
      builder: () => { this.scheduleEditBuilder(); },
      autoCancel: true,
      alignment: DialogAlignment.Center,
    });
    this.dialogController.open();
  }

  private closeDialog(): void {
    if (this.dialogController) {
      this.dialogController.close();
      this.dialogController = null;
    }
  }

  private onSaveSchedule(event: ScheduleEvent): void {
    this.closeDialog();
    this.performSaveSchedule(event);
  }

  private async performSaveSchedule(event: ScheduleEvent): Promise<void> {
    try {
      const context = getContext(this);
      console.info(`[ReminderDebug] CalendarPage.performSaveSchedule: event=${JSON.stringify(event)}`);
      await ScheduleService.saveSchedule(context, event);
      console.info('[ReminderDebug] CalendarPage.performSaveSchedule: schedule saved, refreshing reminders...');
      await ReminderService.refreshScheduleReminders(context);
      console.info('[ReminderDebug] CalendarPage.performSaveSchedule: reminders refreshed');
      await this.loadAllEvents();
    } catch (error) {
      console.error('CalendarPage performSaveSchedule error:', JSON.stringify(error));
    }
  }

  private onDeleteSchedule(eventId: string): void {
    this.closeDialog();
    this.performDeleteSchedule(eventId);
  }

  private async performDeleteSchedule(eventId: string): Promise<void> {
    try {
      const context = getContext(this);
      await ScheduleService.deleteSchedule(context, eventId);
      await this.loadAllEvents();
    } catch (error) {
      console.error('CalendarPage performDeleteSchedule error:', JSON.stringify(error));
    }
  }

  aboutToDisappear(): void {
    this.closeDialog();
    if (this.settingsDialogController) {
      this.settingsDialogController.close();
      this.settingsDialogController = null;
    }
  }

  private closeSettingsPanel(): void {
    if (this.settingsDialogController) {
      this.settingsDialogController.close();
      this.settingsDialogController = null;
    }
  }

  private openSettingsPanel(): void {
    this.settingsDialogController = new CustomDialogController({
      builder: () => { this.scheduleSettingsBuilder(); },
      autoCancel: true,
      alignment: DialogAlignment.Center,
    });
    this.settingsDialogController.open();
  }

  @Builder
  private scheduleSettingsBuilder(): void {
    ScheduleSettingsPanel({
      onDialogClose: () => {
        this.closeSettingsPanel();
      },
    })
  }

  @Builder
  private scheduleAddBuilder(): void {
    ScheduleEditor({
      isEditing: false,
      existingEvent: this.editingEvent,
      onSave: (evt: ScheduleEvent) => {
        this.onSaveSchedule(evt);
      },
      onDelete: (evtId: string) => {
        this.onDeleteSchedule(evtId);
      },
      onDialogClose: () => {
        this.closeDialog();
      },
    })
  }

  @Builder
  private scheduleEditBuilder(): void {
    ScheduleEditor({
      isEditing: true,
      existingEvent: this.editingEvent,
      onSave: (evt: ScheduleEvent) => {
        this.onSaveSchedule(evt);
      },
      onDelete: (evtId: string) => {
        this.onDeleteSchedule(evtId);
      },
      onDialogClose: () => {
        this.closeDialog();
      },
    })
  }

  @Builder
  private eventItemBuilder(event: ScheduleEvent): void {
    Row() {
      Rect()
        .width(4)
        .height(44)
        .fill(event.color)
        .borderRadius(2);

      Column() {
        Text(event.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Row({ space: 8 }) {
          if (event.timeRange) {
            Row({ space: 2 }) {
              Text(event.timeRange)
                .fontSize(11)
                .fontColor(ThemeManager.getTextTertiaryColor());
            }
          }
          if (event.location) {
            Text(event.location)
              .fontSize(11)
              .fontColor(ThemeManager.getTextTertiaryColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          Text(ScheduleUtils.getTypeLabel(event.type))
            .fontSize(10)
            .fontColor(Color.White)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(4)
            .backgroundColor(event.color);
        }
        .margin({ top: 2 });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 });

      if (event.type === 'custom' || event.type === 'assignment') {
        Image($r('app.media.startIcon'))
          .width(28)
          .height(28)
          .fillColor(ThemeManager.getTextTertiaryColor())
          .padding(4)
          .borderRadius(14)
          .backgroundColor(ThemeManager.isDarkMode() ? '#3D3D3D' : '#F0F0F0')
          .onClick(() => this.prepareEditEvent(event));
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor(ThemeManager.getCardColor());
  }

  build() {
    Stack() {
      Column() {
        this.titleBarBuilder();

        this.weekHeaderBuilder();

        this.calendarGridBuilder();

        Divider()
          .strokeWidth(0.5)
          .color(ThemeManager.getBorderColor())
          .margin({ top: 8, bottom: 4 });

        this.eventListSectionBuilder();
      }
      .width('100%')
      .height('100%')

      Button('+')
        .fontSize(26)
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor(ThemeManager.getAccentColor())
        .fontColor(Color.White)
        .shadow({ radius: 10, color: ThemeManager.getShadowColor(), offsetY: 4 })
        .position({ right: 20, bottom: 24 })
        .onClick(() => this.prepareAddEvent());
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor());
  }

  @Builder
  private titleBarBuilder(): void {
    Row() {
      Button('返回')
        .fontSize(14)
        .fontColor(ThemeManager.getAccentColor())
        .backgroundColor('#00000000')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => router.back());

      Image($r('app.media.arrow_left'))
        .width(14)
        .height(12)
        .fillColor(ThemeManager.getTextPrimaryColor())
        .margin({ left: 4, right: -4 })
        .onClick(() => this.prevMonth());

      Text(`${this.currentYear}年 ${this.currentMonth}月`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .layoutWeight(1)
        .textAlign(TextAlign.Center);

      Image($r('app.media.arrow_right'))
        .width(14)
        .height(12)
        .fillColor(ThemeManager.getTextPrimaryColor())
        .margin({ left: -4, right: 4 })
        .onClick(() => this.nextMonth());

      Button('今天')
        .fontSize(12)
        .fontColor(ThemeManager.getAccentColor())
        .backgroundColor(ThemeManager.getAccentBgColor())
        .borderRadius(12)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .onClick(() => this.goToday());

      Image($r('app.media.settings_icon'))
        .width(20)
        .height(20)
        .fillColor(ThemeManager.getTextPrimaryColor())
        .margin({ left: 6 })
        .onClick(() => this.openSettingsPanel());
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 4 });
  }

  @Builder
  private weekHeaderBuilder(): void {
    Row() {
      ForEach(WEEK_HEADERS, (header: string, index: number) => {
        Text(header)
          .width('13.7%')
          .fontSize(12)
          .fontColor(index === 0 || index === 6
            ? ThemeManager.getAccentColor()
            : ThemeManager.getTextTertiaryColor())
          .textAlign(TextAlign.Center);
      });
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 });
  }

  @Builder
  private calendarGridBuilder(): void {
    Grid() {
      ForEach(this.dayGrid, (dayItem: DayInfo) => {
        GridItem() {
          Column() {
            Text(dayItem.day.toString())
              .fontSize(14)
              .fontColor(this.getDayTextColor(dayItem))
              .fontWeight(dayItem.isToday ? FontWeight.Bold : FontWeight.Normal)
              .backgroundColor(dayItem.isToday ? ThemeManager.getAccentColor() : '#00000000')
              .borderRadius(dayItem.isToday ? 12 : 0)
              .width(dayItem.isToday ? 24 : 'auto')
              .height(dayItem.isToday ? 24 : 'auto')
              .textAlign(TextAlign.Center);

            if (dayItem.markers.length > 0) {
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
          .backgroundColor(this.getDayBackground(dayItem))
          .onClick(() => this.selectDate(dayItem.date));
        }
      });
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
    .rowsGap(2)
    .columnsGap(2)
    .width('100%')
    .constraintSize({ maxHeight: 210 })
    .padding({ left: 4, right: 4 });
  }

  @Builder
  private eventListSectionBuilder(): void {
    Column() {
      Row() {
        Text(this.selectedDate)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeManager.getTextPrimaryColor());

        if (this.selectedEvents.length > 0) {
          Text(`  ${this.selectedEvents.length}个日程`)
            .fontSize(12)
            .fontColor(ThemeManager.getTextTertiaryColor());
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 6 });

      if (this.isLoading) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(ThemeManager.getAccentColor())
          .margin({ top: 32 });
      } else if (this.loadingError) {
        Column({ space: 8 }) {
          Text(this.loadingError)
            .fontSize(14)
            .fontColor(ThemeManager.getTextTertiaryColor());
          Button('重试')
            .fontSize(13)
            .fontColor(ThemeManager.getAccentColor())
            .backgroundColor(ThemeManager.getAccentBgColor())
            .borderRadius(8)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .margin({ top: 4 })
            .onClick(() => this.loadAllEvents());
        }
        .margin({ top: 36 });
      } else if (this.selectedEvents.length === 0) {
        Column({ space: 6 }) {
          Text('当天无日程')
            .fontSize(14)
            .fontColor(ThemeManager.getTextTertiaryColor());
          Text('点击右下角 + 按钮添加自定义日程')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .opacity(0.6);
        }
        .margin({ top: 36 });
      } else {
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.selectedEvents, (event: ScheduleEvent, index: number) => {
              Row() {
                Row() {
                  Row()
                    .width(4)
                    .height(44)
                    .backgroundColor(event.color)
                    .borderRadius(2);

                  Column() {
                    Text(event.title)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(ThemeManager.getTextPrimaryColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });

                    Row({ space: 8 }) {
                      if (event.timeRange) {
                        Text(event.timeRange)
                          .fontSize(11)
                          .fontColor(ThemeManager.getTextTertiaryColor());
                      }
                      if (event.location) {
                        Text(event.location)
                          .fontSize(11)
                          .fontColor(ThemeManager.getTextTertiaryColor())
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis });
                      }
                      Text(ScheduleUtils.getTypeLabel(event.type))
                        .fontSize(10)
                        .fontColor(Color.White)
                        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                        .borderRadius(4)
                        .backgroundColor(event.color);
                    }
                    .margin({ top: 2 });
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 });

                  if (event.type === 'custom' || event.type === 'assignment') {
                    Image($r('app.media.startIcon'))
                      .width(28)
                      .height(28)
                      .fillColor(ThemeManager.getTextTertiaryColor())
                      .padding(4)
                      .borderRadius(14)
                      .backgroundColor(ThemeManager.isDarkMode() ? '#3D3D3D' : '#F0F0F0')
                      .onClick(() => this.prepareEditEvent(event));
                  }
                }
                .width('100%')
                .padding(10)
                .borderRadius(10)
                .backgroundColor(ThemeManager.getCardColor());
              }
              .width('100%')
              .onClick(() => {
                this.prepareEditEvent(event);
              });
            }, (event: ScheduleEvent, index: number) => event.id);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 12, top: 4 });
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart);
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start);
  }

  private getDayTextColor(dayItem: DayInfo): string | Color {
    if (dayItem.isToday) {
      return Color.White;
    }
    if (dayItem.isCurrentMonth) {
      return ThemeManager.getTextPrimaryColor();
    }
    return ThemeManager.isDarkMode() ? '#555555' : '#C0C0C0';
  }

  private getDayBackground(dayItem: DayInfo): string {
    if (this.selectedDate === dayItem.date) {
      return ThemeManager.isDarkMode() ? '#1E3A5F' : '#E3F2FD';
    }
    return '#00000000';
  }
}
