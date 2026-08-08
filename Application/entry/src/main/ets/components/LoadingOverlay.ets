import { ThemeManager } from '../common/utils/ThemeManager';

@Component
export struct LoadingOverlay {
  @Prop isVisible: boolean = false;
  @Prop message: string = '加载中...';
  @Prop showSpinner: boolean = true;
  @State private dotCount: number = 0;
  @State private cardScale: number = 0.9;
  private dotTimer: number = -1;

  aboutToAppear(): void {
    this.startDotAnimation();
    this.animateCardIn();
  }

  aboutToDisappear(): void {
    this.stopDotAnimation();
  }

  private startDotAnimation(): void {
    this.stopDotAnimation();
    this.dotTimer = setInterval(() => {
      this.dotCount = (this.dotCount + 1) % 4;
    }, 500);
  }

  private stopDotAnimation(): void {
    if (this.dotTimer >= 0) {
      clearInterval(this.dotTimer);
      this.dotTimer = -1;
    }
  }

  private animateCardIn(): void {
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.cardScale = 1.0;
    });
  }

  build() {
    if (this.isVisible) {
      Stack() {
        Column({ space: 20 }) {
          if (this.showSpinner) {
            Stack() {
              LoadingProgress()
                .width(44)
                .height(44)
                .color(ThemeManager.getAccentColor());
            }
            .width(56)
            .height(56)
            .alignContent(Alignment.Center);
          }

          Row() {
            Text(this.message)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .opacity(0.92);

            Text('.'.repeat(this.dotCount))
              .fontSize(14)
              .fontColor('#FFFFFF')
              .opacity(0.7)
              .width(18)
              .textAlign(TextAlign.Start);
          };
        }
        .padding({ top: 28, bottom: 28, left: 36, right: 36 })
        .borderRadius(18)
        .backgroundColor('rgba(24, 30, 45, 0.88)')
        .shadow({
          radius: 32,
          color: 'rgba(0, 0, 0, 0.2)',
          offsetX: 0,
          offsetY: 12
        })
        .scale({ x: this.cardScale, y: this.cardScale });
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0, 0, 0, 0.35)')
      .align(Alignment.Center);
    }
  }
}
