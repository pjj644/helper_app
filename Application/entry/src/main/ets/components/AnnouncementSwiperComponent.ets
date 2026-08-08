import { ImmersiveLightWrapper } from '../common/ImmersiveLightWrapper';
import { AnnounceItem } from '../common/types/ModelTypes';
import { AppConstants } from '../common/constants/AppConstants';

@Component
export struct AnnouncementSwiperComponent {
  @Prop announceList: AnnounceItem[] = [];

  build() {
    Swiper() {
      ForEach(this.announceList, (item: AnnounceItem) => {
        ImmersiveLightWrapper({
          radius: AppConstants.CARD_RADIUS,
          lightIntensity: AppConstants.LIGHT_INTENSITY_DEFAULT,
          noBackground: true
        }) {
          Row() {
            Column() {
              Text(item.title.substring(1, 3))
                .fontSize(AppConstants.FONT_CAPTION)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_white'))
            }
            .width(56)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor('rgba(0, 0, 0, 0.15)')
            .borderRadius({ topLeft: AppConstants.CARD_RADIUS, bottomLeft: AppConstants.CARD_RADIUS })

            Column() {
              Text(item.title.substring(4))
                .fontSize(AppConstants.FONT_BODY)
                .fontColor($r('app.color.text_white'))
                .fontWeight(FontWeight.Medium)
                .maxLines(AppConstants.MAX_LINES)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ left: AppConstants.PAGE_PADDING, right: AppConstants.PAGE_PADDING })
          }
          .width('100%')
          .height(100)
          .backgroundColor(item.bgColor)
          .borderRadius(AppConstants.CARD_RADIUS)
          .shadow({
            radius: AppConstants.SHADOW_LARGE,
            color: 'rgba(0, 0, 0, 0.15)',
            offsetX: 0,
            offsetY: 6
          })
        }
      }, (item: AnnounceItem) => item.id || item.title)
    }
    .width('92%')
    .height(110)
    .autoPlay(true)
    .interval(AppConstants.SWIPER_INTERVAL)
    .indicator(true)
    .borderRadius(AppConstants.CARD_RADIUS)
  }
}
