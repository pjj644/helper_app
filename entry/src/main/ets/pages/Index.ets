import { router, curves, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AssistantPage } from '../pages/quick/AssistantPage';
import { CalendarPage } from '../pages/schedulePages/CalendarPage';
import {
  Course,
  CourseTableModel,
  SECTION_TIMES,
  courseTableModel,
  getCurrentWeek,
} from '../model/classTableModel/CourseModel';
import { DisplaySettings, CourseTableStorage } from '../model/classTableModel/CourseTableStorage';
import { ExamItem, normalizeExam, sortExams } from '../model/classTableModel/ExamModel';
import { CountdownCard } from '../components/CountdownCard';
import {
  calculateSemesterId,
  EXAM_TYPE_OPTIONS,
  getExamTypeIdByIndex,
  getExamTypeIndexById,
  getExamTypeLabelById,
} from '../model/classTableModel/ExamAccessRules';
import { CourseRepository } from '../repository/CourseRepository';
import { ReminderService } from '../service/ReminderService';
import { AppConstants, RouterConstants } from '../common/constants/AppConstants';
import { ImmersiveLightWrapper } from '../common/ImmersiveLightWrapper';
import { UISettings } from '../common/UISettings';
import { QuickStatComponent } from '../components/QuickStatComponent';
import { AnimatedCard, AnimatedListItem } from '../components/AnimatedComponents';
import { ToastComponent } from '../components/ToastComponents';
import { ServiceItem } from '../common/types/ModelTypes';
import { GradeService } from '../service/GradeService';
import { ScheduleService } from '../service/ScheduleService';
import { AuthService } from '../service/AuthService';

interface ToolItem {
  title: string;
  icon: string;
  color: string;
  route?: string;
  url?: string;
  iconImage?: Resource;
}

