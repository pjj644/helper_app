import { ExamItem } from '../model/classTableModel/ExamModel';
import { DateUtils } from '../common/utils/DateUtils';
import { ExamUtils } from '../common/utils/ExamUtils';
import { ThemeManager } from '../common/utils/ThemeManager';

@Component
export struct ExamCard {
  @Prop exam: ExamItem = {} as ExamItem;
  @Prop nowTick: number = Date.now();
  @Prop isCompact: boolean = false;
  onClick?: () => void;

  private shouldShowCountDown(): boolean {
    return this.exam.beginTime > this.nowTick;
  }

  private getSemesterLabel(): string {
    if (this.exam.semesterLabel) {
      return this.exam.semesterLabel;
    }
    if (this.exam.semesterId > 0) {
      return `学期 ${this.exam.semesterId}`;
    }
    return '学期未知';
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.exam.courseName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');

          Text(`${this.exam.examDate} ${this.exam.examTimeRange}`)
            .fontSize(13)
            .fontColor(ThemeManager.getTextSecondaryColor())
            .width('100%');
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);

        if (this.exam.examStatus) {
          Text(this.exam.examStatus)
            .fontSize(11)
            .fontColor(ThemeManager.getAccentColor())
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(ThemeManager.getAccentBgColor())
            .borderRadius(10);
        }
      }
      .width('100%');

      Text(this.exam.examLocation || '地点未知')
        .fontSize(13)
        .fontColor(ThemeManager.getTextSecondaryColor())
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      Row() {
        Text(this.getSemesterLabel())
          .fontSize(12)
          .fontColor(ThemeManager.getTextSecondaryColor());

        Blank();

        if (this.shouldShowCountDown()) {
          Text(`倒计时 ${DateUtils.formatCountDown(this.nowTick, this.exam.beginTime)}`)
            .fontSize(12)
            .fontColor(ThemeManager.getAccentColor());
        }
      }
      .width('100%');
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor(ThemeManager.getCardColor())
    .onClick(() => {
      if (this.onClick) {
        this.onClick();
      }
    });
  }
}
