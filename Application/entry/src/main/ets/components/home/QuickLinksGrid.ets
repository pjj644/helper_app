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
    return '1fr 1fr 1fr 1fr 1fr';
  }

  build() {
    Column({ space: 10 }) {
      Column({ space: 4 }) {
        Text('发现')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'));

        Text('校园实用工具')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'));
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16 });

      Text('最近使用')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ left: 16, right: 16 });

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
        .height(90)
        .borderRadius(14)
        .backgroundColor($r('app.color.accent_bg_color'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const gradeTool = this.tools.find(t => t.title === '成绩查询');
          if (gradeTool) this.onToolClick(gradeTool);
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
        .height(90)
        .borderRadius(14)
        .backgroundColor($r('app.color.tag_bg_done'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const calTool = this.tools.find(t => t.title === '校园日历');
          if (calTool) this.onToolClick(calTool);
        });

        Column() {
          Text('📚')
            .fontSize(24);
          Text('图书馆')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 4 });
          Text('点击打开')
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .height(90)
        .borderRadius(14)
        .backgroundColor($r('app.color.primary_light_color'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const libTool = this.tools.find(t => t.title === '图书馆');
          if (libTool) this.onToolClick(libTool);
        });
      }
      .width('100%')
      .padding({ left: 16, right: 16 });

      Text('所有功能')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ left: 16, right: 16 });

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
                  .fontSize(28);
              }
              Text(tool.title)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'));
            }
            .width('100%')
            .height(90)
            .borderRadius(16)
            .backgroundColor($r('app.color.card_background'))
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.onToolClick(tool));
          }
        });
      }
      .columnsTemplate(this.getGridColumns())
      .columnsGap(14)
      .rowsGap(14)
      .padding({ left: 16, right: 16 })
      .width('100%');
    }
    .width('100%')
    .padding({ top: 8, bottom: 24 });
  }
}
