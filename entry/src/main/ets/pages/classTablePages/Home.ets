import { router, curves } from '@kit.ArkUI';
import {
  Course,
  CourseTableModel,
  SECTION_TIMES,
  courseTableModel,
  getCurrentWeek,
} from '../../model/classTableModel/CourseModel';
import { AppSettings, CourseTableStorage } from '../../model/classTableModel/CourseTableStorage';
import { ExamItem, formatCountDown, normalizeExam, sortExams } from '../../model/classTableModel/ExamModel';
import {
  calculateSemesterId,
  EXAM_TYPE_OPTIONS,
  getExamTypeIdByIndex,
  getExamTypeIndexById,
  getExamTypeLabelById,
} from '../../model/classTableModel/ExamAccessRules';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { CourseRepository } from '../../repository/CourseRepository';
import { ReminderService } from '../../service/ReminderService';

@Entry
@Component
struct Home {
  @State currentWeek: number = getCurrentWeek();
  @State hasData: boolean = false;
  @State todayCourses: Course[] = [];
  @State tomorrowCourses: Course[] = [];
  @State settings: AppSettings = {
    themeDark: false,
    showToday: true,
    showTomorrow: true,
    showExamCountdown: true,
    examRemindMinutes: 30,
    courseRemindMinutes: 30,
  };
  @State exams: ExamItem[] = [];
  @State pageReady: boolean = false;
  @State selectedExamTypeIndex: number = 0;
  @State selectedSemesterId: number = 0;
  private model: CourseTableModel = courseTableModel;

  private normalizeExamTypeIndex(index: number): number {
    if (index < 0 || index >= EXAM_TYPE_OPTIONS.length) {
      return 0;
    }
    return index;
  }

  aboutToAppear(): void {
    this.pageReady = false;
    this.loadPageData();
    setTimeout(() => {
      animateTo({ curve: curves.springMotion(0.6, 0.8) }, () => {
        this.pageReady = true;
      });
    }, 40);
  }

  onPageShow(): void {
    this.loadPageData();
    ReminderService.refreshAllReminders(getContext(this));
  }

  private async loadPageData(): Promise<void> {
    try {
      const context = getContext(this);
      this.settings = await CourseTableStorage.loadSettings(context);
      ThemeManager.setDarkMode(this.settings.themeDark);

      const localData: string = await CourseRepository.loadCourseData(context);
      const examData: string = await CourseTableStorage.loadExamData(context);
      const examSelection = await CourseTableStorage.loadExamSelectionPreference(context);
      this.selectedExamTypeIndex = this.normalizeExamTypeIndex(getExamTypeIndexById(examSelection.examTypeId));
      this.selectedSemesterId = examSelection.semesterId;

      if (examData) {
        try {
          const parsedExam: ExamItem[] = JSON.parse(examData) as ExamItem[];
          this.exams = sortExams(parsedExam.map((item: ExamItem) => normalizeExam({
            courseNo: item.courseNo,
            courseName: item.courseName,
            examDate: item.examDate,
            examTimeRange: item.examTimeRange,
            examLocation: item.examLocation,
            seatNo: item.seatNo,
            examStatus: item.examStatus,
            examType: item.examType,
            remark: item.remark,
            semesterId: item.semesterId,
            semesterLabel: item.semesterLabel,
            beginTime: item.beginTime,
            endTime: item.endTime,
          })));
        } catch (error) {
          this.exams = [];
        }
      } else {
        this.exams = [];
      }

      if (!localData) {
        this.hasData = false;
        this.todayCourses = [];
        this.tomorrowCourses = [];
        return;
      }

      this.hasData = true;
      this.model.loadFromJson(localData);

      const maxWeek: number = this.model.getMaxWeekNumber();
      if (this.currentWeek > maxWeek) {
        this.currentWeek = maxWeek;
      }
      if (this.currentWeek < 1) {
        this.currentWeek = 1;
      }

      const today = new Date();
      const todayDay: number = today.getDay() || 7;
      const tomorrowDay: number = todayDay === 7 ? 1 : todayDay + 1;
      const tomorrowWeek: number = todayDay === 7 ? this.currentWeek + 1 : this.currentWeek;

      this.todayCourses = this.sortBySection(this.model.getCoursesForDayAndWeek(todayDay, this.currentWeek));
      this.tomorrowCourses = this.sortBySection(this.model.getCoursesForDayAndWeek(tomorrowDay, tomorrowWeek));

      if (this.hasData) {
        ReminderService.refreshAllReminders(context);
      }
    } catch (error) {
      console.error('Home加载数据失败:', error);
      this.hasData = false;
    }
  }

