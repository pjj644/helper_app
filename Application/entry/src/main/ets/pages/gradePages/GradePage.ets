import { router } from '@kit.ArkUI';
import { GradeItem, GradeSemesterOption, GradeUtils } from '../../model/GradeModel';
import { getPreviousSemesterId } from '../../model/classTableModel/ExamAccessRules';
import { GradeService } from '../../service/GradeService';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { EmptyState } from '../../components/EmptyState';
import { PageContextTracker } from '../../common/agent/PageContextTracker';
import { UIActionDispatcher } from '../../common/agent/UIActionDispatcher';
import { VisionScheduleHelper, VisionGradeReportResult, VisionGradeItem } from '../../common/agent/VisionScheduleHelper';

@Entry
@Component
struct GradePage {
  @State grades: GradeItem[] = [];
  @State filteredGrades: GradeItem[] = [];
  @State semesterOptions: GradeSemesterOption[] = [{ semesterId: 0, label: '所有学期' }];
  @State selectedSemesterIndex: number = 0;
  @State gpa: number = 0;
  @State totalCredits: number = 0;
  @State courseCount: number = 0;
  @State isLoading: boolean = true;
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  private unregisterAction: (() => void) | null = null;

  aboutToAppear(): void {
    this.loadGrades();
    this.unregisterAction = UIActionDispatcher.getInstance().registerHandler('import_grades', (params: Record<string, Object>) => {
      this.openGradeImport();
      return true;
    });
  }

  aboutToDisappear(): void {
    if (this.unregisterAction) {
      this.unregisterAction();
      this.unregisterAction = null;
    }
  }

  onPageShow(): void {
    this.loadGrades();
  }

  private async loadGrades(): Promise<void> {
    try {
      this.isLoading = true;
      const context = getContext(this);
      this.grades = await GradeService.loadGrades(context);
      this.semesterOptions = GradeService.getSemesterList(this.grades);
      this.applyFilter();
    } catch (error) {
      console.error('[GradePage] loadGrades error:', JSON.stringify(error));
      this.grades = [];
    } finally {
      this.isLoading = false;
    }
  }