@Entry
@Component
struct MainPage {
  @State currentTabIndex: number = 2;
  @State currentWeek: number = getCurrentWeek();
  @State hasData: boolean = false;
  @State todayCourses: Course[] = [];
  @State tomorrowCourses: Course[] = [];
  @State settings: DisplaySettings = {
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
  @State nowTick: number = Date.now();
  @StorageProp('app_theme_dark') isDarkMode: boolean = false;
  @State customBackgroundImage: string = '';
  @State customBackgroundEnabled: boolean = false;
  @State latestGpa: string = '--';
  @State todayEventCount: number = 0;
  @State toastMessage: string = '';
  @State toastVisible: boolean = false;
  @State isLoggedIn: boolean = false;
  @State loginEmail: string = '';
  @State showExamInfoCard: boolean = false;

  private tickTimer: number = -1;
  private model: CourseTableModel = courseTableModel;
  private appSettings: UISettings = UISettings.getInstance();
  // 记录“无未来考试”日志的上次 breakdown，避免 tick 每 5s 重复打印同一条
  private lastNoFutureExamKey: string = '';

  private tools: ToolItem[] = [
    { title: 'AI 助手', icon: '🤖', color: '#6366F1', route: 'pages/quick/AssistantPage', iconImage: $r('app.media.ic_ai_assistant') },
    { title: '校园地图', icon: '🗺️', color: '#3B82FF', url: AppConstants.GIS_MAP_URL, iconImage: $r('app.media.ic_campus_map') },
    { title: '图书馆', icon: '📚', color: '#10B981', url: AppConstants.LIB_FULL_URL },
    { title: '校园卡', icon: '💳', color: '#F59E0B' },
    { title: '计算器', icon: '🧮', color: '#EF4444' },
    { title: '天气', icon: '🌤️', color: '#8B5CF6' },
    { title: '成绩查询', icon: '📊', color: '#EC4899', route: 'pages/gradePages/GradePage' },
    { title: '空教室', icon: '🏫', color: '#06B6D4' },
    { title: '校园日历', icon: '📅', color: '#84CC16', route: 'pages/schedulePages/CalendarPage' },
    { title: '清水河畔', icon: '🌊', color: '#0EA5E9', url: AppConstants.QINGSHUI_RIVER_URL, iconImage: $r('app.media.ic_qingshui_river') },
    { title: '一卡通余额', icon: '💰', color: '#F97316', url: AppConstants.CARD_BALANCE_URL, iconImage: $r('app.media.ic_card_balance') },
  ];

  private normalizeExamTypeIndex(index: number): number {
    if (index < 0 || index >= EXAM_TYPE_OPTIONS.length) {
      return 0;
    }
    return index;
  }

  aboutToAppear(): void {
    this.pageReady = false;
    this.customBackgroundImage = this.appSettings.customBackgroundImage;
    this.customBackgroundEnabled = this.appSettings.customBackgroundEnabled;
    this.loadPageData();
    this.loadQuickInfo();
    this.checkLoginStatus();
    this.nowTick = Date.now();
    console.info(`[HomeDebug] aboutToAppear: nowTick=${this.nowTick} exams=${this.exams.length}`);
    this.tickTimer = setInterval(() => {
      const prev = this.nowTick;
      this.nowTick = Date.now();
      if (Math.floor(this.nowTick / 1000) % 5 === 0) {
        const nextExam = this.getNextExam();
        console.info(`[HomeDebug] tick: nowTick=${this.nowTick} delta=${this.nowTick - prev}ms nextExam=${nextExam?.courseName ?? 'none'} beginTime=${nextExam?.beginTime ?? 0} remaining=${nextExam ? Math.floor((nextExam.beginTime - this.nowTick) / 1000) : -1}s examsTotal=${this.exams.length}`);
      }
    }, 1000);
    console.info(`[HomeDebug] tickTimer started: id=${this.tickTimer}`);
    setTimeout(() => {
      animateTo({ curve: curves.springMotion(0.6, 0.8) }, () => {
        this.pageReady = true;
      });
    }, 40);
  }

  aboutToDisappear(): void {
    console.info(`[HomeDebug] aboutToDisappear: tickTimer=${this.tickTimer}`);
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  onPageShow(): void {
    console.info(`[HomeDebug] onPageShow: exams=${this.exams.length} nowTick=${this.nowTick}`);
    this.loadPageData();
    this.loadQuickInfo();
    this.checkLoginStatus();
    ReminderService.refreshAllReminders(getContext(this));
  }

  private async loadPageData(): Promise<void> {
    try {
      const context = getContext(this);
      this.settings = await CourseTableStorage.loadSettings(context);

      const localData: string = await CourseRepository.loadCourseData(context);
      const examData: string = await CourseTableStorage.loadExamData(context);
      const examSelection = await CourseTableStorage.loadExamSelectionPreference(context);
      this.selectedExamTypeIndex = this.normalizeExamTypeIndex(getExamTypeIndexById(examSelection.examTypeId));
      this.selectedSemesterId = examSelection.semesterId;

      if (examData) {
        try {
          const parsedExam: ExamItem[] = JSON.parse(examData) as ExamItem[];
          console.info(`[ExamDebug] Home: examData length=${examData.length} parsed=${parsedExam.length}`);
          this.exams = sortExams(parsedExam.map((item: ExamItem): ExamItem => normalizeExam({
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
          const now = Date.now();
          let futureCount = 0;
          for (let i = 0; i < this.exams.length; i++) {
            if (this.exams[i].beginTime > now) {
              futureCount++;
            }
            if (i < 3) {
              console.info(`[ExamDebug] Home: exam[${i}] name=${this.exams[i].courseName} date=${this.exams[i].examDate} timeRange=${this.exams[i].examTimeRange} beginTime=${this.exams[i].beginTime} endTime=${this.exams[i].endTime}`);
            }
          }
          console.info(`[ExamDebug] Home: total=${this.exams.length} futureCount=${futureCount} now=${now}`);
        } catch (error) {
          console.error('[ExamDebug] Home: parse exam error', JSON.stringify(error));
          this.exams = [];
        }
      } else {
        console.info('[ExamDebug] Home: examData is empty/null, no exams stored');
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

      const upcoming = this.getUpcomingExams(1);
      console.info(`[ExamDebug] Home: loadPageData done hasData=${this.hasData} showExamCountdown=${this.settings.showExamCountdown} upcomingCount=${upcoming.length} examTotal=${this.exams.length}`);
    } catch (error) {
      console.error('[ExamDebug] Home加载数据失败:', JSON.stringify(error));
      this.hasData = false;
    }
  }

  private async loadQuickInfo(): Promise<void> {
    try {
      const context = getContext(this);
      const grades = await GradeService.loadGrades(context);
      if (grades.length > 0) {
        const gpa: number = GradeService.getLatestSemesterGPA(grades);
        this.latestGpa = gpa > 0 ? gpa.toFixed(2) : '--';
      } else {
        this.latestGpa = '--';
      }

      const events = await ScheduleService.getAllEvents(context);
      const today = new Date();
      const todayStr: string = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
      let count: number = 0;
      for (let i = 0; i < events.length; i++) {
        if (events[i].date === todayStr) {
          count++;
        }
      }
      this.todayEventCount = count;
    } catch (error) {
      console.error('loadQuickInfo error:', JSON.stringify(error));
    }
  }

  private sortBySection(courses: Course[]): Course[] {
    const copied: Course[] = [...courses];
    copied.sort((a, b) => a.time.startSection - b.time.startSection);
    return copied;
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

  private openImporter(): void {
    router.pushUrl({
      url: RouterConstants.PAGE_COURSE_IMPORT,
      params: {
        returnHome: '1',
        semesterId: String(calculateSemesterId())
      }
    }).catch((error: Error) => {
      console.error('跳转导入页面失败:', error);
    });
  }

  private openTable(): void {
    router.pushUrl({ url: RouterConstants.PAGE_TABLE_UI }).catch((error: Error) => {
      console.error('跳转课表页面失败:', error);
    });
  }

  private openExamImport(): void {
    const semesterId: number = this.selectedSemesterId > 0 ? this.selectedSemesterId : calculateSemesterId();
    router.pushUrl({
      url: RouterConstants.PAGE_EXAM_IMPORT,
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
      url: RouterConstants.PAGE_EXAM,
      params: {
        examTypeId: String(this.getSelectedExamTypeId()),
        semesterId: String(this.selectedSemesterId)
      }
    }).catch((error: Error) => {
      console.error('跳转考试页面失败:', error);
    });
  }

  private openSchedule(): void {
    router.pushUrl({ url: RouterConstants.PAGE_CALENDAR }).catch((error: Error) => {
      console.error('跳转日程页面失败:', error);
    });
  }

  private openSettings(): void {
    router.pushUrl({ url: RouterConstants.PAGE_SETTINGS }).catch((error: Error) => {
      console.error('跳转设置页面失败:', error);
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

  private formatCourseTime(course: Course): string {
    const startSection: number = course.time.startSection;
    const endSection: number = startSection + course.time.duration - 1;
    const startTime: string = SECTION_TIMES[startSection - 1].startTime;
    const endTime: string = SECTION_TIMES[endSection - 1].endTime;
    return `${startSection}-${endSection}节 ${startTime}-${endTime}`;
  }

  private getNextExam(): ExamItem | undefined {
    const upcoming = this.getUpcomingExams(1);
    const result = upcoming.length > 0 ? upcoming[0] : undefined;
    if (Math.floor(this.nowTick / 1000) % 10 === 0) {
      console.info(`[HomeDebug] getNextExam: result=${result?.courseName ?? 'none'} beginTime=${result?.beginTime ?? 0}`);
    }
    return result;
  }

  private getUpcomingExams(n: number): ExamItem[] {
    const now: number = this.nowTick;
    const result: ExamItem[] = [];
    for (let i = 0; i < this.exams.length && result.length < n; i++) {
      if (this.exams[i].beginTime > now) {
        result.push(this.exams[i]);
      }
    }
    if (Math.floor(now / 1000) % 10 === 0) {
      console.info(`[HomeDebug] getUpcomingExams(${n}): nowTick=${now} total=${this.exams.length} found=${result.length}`);
    }
    if (result.length === 0 && this.exams.length > 0) {
      const zeroTimeCount = this.exams.filter(e => e.beginTime <= 0).length;
      const pastCount = this.exams.filter(e => e.beginTime > 0 && e.beginTime <= now).length;
      const key = `${this.exams.length}:${zeroTimeCount}:${pastCount}`;
      // 仅在 breakdown 变化时打印一次，避免 1s tick 导致日志刷屏
      if (key !== this.lastNoFutureExamKey) {
        this.lastNoFutureExamKey = key;
        console.info(`Home: 无未来考试 total=${this.exams.length} beginTime=0:${zeroTimeCount} past:${pastCount}`);
      }
    }
    return result;
  }

  private getSelectedExamTypeId(): number {
    return getExamTypeIdByIndex(this.selectedExamTypeIndex);
  }

  private getSelectedExamTypeLabel(): string {
    return getExamTypeLabelById(this.getSelectedExamTypeId());
  }

  private getHeroHint(): string {
    const nextExam: ExamItem | undefined = this.getNextExam();
    if (nextExam && this.settings.showExamCountdown) {
      return `最近考试：${nextExam.courseName}`;
    }
    if (!this.hasData) {
      return '尚未导入课表，先完成一次在线导入吧';
    }
    return `今日课程 ${this.todayCourses.length} 门，明日课程 ${this.tomorrowCourses.length} 门`;
  }

  private getWeekCourseCount(): number {
    if (!this.hasData) {
      return 0;
    }
    let total = 0;
    for (let day = 1; day <= 7; day++) {
      total += this.model.getCoursesForDayAndWeek(day, this.currentWeek).length;
    }
    return total;
  }

  private getFutureExamCount(): number {
    const now = this.nowTick;
    let count = 0;
    for (let i = 0; i < this.exams.length; i++) {
      if (this.exams[i].beginTime > now) {
        count++;
      }
    }
    return count;
  }

  private onToolClick(tool: ToolItem): void {
    if (tool.route) {
      router.pushUrl({ url: tool.route }, router.RouterMode.Standard)
        .catch((error: Error) => console.error(`跳转 ${tool.title} 页面失败:`, error));
    } else if (tool.url) {
      router.pushUrl({
        url: RouterConstants.PAGE_WEB,
        params: { title: tool.title, url: tool.url }
      }, router.RouterMode.Standard)
        .catch((error: Error) => console.error(`打开 ${tool.title} 网页失败:`, error));
    } else {
      this.showToast(`${tool.title} 功能开发中`);
    }
  }

  private onServiceClick(item: ServiceItem): void {
    if (item.route) {
      router.pushUrl({ url: item.route }).catch((error: Error) => {
        console.error(`跳转 ${item.name} 页面失败:`, error);
      });
    } else if (item.name === '图书馆') {
      router.pushUrl({
        url: RouterConstants.PAGE_WEB,
        params: { title: '图书馆', url: AppConstants.LIB_FULL_URL }
      }).catch((error: Error) => {
        console.error('打开图书馆网页失败:', error);
      });
    } else if (item.name === '校园卡') {
      router.pushUrl({
        url: RouterConstants.PAGE_WEB,
        params: { title: '校园卡', url: AppConstants.CARD_BALANCE_URL }
      }).catch((error: Error) => {
        console.error('打开校园卡网页失败:', error);
      });
    } else {
      this.showToast(`${item.name} 功能开发中`);
    }
  }

  private showToast(message: string): void {
    this.toastMessage = message;
    this.toastVisible = true;
    setTimeout(() => {
      this.toastVisible = false;
    }, 2000);
  }

  private showFeedbackDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '意见反馈',
      message: '感谢您使用成电校园助手！如遇问题或有建议，欢迎通过邮件联系我们：\npjj644@users.noreply.github.com',
      buttons: [
        { text: '复制邮箱', color: '#007AFF', primary: true },
        { text: '取消', color: '#888888' }
      ]
    }).then((value: promptAction.ShowDialogSuccessResponse) => {
      if (value.index === 0) {
        this.copyToClipboard('pjj644@users.noreply.github.com');
      }
    }).catch((error: Error) => {
      console.error('意见反馈弹窗失败', error);
    });
  }

  private showAboutDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '关于应用',
      message: '成电校园助手 v1.0.0\n\n一站式校园学习生活工具，集成课表、考试、日程、成绩查询与 AI 智能助手，助力每一天的校园生活。\n\n如有问题建议请通过「意见反馈」联系开发团队。',
      buttons: [
        { text: '知道了', color: '#007AFF', primary: true }
      ]
    }).catch((error: Error) => {
      console.error('关于应用弹窗失败', error);
    });
  }

  private copyToClipboard(text: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.showToast('邮箱已复制到剪贴板');
      }).catch((error: Error) => {
        console.error('写入剪贴板失败', error);
        this.showToast('复制失败');
      });
    } catch (error) {
      console.error('复制邮箱异常', JSON.stringify(error));
      this.showToast('复制失败');
    }
  }

  private openExamDetail(_exam: ExamItem): void {
    this.openExamPage();
  }

  private logExamCardRender(exam: ExamItem): string {
    if (Math.floor(this.nowTick / 1000) % 10 === 0) {
      console.info(`[HomeDebug] ExamCardBuilder render: exam=${exam.courseName} beginTime=${exam.beginTime} nowTick=${this.nowTick} remaining=${Math.floor((exam.beginTime - this.nowTick) / 1000)}s`);
    }
    return exam.courseName;
  }

  private logExamSectionRender(): string {
    const nextExam = this.getNextExam();
    if (Math.floor(this.nowTick / 1000) % 10 === 0) {
      console.info(`[HomeDebug] ExamCardsSection render: nowTick=${this.nowTick} nextExam=${nextExam?.courseName ?? 'none'}`);
    }
    return '最近考试倒计时';
  }

  @Builder
  private HomeContent(): void {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 12 }) {
          Row() {
            Row({ space: 12 }) {
              Stack() {
                Circle()
                  .width(52)
                  .height(52)
                  .fill('rgba(255,255,255,0.2)')
                Image($r('app.media.mine'))
                  .width(28)
                  .height(28)
                  .fillColor('#FFFFFF')
              }

              Column({ space: 4 }) {
                Text('HI助手')
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')

                Text(`第${this.currentWeek}周`)
                  .fontSize(13)
                  .fontColor('rgba(255,255,255,0.7)')
              }
              .alignItems(HorizontalAlign.Start);
            }

            Blank();

            Column({ space: 4 }) {
              Image($r('app.media.set'))
                .width(20)
                .height(20)
                .fillColor('#FFFFFF')
              Text('设置')
                .fontSize(11)
                .fontColor('rgba(255,255,255,0.8)')
            }
            .onClick(() => this.openSettings());
          }
          .width('100%');

          Text(this.getHeroHint())
            .fontSize(13)
            .fontColor('rgba(255,255,255,0.85)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');

          QuickStatComponent({
            stats: [
              { label: '今日课程', value: this.todayCourses.length.toString(), color: $r('app.color.primary_color') },
              { label: '待考科目', value: this.getFutureExamCount().toString(), color: $r('app.color.warning_color') },
              { label: '本周课程', value: this.getWeekCourseCount().toString(), color: $r('app.color.success_color') },
            ]
          });
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 8 })
        .borderRadius(24)
        .linearGradient({
          angle: 135,
          colors: [['#667eea', 0], ['#764ba2', 0.5], ['#f093fb', 1]]
        })
        .shadow({ radius: 20, color: 'rgba(102, 126, 234, 0.3)', offsetY: 8 });

