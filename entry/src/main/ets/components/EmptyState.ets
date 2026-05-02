import { ThemeManager } from '../common/utils/ThemeManager';

@Component
export struct EmptyState {
  @Prop title: string = '暂无数据';
  @Prop description: string = '';
  @Prop buttonText: string = '';
  private onButtonClick?: () => void;

  build() {
    Column({ space: 12 }) {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextPrimaryColor());

      if (this.description) {
        Text(this.description)
          .fontSize(13)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .width('100%');
      }

      if (this.buttonText) {
        Button(this.buttonText)
          .height(40)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeManager.getAccentColor())
          .borderRadius(20)
          .onClick(() => {
            if (this.onButtonClick) {
              this.onButtonClick();
            }
          });
      }
    }
    .width('100%')
    .padding(24)
    .borderRadius(20)
    .backgroundColor(ThemeManager.getCardColor())
    .alignItems(HorizontalAlign.Center);
  }
}