  private sortBySection(courses: Course[]): Course[] {
    const copied: Course[] = [...courses];
    copied.sort((a, b) => a.time.startSection - b.time.startSection);
    return copied;
  }

  private openImporter(): void {
    router.pushUrl({
      url: 'pages/classTablePages/Index',
      params: {
        returnHome: '1',
        semesterId: String(calculateSemesterId())
      }
    }).catch((error: Error) => {
      console.error('跳转导入页面失败:', error);
    });
  }

  private openTable(): void {
    router.pushUrl({ url: 'pages/classTablePages/tableUI' }).catch((error: Error) => {
      console.error('跳转课表页面失败:', error);
    });
  }

  private openExamImport(): void {
    const semesterId: number = this.selectedSemesterId > 0 ? this.selectedSemesterId : calculateSemesterId();
    router.pushUrl({
      url: 'pages/classTablePages/ExamImport',
      params: {
        returnHome: '1',
        examTypeId: String(this.getSelectedExamTypeId()),
        semesterId: String(semesterId)
      }
    }).catch((error: Error) => {
      console.error('跳转考试导入失败:', error);
    });
  }

  private openExamPage(): void {
    router.pushUrl({
      url: 'pages/classTablePages/ExamPage',
      params: {
        examTypeId: String(this.getSelectedExamTypeId()),
        semesterId: String(this.selectedSemesterId)
      }
    }).catch((error: Error) => {
      console.error('跳转考试页面失败:', error);
    });
  }

  private openSchedule(): void {
    router.pushUrl({ url: 'pages/schedulePages/CalendarPage' }).catch((error: Error) => {
      console.error('跳转日程页面失败:', error);
    });
  }

  private saveExamSelectionPreference(): void {
    const examTypeId: number = this.getSelectedExamTypeId();
    const semesterId: number = this.selectedSemesterId;
    CourseTableStorage.saveExamSelectionPreference(getContext(this), {
      examTypeId: examTypeId,
      semesterId: semesterId,
    }).catch((error: Error) => {
      console.error('保存考试筛选偏好失败', error);
    });
  }

  private openSettings(): void {
    router.pushUrl({ url: 'pages/classTablePages/Settings' }).catch((error: Error) => {
      console.error('跳转设置页面失败:', error);
    });
  }

  private formatCourseTime(course: Course): string {
    const startSection: number = course.time.startSection;
    const endSection: number = startSection + course.time.duration - 1;
    const startTime: string = SECTION_TIMES[startSection - 1].startTime;
    const endTime: string = SECTION_TIMES[endSection - 1].endTime;
    return `${startSection}-${endSection}节 ${startTime}-${endTime}`;
  }

  private getNextExam(): ExamItem | undefined {
    const now: number = Date.now();
    return this.exams.find((item: ExamItem) => {
      if (item.beginTime <= now) {
        return false;
      }
      return true;
    });
  }

  private getSelectedExamTypeId(): number {
    return getExamTypeIdByIndex(this.selectedExamTypeIndex);
  }

  private getSelectedExamTypeLabel(): string {
    return getExamTypeLabelById(this.getSelectedExamTypeId());
  }

  private getHeroHint(): string {
    if (!this.hasData) {
      return '尚未导入课表，先完成一次在线导入吧';
    }
    const nextExam: ExamItem | undefined = this.getNextExam();
    if (nextExam && this.settings.showExamCountdown) {
      return `最近考试：${nextExam.courseName}`;
    }
    return `今日课程 ${this.todayCourses.length} 门，明日课程 ${this.tomorrowCourses.length} 门`;
  }

  @Builder
  private HeroBuilder(): void {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('Classtable')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF');

          Text(`${this.currentWeek}周`)
            .fontSize(13)
            .fontColor('#DCE8FF');
        }
        .alignItems(HorizontalAlign.Start);

        Blank();

