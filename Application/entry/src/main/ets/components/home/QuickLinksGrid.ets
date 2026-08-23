import { AppConstants } from '../../common/constants/AppConstants';

export interface HomeToolItem {
  title: string;
  icon: string;
  color: string;
  route?: string;
  url?: string;
  iconImage?: Resource;
}

@Component
export struct QuickLinksGrid {
  @Prop tools: HomeToolItem[] = [];
  @Prop latestGpa: string = '--';
  @Prop todayEventCount: number = 0;
  @Prop currentBreakpoint: string = 'sm';
  onToolClick: (tool: HomeToolItem) => void = () => {};

  private getGridColumns(): string {
    if (this.currentBreakpoint === 'lg') {
      return '1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr';
    } else if (this.currentBreakpoint === 'md') {
      return '1fr 1fr 1fr 1fr 1fr 1fr';
    }
    return '1fr 1fr 1fr 1fr';
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 4 }) {
        Text('发现')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'));

        Text('校园实用工具与服务直达')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'));
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16 });

      // 云中成电 Hero Banner
      Row() {
        Row({ space: 14 }) {
          Stack() {
            Circle()
              .width(46)
              .height(46)
              .fill($r('app.color.accent_bg_color'));
            Text('☁️')
              .fontSize(24);
          }

          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text('云中成电')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'));

              Text('官方门户')
                .fontSize(10)
                .fontColor($r('app.color.primary_color'))
                .backgroundColor($r('app.color.accent_bg_color'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(4);
            }

            Text('全校80+综合办事与系统直达')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'));
          }
          .alignItems(HorizontalAlign.Start);
        }

        Blank();

        Row({ space: 2 }) {
          Text('进入')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_color'));
          Text('›')
            .fontSize(16)
            .fontColor($r('app.color.primary_color'));
        }
        .padding({ left: 12, right: 10, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.accent_bg_color'))
        .borderRadius(14);
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .onClick(() => {
        const cloudTool = this.tools.find((t: HomeToolItem) => t.title === '云中成电');
        if (cloudTool) {
          this.onToolClick(cloudTool);
        } else {
          this.onToolClick({
            title: '云中成电',
            icon: '☁️',
            color: '#0A59F7',
            url: AppConstants.ONLINE_URL
          });
        }
      });

      Text('常用服务')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 });

      Row({ space: 12 }) {
        Column() {
          Text('📊')
            .fontSize(24);
          Text('成绩查询')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 4 });
          Text(this.latestGpa === '--' ? '点击导入' : `GPA ${this.latestGpa}`)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .height(86)
        .borderRadius(14)
        .backgroundColor($r('app.color.accent_bg_color'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const gradeTool = this.tools.find((t: HomeToolItem) => t.title === '成绩查询');
          if (gradeTool) this.onToolClick(gradeTool);
        });

        Column() {
          Text('🚌')
            .fontSize(24);
          Text('成电班车')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 4 });
          Text('两校区时刻')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .height(86)
        .borderRadius(14)
        .backgroundColor($r('app.color.tag_bg_exam'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const busTool = this.tools.find((t: HomeToolItem) => t.title === '成电班车');
          if (busTool) this.onToolClick(busTool);
        });

        Column() {
          Text('📅')
            .fontSize(24);
          Text('校园日历')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 4 });
          Text(this.todayEventCount > 0 ? `今日 ${this.todayEventCount} 件事` : '查看日程')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .height(86)
        .borderRadius(14)
        .backgroundColor($r('app.color.tag_bg_done'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const calTool = this.tools.find((t: HomeToolItem) => t.title === '校园日历');
          if (calTool) this.onToolClick(calTool);
        });
      }
      .width('100%')
      .padding({ left: 16, right: 16 });

      Text('所有功能')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 });

      Grid() {
        ForEach(this.tools, (tool: HomeToolItem) => {
          GridItem() {
            Column({ space: 8 }) {
              if (tool.iconImage) {
                Image(tool.iconImage)
                  .width(28)
                  .height(28);
              } else {
                Text(tool.icon)
                  .fontSize(26);
              }
              Text(tool.title)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .width('100%')
            .height(82)
            .borderRadius(14)
            .backgroundColor($r('app.color.card_background'))
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.onToolClick(tool));
          }
        });
      }
      .columnsTemplate(this.getGridColumns())
      .columnsGap(10)
      .rowsGap(10)
      .padding({ left: 16, right: 16 })
      .width('100%');
    }
    .width('100%')
    .padding({ top: 8, bottom: 24 });
  }
}
