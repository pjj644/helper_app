interface LoadingOverlayProps {
  isVisible: boolean;
  message: string;
}

@Component
export struct LoadingOverlay {
  @Prop isVisible: boolean = false;
  @Prop message: string = '加载中...';

  build() {
    if (this.isVisible) {
      Stack() {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#3B82FF');

          Text(this.message)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .margin({ top: 12 });
        }
        .padding(24)
        .backgroundColor('rgba(0, 0, 0, 0.7)')
        .borderRadius(12);
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0, 0, 0, 0.3)')
      .align(Alignment.Center);
    }
  }
}
