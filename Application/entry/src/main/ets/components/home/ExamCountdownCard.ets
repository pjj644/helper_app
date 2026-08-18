import { ExamItem } from '../../model/classTableModel/ExamModel';
import { ImmersiveLightWrapper } from '../../common/ImmersiveLightWrapper';
import { CountdownCard } from '../CountdownCard';

@Component
export struct ExamCountdownCard {
  @Prop nextExam: ExamItem | undefined = undefined;
  @Prop nowTick: number = 0;
  onSwitchToCourse: () => void = () => {};
  onOpenExamPage: () => void = () => {};
  onOpenExamDetail: (exam: ExamItem) => void = () => {};

  build() {
    ImmersiveLightWrapper({ radius: 20, lightIntensity: 2.0 }) {
      Column({ space: 10 }) {
        Row() {
          Row({ space: 6 }) {
            Text('⏳')
              .fontSize(16);
            Text('最近考试倒计时')
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
            .onClick(() => {
              this.onOpenExamPage();
            });

          Image($r('app.media.switch'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.warning_color'))
            .margin({ left: 10 })
            .onClick(() => {
              this.onSwitchToCourse();
            });
        }
        .width('100%');

        if (this.nextExam) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text(this.nextExam.courseName)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1);

              Text(this.nextExam.examType || '未知')
                .fontSize(10)
                .fontColor($r('app.color.primary_color'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.accent_bg_color'))
                .borderRadius(8);
            }
            .width('100%');

            CountdownCard({
              examName: '',
              examDate: this.nextExam.examDate,
              examTimeRange: this.nextExam.examTimeRange,
              beginTime: this.nextExam.beginTime,
              compact: false
            });
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.page_background'))
          .onClick(() => {
            if (this.nextExam) {
              this.onOpenExamDetail(this.nextExam);
            }
          });
        } else {
          Text('暂无考试安排，好好放松一下吧 🎉')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 16, bottom: 16 });
        }
      }
      .width('100%')
      .padding(12);
    }
  }
}
