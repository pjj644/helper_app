import { router } from '@kit.ArkUI';
import { GradeItem, GradeSemesterOption, GradeUtils } from '../../model/GradeModel';
import { getPreviousSemesterId } from '../../model/classTableModel/ExamAccessRules';
import { GradeService } from '../../service/GradeService';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { EmptyState } from '../../components/EmptyState';
import { PageContextTracker } from '../../common/agent/PageContextTracker';
import { UIActionDispatcher } from '../../common/agent/UIActionDispatcher';

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
      console.error('GradePage loadGrades error:', JSON.stringify(error));
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

  private openGradeImport(): void {
    const currentSemId: number = this.getSelectedSemesterId();
    const targetSemId: number = currentSemId > 0 ? currentSemId : getPreviousSemesterId();
    router.pushUrl({
      url: 'pages/gradePages/GradeImport',
      params: { semesterId: targetSemId }
    });
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
        Text('成绩查询')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor());
        Blank();
        Button('在线导入')
          .fontSize(13)
          .fontColor(ThemeManager.getAccentColor())
          .backgroundColor(ThemeManager.getAccentBgColor())
          .borderRadius(8)
          .onClick(() => {
            this.openGradeImport();
          });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 });

      if (this.isLoading) {
        LoadingProgress().margin(40);
        Blank();
      } else {
        Column() {
          Row() {
            Text(`GPA ${this.gpa.toFixed(2)}`)
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.gpa >= 3.5 ? '#4CAF50' : (this.gpa >= 2.5 ? '#FF9800' : '#F44336'));
            Blank();
            Column() {
              Text(`${this.courseCount} 门课程`).fontSize(12).fontColor('#9E9E9E');
              Text(`已修 ${this.totalCredits} 学分`).fontSize(12).fontColor('#9E9E9E');
            }
          }
          .width('100%');
        }
        .width('92%')
        .padding(16)
        .borderRadius(12)
        .backgroundColor(ThemeManager.getAccentBgColor())
        .margin({ top: 12, bottom: 8 });

        Row() {
          Text('学期筛选')
            .fontSize(14)
            .fontColor(ThemeManager.getTextSecondaryColor());
          Blank();
          Select(this.getSelectOptions())
            .selected(this.selectedSemesterIndex)
            .value(String(this.getSelectOptions()[this.selectedSemesterIndex].value))
            .onSelect((index: number) => {
              this.selectedSemesterIndex = index;
              this.applyFilter();
            })
            .width(180);
        }
        .width('92%')
        .margin({ top: 8, bottom: 8 });

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
                  Column() {
                    Text(item.courseName)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(ThemeManager.getTextPrimaryColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Row({ space: 6 }) {
                      Text(`${item.credit}学分`)
                        .fontSize(11)
                        .fontColor('#9E9E9E');
                      if (item.courseCategory) {
                        Text(item.courseCategory)
                          .fontSize(11)
                          .fontColor('#BDBDBD');
                      }
                    }
                    .margin({ top: 2 });
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1);

                  Column() {
                    if (item.totalScore && item.totalScore !== '--') {
                      Text(item.totalScore)
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(ThemeManager.getTextPrimaryColor());
                      Text('总评')
                        .fontSize(10)
                        .fontColor('#9E9E9E');
                    } else if (item.finalScore && item.finalScore !== '--') {
                      Text(item.finalScore)
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(ThemeManager.getTextPrimaryColor());
                      Text('最终')
                        .fontSize(10)
                        .fontColor('#9E9E9E');
                    } else {
                      Text('--')
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#9E9E9E');
                    }
                  }
                  .margin({ left: 8, right: 12 })
                  .alignItems(HorizontalAlign.Center);

                  Text(GradeUtils.getGpaLabel(item.gradePoint))
                    .fontSize(11)
                    .fontColor(Color.White)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(10)
                    .backgroundColor(GradeUtils.getGpaColor(item.gradePoint));
                }
                .width('100%')
                .padding(12);
              }
              .borderRadius(10)
              .backgroundColor(ThemeManager.isDarkMode() ? '#2D2D2D' : '#FFFFFF');
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