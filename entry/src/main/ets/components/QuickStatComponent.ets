import { AppConstants } from '../common/constants/AppConstants';
import { StatData } from '../common/types/ModelTypes';

@Component
export struct QuickStatComponent {
  @Prop stats: StatData[] = [];

  build() {
    Row() {
      ForEach(this.stats, (stat: StatData, index: number) => {
        if (index > 0) {
          Divider()
            .vertical(true)
            .height(30)
            .color('rgba(255, 255, 255, 0.3)')
        }

        Column({ space: 4 }) {
          Text(stat.value.toString())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_white'))
          Text(stat.label)
            .fontSize(AppConstants.FONT_SMALL)
            .fontColor('rgba(255, 255, 255, 0.8)')
        }
      }, (stat: StatData) => stat.label)
    }
    .width('100%')
    .padding({ top: 12, bottom: 16 })
    .justifyContent(FlexAlign.SpaceEvenly)
  }
}
