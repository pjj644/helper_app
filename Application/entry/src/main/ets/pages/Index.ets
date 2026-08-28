import { router, curves, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { bundleManager } from '@kit.AbilityKit';
import { AssistantPage } from '../pages/quick/AssistantPage';
import { CalendarPage } from '../pages/schedulePages/CalendarPage';
import {
  Course,
  CourseTableModel,
  courseTableModel,
  getCurrentWeek,
} from '../model/classTableModel/CourseModel';
import { DisplaySettings, CourseTableStorage } from '../model/classTableModel/CourseTableStorage';
import { ExamItem, normalizeExam, sortExams } from '../model/classTableModel/ExamModel';
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
import { AnimatedCard } from '../components/AnimatedComponents';
import { ToastComponent } from '../components/ToastComponents';
import { GradeService } from '../service/GradeService';
import { ScheduleService } from '../service/ScheduleService';
import { AuthService } from '../service/AuthService';
import { PageContextTracker } from '../common/agent/PageContextTracker';
import { FloatingWindowManager } from '../common/agent/FloatingWindowManager';
import { UIActionDispatcher } from '../common/agent/UIActionDispatcher';
import { BreakpointUtils } from '../common/utils/BreakpointUtils';
import { HomeHeaderComponent } from '../components/home/HomeHeaderComponent';
import { NextCourseCardComponent } from '../components/home/NextCourseCardComponent';
import { ExamCountdownCard } from '../components/home/ExamCountdownCard';
import { QuickLinksGrid, HomeToolItem } from '../components/home/QuickLinksGrid';

import { PreferencesUtil } from '../common/PreferencesUtil';
import { PrivacyDialogComponent } from '../components/PrivacyDialogComponent';
import { AgentEndpointConfig } from '../common/agent/AgentEndpointConfig';

// 首页时间节拍间隔：本页所有依赖时间的展示（最近考试、未来考试数）均为分钟级文案，
// 秒级跳动的倒计时数字由 CountdownCard 组件内部定时器自行驱动，不依赖本页节拍，
// 因此采用低频探测而非每秒空转。
const HOME_TICK_INTERVAL_MS: number = 30000;

@Entry
@Component
struct MainPage {
  @State currentTabIndex: number = 2;
  @State currentWeek: number = getCurrentWeek();
  @State hasData: boolean = false;
  @State versionName: string = '';
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
  @State currentBreakpoint: string = 'sm';

  private tickTimer: number = -1;
  private model: CourseTableModel = courseTableModel;
  private appSettings: UISettings = UISettings.getInstance();
  private lastNoFutureExamKey: string = '';
  // 上一次节拍时“未来考试集合”的指纹，用于判断展示值是否实际变化
  private lastExamDisplayKey: string = '';
  private privacyDialogController: CustomDialogController | null = new CustomDialogController({
    builder: PrivacyDialogComponent({
      onAgree: () => {
        this.checkLoginStatus();
      }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true
  });

  private tools: HomeToolItem[] = [
    { title: '云中成电', icon: '☁️', color: '#0A59F7', url: AppConstants.ONLINE_URL },
    { title: '成电班车', icon: '🚌', color: '#10B981', route: RouterConstants.PAGE_BUS_SCHEDULE },
    { title: 'AI 助手', icon: '🤖', color: '#6366F1', route: RouterConstants.PAGE_ASSISTANT, iconImage: $r('app.media.ic_ai_assistant') },
    { title: '成绩查询', icon: '📊', color: '#EC4899', route: RouterConstants.PAGE_GRADE },
    { title: '校园地图', icon: '🗺️', color: '#3B82FF', url: AppConstants.GIS_MAP_URL, iconImage: $r('app.media.ic_campus_map') },
    { title: '图书馆', icon: '📚', color: '#06B6D4', url: AppConstants.LIB_FULL_URL },
    { title: '校园日历', icon: '📅', color: '#84CC16', route: RouterConstants.PAGE_CALENDAR },
    { title: '清水河畔', icon: '🌊', color: '#0EA5E9', url: AppConstants.QINGSHUI_RIVER_URL, iconImage: $r('app.media.ic_qingshui_river') },
    { title: '一卡通余额', icon: '💰', color: '#F97316', url: AppConstants.CARD_BALANCE_URL, iconImage: $r('app.media.ic_card_balance') }
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
    this.versionName = this.loadVersionName();

    if (!PreferencesUtil.getInstance().hasAgreedPrivacy()) {
      this.privacyDialogController?.open();
    }

    BreakpointUtils.registerBreakpoint(getContext(this), (bp: string) => {
      this.currentBreakpoint = bp;
    });

    // 低频节拍 + 按需刷新：仅当未来考试集合实际变化（如某场考试开始）时才更新 @State，
    // 其余节拍零状态写入、零重绘，替代原先每秒无条件刷新整页的空转实现。
    this.lastExamDisplayKey = this.examDisplayKey(this.nowTick);
    this.tickTimer = setInterval(() => {
      this.refreshNowTick();
    }, HOME_TICK_INTERVAL_MS);

    setTimeout(() => {
      animateTo({ curve: curves.springMotion(0.6, 0.8) }, () => {
        this.pageReady = true;
      });
      this.updateCurrentTabContext();
    }, 40);

    UIActionDispatcher.getInstance().registerHandler('switch_tab', (params: Record<string, Object>) => {
      const idx = Number(params['tabIndex'] !== undefined ? params['tabIndex'] : 2);
      this.currentTabIndex = idx;
      this.updateCurrentTabContext();
      return true;
    });
  }

  aboutToDisappear(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  onPageShow(): void {
    this.loadPageData();
    this.loadQuickInfo();
    this.checkLoginStatus();
    ReminderService.refreshAllReminders(getContext(this));
    AgentEndpointConfig.syncConfiguredState(getContext(this));
    this.updateCurrentTabContext();
  }

  private updateCurrentTabContext(): void {
    FloatingWindowManager.getInstance().setAssistantPageActive(this.currentTabIndex === 1);
    if (this.currentTabIndex === 1) {
      AgentEndpointConfig.syncConfiguredState(getContext(this));
    }

    if (this.currentTabIndex === 0) {
      PageContextTracker.getInstance().updateSnapshot(
        'discover',
        '发现',
        '校园常用服务与功能导航',
        { 'latestGpa': this.latestGpa, 'todayEvents': this.todayEventCount },
        [
          { actionId: 'open_map', label: '打开校园地图', description: '导航至校园GIS地图' },
          { actionId: 'open_grades', label: '查成绩', description: '进入成绩查询页面' }
        ]
      );
    } else if (this.currentTabIndex === 1) {
      PageContextTracker.getInstance().updateSnapshot(
        'assistant',
        'AI助手',
        '全屏智能助手对话',
        {},
        []
      );
    } else if (this.currentTabIndex === 2) {
      const todayNames = this.todayCourses.map((c: Course) => `${c.name}@${c.roomName || '待定'}(第${c.time.startSection}节)`);
      const dataSnap: Record<string, Object> = {
        'currentWeek': this.currentWeek,
        'todayCourseCount': this.todayCourses.length,
        'tomorrowCourseCount': this.tomorrowCourses.length,
        'futureExamCount': this.getFutureExamCount(),
        'todayCourses': todayNames
      };
      PageContextTracker.getInstance().updateSnapshot(
        'home_course',
        '课程首页',
        `当前第${this.currentWeek}周，今日${this.todayCourses.length}节课，明日${this.tomorrowCourses.length}节课，未来考试${this.getFutureExamCount()}场`,
        dataSnap,
        [
          { actionId: 'open_full_table', label: '查看完整周课表', description: '跳转至全周课表网格页面' },
          { actionId: 'import_courses', label: '导入教务课表', description: '从教务系统导入课表' },
          { actionId: 'open_calendar', label: '打开日历', description: '进入日程日历' }
        ]
      );
    } else if (this.currentTabIndex === 3) {
      PageContextTracker.getInstance().updateSnapshot(
        'calendar',
        '校园日历',
        '日程管理与系统日历事件',
        { 'todayEvents': this.todayEventCount },
        [
          { actionId: 'add_schedule', label: '新建日程', description: '创建新的待办或日程' }
        ]
      );
    } else if (this.currentTabIndex === 4) {
      PageContextTracker.getInstance().updateSnapshot(
        'mine',
        '个人中心',
        this.isLoggedIn ? `已登录用户：${this.loginEmail}` : '未登录状态',
        { 'isLoggedIn': this.isLoggedIn, 'email': this.loginEmail },
        [
          { actionId: 'open_settings', label: '应用设置', description: '打开偏好设置' },
          { actionId: 'open_login', label: '登录账号', description: '进入登录页面' }
        ]
      );
    }
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
        } catch (error) {
          console.error('[ExamDebug] Home: parse exam error', JSON.stringify(error));
          this.exams = [];
        }
      } else {
        this.exams = [];
      }

      // 考试数据加载后同步展示值指纹，避免下一次节拍把加载本身误判为“时间流逝导致的变化”
      this.lastExamDisplayKey = this.examDisplayKey(this.nowTick);

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
      console.error('[Index] loadQuickInfo error:', JSON.stringify(error));
    }
  }

  private sortBySection(courses: Course[]): Course[] {
    const copied: Course[] = [...courses];
    copied.sort((a, b) => a.time.startSection - b.time.startSection);
    return copied;
  }

  private async checkLoginStatus(): Promise<void> {
    try {
      const session = await AuthService.getLoginSession(getContext(this));
      this.isLoggedIn = !!session?.userId;
      this.loginEmail = session?.email || '';
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
      console.error('[Index] 跳转导入页面失败:', error);
    });
  }

  private openTable(): void {
    router.pushUrl({ url: RouterConstants.PAGE_TABLE_UI }).catch((error: Error) => {
      console.error('[Index] 跳转课表页面失败:', error);
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
      console.error('[Index] 跳转考试页面失败:', error);
    });
  }

  private openSchedule(): void {
    router.pushUrl({ url: RouterConstants.PAGE_CALENDAR }).catch((error: Error) => {
      console.error('[Index] 跳转日程页面失败:', error);
    });
  }

  private openSettings(): void {
    router.pushUrl({ url: RouterConstants.PAGE_SETTINGS }).catch((error: Error) => {
      console.error('[Index] 跳转设置页面失败:', error);
    });
  }

  private getNextExam(): ExamItem | undefined {
    const upcoming = this.getUpcomingExams(1);
    return upcoming.length > 0 ? upcoming[0] : undefined;
  }

  private getUpcomingExams(n: number): ExamItem[] {
    const now: number = this.nowTick;
    const exams = this.exams;
    const result: ExamItem[] = [];
    for (let i = 0; i < exams.length && result.length < n; i++) {
      if (exams[i].beginTime > now) {
        result.push(exams[i]);
      }
    }
    return result;
  }

  /**
   * 计算指定时刻“未来考试集合”的展示值指纹（数量 + 最近一场的开始时间）。
   * 首页所有随时间变化的文案均由该集合派生，集合不变则展示不变，无需重绘。
   */
  private examDisplayKey(now: number): string {
    let futureCount: number = 0;
    let nextBeginTime: number = -1;
    const exams = this.exams;
    for (let i = 0; i < exams.length; i++) {
      if (exams[i].beginTime > now) {
        futureCount++;
        if (nextBeginTime < 0 || exams[i].beginTime < nextBeginTime) {
          nextBeginTime = exams[i].beginTime;
        }
      }
    }
    return `${futureCount}_${nextBeginTime}`;
  }

  /** 低频节拍回调：仅在展示值实际变化时才写入 @State 触发刷新。 */
  private refreshNowTick(): void {
    const candidate: number = Date.now();
    const nextKey: string = this.examDisplayKey(candidate);
    if (nextKey !== this.lastExamDisplayKey) {
      this.lastExamDisplayKey = nextKey;
      this.nowTick = candidate;
    }
  }

  private getSelectedExamTypeId(): number {
    return getExamTypeIdByIndex(this.selectedExamTypeIndex);
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
    const week = this.currentWeek;
    for (let day = 1; day <= 7; day++) {
      total += this.model.getCoursesForDayAndWeek(day, week).length;
    }
    return total;
  }

  private getFutureExamCount(): number {
    const now = this.nowTick;
    const exams = this.exams;
    let count = 0;
    for (let i = 0; i < exams.length; i++) {
      if (exams[i].beginTime > now) {
        count++;
      }
    }
    return count;
  }

  private onToolClick(tool: HomeToolItem): void {
    if (tool.route) {
      router.pushUrl({ url: tool.route }, router.RouterMode.Standard)
        .catch((error: Error) => console.error(`[Index] 跳转 ${tool.title} 页面失败:`, error));
    } else if (tool.url) {
      router.pushUrl({
        url: RouterConstants.PAGE_WEB,
        params: { title: tool.title, url: tool.url }
      }, router.RouterMode.Standard)
        .catch((error: Error) => console.error(`[Index] 打开 ${tool.title} 网页失败:`, error));
    } else {
      this.showToast(`${tool.title} 功能开发中`);
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
      console.error('[Index] 意见反馈弹窗失败', error);
    });
  }

  /** 从应用包信息读取版本号（aboutToAppear 时调用），读取失败回退空串 */
  private loadVersionName(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName ? info.versionName : '';
    } catch (e) {
      console.error('[Index] 读取版本号失败:', JSON.stringify(e));
      return '';
    }
  }

  private showAboutDialog(): void {
    const versionText = this.versionName ? ` v${this.versionName}` : '';
    this.getUIContext().getPromptAction().showDialog({
      title: '关于应用',
      message: `成电校园助手${versionText}\n\n一站式校园学习生活工具，集成课表、考试、日程、成绩查询与 AI 智能助手，助力每一天的校园生活。\n\n如有问题建议请通过「意见反馈」联系开发团队。`,
      buttons: [
        { text: '知道了', color: '#007AFF', primary: true }
      ]
    }).catch((error: Error) => {
      console.error('[Index] 关于应用弹窗失败', error);
    });
  }

  private copyToClipboard(text: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.showToast('邮箱已复制到剪贴板');
      }).catch((error: Error) => {
        console.error('[Index] 写入剪贴板失败', error);
        this.showToast('复制失败');
      });
    } catch (error) {
      console.error('[Index] 复制邮箱异常', JSON.stringify(error));
      this.showToast('复制失败');
    }
  }

  private openExamDetail(_exam: ExamItem): void {
    this.openExamPage();
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
  private ActionButtonsRow(): void {
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

  @Builder
  private HomeScheduleSection(): void {
    if (!this.hasData) {
      AnimatedCard({ delay: 200 }) {
        this.EmptyStateBuilder();
      }
    } else if (this.showExamInfoCard) {
      AnimatedCard({ delay: 200 }) {
        ExamCountdownCard({
          nextExam: this.getNextExam(),
          nowTick: this.nowTick,
          onSwitchToCourse: () => {
            this.showExamInfoCard = false;
          },
          onOpenExamPage: () => {
            this.openExamPage();
          },
          onOpenExamDetail: (e: ExamItem) => {
            this.openExamDetail(e);
          }
        });
      }
    } else {
      if (this.settings.showToday) {
        AnimatedCard({ delay: 200 }) {
          NextCourseCardComponent({
            title: '今日课程',
            courses: this.todayCourses,
            isToday: true,
            onSwitchToExam: () => {
              this.showExamInfoCard = true;
            }
          });
        }
      }
      if (this.settings.showTomorrow) {
        AnimatedCard({ delay: 300 }) {
          NextCourseCardComponent({
            title: '明日课程',
            courses: this.tomorrowCourses,
            isToday: false
          });
        }
      }
    }
  }

  @Builder
  private HomeContent(): void {
    Scroll() {
      Column({ space: 12 }) {
        if (this.currentBreakpoint === 'sm') {
          HomeHeaderComponent({
            currentWeek: this.currentWeek,
            heroHint: this.getHeroHint(),
            todayCourseCount: this.todayCourses.length,
            futureExamCount: this.getFutureExamCount(),
            weekCourseCount: this.getWeekCourseCount(),
            onOpenSettings: () => {
              this.openSettings();
            }
          });

          this.HomeScheduleSection();
          this.ActionButtonsRow();
        } else {
          // 折叠屏与平板宽屏响应式布局（双栏联动）
          GridRow({ columns: { md: 8, lg: 12 }, gutter: { x: 16, y: 16 } }) {
            GridCol({ span: { md: 3, lg: 4 } }) {
              Column({ space: 12 }) {
                HomeHeaderComponent({
                  currentWeek: this.currentWeek,
                  heroHint: this.getHeroHint(),
                  todayCourseCount: this.todayCourses.length,
                  futureExamCount: this.getFutureExamCount(),
                  weekCourseCount: this.getWeekCourseCount(),
                  onOpenSettings: () => {
                    this.openSettings();
                  }
                });
                this.ActionButtonsRow();
              }
            }

            GridCol({ span: { md: 5, lg: 8 } }) {
              Column({ space: 12 }) {
                this.HomeScheduleSection();
              }
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 });
        }
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
      QuickLinksGrid({
        tools: this.tools,
        latestGpa: this.latestGpa,
        todayEventCount: this.todayEventCount,
        currentBreakpoint: this.currentBreakpoint,
        onToolClick: (tool: HomeToolItem) => {
          this.onToolClick(tool);
        }
      });
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
                console.error('[Index] 跳转登录页面失败:', error);
              });
            } else {
              router.pushUrl({ url: RouterConstants.PAGE_ACCOUNT_MANAGE }).catch((error: Error) => {
                console.error('[Index] 跳转账号管理失败:', error);
              });
            }
          });
        }

        Column({ space: 0 }) {
          this.MineMenuItem('个人信息', $r('app.media.ic_public_edit'), () => {
            router.pushUrl({ url: RouterConstants.PAGE_PERSONAL_INFO }).catch((error: Error) => {
              console.error('[Index] 跳转个人信息页面失败:', error);
            });
          });
          this.MineMenuItem('账号设置', $r('app.media.settings_icon'), () => {
            router.pushUrl({ url: RouterConstants.PAGE_ACCOUNT_MANAGE }).catch((error: Error) => {
              console.error('[Index] 跳转账号管理失败:', error);
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

        Text(this.versionName ? `v${this.versionName}` : '')
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
          this.updateCurrentTabContext();
        })
        .layoutWeight(1)
        .width('100%');
      }
      .width('100%')
      .height('100%');

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
