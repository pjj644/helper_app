import { LoadingState } from '../common/types/ModelTypes';
import { AppConstants } from '../common/constants/AppConstants';

@Component
export struct LoadingComponent {
  @Prop type: number = 1;

  build() {
    if (this.type === 1) {
      Column() {
        Row() {
          Column() {
            Row()
              .width(120)
              .height(20)
              .backgroundColor($r('app.color.skeleton_color'))
              .borderRadius(4)
            Row()
              .width(80)
              .height(16)
              .backgroundColor($r('app.color.skeleton_color'))
              .borderRadius(4)
              .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Row()
            .width(60)
            .height(28)
            .backgroundColor($r('app.color.skeleton_color'))
            .borderRadius(14)
        }
        .width('100%')
        .padding(AppConstants.PAGE_PADDING)
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(AppConstants.CARD_RADIUS)

    } else if (this.type === 2) {
      Row() {
        Row()
          .width(AppConstants.SMALL_AVATAR_SIZE)
          .height(AppConstants.SMALL_AVATAR_SIZE)
          .backgroundColor($r('app.color.skeleton_color'))
          .borderRadius(AppConstants.SMALL_AVATAR_SIZE / 2)

        Column({ space: 8 }) {
          Row()
            .width(100)
            .height(16)
            .backgroundColor($r('app.color.skeleton_color'))
            .borderRadius(4)
          Row()
            .width('60%')
            .height(14)
            .backgroundColor($r('app.color.skeleton_color'))
            .borderRadius(4)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: AppConstants.LIST_ITEM_SPACE })
      }
      .width('100%')
      .padding(AppConstants.LIST_ITEM_SPACE)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(AppConstants.SMALL_RADIUS)

    } else {
      Column({ space: 8 }) {
        Row()
          .width(40)
          .height(40)
          .backgroundColor($r('app.color.skeleton_color'))
          .borderRadius(20)
        Row()
          .width(60)
          .height(14)
          .backgroundColor($r('app.color.skeleton_color'))
          .borderRadius(4)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(18)
    }
  }
}

@Component
export struct EmptyComponent {
  @Prop message: string = '暂无数据';
  @Prop icon: Resource = $r('app.media.startIcon');
  @Prop buttonText: string = '';
  onButtonClick?: () => void;

  build() {
    Column({ space: AppConstants.LIST_ITEM_SPACE }) {
      Image(this.icon)
        .width(64)
        .height(64)
        .fillColor($r('app.color.text_tertiary'))

      Text(this.message)
        .fontSize(AppConstants.FONT_BODY)
        .fontColor($r('app.color.text_tertiary'))

      if (this.buttonText) {
        Button(this.buttonText)
          .fontSize(AppConstants.FONT_CAPTION)
          .fontColor($r('app.color.text_white'))
          .backgroundColor($r('app.color.primary_color'))
          .borderRadius(AppConstants.SMALL_RADIUS)
          .height(36)
          .padding({ left: 24, right: 24 })
          .onClick(() => {
            if (this.onButtonClick) {
              this.onButtonClick!();
            }
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct ErrorComponent {
  @Prop message: string = '加载失败，请重试';
  onRetry?: () => void;

  build() {
    Column({ space: AppConstants.LIST_ITEM_SPACE }) {
      Image($r('app.media.startIcon'))
        .width(64)
        .height(64)
        .fillColor($r('app.color.danger_color'))

      Text(this.message)
        .fontSize(AppConstants.FONT_BODY)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      Button('重新加载')
        .fontSize(AppConstants.FONT_CAPTION)
        .fontColor($r('app.color.text_white'))
        .backgroundColor($r('app.color.primary_color'))
        .borderRadius(AppConstants.SMALL_RADIUS)
        .height(40)
        .padding({ left: 32, right: 32 })
        .onClick(() => {
          if (this.onRetry) {
            this.onRetry!();
          }
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct StateContainerComponent {
  @Prop state: LoadingState = LoadingState.Initial;
  @Prop emptyMessage: string = '暂无数据';
  @Prop errorMessage: string = '加载失败';
  onRetry?: () => void;
  @BuilderParam content: () => void;

  build() {
    if (this.state === LoadingState.Loading) {
      Column() {
        LoadingComponent({ type: 1 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

    } else if (this.state === LoadingState.Error) {
      ErrorComponent({
        message: this.errorMessage,
        onRetry: this.onRetry
      })

    } else if (this.state === LoadingState.Empty) {
      EmptyComponent({
        message: this.emptyMessage
      })

    } else {
      this.content()
    }
  }
}
