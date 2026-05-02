import { router } from '@kit.ArkUI';
import {
  Course,
  CourseTableModel,
  courseTableModel,
  COURSE_COLORS,
  SECTION_TIMES,
  SectionTime,
  WeekDateInfo,
  getCurrentWeek,
  getCurrentDateInfo,
  getWeekDates,
} from '../../model/classTableModel/CourseModel';
import { CourseTableStorage } from '../../model/classTableModel/CourseTableStorage';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { getSemesterOptions, SemesterOptionSet, getSemesterLabelById, calculateSemesterId } from '../../model/classTableModel/ExamAccessRules';
import { CourseRepository } from '../../repository/CourseRepository';

@Entry
@Component
struct TableUI {
  @State currentWeek: number = getCurrentWeek();
  @State selectedDay: number = getCurrentDateInfo().dayOfWeek;
  @State weekDates: WeekDateInfo[] = getWeekDates();
  @State maxWeeks: number = 20;
  @State dataVersion: number = 0;
  @State zoomScale: number = 0.75;
  @State pinchBaseScale: number = 1;
  @State pinchCenterX: number = 0;
  @State pinchCenterY: number = 0;
  @State selectedSemesterId: number = 0;
  @State semesterOptions: SelectOption[] = [];
  @State semesterOptionIds: number[] = [];
  @State hasCourseDataForSemester: boolean = false;
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  @StorageProp('pendingCourseData') pendingCourseData: string = '';
  @StorageProp('pendingCourseSemesterId') pendingCourseSemesterId: number = 0;
  private courseModel: CourseTableModel = courseTableModel;
  private horizontalScroller: Scroller = new Scroller();
  private verticalScroller: Scroller = new Scroller();
  private lastHorizontalOffset: number = 0;
  private lastVerticalOffset: number = 0;
  private hasNavigatedToWebFetch: boolean = false;
  private isInitializing: boolean = false;

  private weekDays: string[] = ['一', '二', '三', '四', '五', '六', '日'];
  private readonly TIME_AXIS_WIDTH: number = 64;
  private readonly DAY_COLUMN_WIDTH: number = 112;
  private readonly DATE_BAR_HEIGHT: number = 60;
  private readonly SECTION_HEIGHT: number = 80;
  private readonly CARD_HORIZONTAL_MARGIN: number = 6;
  private readonly MIN_ZOOM_SCALE: number = 0.75;
  private readonly MAX_ZOOM_SCALE: number = 1.4;
  private readonly TABLE_EDGE_PADDING: number = 20;
  private readonly TABLE_BOTTOM_GAP: number = 68;

  aboutToAppear() {
    this.initSemesterOptions();
    this.tryLoadPendingCourseData();
    this.tryLoadCourseData();
  }

  onPageShow() {
    this.tryLoadPendingCourseData();
  }

  private initSemesterOptions(): void {
    const semesterSet: SemesterOptionSet = getSemesterOptions();
    const filteredOptions: SelectOption[] = [];
    const filteredIds: number[] = [];
    for (let i = 1; i < semesterSet.options.length; i++) {
      filteredOptions.push(semesterSet.options[i]);
      filteredIds.push(semesterSet.semesterIds[i]);
    }
    this.semesterOptions = filteredOptions;
    this.semesterOptionIds = filteredIds;

    const params = router.getParams() as Record<string, string>;
    const routeSemesterId: number = params && params['semesterId'] ? Number(params['semesterId']) : 0;
    if (routeSemesterId > 0) {
      this.selectedSemesterId = routeSemesterId;
    } else {
      this.selectedSemesterId = calculateSemesterId();
    }
  }

  private tryLoadPendingCourseData(): void {
    if (this.pendingCourseData.length > 0 && this.pendingCourseSemesterId > 0) {
      this.selectedSemesterId = this.pendingCourseSemesterId;
      this.applyCourseData(this.pendingCourseData);
      this.saveCourseDataToLocal(this.pendingCourseData);
      this.hasCourseDataForSemester = true;
      this.pendingCourseData = '';
      this.pendingCourseSemesterId = 0;
    }
  }

