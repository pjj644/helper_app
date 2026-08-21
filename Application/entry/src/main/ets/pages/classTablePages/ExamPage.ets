import { router } from '@kit.ArkUI';
import { ExamItem } from '../../model/classTableModel/ExamModel';
import { EXAM_TYPE_OPTIONS, calculateSemesterId, getExamTypeLabelById, getSemesterLabelById, getSemesterOptions, SemesterOptionSet } from '../../model/classTableModel/ExamAccessRules';
import { ExamService } from '../../service/ExamService';
import { ExamUtils } from '../../common/utils/ExamUtils';
import { DateUtils } from '../../common/utils/DateUtils';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { PageContextTracker } from '../../common/agent/PageContextTracker';
import { UIActionDispatcher } from '../../common/agent/UIActionDispatcher';
import { AppConstants } from '../../common/constants/AppConstants';

@Entry
@Component
struct ExamPage {
  @State allExams: ExamItem[] = [];
  @State exams: ExamItem[] = [];
  @State nowTick: number = Date.now();
  @State showDetail: boolean = false;
  @State selected: ExamItem = ExamUtils.createEmptyExam();
  @State selectedExamTypeIndex: number = 0;
  @State semesterOptions: SelectOption[] = [{ value: '全部学期' }];
  @State semesterOptionIds: number[] = [0];
  @State selectedSemesterIndex: number = 0;
  private tickTimer: number = -1;
  private unregisterImport: (() => void) | null = null;

  private normalizeExamTypeIndex(index: number): number {
    if (index < 0 || index >= EXAM_TYPE_OPTIONS.length) {
      return 0;
    }
    return index;
  }

  private getSelectedExamTypeId(): number {
    return ExamService.getExamTypeIdByIndex(this.selectedExamTypeIndex);
  }

  private getSelectedExamTypeLabel(): string {
    return getExamTypeLabelById(this.getSelectedExamTypeId());
  }

  private normalizeSemesterIndex(index: number): number {
    if (index < 0 || index >= this.semesterOptionIds.length) {
      return 0;
    }
    return index;
  }

  aboutToAppear(): void {
    const semesterSet: SemesterOptionSet = getSemesterOptions();
    this.semesterOptions = semesterSet.options;
    this.semesterOptionIds = semesterSet.semesterIds;
    this.initSelection();
    this.tickTimer = setInterval(() => {
      this.nowTick = Date.now();
    }, 1000);

    this.unregisterImport = UIActionDispatcher.getInstance().registerHandler('import_exams', () => {
      this.openImport();
      return true;
    });
  }

  aboutToDisappear(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    if (this.unregisterImport) {
      this.unregisterImport();
      this.unregisterImport = null;
    }
  }

  private async initSelection(): Promise<void> {
    const params = router.getParams() as Record<string, string>;
    const hasExamTypeParam: boolean = !!(params && params['examTypeId']);
    const hasSemesterParam: boolean = !!(params && params['semesterId']);
    const context = getContext(this);
    const savedSelection = await ExamService.loadSelectionPreference(context);

    const selectedExamTypeId: number = hasExamTypeParam
      ? Number.parseInt(params['examTypeId'] || '0', 10)
      : savedSelection.examTypeId;
    this.selectedExamTypeIndex = this.normalizeExamTypeIndex(ExamService.getExamTypeIndexById(selectedExamTypeId));

    const semesterValue: string | number | undefined = hasSemesterParam ? params['semesterId'] : savedSelection.semesterId;
    const parsedSemesterId: number = typeof semesterValue === 'number'
      ? semesterValue
      : Number.parseInt(String(semesterValue || ''), 10);
    if (Number.isFinite(parsedSemesterId) && parsedSemesterId >= 0) {
      const semesterIndex: number = this.semesterOptionIds.indexOf(parsedSemesterId);
      this.selectedSemesterIndex = this.normalizeSemesterIndex(semesterIndex >= 0 ? semesterIndex : 0);
    } else {
      this.selectedSemesterIndex = 0;
    }
    this.loadExamData();
  }

  onPageShow(): void {
    this.loadExamData();
  }

  private async loadExamData(): Promise<void> {
    try {
      const context = getContext(this);
      this.allExams = await ExamService.loadExams(context);
      this.applyFilters();
    } catch (error) {
      console.error('加载考试数据失败:', error);
      this.allExams = [];
      this.exams = [];
    }
  }

