// 截图导入预览弹窗（P2-9）：
// 课表 / 成绩两处「截图导入」共用的入库前核对界面。
// 页面解析成功后构造 PreviewItem 数组并传入本组件（CustomDialogController 按需创建，
// 参考 CalendarPage 的用法）；行内 TextInput 直接把修改写回条目对象，勾选框决定该条
// 是否入库；点击「确认入库」经回调把选中条目交还页面，复用页面原有保存流程。
// confidence < 0.85 的整条以琥珀色高亮并提示核对（解析结构为条目级置信度）。

import { ThemeManager } from '../../common/utils/ThemeManager';
import { VisionCoursePreviewItem, VisionGradePreviewItem, isLowConfidenceScore } from '../../model/VisionImportModel';

const AMBER_COLOR: string = '#F59E0B';
const AMBER_SOFT_BG: string = 'rgba(245, 158, 11, 0.08)';

@Component
export struct VisionImportPreviewDialog {
  /** 预览模式：'course' 课表条目；'grade' 成绩条目 */
  previewMode: string = 'course';
  courseItems: VisionCoursePreviewItem[] = [];
  gradeItems: VisionGradePreviewItem[] = [];
  onConfirmCourses?: (items: VisionCoursePreviewItem[]) => void;
  onConfirmGrades?: (items: VisionGradePreviewItem[]) => void;
  onCancel?: () => void;

  private isGradeMode(): boolean {
    return this.previewMode === 'grade';
  }

  private totalCount(): number {
    return this.isGradeMode() ? this.gradeItems.length : this.courseItems.length;
  }

  private countSelected(): number {
    let count: number = 0;
    if (this.isGradeMode()) {
      for (let i = 0; i < this.gradeItems.length; i++) {
        if (this.gradeItems[i].selected) {
          count++;
        }
      }
    } else {
      for (let i = 0; i < this.courseItems.length; i++) {
        if (this.courseItems[i].selected) {
          count++;
        }
      }
    }
    return count;
  }

  private hasLowConfidenceItem(): boolean {
    if (this.isGradeMode()) {
      for (let i = 0; i < this.gradeItems.length; i++) {
        if (isLowConfidenceScore(this.gradeItems[i].confidence)) {
          return true;
        }
      }
      return false;
    }
    for (let i = 0; i < this.courseItems.length; i++) {
      if (isLowConfidenceScore(this.courseItems[i].confidence)) {
        return true;
      }
    }
    return false;
  }

  private handleCancel(): void {
    if (this.onCancel) {
      this.onCancel();
    }
  }

  private handleConfirm(): void {
    if (this.countSelected() === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请至少勾选一条要入库的记录' });
      return;
    }
    if (this.isGradeMode()) {
      const picked: VisionGradePreviewItem[] = [];
      for (let i = 0; i < this.gradeItems.length; i++) {
        if (this.gradeItems[i].selected) {
          picked.push(this.gradeItems[i]);
        }
      }
      if (this.onConfirmGrades) {
        this.onConfirmGrades(picked);
      }
    } else {
      const picked: VisionCoursePreviewItem[] = [];
      for (let i = 0; i < this.courseItems.length; i++) {
        if (this.courseItems[i].selected) {
          picked.push(this.courseItems[i]);
        }
      }
      if (this.onConfirmCourses) {
        this.onConfirmCourses(picked);
      }
    }
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(this.isGradeMode() ? '成绩导入预览' : '课表导入预览')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor());
        Blank();
        Text(`共 ${this.totalCount()} 条`)
          .fontSize(13)
          .fontColor(ThemeManager.getTextTertiaryColor());
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Text('请核对 AI 识别结果：可直接修改内容，取消勾选的条目不会入库')
        .fontSize(12)
        .fontColor(ThemeManager.getTextSecondaryColor())
        .width('100%');

      if (this.hasLowConfidenceItem()) {
        Row({ space: 6 }) {
          Circle()
            .width(8)
            .height(8)
            .fill(AMBER_COLOR);
          Text('存在低置信度条目，建议逐项核对')
            .fontSize(12)
            .fontColor(AMBER_COLOR);
        }
        .width('100%');
      }

      List({ space: 8 }) {
        if (this.isGradeMode()) {
          ForEach(this.gradeItems, (item: VisionGradePreviewItem, index: number) => {
            ListItem() {
              VisionGradePreviewRow({ item: item })
            }
          }, (item: VisionGradePreviewItem, index: number) => `g_${index}`)
        } else {
          ForEach(this.courseItems, (item: VisionCoursePreviewItem, index: number) => {
            ListItem() {
              VisionCoursePreviewRow({ item: item })
            }
          }, (item: VisionCoursePreviewItem, index: number) => `c_${index}`)
        }
      }
      .layoutWeight(1)
      .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
          .borderRadius(12)
          .onClick(() => {
            this.handleCancel();
          });
        Button('确认入库')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor(ThemeManager.getAccentColor())
          .borderRadius(12)
          .onClick(() => {
            this.handleConfirm();
          });
      }
      .width('100%');
    }
    .width('92%')
    .height('82%')
    .padding(16)
    .backgroundColor(ThemeManager.getBackgroundColor())
    .borderRadius(16);
  }
}

@Component
struct VisionCoursePreviewRow {
  item: VisionCoursePreviewItem = new VisionCoursePreviewItem();
  private lowConfidence: boolean = false;