  private async tryLoadCourseData(): Promise<void> {
    if (this.isInitializing) {
      return;
    }
    this.isInitializing = true;

    try {
      const context = getContext(this);
      const semesterData: string = await CourseRepository.loadCourseDataBySemester(context, this.selectedSemesterId);
      if (semesterData) {
        this.applyCourseData(semesterData);
        this.hasCourseDataForSemester = true;
        return;
      }

      const localData: string = await CourseTableStorage.loadCourseData(context);
      if (localData) {
        this.applyCourseData(localData);
        this.hasCourseDataForSemester = true;
        return;
      }

      this.courseModel.clear();
      this.dataVersion++;
      this.hasCourseDataForSemester = false;
      this.navigateToWebFetchPage();
    } catch (error) {
      console.error('加载课表本地数据失败:', error);
      this.navigateToWebFetchPage();
    } finally {
      this.isInitializing = false;
    }
  }

  private applyCourseData(courseData: string): void {
    this.courseModel.loadFromJson(courseData);
    this.maxWeeks = this.courseModel.getMaxWeekNumber();
    if (this.currentWeek > this.maxWeeks) {
      this.currentWeek = this.maxWeeks;
    }
    if (this.currentWeek < 1) {
      this.currentWeek = 1;
    }
    this.dataVersion++;
  }

  private async saveCourseDataToLocal(courseData: string): Promise<void> {
    try {
      const context = getContext(this);
      await CourseRepository.saveCourseDataBySemester(context, this.selectedSemesterId, courseData);
    } catch (error) {
      console.error('保存课表本地数据失败:', error);
    }
  }

  private navigateToWebFetchPage(): void {
    if (this.hasNavigatedToWebFetch) {
      return;
    }
    this.hasNavigatedToWebFetch = true;
    router.pushUrl({
      url: 'pages/classTablePages/Index',
      params: {
        semesterId: String(this.selectedSemesterId)
      }
    }).catch((error: Error) => {
      console.error('跳转网页抓取页失败:', error);
    });
  }

  private getSelectedSemesterIndex(): number {
    const index: number = this.semesterOptionIds.indexOf(this.selectedSemesterId);
    return index >= 0 ? index : 0;
  }

  private getSelectedSemesterLabel(): string {
    return getSemesterLabelById(this.selectedSemesterId);
  }

  private async onSemesterChange(index: number): Promise<void> {
    this.selectedSemesterId = this.semesterOptionIds[index];
    this.courseModel.clear();
    this.dataVersion++;
    const context = getContext(this);
    const data: string = await CourseRepository.loadCourseDataBySemester(context, this.selectedSemesterId);
    if (data) {
      this.applyCourseData(data);
      this.hasCourseDataForSemester = true;
    } else {
      this.hasCourseDataForSemester = false;
    }
  }

  private refreshFromWeb(): void {
    router.pushUrl({
      url: 'pages/classTablePages/Index',
      params: {
        semesterId: String(this.selectedSemesterId)
      }
    }).catch((error: Error) => {
      console.error('跳转网页刷新页失败:', error);
    });
  }

  build() {
    Column() {
      this.HeaderBuilder()
      this.CourseTableBuilder()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getCardColor())
  }

