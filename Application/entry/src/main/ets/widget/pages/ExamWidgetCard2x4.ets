import { AppConstants } from '../../common/constants/AppConstants';

let storageExam2x4 = new LocalStorage();

@Entry(storageExam2x4)
@Component
struct ExamWidgetCard2x4 {
  @LocalStorageProp('examHasUpcoming') examHasUpcoming: boolean = false;
  @LocalStorageProp('examCount') examCount: number = 0;
  @LocalStorageProp('exam1_name') exam1_name: string = '';
  @LocalStorageProp('exam1_date') exam1_date: string = '';
  @LocalStorageProp('exam1_time') exam1_time: string = '';
  @LocalStorageProp('exam1_location') exam1_location: string = '';
  @LocalStorageProp('exam1_countdown') exam1_countdown: string = '';
  @LocalStorageProp('exam2_name') exam2_name: string = '';
  @LocalStorageProp('exam2_date') exam2_date: string = '';
  @LocalStorageProp('exam2_time') exam2_time: string = '';
  @LocalStorageProp('exam2_location') exam2_location: string = '';
  @LocalStorageProp('exam2_countdown') exam2_countdown: string = '';
  @LocalStorageProp('exam3_name') exam3_name: string = '';
  @LocalStorageProp('exam3_date') exam3_date: string = '';
  @LocalStorageProp('exam3_time') exam3_time: string = '';
  @LocalStorageProp('exam3_location') exam3_location: string = '';
  @LocalStorageProp('exam3_countdown') exam3_countdown: string = '';

  build() {
    Column() {
      // 头部栏
      Row() {
        Row({ space: 6 }) {
          Image($r('app.media.startIcon'))
            .width(16)
            .height(16)
            .borderRadius(4)
          Text('考试日程')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
        }

        Blank()

        Text(this.examCount > 0 ? `待考 ${this.examCount} 场` : '暂无考试')
          .fontSize(11)
          .fontColor(this.examCount > 0 ? '#DC2626' : '#6B7280')
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.examCount > 0 ? '#FEF2F2' : '#F3F4F6')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (!this.examHasUpcoming || !this.exam1_name) {
        // 无考试状态
        Column({ space: 4 }) {
          Blank()
          Text('🎉')
            .fontSize(22)
          Text('暂无考试安排')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#374151')
          Text('好好复习，轻松应考')
            .fontSize(11)
            .fontColor('#9CA3AF')
          Blank()
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 考试列表（最近 3 场）
        Column({ space: 6 }) {
          if (this.exam1_name) {
            this.ExamRow(this.exam1_name, this.exam1_date, this.exam1_time, this.exam1_location, this.exam1_countdown)
          }
          if (this.exam2_name) {
            this.ExamRow(this.exam2_name, this.exam2_date, this.exam2_time, this.exam2_location, this.exam2_countdown)
          }
          if (this.exam3_name) {
            this.ExamRow(this.exam3_name, this.exam3_date, this.exam3_time, this.exam3_location, this.exam3_countdown)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .padding(12)
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

  @Builder
  private ExamRow(name: string, date: string, time: string, location: string, countdown: string) {
    Row() {
      Text(countdown)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(countdown === '今天' || countdown === '明天' || countdown === '进行中' ? '#DC2626' : '#0A59F7')
        .width(44)
        .textAlign(TextAlign.Center)
        .padding({ top: 2, bottom: 2 })
        .backgroundColor(countdown === '今天' || countdown === '明天' || countdown === '进行中' ? '#FEF2F2' : '#EFF6FF')
        .borderRadius(4)

      Column({ space: 2 }) {
        Text(name)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(date && time ? `${date} ${time} · ${location}` : `${date}${location}`)
          .fontSize(10)
          .fontColor('#6B7280')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor('#F9FAFB')
    .borderRadius(8)
  }
}
