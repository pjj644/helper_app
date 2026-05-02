import { router } from '@kit.ArkUI';
import { FEATURE_LINKS, FeatureLink } from '../../model/classTableModel/FeatureLinks';
import { CourseTableStorage, RecentLinkItem } from '../../model/classTableModel/CourseTableStorage';

@Entry
@Component
struct FeatureNav {
  @State recentItems: RecentLinkItem[] = [];

  aboutToAppear(): void {
    this.loadRecent();
  }

  private async loadRecent(): Promise<void> {
    const context = getContext(this);
    const items = await CourseTableStorage.loadRecentLinks(context);
    this.recentItems = items.sort((a, b) => b.visitedAt - a.visitedAt).slice(0, 8);
  }

  private async openLink(item: FeatureLink): Promise<void> {
    const context = getContext(this);
    const current = await CourseTableStorage.loadRecentLinks(context);
    const filtered = current.filter(it => it.url !== item.url);
    filtered.unshift({ title: item.title, url: item.url, visitedAt: Date.now() });
    await CourseTableStorage.saveRecentLinks(context, filtered.slice(0, 20));

    router.pushUrl({
      url: 'pages/classTablePages/WebPage',
      params: {
        title: item.title,
        url: item.url
      }
    });
  }

  build() {
    Column() {
      Row() {
        Text('功能导航')
          .fontSize(24)
          .fontWeight(FontWeight.Bold);
        Blank();
        Button('返回').onClick(() => router.back());
      }
      .width('100%')
      .padding(12);

      if (this.recentItems.length > 0) {
        Column() {
          Row() {
            Text('最近使用')
              .fontSize(16)
              .fontWeight(FontWeight.Medium);
            Blank();
          }
          .width('100%')
          .margin({ bottom: 6 });

          ForEach(this.recentItems, (item: RecentLinkItem) => {
            Row() {
              Text(item.title)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
              Text('打开')
                .fontColor('#1976D2');
            }
            .width('100%')
            .padding(10)
            .backgroundColor('#F7F9FB')
            .borderRadius(8)
            .margin({ bottom: 6 })
            .onClick(() => {
              this.openLink({ title: item.title, url: item.url, category: '' });
            });
          });
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 8 });
      }

      List() {
        ForEach(FEATURE_LINKS, (item: FeatureLink) => {
          ListItem() {
            Column() {
              Text(item.title)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .width('100%');
              Text(item.category)
                .fontSize(12)
                .fontColor('#666666')
                .width('100%')
                .margin({ top: 2 });
              Text(item.url)
                .fontSize(11)
                .fontColor('#999999')
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 2 });
            }
            .padding(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(10)
            .onClick(() => this.openLink(item));
          }
          .margin({ left: 12, right: 12, top: 6, bottom: 6 });
        });
      }
      .layoutWeight(1)
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF');
  }
}
