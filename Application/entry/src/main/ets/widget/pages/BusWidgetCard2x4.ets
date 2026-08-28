import { AppConstants } from '../../common/constants/AppConstants';

let storageBus2x4 = new LocalStorage();

@Entry(storageBus2x4)
@Component
struct BusWidgetCard2x4 {
  @LocalStorageProp('busDayType') busDayType: string = '工作日';
  @LocalStorageProp('bus1_label') bus1_label: string = '清水河 ➔ 沙河';
  @LocalStorageProp('bus1_time') bus1_time: string = '--:--';
  @LocalStorageProp('bus1_countdown') bus1_countdown: string = '暂无班次';
  @LocalStorageProp('bus1_type') bus1_type: string = '';
  @LocalStorageProp('bus2_label') bus2_label: string = '沙河 ➔ 清水河';
  @LocalStorageProp('bus2_time') bus2_time: string = '--:--';
  @LocalStorageProp('bus2_countdown') bus2_countdown: string = '暂无班次';
  @LocalStorageProp('bus2_type') bus2_type: string = '';

  build() {
    Column() {
      // 头部栏
      Row() {
        Row({ space: 6 }) {
          Image($r('app.media.startIcon'))
            .width(16)
            .height(16)
            .borderRadius(4)
          Text('成电班车')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
        }

        Blank()

        Text(this.busDayType)
          .fontSize(11)
          .fontColor('#0A59F7')
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#EFF6FF')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
      }
      .width('100%')
      .margin({ bottom: 8 })

      // 双方向下一班
      Column({ space: 6 }) {
        this.BusRow(this.bus1_label, this.bus1_time, this.bus1_countdown, this.bus1_type)
        this.BusRow(this.bus2_label, this.bus2_time, this.bus2_countdown, this.bus2_type)
      }
      .width('100%')
      .layoutWeight(1)

      Text('点击查看全部班次 ›')
        .fontSize(10)
        .fontColor('#9CA3AF')
        .width('100%')
        .textAlign(TextAlign.End)
        .margin({ top: 4 })
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
        params: { targetPage: AppConstants.WIDGET_TARGET_BUS }
      });
    })
  }

  @Builder
  private BusRow(label: string, time: string, countdown: string, busType: string) {
    Row() {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 4 }) {
          if (busType) {
            Text(busType)
              .fontSize(9)
              .fontColor('#6B7280')
              .backgroundColor('#F3F4F6')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(3)
          }
          Text(countdown)
            .fontSize(10)
            .fontColor('#059669')
        }
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(time)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0A59F7')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#F9FAFB')
    .borderRadius(8)
  }
}
