import { QuickStatComponent } from '../QuickStatComponent';

@Component
export struct HomeHeaderComponent {
  @Prop currentWeek: number = 1;
  @Prop heroHint: string = '';
  @Prop todayCourseCount: number = 0;
  @Prop futureExamCount: number = 0;
  @Prop weekCourseCount: number = 0;
  onOpenSettings: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Row({ space: 12 }) {
          Stack() {
            Circle()
              .width(52)
              .height(52)
              .fill('rgba(255,255,255,0.2)');
            Image($r('app.media.mine'))
              .width(28)
              .height(28)
              .fillColor('#FFFFFF');
          }

          Column({ space: 4 }) {
            Text('HI助手')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF');

            Text(`第${this.currentWeek}周`)
              .fontSize(13)
              .fontColor('rgba(255,255,255,0.7)');
          }
          .alignItems(HorizontalAlign.Start);
        }

        Blank();

        Column({ space: 4 }) {
          Image($r('app.media.set'))
            .width(20)
            .height(20)
            .fillColor('#FFFFFF');
          Text('设置')
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.8)');
        }
        .onClick(() => {
          this.onOpenSettings();
        });
      }
      .width('100%');

      Text(this.heroHint)
        .fontSize(13)
        .fontColor('rgba(255,255,255,0.85)')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');

      QuickStatComponent({
        stats: [
          { label: '今日课程', value: this.todayCourseCount.toString(), color: $r('app.color.primary_color') },
          { label: '待考科目', value: this.futureExamCount.toString(), color: $r('app.color.warning_color') },
          { label: '本周课程', value: this.weekCourseCount.toString(), color: $r('app.color.success_color') },
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
  }
}
