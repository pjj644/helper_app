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
  getWeekDatesForWeek,
} from '../../model/classTableModel/CourseModel';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { getSemesterOptions, SemesterOptionSet, getSemesterLabelById, calculateSemesterId } from '../../model/classTableModel/ExamAccessRules';
import { CourseRepository } from '../../repository/CourseRepository';
import { CourseService } from '../../service/CourseService';
import { SyncService } from '../../service/SyncService';
import { PageContextTracker } from '../../common/agent/PageContextTracker';
import { UIActionDispatcher } from '../../common/agent/UIActionDispatcher';

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
  @State showCourseManage: boolean = false;
  @State courses: Course[] = [];
  @State showEditor: boolean = false;
  @State editIndex: number = -1;
  @State formId: string = '';
  @State formName: string = '';
  @State formTeacher: string = '';
  @State formRoom: string = '';
  @State formDay: number = 1;
  @State formStartSection: number = 1;
  @State formDuration: number = 2;
  @State formWeeks: string = '1-20';
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
  private unregisterSwitchWeek: (() => void) | null = null;
  private unregisterImport: (() => void) | null = null;

  aboutToAppear() {
    this.initSemesterOptions();
    this.updateWeekDates();
    this.tryLoadPendingCourseData();
    this.tryLoadCourseData();

    this.unregisterSwitchWeek = UIActionDispatcher.getInstance().registerHandler('switch_week', (params: Record<string, Object>) => {
      const targetWeek = Number(params['week'] || params['targetWeek']);
      if (targetWeek >= 1 && targetWeek <= this.maxWeeks) {
        this.currentWeek = targetWeek;
        this.updateWeekDates();
        this.reportPageContext();
        return true;
      }
      return false;
    });

    this.unregisterImport = UIActionDispatcher.getInstance().registerHandler('import_courses', () => {
      router.pushUrl({ url: 'pages/classTablePages/Index' });
      return true;
    });

    this.reportPageContext();
  }

  aboutToDisappear() {
    if (this.unregisterSwitchWeek) {
      this.unregisterSwitchWeek();
      this.unregisterSwitchWeek = null;
    }
    if (this.unregisterImport) {
      this.unregisterImport();
      this.unregisterImport = null;
    }
  }

  onPageShow() {
    this.tryLoadPendingCourseData();
    this.reportPageContext();
  }

  private reportPageContext(): void {
    const weekCourses = this.courseModel.getCoursesForWeek(this.currentWeek);
    const names = weekCourses.slice(0, 10).map((c: Course) => `${c.name}@周${c.time.dayOfWeek}第${c.time.startSection}节(${c.roomName || '待定'})`);
    PageContextTracker.getInstance().updateSnapshot(
      'tableUI',
      '周课表网格',
      `当前展示第 ${this.currentWeek} 周课表，本周共有 ${weekCourses.length} 门课`,
      {
        'currentWeek': this.currentWeek,
        'courseCount': weekCourses.length,
        'courses': names
      },
      [
        { actionId: 'switch_week', label: '切换周次', description: '切换至指定教学周课表' },
        { actionId: 'import_courses', label: '导入教务课表', description: '从教务系统导入课表' }
      ]
    );
  }

  private async initSemesterOptions(): Promise<void> {
    const semesterSet: SemesterOptionSet = getSemesterOptions();
    const filteredOptions: SelectOption[] = [];
    const filteredIds: number[] = [];

    const params = router.getParams() as Record<string, string>;
    const routeSemesterId: number = params && params['semesterId'] ? Number(params['semesterId']) : 0;
    const currentSemId = calculateSemesterId();
    if (routeSemesterId > 0) {
      this.selectedSemesterId = routeSemesterId;
    } else {
      this.selectedSemesterId = currentSemId;
    }

    try {
      const context = getContext(this);
      const summaries = await CourseRepository.getArchivedSemestersSummary(context);
      const summaryMap = new Map<number, number>();
      for (let i = 0; i < summaries.length; i++) {
        summaryMap.set(summaries[i].semesterId, summaries[i].courseCount);
      }

      for (let i = 1; i < semesterSet.options.length; i++) {
        const semId = semesterSet.semesterIds[i];
        const count = summaryMap.get(semId);
        let baseLabel = String(semesterSet.options[i].value);
        if (count !== undefined && count > 0) {
          if (semId === currentSemId) {
            baseLabel = `${baseLabel} (当前·已归档${count}门)`;
          } else {
            baseLabel = `${baseLabel} (已归档${count}门)`;
          }
        } else {
          if (semId === currentSemId) {
            baseLabel = `${baseLabel} (当前·未导入)`;
          } else {
            baseLabel = `${baseLabel} (未导入)`;
          }
        }
        filteredOptions.push({ value: baseLabel });
        filteredIds.push(semId);
      }
    } catch (e) {
      for (let i = 1; i < semesterSet.options.length; i++) {
        filteredOptions.push(semesterSet.options[i]);
        filteredIds.push(semesterSet.semesterIds[i]);
      }
    }

    this.semesterOptions = filteredOptions;
    this.semesterOptionIds = filteredIds;
  }

  private tryLoadPendingCourseData(): void {
    if (this.pendingCourseData.length > 0 && this.pendingCourseSemesterId > 0) {
      this.selectedSemesterId = this.pendingCourseSemesterId;
      this.applyCourseData(this.pendingCourseData);
      this.saveCourseDataToLocal(this.pendingCourseData);
      this.hasCourseDataForSemester = true;
      this.pendingCourseData = '';
      this.pendingCourseSemesterId = 0;
      this.initSemesterOptions();
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

      this.courseModel.clear();
      this.dataVersion++;
      this.hasCourseDataForSemester = false;
    } catch (error) {
      console.error('[TableUI] 加载课表本地数据失败:', error);
      this.hasCourseDataForSemester = false;
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
      SyncService.triggerAutoSyncIfEnabled(context);
    } catch (error) {
      console.error('[TableUI] 保存课表本地数据失败:', error);
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
      console.error('[TableUI] 跳转网页抓取页失败:', error);
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
    this.reportPageContext();
  }

  private refreshFromWeb(): void {
    router.pushUrl({
      url: 'pages/classTablePages/Index',
      params: {
        semesterId: String(this.selectedSemesterId)
      }
    }).catch((error: Error) => {
      console.error('[TableUI] 跳转网页刷新页失败:', error);
    });
  }

  private async loadCourseList(): Promise<void> {
    try {
      // 按当前查看学期读取课程列表（与主网格数据源一致），
      // 不再读 CourseService.loadCourses 的「当前真实学期」分片，避免列表与查看学期脱钩
      const allCourses: Course[] =
        await CourseService.loadCoursesForSemester(getContext(this), this.selectedSemesterId);
      allCourses.sort((a, b) => {
        if (a.time.dayOfWeek !== b.time.dayOfWeek) {
          return a.time.dayOfWeek - b.time.dayOfWeek;
        }
        return a.time.startSection - b.time.startSection;
      });
      this.courses = allCourses;
    } catch (error) {
      console.error('[TableUI] 加载本地课程失败:', error);
      this.courses = [];
    }
  }

  private buildValidWeeksFromText(weeksText: string): string {
    const weeks: boolean[] = [];
    for (let i = 0; i < 31; i++) {
      weeks.push(false);
    }
    const cleaned: string = weeksText.replace(/\s+/g, '');
    const segments: string[] = cleaned.split(',').filter(item => item.length > 0);

    if (segments.length === 0) {
      for (let w = 1; w <= 20; w++) {
        weeks[w] = true;
      }
    } else {
      for (const segment of segments) {
        if (segment.includes('-')) {
          const parts: string[] = segment.split('-');
          if (parts.length !== 2) {
            continue;
          }
          const start: number = Number(parts[0]);
          const end: number = Number(parts[1]);
          if (Number.isNaN(start) || Number.isNaN(end)) {
            continue;
          }
          const left: number = Math.max(1, Math.min(start, end));
          const right: number = Math.min(30, Math.max(start, end));
          for (let w = left; w <= right; w++) {
            weeks[w] = true;
          }
        } else {
          const week: number = Number(segment);
          if (!Number.isNaN(week) && week >= 1 && week <= 30) {
            weeks[week] = true;
          }
        }
      }
    }

    let result: string = '0';
    for (let w = 1; w <= 30; w++) {
      result += weeks[w] ? '1' : '0';
    }
    return result;
  }

  private validWeeksToText(validWeeks: string): string {
    if (!validWeeks || validWeeks.length < 2) {
      return '1-20';
    }

    const ranges: string[] = [];
    let start: number = -1;
    let prev: number = -1;

    for (let i = 1; i < validWeeks.length; i++) {
      if (validWeeks[i] === '1') {
        if (start === -1) {
          start = i;
        }
        prev = i;
      } else if (start !== -1) {
        ranges.push(start === prev ? `${start}` : `${start}-${prev}`);
        start = -1;
        prev = -1;
      }
    }

    if (start !== -1) {
      ranges.push(start === prev ? `${start}` : `${start}-${prev}`);
    }

    return ranges.length > 0 ? ranges.join(',') : '1-20';
  }

  private generateCourseId(name: string): string {
    return `${name}_${Date.now()}`;
  }

  private openAddEditor(): void {
    this.editIndex = -1;
    this.formId = '';
    this.formName = '';
    this.formTeacher = '';
    this.formRoom = '';
    this.formDay = 1;
    this.formStartSection = 1;
    this.formDuration = 2;
    this.formWeeks = '1-20';
    this.showEditor = true;
  }

  private openEditEditor(index: number): void {
    const course: Course = this.courses[index];
    this.editIndex = index;
    this.formId = course.id;
    this.formName = course.name;
    this.formTeacher = course.teacherName;
    this.formRoom = course.roomName;
    this.formDay = course.time.dayOfWeek;
    this.formStartSection = course.time.startSection;
    this.formDuration = course.time.duration;
    this.formWeeks = this.validWeeksToText(course.validWeeks);
    this.showEditor = true;
  }

  private async confirmEditor(): Promise<void> {
    if (!this.formName.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '课程名称不能为空' });
      return;
    }

    const newCourse: Course = {
      id: this.formId.trim() || this.generateCourseId(this.formName.trim()),
      name: this.formName.trim(),
      teacherName: this.formTeacher.trim(),
      roomName: this.formRoom.trim(),
      validWeeks: this.buildValidWeeksFromText(this.formWeeks),
      colorIndex: Math.floor(Math.random() * 10),
      time: {
        dayOfWeek: this.formDay,
        startSection: this.formStartSection,
        duration: this.formDuration,
      }
    };

    const context = getContext(this);
    // 按当前查看学期读写，杜绝「读当前学期分片 → 写 selected 分片」的跨学期拷贝；
    // 以 (id, dayOfWeek, startSection) 定位被编辑课程（loadFromJson 合并连堂后每条课程在该学期内唯一）
    const semesterCourses: Course[] =
      await CourseService.loadCoursesForSemester(context, this.selectedSemesterId);
    let edited: Course | null = null;
    if (this.editIndex >= 0 && this.editIndex < this.courses.length) {
      edited = this.courses[this.editIndex];
    }
    let replaced = false;
    if (edited !== null) {
      for (let i = 0; i < semesterCourses.length; i++) {
        const candidate = semesterCourses[i];
        if (candidate.id === edited.id &&
            candidate.time.dayOfWeek === edited.time.dayOfWeek &&
            candidate.time.startSection === edited.time.startSection) {
          semesterCourses[i] = newCourse;
          replaced = true;
          break;
        }
      }
    }
    if (!replaced) {
      semesterCourses.push(newCourse);
    }

    this.showEditor = false;
    await CourseService.saveCoursesForSemester(context, this.selectedSemesterId, semesterCourses);

    const rawJson = await CourseRepository.loadCourseDataBySemester(context, this.selectedSemesterId);
    if (rawJson) {
      this.applyCourseData(rawJson);
      this.hasCourseDataForSemester = true;
    }

    await this.loadCourseList();
  }

  private async deleteCourse(index: number): Promise<void> {
    if (index < 0 || index >= this.courses.length) {
      return;
    }
    const context = getContext(this);
    const target: Course = this.courses[index];
    // 按当前查看学期读写，按 (id, dayOfWeek, startSection) 身份删除，杜绝跨学期拷贝
    const semesterCourses: Course[] =
      await CourseService.loadCoursesForSemester(context, this.selectedSemesterId);
    const remaining: Course[] = [];
    let removed = false;
    for (const c of semesterCourses) {
      if (!removed && c.id === target.id &&
          c.time.dayOfWeek === target.time.dayOfWeek &&
          c.time.startSection === target.time.startSection) {
        removed = true;
        continue;
      }
      remaining.push(c);
    }
    if (!removed) {
      console.warn('[TableUI] 待删除课程不在当前查看学期分片中，跳过删除');
      await this.loadCourseList();
      return;
    }

    await CourseService.saveCoursesForSemester(context, this.selectedSemesterId, remaining);

    const rawJson = await CourseRepository.loadCourseDataBySemester(context, this.selectedSemesterId);
    if (rawJson) {
      this.applyCourseData(rawJson);
      this.hasCourseDataForSemester = remaining.length > 0;
    }

    await this.loadCourseList();
  }

  build() {
    Column() {
      this.HeaderBuilder()
      this.CourseTableBuilder()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getCardColor())
    .bindSheet($$this.showCourseManage, this.CourseManagerSheetBuilder(), {
      detents: [SheetSize.LARGE],
      showClose: true,
      title: { title: '课程管理' }
    })
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

        Row({ space: 8 }) {

          Image($r('app.media.settings_icon'))
            .width(20)
            .height(20)
            .padding(1)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.showCourseManage = true;
              this.loadCourseList();
            })

          Image($r('app.media.download'))
            .width(20)
            .height(20)
            .padding(1)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.refreshFromWeb();
            })
        }
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

  @Builder
  CourseManagerSheetBuilder() {
    Column() {
      Row({ space: 8 }) {
        Button('新增课程')
          .onClick(() => this.openAddEditor());
        Button('截图/全屏管理')
          .onClick(() => {
            this.showCourseManage = false;
            router.pushUrl({ url: 'pages/classTablePages/CourseManage' });
          });
        Button('刷新')
          .onClick(() => this.loadCourseList());
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      if (this.showEditor) {
        this.CourseEditorBuilder()
      } else if (this.courses.length === 0) {
        Text('暂无本地课程')
          .fontSize(14)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .margin({ top: 24 })
      } else {
        List() {
          ForEach(this.courses, (course: Course, index: number) => {
            ListItem() {
              Column() {
                Text(course.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .width('100%');
                Text(`周${this.weekDays[course.time.dayOfWeek - 1]} ${course.time.startSection}-${course.time.startSection + course.time.duration - 1}节`)
                  .fontSize(13)
                  .fontColor(ThemeManager.getTextPrimaryColor())
                  .width('100%')
                  .margin({ top: 4 });
                Text(`${course.roomName || '地点未知'} ${course.teacherName || '教师未知'}`)
                  .fontSize(13)
                  .fontColor(ThemeManager.getTextSecondaryColor())
                  .width('100%')
                  .margin({ top: 2 });
                Text(`周次: ${this.validWeeksToText(course.validWeeks)}`)
                  .fontSize(12)
                  .fontColor(ThemeManager.getTextTertiaryColor())
                  .width('100%')
                  .margin({ top: 2 });

                Row({ space: 8 }) {
                  Button('编辑')
                    .onClick(() => this.openEditEditor(index));
                  Button('删除')
                    .fontColor('#D32F2F')
                    .onClick(() => this.deleteCourse(index));
                }
                .margin({ top: 8 });
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(ThemeManager.getBackgroundColor())
              .margin({ left: 12, right: 12, top: 6, bottom: 6 });
            }
          });
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  CourseEditorBuilder() {
    Column() {
      Text(this.editIndex >= 0 ? '编辑课程' : '新增课程')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 });

      TextInput({ text: this.formName, placeholder: '课程名称' })
        .onChange((v: string) => this.formName = v)
        .width('100%')
        .margin({ bottom: 8 });

      TextInput({ text: this.formTeacher, placeholder: '教师' })
        .onChange((v: string) => this.formTeacher = v)
        .width('100%')
        .margin({ bottom: 8 });

      TextInput({ text: this.formRoom, placeholder: '地点' })
        .onChange((v: string) => this.formRoom = v)
        .width('100%')
        .margin({ bottom: 8 });

      TextInput({ text: this.formWeeks, placeholder: '上课周次,如 1-16,18' })
        .onChange((v: string) => this.formWeeks = v)
        .width('100%')
        .margin({ bottom: 8 });

      Row({ space: 8 }) {
        Text('星期')
          .width(60);
        Select(this.getDayOptions())
          .selected(this.formDay - 1)
          .value(String(this.getDayOptions()[this.formDay - 1].value))
          .onSelect((index: number) => this.formDay = index + 1)
          .layoutWeight(1);
      }
      .width('100%')
      .margin({ bottom: 8 });

      Row({ space: 8 }) {
        Text('开始节次')
          .width(60);
        Select(this.getSectionOptions())
          .selected(this.formStartSection - 1)
          .value(String(this.getSectionOptions()[this.formStartSection - 1].value))
          .onSelect((index: number) => this.formStartSection = index + 1)
          .layoutWeight(1);
      }
      .width('100%')
      .margin({ bottom: 8 });

      Row({ space: 8 }) {
        Text('持续节数')
          .width(60);
        Select(this.getDurationOptions())
          .selected(this.formDuration - 1)
          .value(String(this.getDurationOptions()[this.formDuration - 1].value))
          .onSelect((index: number) => this.formDuration = index + 1)
          .layoutWeight(1);
      }
      .width('100%')
      .margin({ bottom: 12 });

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => this.showEditor = false);
        Button('保存')
          .layoutWeight(1)
          .onClick(() => this.confirmEditor());
      }
      .width('100%');
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }

  private getDayOptions(): SelectOption[] {
    return [
      { value: '周一' }, { value: '周二' }, { value: '周三' }, { value: '周四' },
      { value: '周五' }, { value: '周六' }, { value: '周日' }
    ];
  }

  private getSectionOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 1; i <= 12; i++) {
      options.push({ value: `${i}节` });
    }
    return options;
  }

  private getDurationOptions(): SelectOption[] {
    return [{ value: '1节' }, { value: '2节' }, { value: '3节' }, { value: '4节' }];
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
    this.weekDates = getWeekDatesForWeek(this.currentWeek);
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
  EmptySemesterCardBuilder() {
    Column({ space: 12 }) {
      Text('📅')
        .fontSize(44)
        .margin({ top: 60, bottom: 8 })

      Text(`${this.getSelectedSemesterLabel()} 暂无本地课表`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getTextPrimaryColor())

      Text('您可以从教务系统一键导入该学期课表，导入后将永久归档至本地，支持无网离线查看。')
        .fontSize(13)
        .fontColor(ThemeManager.getTextSecondaryColor())
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      Button('📥 导入该学期课表')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor(ThemeManager.getAccentColor())
        .borderRadius(12)
        .height(40)
        .padding({ left: 24, right: 24 })
        .margin({ top: 12 })
        .onClick(() => {
          this.refreshFromWeb();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({ top: 20, bottom: 40 })
  }

  @Builder
  CourseTableBuilder() {
    if (!this.hasCourseDataForSemester) {
      this.EmptySemesterCardBuilder()
    } else {
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

  private isTodayColumn(dayOfWeek: number): boolean {
    const today = new Date();
    const todayDow = today.getDay() === 0 ? 7 : today.getDay();
    return this.currentWeek === getCurrentWeek() && dayOfWeek === todayDow;
  }

  private getCurrentTimeOffset(): number {
    const now = new Date();
    const currentMinutes = now.getHours() * 60 + now.getMinutes();
    const dayStartMinutes = 8 * 60 + 30; // 08:30
    const dayEndMinutes = 22 * 60 + 45;   // 22:45
    if (currentMinutes < dayStartMinutes || currentMinutes > dayEndMinutes) {
      return -1;
    }
    const ratio = (currentMinutes - dayStartMinutes) / (dayEndMinutes - dayStartMinutes);
    return ratio * (12 * this.getScaledSectionHeight());
  }

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

      if (this.isTodayColumn(dayOfWeek) && this.getCurrentTimeOffset() >= 0) {
        Row() {
          Circle({ width: 7, height: 7 })
            .fill('#FF3B30')
            .margin({ left: -3.5 })
          Row()
            .layoutWeight(1)
            .height(2)
            .backgroundColor('#FF3B30')
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .position({ x: 0, y: this.getCurrentTimeOffset() })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.getScaledDayColumnWidth())
    .height(this.getTableHeight())
  }

  @Builder
  CourseCardBuilder(course: Course) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(3.5)
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.15)')
        .borderRadius({ topLeft: 10, bottomLeft: 10 })

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
          Row({ space: 2 }) {
            Text('📍')
              .fontSize(9)
            Text(course.roomName)
              .fontSize(11)
              .fontColor(ThemeManager.getTextSecondaryColor())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(14)
              .layoutWeight(1)
          }
          .margin({ top: 4 })
          .width('100%')
        }

        if (course.teacherName) {
          Text(course.teacherName)
            .fontSize(10)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(13)
            .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 9, right: 6, top: 7, bottom: 7 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
    }
    .width(this.getScaledDayColumnWidth() - this.CARD_HORIZONTAL_MARGIN * 2)
    .height(course.time.duration * this.getScaledSectionHeight() - 8)
    .backgroundColor(COURSE_COLORS[course.colorIndex % COURSE_COLORS.length])
    .borderRadius(10)
    .shadow({ radius: 4, color: 'rgba(0, 0, 0, 0.06)', offsetX: 0, offsetY: 1 })
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
