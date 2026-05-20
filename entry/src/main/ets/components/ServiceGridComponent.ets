import { ImmersiveLightWrapper } from '../common/ImmersiveLightWrapper';
import { AnimationSettings } from '../common/AnimationSettings';
import { ServiceItem } from '../common/types/ModelTypes';
import { AppConstants } from '../common/constants/AppConstants';

@Component
export struct ServiceCardComponent {
  @Prop item: ServiceItem | null = null;

  build() {
    if (this.item) {
      ImmersiveLightWrapper({
        radius: 18,
        lightIntensity: 2.0
      }) {
        Column({ space: 8 }) {
          Text(this.item!.icon)
            .fontSize(AppConstants.LARGE_ICON_SIZE)
            .margin({ top: 16 })

          Text(this.item!.name)
            .fontSize(AppConstants.FONT_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text(this.item!.desc)
            .fontSize(AppConstants.FONT_TINY)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(AppConstants.SINGLE_LINE)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ bottom: AppConstants.LIST_ITEM_SPACE })
      }
    }
  }
}

@Component
export struct ServiceGridComponent {
  @Prop serviceList: ServiceItem[] = [];
  @Prop title: string = '校园便民服务';
  @Prop columns: number = AppConstants.SERVICE_GRID_COLUMNS;
  @Prop rows: number = AppConstants.SERVICE_GRID_ROWS;
  onMore?: () => void;

  @State titleOpacity: number = 0;
  @State titleTranslateY: number = 20;
  @State gridOpacity: number = 0;
  @State gridScale: number = 0.9;

  private animationSettings: AnimationSettings = AnimationSettings.getInstance();
  private hasAnimated: boolean = false;

  aboutToAppear(): void {
    this.playEnterAnimation();
  }

  private playEnterAnimation(): void {
    if (!this.animationSettings.cardEnterEnabled || this.hasAnimated) {
      this.titleOpacity = 1;
      this.titleTranslateY = 0;
      this.gridOpacity = 1;
      this.gridScale = 1;
      return;
    }

    this.hasAnimated = true;
    const params = this.animationSettings.getCardEnterParams();

    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: params.duration,
        curve: params.curve
      }, () => {
        this.titleOpacity = 1;
        this.titleTranslateY = 0;
      });
    }, 0);

    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: params.duration,
        curve: params.curve
      }, () => {
        this.gridOpacity = 1;
        this.gridScale = 1;
      });
    }, 100);
  }

  build() {
    Scroll() {
      Column({ space: 24 }) {
        Row() {
          Text(this.title)
            .fontSize(AppConstants.FONT_TITLE)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text('更多 >')
            .fontSize(AppConstants.FONT_CAPTION)
            .fontColor($r('app.color.text_tertiary'))
            .onClick(() => {
              if (this.onMore) {
                this.onMore();
              }
            })
        }
        .width('92%')
        .margin({ top: 20 })
        .opacity(this.titleOpacity)
        .translate({ y: this.titleTranslateY })

        Grid() {
          ForEach(this.serviceList, (item: ServiceItem) => {
            GridItem() {
              ServiceCardComponent({ item: item })
            }
          }, (item: ServiceItem) => item.id || item.name)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr')
        .columnsGap(AppConstants.GRID_GAP)
        .rowsGap(AppConstants.GRID_GAP)
        .width('92%')
        .height(280)
        .opacity(this.gridOpacity)
        .scale({ x: this.gridScale, y: this.gridScale })

        Text('更多功能即将上线')
          .fontSize(AppConstants.FONT_CAPTION)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 20 })
          .opacity(this.gridOpacity)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