  private getSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < this.semesterOptions.length; i++) {
      opts.push({ value: this.semesterOptions[i].label });
    }
    return opts;
  }

  private getSelectedSemesterId(): number {
    return this.semesterOptions[this.selectedSemesterIndex]?.semesterId || 0;
  }

  @State isImportingVision: boolean = false;

  private openGradeImport(): void {
    const currentSemId: number = this.getSelectedSemesterId();
    const targetSemId: number = currentSemId > 0 ? currentSemId : getPreviousSemesterId();
    router.pushUrl({
      url: 'pages/gradePages/GradeImport',
      params: { semesterId: targetSemId }
    });
  }

  private async importGradesFromScreenshot(): Promise<void> {
    if (this.isImportingVision) {
      return;
    }
    try {
      const uri = await VisionScheduleHelper.pickImage();
      if (!uri) {
        return;
      }
      this.isImportingVision = true;
      this.getUIContext().getPromptAction().showToast({ message: '正在通过 AI 识别成绩单截图...' });

      const base64 = await VisionScheduleHelper.convertUriToBase64(uri);
      if (!base64) {
        this.getUIContext().getPromptAction().showToast({ message: '读取图片失败' });
        this.isImportingVision = false;
        return;
      }

      const result: VisionGradeReportResult | null = await VisionScheduleHelper.parseGradeReportFromImage(getContext(this), base64);
      if (!result || !result.grades || result.grades.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '未能识别出成绩数据，请确保图片清晰' });
        this.isImportingVision = false;
        return;
      }

      const currentSemId = this.getSelectedSemesterId() > 0 ? this.getSelectedSemesterId() : getPreviousSemesterId();
      const newGrades: GradeItem[] = [];
      for (let i = 0; i < result.grades.length; i++) {
        const vg: VisionGradeItem = result.grades[i];
        const item: GradeItem = {
          academicYear: vg.semester || '2025-2026-1',
          courseCode: vg.courseCode || `VIS_${Date.now()}_${i + 1}`,
          courseSeq: '01',
          courseName: vg.courseName || '未知课程',
          courseCategory: vg.courseCategory || '必修',
          credit: Number(vg.credit) || 0,
          finalExamScore: String(vg.score || ''),
          totalScore: String(vg.score || ''),
          makeupScore: '',
          finalScore: String(vg.score || ''),
          gradePoint: Number(vg.gradePoint) || 0,
          semesterId: currentSemId
        };
        newGrades.push(item);
      }

      const merged = GradeService.mergeGrades(this.grades, newGrades);
      await GradeService.saveGrades(getContext(this), merged);
      await this.loadGrades();
      this.getUIContext().getPromptAction().showToast({ message: `成功识别并导入 ${newGrades.length} 门课程成绩` });
    } catch (e) {
      console.error('[GradePage] 截图识别成绩失败:', JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '截图识别成绩失败' });
    } finally {
      this.isImportingVision = false;
    }
  }

  private applyFilter(): void {
    const semesterId: number = this.getSelectedSemesterId();
    if (semesterId === 0) {
      this.filteredGrades = this.grades;
      this.gpa = GradeService.calculateOverallGPA(this.grades);
    } else {
      this.filteredGrades = GradeService.filterBySemester(this.grades, semesterId);
      this.gpa = GradeService.calculateSemesterGPA(this.filteredGrades);
    }
    this.totalCredits = GradeUtils.getTotalCredits(this.filteredGrades);
    this.courseCount = this.filteredGrades.length;

    const gradeListSummary = this.filteredGrades.slice(0, 10).map((g: GradeItem) => `${g.courseName}: ${g.finalScore || g.totalScore || '--'}分 (${g.gradePoint}绩点, ${g.credit}学分)`);
    PageContextTracker.getInstance().updateSnapshot(
      'grade',
      '成绩查询',
      `当前学期GPA: ${this.gpa.toFixed(2)}，总学分: ${this.totalCredits}，已出成绩科目: ${this.courseCount}门`,
      {
        'gpa': this.gpa.toFixed(2),
        'totalCredits': this.totalCredits,
        'courseCount': this.courseCount,
        'topGrades': gradeListSummary
      },
      [
        { actionId: 'import_grades', label: '从教务系统导入成绩', description: '打开教务成绩导入页面' }
      ]
    );
  }

  build() {
    Column() {
      Row() {
        Button() {
          Text('‹')
            .fontSize(24)
            .fontColor(ThemeManager.getTextPrimaryColor())
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back();
        })

        Text('成绩查询')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .margin({ left: 4 })

        Blank();

        Button(this.isImportingVision ? '识别中...' : '截图导入')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeManager.getAccentColor())
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(16)
          .height(32)
          .padding({ left: 12, right: 12 })
          .margin({ right: 8 })
          .enabled(!this.isImportingVision)
          .onClick(() => {
            this.importGradesFromScreenshot();
          });

        Button('在线导入')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeManager.getAccentColor())
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(16)
          .height(32)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.openGradeImport();
          });
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 6 })
      .alignItems(VerticalAlign.Center);

      if (this.isLoading) {
        LoadingProgress().margin(40);
        Blank();
      } else {
        // 🏆 GPA 综合概览 Hero 卡片
        Column({ space: 12 }) {
          Row() {
            Column({ space: 4 }) {
              Text('当前学期 GPA')
                .fontSize(12)
                .fontColor(ThemeManager.getTextSecondaryColor());

              Row({ space: 8 }) {
                Text(this.gpa > 0 ? this.gpa.toFixed(2) : '--')
                  .fontSize(38)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.gpa >= 3.5 ? '#10B981' : (this.gpa >= 2.5 ? '#F59E0B' : '#EF4444'));

                if (this.gpa > 0) {
                  Text(this.gpa >= 3.7 ? '优秀' : (this.gpa >= 2.7 ? '良好' : '及格'))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(10)
                    .backgroundColor(this.gpa >= 3.5 ? '#10B981' : (this.gpa >= 2.5 ? '#F59E0B' : '#EF4444'));
                }
              }
              .alignItems(VerticalAlign.Center);
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1);

            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text('已修学分')
                  .fontSize(11)
                  .fontColor(ThemeManager.getTextTertiaryColor());
                Text(`${this.totalCredits}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeManager.getTextPrimaryColor());
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.isDarkMode ? '#1E293B' : '#F1F5F9')
              .borderRadius(8);

              Column({ space: 2 }) {
                Text('课程总数')
                  .fontSize(11)
                  .fontColor(ThemeManager.getTextTertiaryColor());
                Text(`${this.courseCount}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeManager.getTextPrimaryColor());
              }
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.isDarkMode ? '#1E293B' : '#F1F5F9')
              .borderRadius(8);
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center);
        }
        .width('92%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(ThemeManager.getCardColor())
        .shadow({ radius: 6, color: 'rgba(0, 0, 0, 0.04)', offsetX: 0, offsetY: 2 })
        .margin({ top: 8, bottom: 8 });

        Row() {
          Text('学期筛选')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getTextSecondaryColor());
          Blank();
          Select(this.getSelectOptions())
            .selected(this.selectedSemesterIndex)
            .value(String(this.getSelectOptions()[this.selectedSemesterIndex]?.value || '所有学期'))
            .onSelect((index: number) => {
              this.selectedSemesterIndex = index;
              this.applyFilter();
            })
            .width(160);
        }
        .width('92%')
        .margin({ top: 4, bottom: 8 });

        if (this.filteredGrades.length === 0) {
          Column() {
            EmptyState({
              title: '暂无成绩数据',
              description: '请点击右上角"在线导入"获取成绩',
              buttonText: '在线导入',
              onButtonClick: () => this.openGradeImport()
            });
          }
          .width('100%')
          .margin({ top: 60 });
          Blank();
        } else {
          List({ space: 8 }) {
            ForEach(this.filteredGrades, (item: GradeItem) => {
              ListItem() {
                Row() {
                  Column()
                    .width(4)
                    .height(36)
                    .backgroundColor(GradeUtils.getGpaColor(item.gradePoint))
                    .borderRadius(2)
                    .margin({ right: 10 });

                  Column({ space: 4 }) {
                    Text(item.courseName)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(ThemeManager.getTextPrimaryColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });

                    Row({ space: 6 }) {
                      Text(`${item.credit} 学分`)
                        .fontSize(11)
                        .fontColor(ThemeManager.getAccentColor())
                        .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                        .backgroundColor(ThemeManager.getAccentBgColor())
                        .borderRadius(4);

                      if (item.courseCategory) {
                        Text(item.courseCategory)
                          .fontSize(11)
                          .fontColor(ThemeManager.getTextTertiaryColor())
                          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                          .backgroundColor(this.isDarkMode ? '#1E293B' : '#F1F5F9')
                          .borderRadius(4);
                      }
                    }
                    .margin({ top: 2 });
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1);

                  Column({ space: 2 }) {
                    if (item.totalScore && item.totalScore !== '--') {
                      Text(item.totalScore)
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(ThemeManager.getTextPrimaryColor());
                      Text('总评')
                        .fontSize(10)
                        .fontColor(ThemeManager.getTextTertiaryColor());
                    } else if (item.finalScore && item.finalScore !== '--') {
                      Text(item.finalScore)
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(ThemeManager.getTextPrimaryColor());
                      Text('最终')
                        .fontSize(10)
                        .fontColor(ThemeManager.getTextTertiaryColor());
                    } else {
                      Text('--')
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(ThemeManager.getTextTertiaryColor());
                    }
                  }
                  .margin({ left: 8, right: 12 })
                  .alignItems(HorizontalAlign.Center);

                  Text(GradeUtils.getGpaLabel(item.gradePoint))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .borderRadius(10)
                    .backgroundColor(GradeUtils.getGpaColor(item.gradePoint));
                }
                .width('100%')
                .padding({ left: 10, right: 12, top: 12, bottom: 12 })
                .borderRadius(12)
                .backgroundColor(ThemeManager.getCardColor())
                .shadow({ radius: 3, color: 'rgba(0, 0, 0, 0.03)', offsetX: 0, offsetY: 1 })
                .alignItems(VerticalAlign.Center);
              }
            });
          }
          .width('92%')
          .layoutWeight(1);
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor());
  }
}