import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { AppConstants } from '../../common/constants/AppConstants';
import { VpnEncoder } from '../../common/utils/VpnEncoder';

@Entry
@Component
struct WebPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State pageTitle: string = '校园网页';
  @State url: string = AppConstants.UESTC_URL;
  @State progress: number = 0;
  @State isLoading: boolean = true;
  @State message: string = '加载中...';
  @State isVpnMode: boolean = false;
  private originalUrl: string = '';
  private hasSwitchedToVpn: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params) {
      if (params['url']) {
        this.url = params['url'];
        this.originalUrl = params['url'];
      }
      if (params['title']) {
        this.pageTitle = params['title'];
      }
    }
  }

  private switchToVpnMode(): void {
    if (this.hasSwitchedToVpn) {
      return;
    }
    this.hasSwitchedToVpn = true;
    this.isVpnMode = true;
    this.message = '检测到非校园网环境，正在切换VPN...';

    try {
      const vpnUrl = VpnEncoder.buildVpnUrlFromOriginal(this.originalUrl);
      this.url = vpnUrl;
      this.controller.loadUrl(vpnUrl);
    } catch (e) {
      console.error('[WebPage] switchToVpnMode error:', e);
    }
  }

  build() {
    Column() {
      // 顶部原生导航栏
      Row() {
        Row({ space: 8 }) {
          Image($r('app.media.arrow_left'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_primary'))
            .onClick(() => {
              router.back();
            });

          Text(this.pageTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
        }
        .layoutWeight(1);

        Image($r('app.media.refresh'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_primary'))
          .margin({ left: 12, right: 4 })
          .onClick(() => {
            this.isLoading = true;
            this.controller.refresh();
          });
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.card_background'))
      .alignItems(VerticalAlign.Center);

      // 加载进度条
      if (this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.primary_color'));
      }

      Web({ src: this.url, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .onPageBegin(() => {
          this.isLoading = true;
          console.info('[WebPage] onPageBegin, url:', this.url);
        })
        .onProgressChange((event) => {
          this.progress = event.newProgress;
        })
        .onHttpErrorReceive((event) => {
          const statusCode = event.response.getResponseCode();
          console.error('[WebPage] HTTP error, status:', statusCode);
          if (!this.hasSwitchedToVpn && statusCode === 403) {
            this.switchToVpnMode();
          }
        })
        .onErrorReceive((event) => {
          const err = event.error.getErrorInfo();
          console.error('[WebPage] error:', err);
          if (!this.hasSwitchedToVpn &&
              (err.includes('net::ERR_CONNECTION') ||
               err.includes('net::ERR_NAME_NOT_RESOLVED'))) {
            this.switchToVpnMode();
          }
        })
        .onPageEnd(() => {
          this.isLoading = false;
          const currentUrl = this.controller.getUrl();
          this.url = currentUrl;
          const docTitle = this.controller.getTitle();
          if (docTitle && docTitle.trim().length > 0 && this.pageTitle === '校园网页') {
            this.pageTitle = docTitle;
          }
        })
        .onSslErrorEvent((event) => {
          console.error('[WebPage] SSL error:', event.error);
        })
        .onConsole((event) => {
          console.info('[WebPage] console:', event.message.getMessage());
          return true;
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'));
  }
}
