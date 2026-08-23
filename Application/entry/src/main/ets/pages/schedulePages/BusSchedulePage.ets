import { router, promptAction } from '@kit.ArkUI';
import { BusScheduleModel, BusItem, NextBusInfo } from '../../model/BusScheduleModel';
import { CalendarKitReminderService } from '../../service/CalendarKitReminderService';
import { ToastComponent } from '../../components/ToastComponents';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct BusSchedulePage {
  @State departure: 'qsh' | 'sh' = 'qsh';
  @State isWeekend: boolean = BusScheduleModel.isWeekendDay();
  @State nextBusInfo: NextBusInfo | null = null;
  @State busList: BusItem[] = [];
  @State toastMessage: string = '';
  @State toastVisible: boolean = false;
  @State nowTick: number = Date.now();

  private timerId: number = -1;

  aboutToAppear(): void {
    this.refreshSchedule();
    this.timerId = setInterval(() => {
      this.nowTick = Date.now();
      this.refreshNextBus();
    }, 10000);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private refreshSchedule(): void {
    this.busList = BusScheduleModel.getBusList(this.departure, this.isWeekend);
    this.refreshNextBus();
  }

  private refreshNextBus(): void {
    this.nextBusInfo = BusScheduleModel.getNextBus(this.departure, this.isWeekend);
  }

  private showToast(msg: string): void {
    this.toastMessage = msg;
    this.toastVisible = true;
    setTimeout(() => {
      this.toastVisible = false;
    }, 2000);
  }

  private async addReminder(bus: BusItem): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const hasPerm = await CalendarKitReminderService.checkCalendarPermission(context);
      if (!hasPerm) {
        const granted = await CalendarKitReminderService.requestCalendarPermission(context);
        if (!granted) {
          this.showToast('需要日历权限以设置发车提醒');
          return;
        }
      }

      const eventId = await CalendarKitReminderService.createBusReminder(
        context,
        bus.departureName,
        bus.destinationName,
        bus.time
      );

      if (eventId > 0) {
        this.showToast(`已添加 ${bus.time} 班车提醒（发车前15分钟）`);
      } else {
        this.showToast('添加日历提醒失败');
      }
    } catch (e) {
      console.error('[BusSchedulePage] addReminder error:', e);
      this.showToast('设置提醒异常');
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Image($r('app.media.arrow_left'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_primary'))
            .onClick(() => {
              router.back();
            });

          Text('成电校车时刻表')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 12 })
            .layoutWeight(1);

          Row({ space: 4 }) {
            Text(this.isWeekend ? '周末时刻' : '工作日时刻')
              .fontSize(12)
              .fontColor($r('app.color.primary_color'))
              .fontWeight(FontWeight.Medium);
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.accent_bg_color'))
          .borderRadius(12)
          .onClick(() => {
            this.isWeekend = !this.isWeekend;
            this.refreshSchedule();
          });
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r('app.color.card_background'))
        .alignItems(VerticalAlign.Center);

        Scroll() {
          Column({ space: 14 }) {
            // 双向校区路线切换
            Row({ space: 8 }) {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 }) {
                  Text('清水河')
                    .fontSize(14)
                    .fontWeight(this.departure === 'qsh' ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.departure === 'qsh' ? '#FFFFFF' : $r('app.color.text_secondary'));
                  Text('➔')
                    .fontSize(12)
                    .fontColor(this.departure === 'qsh' ? '#FFFFFF' : $r('app.color.text_tertiary'));
                  Text('沙河')
                    .fontSize(14)
                    .fontWeight(this.departure === 'qsh' ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.departure === 'qsh' ? '#FFFFFF' : $r('app.color.text_secondary'));
                }
              }
              .layoutWeight(1)
              .height(42)
              .borderRadius(12)
              .backgroundColor(this.departure === 'qsh' ? $r('app.color.primary_color') : $r('app.color.card_background'))
              .onClick(() => {
                this.departure = 'qsh';
                this.refreshSchedule();
              });

              Button({ type: ButtonType.Normal }) {
                Row({ space: 6 }) {
                  Text('沙河')
                    .fontSize(14)
                    .fontWeight(this.departure === 'sh' ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.departure === 'sh' ? '#FFFFFF' : $r('app.color.text_secondary'));
                  Text('➔')
                    .fontSize(12)
                    .fontColor(this.departure === 'sh' ? '#FFFFFF' : $r('app.color.text_tertiary'));
                  Text('清水河')
                    .fontSize(14)
                    .fontWeight(this.departure === 'sh' ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.departure === 'sh' ? '#FFFFFF' : $r('app.color.text_secondary'));
                }
              }
              .layoutWeight(1)
              .height(42)
              .borderRadius(12)
              .backgroundColor(this.departure === 'sh' ? $r('app.color.primary_color') : $r('app.color.card_background'))
              .onClick(() => {
                this.departure = 'sh';
                this.refreshSchedule();
              });
            }
            .width('100%');

            // 「下一班车」Hero 倒计时卡片
            if (this.nextBusInfo) {
              Column({ space: 8 }) {
                Row() {
                  Row({ space: 6 }) {
                    Text('🚌')
                      .fontSize(18);
                    Text('下一班发车')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'));
                  }

                  Blank();

                  Text(this.nextBusInfo.isTomorrow ? '明日首班' : (this.nextBusInfo.minutesLeft === 0 ? '即将发车' : `约 ${this.nextBusInfo.minutesLeft} 分钟后`))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#FFFFFF')
                    .backgroundColor($r('app.color.primary_color'))
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(10);
                }
                .width('100%');

                Row() {
                  Column({ space: 4 }) {
                    Text(this.nextBusInfo.time)
                      .fontSize(32)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'));

                    Text(`${this.nextBusInfo.busItem.departureName}主楼 ➔ ${this.nextBusInfo.busItem.destinationName}主楼`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'));
                  }
                  .alignItems(HorizontalAlign.Start);

                  Blank();

                  Button('🔔 设为提醒')
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.primary_color'))
                    .backgroundColor($r('app.color.accent_bg_color'))
                    .borderRadius(16)
                    .height(34)
                    .onClick(() => {
                      if (this.nextBusInfo) {
                        this.addReminder(this.nextBusInfo.busItem);
                      }
                    });
                }
                .width('100%')
                .alignItems(VerticalAlign.Center);
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(16);
            }

            // 时刻表全览
            Column({ space: 8 }) {
              Row() {
                Text(`${this.departure === 'qsh' ? '清水河 ➔ 沙河' : '沙河 ➔ 清水河'} 班次列表`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'));

                Blank();

                Text(`共 ${this.busList.length} 班次`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'));
              }
              .width('100%')
              .padding({ left: 4, right: 4 });

              Column({ space: 6 }) {
                ForEach(this.busList, (bus: BusItem) => {
                  Row() {
                    Row({ space: 10 }) {
                      Text(bus.time)
                        .fontSize(18)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'));

                      Text(bus.busType)
                        .fontSize(10)
                        .fontColor(bus.busType === '高峰直达' ? $r('app.color.warning_color') : $r('app.color.text_secondary'))
                        .backgroundColor(bus.busType === '高峰直达' ? $r('app.color.tag_bg_exam') : $r('app.color.accent_bg_color'))
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .borderRadius(4);
                    }

                    Blank();

                    Row({ space: 8 }) {
                      Text('主楼站台')
                        .fontSize(12)
                        .fontColor($r('app.color.text_tertiary'));

                      Button('🔔')
                        .fontSize(12)
                        .height(30)
                        .width(36)
                        .backgroundColor($r('app.color.accent_bg_color'))
                        .borderRadius(10)
                        .onClick(() => {
                          this.addReminder(bus);
                        });
                    }
                  }
                  .width('100%')
                  .padding({ left: 14, right: 12, top: 10, bottom: 10 })
                  .backgroundColor($r('app.color.card_background'))
                  .borderRadius(12);
                }, (bus: BusItem) => bus.id)
              }
              .width('100%');
            }
            .width('100%');

            // 乘车须知
            Column({ space: 6 }) {
              Text('乘车温馨提示')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_secondary'));

              Text('1. 上车地点：清水河校区主楼东侧班车站 / 沙河校区主楼东侧班车站\n2. 乘坐方式：上车前请出示校园卡或微信扫码核验乘车\n3. 高峰期请提前 5-10 分钟到站候车，如遇客流高峰将动态增派加班车。')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .lineHeight(18);
            }
            .width('100%')
            .padding(14)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(14)
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 28 });
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off);
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'));

      ToastComponent({
        message: this.toastMessage,
        visible: this.toastVisible,
        duration: 2000,
        type: 4
      });
    }
    .width('100%')
    .height('100%');
  }
}