  private applyFilters(): void {
    this.selectedExamTypeIndex = this.normalizeExamTypeIndex(this.selectedExamTypeIndex);
    this.selectedSemesterIndex = this.normalizeSemesterIndex(this.selectedSemesterIndex);
    const selectedTypeId: number = ExamService.getExamTypeIdByIndex(this.selectedExamTypeIndex);
    const selectedSemesterId: number = this.semesterOptionIds[this.selectedSemesterIndex] || 0;
    const now: number = Date.now();
    this.exams = ExamService.filterExams(this.allExams, selectedTypeId, selectedSemesterId);

    const examSummary = this.exams.slice(0, 8).map((e: ExamItem) => `${e.courseName}: ${e.examDate} ${e.examTimeRange} (${e.examLocation || '考场未定'})`);
    PageContextTracker.getInstance().updateSnapshot(
      'exam',
      '考试安排',
      `当前类型[${this.getSelectedExamTypeLabel()}]，共 ${this.exams.length} 场考试`,
      {
        'examType': this.getSelectedExamTypeLabel(),
        'semester': this.getSelectedSemesterLabel(),
        'totalExams': this.exams.length,
        'exams': examSummary
      },
      [
        { actionId: 'import_exams', label: '导入教务考试', description: '从教务系统在线导入考试安排' }
      ]
    );
  }

  private getSelectedSemesterId(): number {
    return this.semesterOptionIds[this.selectedSemesterIndex] || 0;
  }

  private getSelectedSemesterLabel(): string {
    const idx: number = this.normalizeSemesterIndex(this.selectedSemesterIndex);
    const option: SelectOption | undefined = this.semesterOptions[idx];
    if (!option) {
      return '全部学期';
    }
    if (typeof option.value === 'string') {
      return option.value;
    }
    const semesterId: number = this.getSelectedSemesterId();
    return semesterId > 0 ? getSemesterLabelById(semesterId) : '全部学期';
  }

  private saveSelectionPreference(): void {
    const examTypeId: number = ExamService.getExamTypeIdByIndex(this.selectedExamTypeIndex);
    const semesterId: number = this.getSelectedSemesterId();
    ExamService.saveSelectionPreference(getContext(this), examTypeId, semesterId).catch((error: Error) => {
      console.error('保存考试筛选偏好失败:', error);
    });
  }

  private openImport(): void {
    const selectedSemesterId: number = this.getSelectedSemesterId() || calculateSemesterId();
    router.pushUrl({
      url: 'pages/classTablePages/ExamImport',
      params: {
        returnHome: '0',
        examTypeId: String(this.getSelectedExamTypeId()),
        semesterId: String(selectedSemesterId),
      }
    });
  }

  private openDetail(item: ExamItem): void {
    this.selected = item;
    this.showDetail = true;
  }

  private async deleteSelected(): Promise<void> {
    try {
      const context = getContext(this);
      const remained: ExamItem[] = this.allExams.filter((item: ExamItem) => !ExamService.isSameExam(item, this.selected));
      await ExamService.saveExams(context, remained);
      this.allExams = ExamUtils.sortExams(remained.map((item: ExamItem) => ExamUtils.normalizeStoredExam(item)));
      this.applyFilters();
      this.showDetail = false;
      this.getUIContext().getPromptAction().showToast({ message: '已删除该考试' });
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试' });
    }
  }

  private shouldShowCountDown(item: ExamItem): boolean {
    return item.beginTime > this.nowTick;
  }

  private getSemesterLabel(item: ExamItem): string {
    if (item.semesterLabel) {
      return item.semesterLabel;
    }
    if (item.semesterId > 0) {
      return getSemesterLabelById(item.semesterId);
    }
    return '学期未知';
  }