  @Builder
  HeaderBuilder() {
    Column() {
      Row() {
        Select(this.semesterOptions)
          .selected(this.getSelectedSemesterIndex())
          .value(this.getSelectedSemesterLabel())
          .font({ size: 13, weight: FontWeight.Bold })
          .fontColor(ThemeManager.getTextPrimaryColor())
          .height(30)
          .backgroundColor(Color.Transparent)
          .onSelect((index: number) => {
            this.onSemesterChange(index);
          })

        Select(this.getWeekSelectOptions())
          .selected(this.currentWeek - 1)
          .value(`第${this.currentWeek}周`)
          .font({ size: 13, weight: FontWeight.Bold })
          .fontColor(ThemeManager.getTextPrimaryColor())
          .height(30)
          .backgroundColor(Color.Transparent)
          .onSelect((index: number) => {
            this.currentWeek = index + 1;
            this.updateWeekDates();
          })

        Blank()

        Image($r('app.media.refresh'))
          .width(20)
          .height(20)
          .padding(1)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.refreshFromWeb();
          })
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12, top: 4, bottom: 2 })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)

      Row() {
        Text(this.getTodayTimeText())
          .fontSize(11)
          .fontColor(ThemeManager.getTextTertiaryColor())

        Blank()

        Text(`${Math.round(this.zoomScale * 100)}%`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#4CAF50')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(12)

        if (this.weekDates && this.weekDates.length > 0) {
          Text(`${this.weekDates[0].month}月${this.weekDates[0].date}日-${this.weekDates[6].month}月${this.weekDates[6].date}日`)
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .lineHeight(14)
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .height(22)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      if (!this.hasCourseDataForSemester) {
        Text('该学期暂无课表数据，请点击刷新按钮导入')
          .fontSize(12)
          .fontColor(ThemeManager.getTextTertiaryColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 2, bottom: 2 })
      }
    }
    .width('100%')
    .backgroundColor(ThemeManager.getCardColor())
    .border({ width: { bottom: 1 }, color: ThemeManager.getBorderColor() })
  }

  private getWeekSelectOptions(): Array<SelectOption> {
    const options: Array<SelectOption> = [];
    for (let i = 1; i <= this.maxWeeks; i++) {
      const option: SelectOption = { value: `第${i}周` };
      options.push(option);
    }
    return options;
  }

  private getTodayTimeText(): string {
    const now = new Date();
    const weekIndex = now.getDay() === 0 ? 6 : now.getDay() - 1;
    const hour = now.getHours().toString().padStart(2, '0');
    const minute = now.getMinutes().toString().padStart(2, '0');
    return `${now.getMonth() + 1}月${now.getDate()}日 周${this.weekDays[weekIndex]} ${hour}:${minute}`;
  }

  @Builder
  WeekSelectorBuilder() {
    Row() {
      Text('')
    }
    .width(0)
    .height(0)
  }

  private updateWeekDates(): void {
  }

  @Builder
  DateBarBuilder() {
    Row() {
      ForEach(this.weekDays, (day: string, index: number) => {
        Column() {
          Text(`周${day}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .lineHeight(16)

          Text(`${this.weekDates[index].date}`)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedDay === index + 1 ? '#FFFFFF' : ThemeManager.getTextPrimaryColor())
            .width(this.getScaledDateBubbleSize())
            .height(this.getScaledDateBubbleSize())
            .textAlign(TextAlign.Center)
            .lineHeight(this.getScaledDateBubbleSize())
            .backgroundColor(this.selectedDay === index + 1 ? '#4CAF50' : Color.Transparent)
            .borderRadius(this.getScaledDateBubbleSize() / 2)
            .margin({ top: 4 })
        }
        .width(this.getScaledDayColumnWidth())
        .height(this.getScaledDateBarHeight())
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .border({ width: { right: 1, bottom: 1 }, color: ThemeManager.getBorderColor() })
        .onClick(() => {
          this.selectedDay = index + 1;
        })
      })
    }
    .width(this.getCourseAreaWidth())
    .height(this.getScaledDateBarHeight())
    .backgroundColor(ThemeManager.getCardColor())
  }

  @Builder
  TimeCornerBuilder() {
    Column() {
      Text('时间')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextTertiaryColor())
    }
    .width(this.getScaledTimeAxisWidth())
    .height(this.getScaledDateBarHeight())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .border({ width: { right: 1, bottom: 1 }, color: ThemeManager.getBorderColor() })
    .backgroundColor(ThemeManager.getCardColor())
  }

  @Builder
  CourseTableBuilder() {
    Scroll(this.verticalScroller) {
      Row({ space: 0 }) {
        Column() {
          this.TimeCornerBuilder()
          this.TimeAxisBuilder()
        }
        .width(this.getScaledTimeAxisWidth())

        Scroll(this.horizontalScroller) {
          Column() {
            this.DateBarBuilder()
            this.CourseGridBuilder()
          }
          .padding({ left: this.TABLE_EDGE_PADDING, right: this.TABLE_EDGE_PADDING })
        }
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .scrollable(ScrollDirection.Horizontal)
        .onDidScroll((xOffset: number) => {
          this.lastHorizontalOffset = xOffset;
        })
        .nestedScroll({
          scrollForward: NestedScrollMode.PARALLEL,
          scrollBackward: NestedScrollMode.PARALLEL
        })
        .width('100%')
      }
      .width('100%')
      .padding({ left: this.TABLE_EDGE_PADDING, right: this.TABLE_EDGE_PADDING, bottom: 8 })
      .backgroundColor(ThemeManager.getCardColor())
    }
    .gesture(
      PinchGesture({ fingers: 2 })
        .onActionStart((event: PinchGestureEvent) => {
          this.pinchBaseScale = this.zoomScale;
          this.pinchCenterX = event.pinchCenterX;
          this.pinchCenterY = event.pinchCenterY;
        })
        .onActionUpdate((event: PinchGestureEvent) => {
          const nextScale: number = this.clampZoom(this.pinchBaseScale * event.scale);
          this.applyZoomKeepingCenter(nextScale, this.pinchCenterX, this.pinchCenterY);
        })
    )
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .scrollable(ScrollDirection.Vertical)
    .onDidScroll((_xOffset: number, yOffset: number) => {
      this.lastVerticalOffset = yOffset;
    })
    .nestedScroll({
      scrollForward: NestedScrollMode.PARALLEL,
      scrollBackward: NestedScrollMode.PARALLEL
    })
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  TimeAxisBuilder() {
    Column() {
      ForEach(SECTION_TIMES, (timeInfo: SectionTime, index: number) => {
        Column() {
          Text(`${timeInfo.section}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .lineHeight(18)

          Text(`${timeInfo.startTime}`)
            .fontSize(10)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .margin({ top: 2 })
            .lineHeight(13)

          Text(`${timeInfo.endTime}`)
            .fontSize(10)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .lineHeight(13)
        }
        .width(this.getScaledTimeAxisWidth())
        .height(this.getScaledSectionHeight())
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .border({
          width: {
            bottom: 1,
            right: 1
          },
          color: ThemeManager.getBorderColor()
        })
      })

      Blank()
        .width(this.getScaledTimeAxisWidth())
        .height(this.TABLE_BOTTOM_GAP)
    }
    .width(this.getScaledTimeAxisWidth())
    .height(this.getTableHeight())
    .backgroundColor(ThemeManager.getCardColor())
  }

  private dayNumbers: number[] = [1, 2, 3, 4, 5, 6, 7];

  @Builder
  CourseGridBuilder() {
    Row() {
      ForEach(this.dayNumbers, (dayOfWeek: number) => {
        this.DayColumnBuilder(dayOfWeek)
      }, (dayOfWeek: number) => `${dayOfWeek}_${this.dataVersion}`)
    }
    .width(this.getCourseAreaWidth())
    .height(this.getTableHeight())
    .backgroundColor(ThemeManager.getCardColor())
  }

  private sectionNumbers: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

  @Builder
  DayColumnBuilder(dayOfWeek: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach(this.sectionNumbers, (section: number) => {
          Row()
            .width('100%')
            .height(this.getScaledSectionHeight())
            .border({ width: { bottom: 1, right: 1 }, color: ThemeManager.getBorderColor() })
        })

        Blank()
          .width('100%')
          .height(this.TABLE_BOTTOM_GAP)
      }
      .width('100%')
      .height('100%')

      Column() {
        ForEach(this.courseModel.getCoursesForDayAndWeek(dayOfWeek, this.currentWeek), (course: Course) => {
          this.CourseCardBuilder(course)
        }, (course: Course) =>
          [
            this.dataVersion,
            course.id,
            course.time.dayOfWeek,
            course.time.startSection,
            course.roomName,
            course.validWeeks,
            course.teacherName,
          ].join('_')
        )
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.getScaledDayColumnWidth())
    .height(this.getTableHeight())
  }

  @Builder
  CourseCardBuilder(course: Course) {
    Column() {
      Text(this.extractCourseName(course.name))
        .fontSize(course.time.duration >= 3 ? 14 : 13)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .maxLines(this.getTitleMaxLines(course.time.duration))
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
        .lineHeight(course.time.duration >= 3 ? 18 : 16)

      if (course.roomName) {
        Text(`@${course.roomName}`)
          .fontSize(11)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .margin({ top: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(14)
          .width('100%')
      }

      if (course.teacherName) {
        Text(course.teacherName)
          .fontSize(11)
          .fontColor(ThemeManager.getTextTertiaryColor())
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(14)
          .width('100%')
      }
    }
    .width(this.getScaledDayColumnWidth() - this.CARD_HORIZONTAL_MARGIN * 2)
    .height(course.time.duration * this.getScaledSectionHeight() - 8)
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(COURSE_COLORS[course.colorIndex % COURSE_COLORS.length])
    .borderRadius(10)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .position({
      x: this.CARD_HORIZONTAL_MARGIN,
      y: (course.time.startSection - 1) * this.getScaledSectionHeight() + 4
    })
  }

  private clampZoom(nextScale: number): number {
    return Math.max(this.MIN_ZOOM_SCALE, Math.min(this.MAX_ZOOM_SCALE, nextScale));
  }

  private applyZoomKeepingCenter(nextScale: number, centerX: number, centerY: number): void {
    const prevScale: number = this.zoomScale;
    if (Math.abs(prevScale - nextScale) < 0.001) {
      return;
    }

    const scaleRatio: number = nextScale / prevScale;
    const targetX: number = (this.lastHorizontalOffset + centerX) * scaleRatio - centerX;
    const targetY: number = (this.lastVerticalOffset + centerY) * scaleRatio - centerY;

    this.zoomScale = nextScale;
    this.syncScrollAfterZoom(targetX, targetY);
  }

  private syncScrollAfterZoom(targetX: number, targetY: number): void {
    this.lastHorizontalOffset = Math.max(0, targetX);
    this.lastVerticalOffset = Math.max(0, targetY);

    this.horizontalScroller.scrollTo({
      xOffset: this.lastHorizontalOffset,
      yOffset: 0,
      animation: { duration: 0 }
    });

    this.verticalScroller.scrollTo({
      xOffset: 0,
      yOffset: this.lastVerticalOffset,
      animation: { duration: 0 }
    });
  }

  private getScaledTimeAxisWidth(): number {
    return Math.round(this.TIME_AXIS_WIDTH * this.zoomScale);
  }

  private getScaledDayColumnWidth(): number {
    return Math.round(this.DAY_COLUMN_WIDTH * this.zoomScale);
  }

  private getScaledDateBarHeight(): number {
    return Math.round(this.DATE_BAR_HEIGHT * this.zoomScale);
  }

  private getScaledDateBubbleSize(): number {
    return Math.round(34 * this.zoomScale);
  }

  private getScaledSectionHeight(): number {
    return Math.round(this.SECTION_HEIGHT * this.zoomScale);
  }

  private getCourseAreaWidth(): number {
    return this.getScaledDayColumnWidth() * this.dayNumbers.length;
  }

  private getTableHeight(): number {
    return this.getScaledSectionHeight() * this.sectionNumbers.length + this.TABLE_BOTTOM_GAP;
  }

  private getTitleMaxLines(duration: number): number {
    if (duration >= 4) {
      return 4;
    }
    if (duration >= 2) {
      return 3;
    }
    return 2;
  }

  private extractCourseName(fullName: string): string {
    if (!fullName) return '';
    return fullName.replace(/\([^)]*\)/g, '').trim();
  }
}
