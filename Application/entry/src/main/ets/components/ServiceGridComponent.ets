import { ImmersiveLightWrapper } from '../common/ImmersiveLightWrapper';
import { AnimationSettings } from '../common/AnimationSettings';
import { ServiceItem } from '../common/types/ModelTypes';
import { AppConstants } from '../common/constants/AppConstants';
import { router } from '@kit.ArkUI';

@Component
export struct ServiceCardComponent {
  @Prop item: ServiceItem | null = null;
  onItemClick?: (item: ServiceItem) => void;

  build() {
    if (this.item) {
      ImmersiveLightWrapper({
        radius: 18,
        lightIntensity: 2.0
      }) {
        Column({ space: 4 }) {
          Text(this.item!.icon)
            .fontSize(28)

          Text(this.item!.name)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text(this.item!.desc)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(8)
        .onClick(() => {
          if (this.onItemClick && this.item) {
            this.onItemClick(this.item);
          }
        })
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

  private handleItemClick(item: ServiceItem): void {
    if (item.route) {
      router.pushUrl({ url: item.route }).catch((error: Error) => {
        console.error('[ServiceGridComponent] 跳转失败:', error);
      });
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('更多 >')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => {
            if (this.onMore) {
              this.onMore();
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .opacity(this.titleOpacity)
      .translate({ y: this.titleTranslateY })

      Grid() {
        ForEach(this.serviceList, (item: ServiceItem) => {
          GridItem() {
            ServiceCardComponent({ item: item, onItemClick: (clickedItem: ServiceItem) => {
              this.handleItemClick(clickedItem);
            }})
          }
        }, (item: ServiceItem) => item.id || item.name)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height(220)
      .padding({ left: 16, right: 16 })
      .opacity(this.gridOpacity)
      .scale({ x: this.gridScale, y: this.gridScale })
    }
    .width('100%')
  }
}
