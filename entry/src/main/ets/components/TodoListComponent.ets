import { ImmersiveLightWrapper } from '../common/ImmersiveLightWrapper';
import { TodoItem } from '../common/types/ModelTypes';
import { AppConstants } from '../common/constants/AppConstants';

@Component
export struct TodoCardComponent {
  @Prop item: TodoItem | null = null;

  build() {
    if (this.item) {
      ImmersiveLightWrapper({
        radius: AppConstants.SMALL_RADIUS,
        lightIntensity: AppConstants.LIGHT_INTENSITY_WEAK
      }) {
        Row() {
          Rect()
            .width(4)
            .height(32)
            .fill(this.item!.tagColor)
            .borderRadius(2)
            .margin({ right: 10 })

          Column({ space: 4 }) {
            Text(this.item!.title)
              .fontSize(AppConstants.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(AppConstants.SINGLE_LINE)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.item!.desc)
              .fontSize(AppConstants.FONT_SMALL)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(AppConstants.SINGLE_LINE)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Text(this.item!.tag)
            .fontSize(AppConstants.FONT_TINY - 1)
            .fontColor($r('app.color.text_white'))
            .backgroundColor(this.item!.tagColor)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .padding({ top: AppConstants.LIST_ITEM_SPACE, bottom: AppConstants.LIST_ITEM_SPACE, left: AppConstants.LIST_ITEM_SPACE, right: 14 })
        .borderRadius(AppConstants.SMALL_RADIUS)
        .shadow({
          radius: AppConstants.SHADOW_MEDIUM,
          color: 'rgba(0, 0, 0, 0.06)',
          offsetX: 0,
          offsetY: 2
        })
      }
    }
  }
}

@Component
export struct TodoListComponent {
  @Prop todoList: TodoItem[] = [];
  @Prop title: string = '最近待办';
  onViewAll?: () => void;

  build() {
    Column({ space: AppConstants.LIST_ITEM_SPACE }) {
      Row() {
        Image($r('app.media.wait'))
          .width(AppConstants.SMALL_ICON_SIZE)
          .height(AppConstants.SMALL_ICON_SIZE)
          .fillColor($r('app.color.text_primary'))
        Text(this.title)
          .fontSize(AppConstants.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .flexGrow(1)
          .margin({ left: 6 })
        Text('查看全部 >')
          .fontSize(AppConstants.FONT_CAPTION)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => {
            if (this.onViewAll) {
              this.onViewAll();
            }
          })
      }
      .width('92%')
      .padding({ left: 8 })

      Column({ space: AppConstants.LIST_ITEM_SPACE }) {
        ForEach(this.todoList, (item: TodoItem) => {
          TodoCardComponent({ item: item })
        }, (item: TodoItem) => item.id || item.title)
      }
      .width('92%')
    }
  }
}