  @Builder
  private DetailLineBuilder(label: string, value: string): void {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontColor(ThemeManager.getTextSecondaryColor())
        .width(84);

      Text(value || '无')
        .layoutWeight(1)
        .fontSize(14)
        .fontColor(ThemeManager.getTextPrimaryColor());
    }
    .width('100%');
  }

  @Builder
  private DetailBuilder(): void {
    Column({ space: 10 }) {
      Text(this.selected.courseName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .width('100%');

      this.DetailLineBuilder('课程序号', this.selected.courseNo);
      this.DetailLineBuilder('考试日期', this.selected.examDate);
      this.DetailLineBuilder('考试时间', this.selected.examTimeRange);
      this.DetailLineBuilder('考试地点', this.selected.examLocation || '地点未知');
      this.DetailLineBuilder('座位号', this.selected.seatNo || '无');
      this.DetailLineBuilder('考试状态', this.selected.examStatus || '未知');
      this.DetailLineBuilder('考试类型', this.selected.examType || '未知');
      this.DetailLineBuilder('所属学期', this.getSemesterLabel(this.selected));
      this.DetailLineBuilder('备注', this.selected.remark || '无');

      Row({ space: 8 }) {
        Button('关闭')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
          .borderRadius(12)
          .onClick(() => this.showDetail = false);

        Button('删除该考试')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#D64545')
          .borderRadius(12)
          .onClick(() => this.deleteSelected());
      }
      .width('100%')
      .margin({ top: 8 });
    }
    .width('100%')
    .padding(16);
  }

  @Builder
  private HeaderBuilder(): void {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text('考试信息')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF');

          Text('支持按考试类型和学期筛选本地数据')
            .fontSize(13)
            .fontColor('#DCE8FF');
        }
        .alignItems(HorizontalAlign.Start);

        Blank();

        Button('返回')
          .height(34)
          .fontSize(13)
          .fontColor(ThemeManager.getAccentColor())
          .backgroundColor('#FFFFFF')
          .borderRadius(17)
          .onClick(() => router.back());
      }
      .width('100%');
    }
    .width('100%')
    .padding(16)
    .borderRadius(20)
    .backgroundColor(ThemeManager.getAccentColor());
  }

  @Builder
  private FilterBuilder(): void {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text('考试类型')
            .fontSize(12)
            .fontColor(ThemeManager.getTextSecondaryColor());

          Select(EXAM_TYPE_OPTIONS)
            .selected(this.selectedExamTypeIndex)
            .value(this.getSelectedExamTypeLabel())
            .onSelect((index: number) => {
              this.selectedExamTypeIndex = this.normalizeExamTypeIndex(index);
              this.applyFilters();
              this.saveSelectionPreference();
            })
            .width('100%');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Column({ space: 4 }) {
          Text('学期')
            .fontSize(12)
            .fontColor(ThemeManager.getTextSecondaryColor());

          Select(this.semesterOptions)
            .selected(this.selectedSemesterIndex)
            .value(this.getSelectedSemesterLabel())
            .onSelect((index: number) => {
              this.selectedSemesterIndex = this.normalizeSemesterIndex(index);
              this.applyFilters();
              this.saveSelectionPreference();
            })
            .width('100%');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%');

      Row({ space: 8 }) {
        Button(`在线导入${getExamTypeLabelById(ExamService.getExamTypeIdByIndex(this.selectedExamTypeIndex))}`)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(12)
          .onClick(() => this.openImport());

        Button('刷新')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(12)
          .onClick(() => this.loadExamData());
      }
      .width('100%');
    }
    .width('100%')
    .padding(12)
    .borderRadius(16)
    .backgroundColor(ThemeManager.getCardColor());
  }

  @Builder
  private EmptyBuilder(): void {
    Column({ space: 8 }) {
      Text('当前筛选条件下暂无考试')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextPrimaryColor());

      Text('请切换学期/考试类型，或先在线导入考试数据')
        .fontSize(13)
        .fontColor(ThemeManager.getTextSecondaryColor())
        .textAlign(TextAlign.Center);
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor(ThemeManager.getCardColor())
    .alignItems(HorizontalAlign.Center);
  }

  private getUrgencyBorderColor(item: ExamItem): string {
    const parts = DateUtils.getCountdownParts(Date.now(), item.beginTime);
    if (parts.isExpired || parts.isUnknown) {
      return 'transparent';
    }
    switch (parts.urgency) {
      case 3: return '#EF4444';
      case 2: return '#F59E0B';
      case 1: return '#3B82FF';
      default: return 'transparent';
    }
  }

  @Builder
  private ExamCardBuilder(item: ExamItem): void {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(item.courseName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');

          Text(`${item.examDate}  ${item.examTimeRange}`)
            .fontSize(13)
            .fontColor(ThemeManager.getTextSecondaryColor())
            .width('100%');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Text(item.examStatus || '状态未知')
          .fontSize(11)
          .fontColor(ThemeManager.getAccentColor())
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(10);
      }
      .width('100%');

      Row({ space: 4 }) {
        Text('📍')
          .fontSize(12)
        Text(item.examLocation || '地点未知')
          .fontSize(13)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (item.examLocation) {
          Row({ space: 2 }) {
            Text('🗺️ 查地图')
              .fontSize(11)
              .fontColor(ThemeManager.getAccentColor())
          }
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(6)
          .onClick((e?: ClickEvent) => {
            router.pushUrl({
              url: 'pages/classTablePages/WebPage',
              params: { title: '校园地图', url: AppConstants.GIS_MAP_URL }
            });
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Row() {
        Text(this.getSemesterLabel(item))
          .fontSize(12)
          .fontColor(ThemeManager.getTextSecondaryColor());

        Blank();

        if (this.shouldShowCountDown(item)) {
          Text(`倒计时 ${DateUtils.formatCountDown(this.nowTick, item.beginTime)}`)
            .fontSize(12)
            .fontColor(this.getUrgencyBorderColor(item) !== 'transparent' ? this.getUrgencyBorderColor(item) : ThemeManager.getAccentColor())
            .fontWeight(FontWeight.Medium);
        }
      }
      .width('100%');
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor(ThemeManager.getCardColor())
    .border({
      width: 1.5,
      color: this.getUrgencyBorderColor(item),
      style: BorderStyle.Solid
    })
    .onClick(() => this.openDetail(item));
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          this.HeaderBuilder();
          this.FilterBuilder();

          if (this.exams.length === 0) {
            this.EmptyBuilder();
          } else {
            List({ space: 8 }) {
              ForEach(this.exams, (item: ExamItem) => {
                ListItem() {
                  this.ExamCardBuilder(item);
                }
              });
            }
            .width('100%')
            .height('100%');
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 16 });
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundColor())
    .bindSheet($$this.showDetail, this.DetailBuilder(), {
      detents: [SheetSize.MEDIUM],
      showClose: true,
      title: {
        title: '考试详情'
      }
    });
  }
}
