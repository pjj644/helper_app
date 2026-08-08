import { AppConstants } from '../common/constants/AppConstants';

@Component
export struct ToastComponent {
  @Prop message: string = '';
  @Prop visible: boolean = false;
  @Prop duration: number = 2000;
  @Prop type: number = 4;

  build() {
    if (this.visible) {
      Row() {
        if (this.type === 1) {
          Text('✓')
            .fontSize(16)
            .fontColor(Color.White)
        } else if (this.type === 2) {
          Text('✗')
            .fontSize(16)
            .fontColor(Color.White)
        } else if (this.type === 3) {
          Text('⚠')
            .fontSize(16)
            .fontColor(Color.White)
        }

        Text(this.message)
          .fontSize(AppConstants.FONT_CAPTION)
          .fontColor(Color.White)
          .margin({ left: 8 })
      }
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(this.getBackgroundColor())
      .borderRadius(AppConstants.SMALL_RADIUS)
      .shadow({
        radius: 8,
        color: 'rgba(0, 0, 0, 0.2)',
        offsetX: 0,
        offsetY: 4
      })
    }
  }

  private getBackgroundColor(): ResourceColor {
    switch (this.type) {
      case 1:
        return $r('app.color.success_color');
      case 2:
        return $r('app.color.danger_color');
      case 3:
        return $r('app.color.warning_color');
      default:
        return $r('app.color.text_secondary');
    }
  }
}

@Component
export struct ProgressComponent {
  @Prop visible: boolean = true;
  @Prop progress: number = -1;
  @Prop message: string = '加载中...';

  build() {
    if (this.visible) {
      Column({ space: AppConstants.LIST_ITEM_SPACE }) {
        if (this.progress >= 0) {
          Progress({
            value: this.progress,
            total: 100,
            type: ProgressType.Linear
          })
            .width(200)
            .color($r('app.color.primary_color'))
        } else {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.primary_color'))
        }

        if (this.message) {
          Text(this.message)
            .fontSize(AppConstants.FONT_CAPTION)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(0, 0, 0, 0.3)')
    }
  }
}