        Button('设置')
          .height(32)
          .fontSize(13)
          .fontColor('#2F6DFF')
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .onClick(() => this.openSettings());
      }
      .width('100%');

      Text(this.getHeroHint())
        .fontSize(13)
        .fontColor('#E8F0FF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');

      Row({ space: 8 }) {
        Button('课表详情')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#2F6DFF')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .height(42)
          .layoutWeight(1)
          .onClick(() => this.openTable());

        Button('考试详情')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor('rgba(255,255,255,0.20)')
          .borderRadius(12)
          .height(42)
          .layoutWeight(1)
          .onClick(() => this.openExamPage());

        Button('日程')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor('rgba(255,255,255,0.20)')
          .borderRadius(12)
          .height(42)
          .layoutWeight(1)
          .onClick(() => this.openSchedule());
      }
      .width('100%');
    }
    .width('100%')
    .padding(16)
    .borderRadius(24)
    .backgroundColor(ThemeManager.getHeroPanelColor())
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.05)', offsetY: 4 });
  }

  @Builder
  private EmptyStateBuilder(): void {
    Column({ space: 12 }) {
      Text('当前没有课表数据')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextPrimaryColor());

      Text('先导入一次课表，首页会自动展示今日课程和考试倒计时')
        .fontSize(13)
        .fontColor(ThemeManager.getTextSecondaryColor())
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .width('100%');

      Button('前往在线导入')
        .height(40)
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor(ThemeManager.getAccentColor())
        .borderRadius(20)
        .onClick(() => this.openImporter());
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
    .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.04)', offsetY: 4 })
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  private CourseListBuilder(title: string, courses: Course[]): void {
    Column() {
      Row() {
        Text(title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor());

        Blank();

        Text(`${courses.length}门`)
          .fontSize(12)
          .fontColor(ThemeManager.getAccentColor())
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(12);
      }
      .width('100%')
      .margin({ bottom: 8 });

      if (courses.length === 0) {
        Text('暂无课程')
          .fontSize(14)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor(ThemeManager.getCardColor());
      } else {
        ForEach(courses, (course: Course) => {
          Row({ space: 10 }) {
            Column()
              .width(4)
              .height(50)
              .borderRadius(3)
              .backgroundColor(ThemeManager.getAccentColor());

            Column({ space: 3 }) {
              Text(course.name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeManager.getTextPrimaryColor())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });

              Text(this.formatCourseTime(course))
                .fontSize(12)
                .fontColor(ThemeManager.getTextSecondaryColor())
                .width('100%');

              Text(`${course.roomName || '地点未知'} · ${course.teacherName || '教师未知'}`)
                .fontSize(12)
                .fontColor(ThemeManager.getTextSecondaryColor())
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .padding(12)
          .margin({ bottom: 8 })
          .borderRadius(12)
          .backgroundColor(ThemeManager.getCardColor());
        });
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(20)
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
    .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.04)', offsetY: 4 });
  }

  @Builder
  private ExamCardBuilder(): void {
    Column() {
      Row() {
        Text('最近考试倒计时')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor());
        Blank();
        Button('详情')
          .height(30)
          .fontSize(12)
          .fontColor(ThemeManager.getAccentColor())
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(12)
          .onClick(() => this.openExamPage());
      }
      .width('100%')
      .margin({ bottom: 8 });

      Text(this.getNextExam()?.courseName ?? '')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .width('100%');

      Text(`${this.getNextExam()?.examDate ?? ''} ${this.getNextExam()?.examTimeRange ?? ''}`)
        .fontSize(12)
        .fontColor(ThemeManager.getTextSecondaryColor())
        .width('100%')
        .margin({ top: 3 });

      Text(formatCountDown(Date.now(), this.getNextExam()?.beginTime ?? 0))
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getAccentColor())
        .width('100%')
        .margin({ top: 8 });
    }
    .width('100%')
    .padding(12)
    .borderRadius(20)
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
    .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.04)', offsetY: 4 });
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          this.HeroBuilder();

          if (!this.hasData) {
            this.EmptyStateBuilder();
          } else {
            if (this.settings.showExamCountdown && this.getNextExam()) {
              this.ExamCardBuilder();
            }
            if (this.settings.showToday) {
              this.CourseListBuilder('今日课程', this.todayCourses);
            }
            if (this.settings.showTomorrow) {
              this.CourseListBuilder('明日课程', this.tomorrowCourses);
            }
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 16 })
        .opacity(this.pageReady ? 1 : 0);
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundColor());
  }
}