  aboutToAppear(): void {
    this.lowConfidence = isLowConfidenceScore(this.item.confidence);
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Checkbox()
          .select(this.item.selected)
          .selectedColor(ThemeManager.getAccentColor())
          .onChange((value: boolean) => {
            this.item.selected = value;
          });
        TextInput({ text: this.item.name, placeholder: '课程名称' })
          .onChange((value: string) => {
            this.item.name = value;
          })
          .layoutWeight(1)
          .height(38)
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .placeholderColor(ThemeManager.getTextTertiaryColor())
          .backgroundColor(ThemeManager.getBackgroundColor())
          .borderRadius(8);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (this.lowConfidence) {
        Row({ space: 6 }) {
          Circle()
            .width(8)
            .height(8)
            .fill(AMBER_COLOR);
          Text('置信度较低，建议核对')
            .fontSize(12)
            .fontColor(AMBER_COLOR);
        }
        .width('100%');
      }

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('教师')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.teacher, placeholder: '教师' })
            .onChange((value: string) => {
              this.item.teacher = value;
            })
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .placeholderColor(ThemeManager.getTextTertiaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Column({ space: 2 }) {
          Text('教室')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.room, placeholder: '教室' })
            .onChange((value: string) => {
              this.item.room = value;
            })
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .placeholderColor(ThemeManager.getTextTertiaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%');

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('星期')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.dayOfWeekText })
            .onChange((value: string) => {
              this.item.dayOfWeekText = value;
            })
            .width(52)
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .alignItems(HorizontalAlign.Start);

        Column({ space: 2 }) {
          Text('起始节')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.startSectionText })
            .onChange((value: string) => {
              this.item.startSectionText = value;
            })
            .width(56)
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .alignItems(HorizontalAlign.Start);

        Column({ space: 2 }) {
          Text('持续节')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.durationText })
            .onChange((value: string) => {
              this.item.durationText = value;
            })
            .width(56)
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .alignItems(HorizontalAlign.Start);

        Blank();
      }
      .width('100%');

      Column({ space: 2 }) {
        Text('周次')
          .fontSize(11)
          .fontColor(ThemeManager.getTextTertiaryColor());
        TextInput({ text: this.item.weeksText, placeholder: '如 1-16,18' })
          .onChange((value: string) => {
            this.item.weeksText = value;
          })
          .width('100%')
          .height(34)
          .fontSize(13)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .placeholderColor(ThemeManager.getTextTertiaryColor())
          .backgroundColor(ThemeManager.getBackgroundColor())
          .borderRadius(8);
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);
    }
    .padding(12)
    .borderRadius(12)
    .width('100%')
    .backgroundColor(this.lowConfidence ? AMBER_SOFT_BG : ThemeManager.getCardColor())
    .border({
      width: this.lowConfidence ? 1 : 0,
      color: AMBER_COLOR
    });
  }
}

@Component
struct VisionGradePreviewRow {
  item: VisionGradePreviewItem = new VisionGradePreviewItem();
  private lowConfidence: boolean = false;
  private hasSemester: boolean = false;

  aboutToAppear(): void {
    this.lowConfidence = isLowConfidenceScore(this.item.confidence);
    this.hasSemester = this.item.semester.length > 0;
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Checkbox()
          .select(this.item.selected)
          .selectedColor(ThemeManager.getAccentColor())
          .onChange((value: boolean) => {
            this.item.selected = value;
          });
        TextInput({ text: this.item.courseName, placeholder: '课程名称' })
          .onChange((value: string) => {
            this.item.courseName = value;
          })
          .layoutWeight(1)
          .height(38)
          .fontSize(15)
          .fontColor(ThemeManager.getTextPrimaryColor())
          .placeholderColor(ThemeManager.getTextTertiaryColor())
          .backgroundColor(ThemeManager.getBackgroundColor())
          .borderRadius(8);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (this.lowConfidence) {
        Row({ space: 6 }) {
          Circle()
            .width(8)
            .height(8)
            .fill(AMBER_COLOR);
          Text('置信度较低，建议核对')
            .fontSize(12)
            .fontColor(AMBER_COLOR);
        }
        .width('100%');
      }

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('成绩')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.score, placeholder: '成绩' })
            .onChange((value: string) => {
              this.item.score = value;
            })
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .placeholderColor(ThemeManager.getTextTertiaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Column({ space: 2 }) {
          Text('学分')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.creditText, placeholder: '学分' })
            .onChange((value: string) => {
              this.item.creditText = value;
            })
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .placeholderColor(ThemeManager.getTextTertiaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        Column({ space: 2 }) {
          Text('绩点')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.gradePointText, placeholder: '绩点' })
            .onChange((value: string) => {
              this.item.gradePointText = value;
            })
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .placeholderColor(ThemeManager.getTextTertiaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%');

      if (this.hasSemester) {
        Column({ space: 2 }) {
          Text('学期')
            .fontSize(11)
            .fontColor(ThemeManager.getTextTertiaryColor());
          TextInput({ text: this.item.semester, placeholder: '如 2025-2026-1' })
            .onChange((value: string) => {
              this.item.semester = value;
            })
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .placeholderColor(ThemeManager.getTextTertiaryColor())
            .backgroundColor(ThemeManager.getBackgroundColor())
            .borderRadius(8);
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);
      }
    }
    .padding(12)
    .borderRadius(12)
    .width('100%')
    .backgroundColor(this.lowConfidence ? AMBER_SOFT_BG : ThemeManager.getCardColor())
    .border({
      width: this.lowConfidence ? 1 : 0,
      color: AMBER_COLOR
    });
  }
}
