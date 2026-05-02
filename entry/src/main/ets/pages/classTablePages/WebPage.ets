import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { AppConstants } from '../../common/constants/AppConstants';

@Entry
@Component
struct WebPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State url: string = AppConstants.UESTC_URL;
  @State progress: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params && params['url']) {
      this.url = params['url'];
    }
  }

  build() {
    Column() {
      if (this.progress < 100) {
        Text(`加载中 ${this.progress}%`)
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 6 });
      }

      Web({ src: this.url, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .onProgressChange((event) => {
          this.progress = event.newProgress;
        });
    }
    .width('100%')
    .height('100%');
  }
}
