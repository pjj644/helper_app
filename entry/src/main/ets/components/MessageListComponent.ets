import { MessageInfo, MsgType } from '../common/types/ModelTypes';
import { AppConstants } from '../common/constants/AppConstants';
import { StringUtils } from '../common/utils/StringUtils';

@Component
export struct MessageItemComponent {
  @Prop message: MessageInfo | null = null;

  build() {
    if (this.message) {
      Row() {
        Stack() {
          Circle()
            .width(AppConstants.SMALL_AVATAR_SIZE)
            .height(AppConstants.SMALL_AVATAR_SIZE)
            .fill(this.message!.avatarBg)
          Text(StringUtils.getFirstChar(this.message!.sender))
            .fontSize(AppConstants.FONT_BODY)
            .fontColor($r('app.color.text_white'))
            .fontWeight(FontWeight.Bold)
          if (this.message!.isUnRead) {
            Circle()
              .width(AppConstants.UNREAD_DOT_SIZE)
              .height(AppConstants.UNREAD_DOT_SIZE)
              .fill($r('app.color.danger_color'))
              .position({ x: 32, y: 0 })
          }
        }
        .margin({ right: AppConstants.LIST_ITEM_SPACE })

        Column({ space: 4 }) {
          Row() {
            Text(this.message!.sender)
              .fontSize(AppConstants.FONT_BODY)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            Text(this.message!.time)
              .fontSize(AppConstants.FONT_TINY)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')

          Text(this.message!.content)
            .fontSize(AppConstants.FONT_SMALL)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(AppConstants.SINGLE_LINE)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .padding({ top: 10, bottom: 10, left: AppConstants.LIST_ITEM_SPACE, right: AppConstants.LIST_ITEM_SPACE })
      .borderRadius(AppConstants.SMALL_RADIUS)
      .shadow({
        radius: 6,
        color: 'rgba(0, 0, 0, 0.05)',
        offsetX: 0,
        offsetY: 2
      })
    }
  }
}

@Component
export struct MessageListComponent {
  @Prop messageList: MessageInfo[] = [];
  @Prop selectedType: MsgType = MsgType.All;
  onTypeChange?: (type: MsgType) => void;

  private msgTypeList: string[] = ['全部', '系统通知', '校园公告', '私人消息'];

  build() {
    Column() {
      Text('消息中心')
        .fontSize(AppConstants.FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 20, bottom: AppConstants.LIST_ITEM_SPACE })

      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.msgTypeList, (title: string, idx: number) => {
            Text(title)
              .fontSize(AppConstants.FONT_CAPTION)
              .fontWeight(this.selectedType === idx ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.selectedType === idx ? $r('app.color.text_white') : $r('app.color.text_secondary'))
              .backgroundColor(this.selectedType === idx ? $r('app.color.primary_color') : $r('app.color.card_background'))
              .padding({ left: AppConstants.PAGE_PADDING, right: AppConstants.PAGE_PADDING, top: 8, bottom: 8 })
              .borderRadius(20)
              .onClick(() => {
                if (this.onTypeChange) {
                  this.onTypeChange!(idx);
                }
              })
          }, (title: string) => title)
        }
        .padding({ left: 6, right: 6 })
      }
      .scrollBar(BarState.Off)
      .margin({ bottom: AppConstants.PAGE_PADDING })

      Column({ space: 10 }) {
        ForEach(this.messageList, (msg: MessageInfo) => {
          MessageItemComponent({ message: msg })
        }, (msg: MessageInfo) => msg.id.toString())
      }
      .width('94%')
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: 0 })
    .alignItems(HorizontalAlign.Center)
  }
}
