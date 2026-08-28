import { AppConstants } from '../../common/constants/AppConstants';

let storageExam2x2 = new LocalStorage();

@Entry(storageExam2x2)
@Component
struct ExamWidgetCard2x2 {
  @LocalStorageProp('examHasUpcoming') examHasUpcoming: boolean = false;
  @LocalStorageProp('examUrgent') examUrgent: boolean = false;
  @LocalStorageProp('examName') examName: string = '暂无考试安排';
  @LocalStorageProp('examDate') examDate: string = '';
  @LocalStorageProp('examTime') examTime: string = '';
  @LocalStorageProp('examLocation') examLocation: string = '';
  @LocalStorageProp('examCountdown') examCountdown: string = '好好休息';
  @LocalStorageProp('examCount') examCount: number = 0;

  build() {
    Column() {
      // 头部
      Row() {
        Row({ space: 4 }) {
          Image($r('app.media.startIcon'))
            .width(16)
            .height(16)
            .borderRadius(4)
          Text('考试倒计时')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4B5563')
        }

        Blank()

        Text(this.examCountdown)
          .fontSize(11)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
          .backgroundColor(this.examHasUpcoming && this.examUrgent ? '#DC2626' : '#0A59F7')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
      .width('100%')

      Blank()

      if (this.examHasUpcoming) {
        // 核心考试信息
        Column({ space: 4 }) {
          Text(this.examName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 4 }) {
            Text('📅')
              .fontSize(10)
            Text(this.examDate && this.examTime ? `${this.examDate} ${this.examTime}` : this.examDate)
              .fontSize(12)
              .fontColor('#4B5563')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Row({ space: 4 }) {
            Text('📍')
              .fontSize(10)
            Text(this.examLocation)
              .fontSize(12)
              .fontColor('#4B5563')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        // 无考试状态
        Column({ space: 6 }) {
          Text('🎉')
            .fontSize(24)
          Text('暂无考试安排')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#374151')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      Blank()

      // 底部状态提示
      Row() {
        Text(this.examCount > 0 ? `待考 ${this.examCount} 场` : '放松一下')
          .fontSize(11)
          .fontColor('#9CA3AF')
          .fontWeight(FontWeight.Medium)

        Blank()

        Text('详情 ›')
          .fontSize(11)
          .fontColor('#9CA3AF')
      }
      .width('100%')
    }
    .padding(14)
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { targetPage: AppConstants.WIDGET_TARGET_EXAM }
      });
    })
  }
}