        if (!this.hasData) {
          AnimatedCard({ delay: 200 }) {
            this.EmptyStateBuilder();
          }
        } else if (this.showExamInfoCard) {
          AnimatedCard({ delay: 200 }) {
            this.ExamCardsSection();
          }
        } else {
          if (this.settings.showToday) {
            AnimatedCard({ delay: 200 }) {
              this.CourseListBuilder('今日课程', this.todayCourses, true);
            }
          }
          if (this.settings.showTomorrow) {
            AnimatedCard({ delay: 300 }) {
              this.CourseListBuilder('明日课程', this.tomorrowCourses, false);
            }
          }
        }

        Row({ space: 12 }) {
          Button('课表详情')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_color'))
            .backgroundColor($r('app.color.accent_bg_color'))
            .borderRadius(12)
            .height(42)
            .layoutWeight(1)
            .onClick(() => this.openTable());

          Button('考试详情')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.warning_color'))
            .backgroundColor($r('app.color.tag_bg_exam'))
            .borderRadius(12)
            .height(42)
            .layoutWeight(1)
            .onClick(() => this.openExamPage());

          Button('日程')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.success_color'))
            .backgroundColor($r('app.color.tag_bg_done'))
            .borderRadius(12)
            .height(42)
            .layoutWeight(1)
            .onClick(() => this.openSchedule());
        }
        .width('100%')
        .padding({ left: 16, right: 16 });
      }
      .width('100%')
      .padding({ left: 0, right: 0, top: 12, bottom: 24 })
      .opacity(this.pageReady ? 1 : 0);
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring);
  }

  @Builder
  private DiscoverContent(): void {
    Scroll() {
      Column({ space: 10 }) {
        Column({ space: 4 }) {
          Text('发现')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'));

          Text('校园实用工具')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'));
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16 });

        Text('最近使用')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: 16, right: 16 });

        Row({ space: 12 }) {
          Column() {
            Text('📊')
              .fontSize(24);
            Text('成绩查询')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 4 });
            Text(this.latestGpa === '--' ? '点击导入' : `GPA ${this.latestGpa}`)
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 });
          }
          .layoutWeight(1)
          .height(90)
          .borderRadius(14)
          .backgroundColor($r('app.color.accent_bg_color'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            const gradeTool = this.tools.find(t => t.title === '成绩查询');
            if (gradeTool) this.onToolClick(gradeTool);
          });

          Column() {
            Text('📅')
              .fontSize(24);
            Text('校园日历')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 4 });
            Text(this.todayEventCount > 0 ? `今日 ${this.todayEventCount} 件事` : '查看日程')
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 });
          }
          .layoutWeight(1)
          .height(90)
          .borderRadius(14)
          .backgroundColor($r('app.color.tag_bg_done'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            const calTool = this.tools.find(t => t.title === '校园日历');
            if (calTool) this.onToolClick(calTool);
          });

          Column() {
            Text('📚')
              .fontSize(24);
            Text('图书馆')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 4 });
            Text('点击打开')
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 });
          }
          .layoutWeight(1)
          .height(90)
          .borderRadius(14)
          .backgroundColor($r('app.color.primary_light_color'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            const libTool = this.tools.find(t => t.title === '图书馆');
            if (libTool) this.onToolClick(libTool);
          });
        }
        .width('100%')
        .padding({ left: 16, right: 16 });

        Text('所有功能')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: 16, right: 16 });

        Grid() {
          ForEach(this.tools, (tool: ToolItem) => {
            GridItem() {
              Column({ space: 8 }) {
                if (tool.iconImage) {
                  Image(tool.iconImage)
                    .width(28)
                    .height(28);
                } else {
                  Text(tool.icon)
                    .fontSize(28);
                }
                Text(tool.title)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'));
              }
              .width('100%')
              .height(90)
              .borderRadius(16)
              .backgroundColor($r('app.color.card_background'))
              .justifyContent(FlexAlign.Center)
              .onClick(() => this.onToolClick(tool));
            }
          });
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
        .columnsGap(14)
        .rowsGap(14)
        .padding({ left: 16, right: 16 })
        .width('100%');
      }
      .width('100%')
      .padding({ top: 8, bottom: 24 });
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring);
  }

  @Builder
  private MineContent(): void {
    Scroll() {
      Column({ space: 10 }) {
        ImmersiveLightWrapper({ radius: 24, lightIntensity: 2.5 }) {
          Row({ space: 14 }) {
            Stack() {
              Circle()
                .width(60)
                .height(60)
                .fill($r('app.color.accent_bg_color'));
              Image($r('app.media.mine'))
                .width(30)
                .height(30)
                .fillColor($r('app.color.primary_color'));
            }

            Column({ space: 4 }) {
              Text(this.isLoggedIn ? this.loginEmail : '校园用户')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });

              if (this.isLoggedIn) {
                Row({ space: 4 }) {
                  Circle()
                    .width(6)
                    .height(6)
                    .fill($r('app.color.success_color'));
                  Text('已登录')
                    .fontSize(12)
                    .fontColor($r('app.color.success_color'));
                }
              } else {
                Row({ space: 4 }) {
                  Circle()
                    .width(6)
                    .height(6)
                    .fill($r('app.color.warning_color'));
                  Text('未登录，点击登录')
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'));
                }
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);

            if (!this.isLoggedIn) {
              Image($r('app.media.arrow_right'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.text_tertiary'));
            }
          }
          .width('92%')
          .padding(16)
          .onClick(() => {
            if (!this.isLoggedIn) {
              router.pushUrl({ url: RouterConstants.PAGE_LOGIN }).catch((error: Error) => {
                console.error('跳转登录页面失败:', error);
              });
            } else {
              router.pushUrl({ url: RouterConstants.PAGE_ACCOUNT_MANAGE }).catch((error: Error) => {
                console.error('跳转账号管理失败:', error);
              });
            }
          });
        }

        Column({ space: 0 }) {
          this.MineMenuItem('个人信息', $r('app.media.ic_public_edit'), () => {
            this.showToast('个人信息功能开发中');
          });
          this.MineMenuItem('账号设置', $r('app.media.settings_icon'), () => {
            router.pushUrl({ url: RouterConstants.PAGE_ACCOUNT_MANAGE }).catch((error: Error) => {
              console.error('跳转账号管理失败:', error);
            });
          });
          this.MineMenuItem('应用设置', $r('app.media.set'), () => {
            this.openSettings();
          });
          this.MineMenuItem('意见反馈', $r('app.media.feedback'), () => {
            this.showFeedbackDialog();
          });
          this.MineMenuItem('关于应用', $r('app.media.about'), () => {
            this.showAboutDialog();
          });
        }
        .width('92%')
        .borderRadius(14)
        .backgroundColor($r('app.color.card_background'));

        Text('v1.0.0')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 8 });
      }
      .width('100%')
      .padding({ top: 12, bottom: 24 })
      .alignItems(HorizontalAlign.Center);
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring);
  }

  @Builder
  private MineMenuItem(title: string, icon: Resource, action: () => void): void {
    Row() {
      Row({ space: 12 }) {
        Image(icon)
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_secondary'));

        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'));
      }

      Blank();

      Text('>')
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'));
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .onClick(action);
  }

  @Builder
  private EmptyStateBuilder(): void {
    ImmersiveLightWrapper({ radius: 20, lightIntensity: 2.0 }) {
      Column({ space: 12 }) {
        Text('当前没有课表数据')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'));

        Text('先导入一次课表，首页会自动展示今日课程和考试倒计时')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .width('100%');

        Button('前往在线导入')
          .height(40)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.primary_color'))
          .borderRadius(20)
          .onClick(() => this.openImporter());
      }
      .width('92%')
      .padding(16)
      .alignItems(HorizontalAlign.Center);
    }
  }

  @Builder
  private CourseListBuilder(title: string, courses: Course[], showSwitch: boolean): void {
    ImmersiveLightWrapper({ radius: 20, lightIntensity: 2.0 }) {
      Column() {
        Row() {
          if (showSwitch) {
            Row({ space: 8 }) {
              Text(title)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'));

              Text(`${courses.length}门课程`)
                .fontSize(12)
                .fontColor($r('app.color.primary_color'));
            }

            Blank();

            Image($r('app.media.switch'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.primary_color'))
              .onClick(() => {
                this.showExamInfoCard = true;
              });
          } else {
            Text(title)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'));

            Blank();

            Text(`${courses.length}门`)
              .fontSize(12)
              .fontColor($r('app.color.primary_color'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.accent_bg_color'))
              .borderRadius(12);
          }
        }
        .width('100%')
        .margin({ bottom: 8 });

        if (courses.length === 0) {
          Text('暂无课程')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor($r('app.color.page_background'));
        } else {
          ForEach(courses, (course: Course, index: number) => {
            AnimatedListItem({ delay: index * 50 }) {
              Row({ space: 10 }) {
                Column()
                  .width(4)
                  .height(50)
                  .borderRadius(3)
                  .backgroundColor($r('app.color.primary_color'));

                Column({ space: 3 }) {
                  Text(course.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });

                  Text(this.formatCourseTime(course))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%');

                  Text(`${course.roomName || '地点未知'} · ${course.teacherName || '教师未知'}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'))
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
              .backgroundColor($r('app.color.page_background'));
            }
          });
        }
      }
      .width('92%')
      .padding(12);
    }
  }

  @Builder
  private ExamCardBuilder(exam: ExamItem): void {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(this.logExamCardRender(exam))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);

        Text(exam.examType || '未知')
          .fontSize(10)
          .fontColor($r('app.color.primary_color'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.accent_bg_color'))
          .borderRadius(8);
      }
      .width('100%');

      CountdownCard({
        examName: '',
        examDate: exam.examDate,
        examTimeRange: exam.examTimeRange,
        beginTime: exam.beginTime,
        compact: false
      });
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.page_background'))
    .onClick(() => this.openExamDetail(exam));
  }

  @Builder
  private ExamCardsSection(): void {
    ImmersiveLightWrapper({ radius: 20, lightIntensity: 2.0 }) {
      Column({ space: 10 }) {
        Row() {
          Row({ space: 6 }) {
            Text('⏳')
              .fontSize(16);
            Text(this.logExamSectionRender())
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'));
          }
          Blank();
          Button('全部')
            .height(30)
            .fontSize(12)
            .fontColor($r('app.color.primary_color'))
            .backgroundColor($r('app.color.accent_bg_color'))
            .borderRadius(12)
            .onClick(() => this.openExamPage());

          Image($r('app.media.switch'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.warning_color'))
            .margin({ left: 10 })
            .onClick(() => {
              this.showExamInfoCard = false;
            });
        }
        .width('100%');

        if (this.getUpcomingExams(1).length > 0) {
          this.ExamCardBuilder(this.getNextExam()!);
        } else {
          Text('暂无考试安排，好好放松一下吧 🎉')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 16, bottom: 16 });
        }
      }
      .width('92%')
      .padding(12);
    }
  }

  @Builder
  private TabBarItem(title: string, iconRes: Resource, index: number): void {
    Column({ space: 4 }) {
      Image(iconRes)
        .width(24)
        .height(24)
        .fillColor(this.currentTabIndex === index ? $r('app.color.primary_color') : $r('app.color.text_tertiary'));

      Text(title)
        .fontSize(11)
        .fontColor(this.currentTabIndex === index ? $r('app.color.primary_color') : $r('app.color.text_tertiary'))
        .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal);
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }

  build() {
    Stack() {
      if (this.customBackgroundEnabled && this.customBackgroundImage) {
        Image(this.customBackgroundImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover);
      }

      Column() {
        Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
          TabContent() {
            this.DiscoverContent();
          }.tabBar(this.TabBarItem('发现', $r('app.media.ic_campus_map'), 0));

          TabContent() {
            AssistantPage();
          }.tabBar(this.TabBarItem('AI助手', $r('app.media.ic_ai_assistant'), 1));

          TabContent() {
            this.HomeContent();
          }.tabBar(this.TabBarItem('课程', $r('app.media.home'), 2));

          TabContent() {
            CalendarPage({ showBack: false });
          }.tabBar(this.TabBarItem('日历', $r('app.media.ic_calendar'), 3));

          TabContent() {
            this.MineContent();
          }.tabBar(this.TabBarItem('我的', $r('app.media.mine'), 4));
        }
        .scrollable(true)
        .barMode(BarMode.Fixed)
        .barBackgroundColor($r('app.color.card_background'))
        .onChange((index: number) => {
          this.currentTabIndex = index;
        })
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')

      ToastComponent({
        message: this.toastMessage,
        visible: this.toastVisible,
        duration: 2000,
        type: 4
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'));
  }
}
