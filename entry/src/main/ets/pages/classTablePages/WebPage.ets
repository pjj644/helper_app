import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { AppConstants } from '../../common/constants/AppConstants';
import { VpnEncoder } from '../../common/utils/VpnEncoder';

@Entry
@Component
struct WebPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State url: string = AppConstants.UESTC_URL;
  @State progress: number = 0;
  @State message: string = '加载中...';
  @State isVpnMode: boolean = false;
  @State showRefreshBtn: boolean = false;
  private originalUrl: string = '';
  private vpnAutoDetected: boolean = false;
  private hasSwitchedToVpn: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params && params['url']) {
      this.url = params['url'];
      this.originalUrl = params['url'];
    }
    this.initVpnMode();
  }

  private async initVpnMode(): Promise<void> {
    this.isVpnMode = false;
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
    Stack() {
      Column() {
        if (this.progress < 100 && !VpnEncoder.isLoginPage(this.url)) {
          Text(`${this.message} ${this.progress}%`)
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
          .onPageBegin(() => {
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
              return;
            }
            if (statusCode !== 403) {
              this.showRefreshBtn = true;
            }
          })
          .onErrorReceive((event) => {
            const err = event.error.getErrorInfo();
            console.error('[WebPage] error:', err);
            if (!this.hasSwitchedToVpn &&
                (err.includes('net::ERR_CONNECTION') ||
                 err.includes('net::ERR_NAME_NOT_RESOLVED'))) {
              this.switchToVpnMode();
              return;
            }
            this.showRefreshBtn = true;
          })
          .onPageEnd(() => {
            const currentUrl = this.controller.getUrl();
            this.url = currentUrl;
            this.showRefreshBtn = false;

            if (this.isVpnMode && VpnEncoder.isLoginPage(currentUrl)) {
              this.message = '请完成统一身份认证登录';
            } else if (!this.isVpnMode && VpnEncoder.isLoginPage(currentUrl)) {
              this.message = '请先登录';
            } else {
              this.message = '正在加载...';
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

      if (this.showRefreshBtn) {
        Button() {
          Text('↻')
            .fontSize(22)
            .fontColor('#FFFFFF')
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor('#FF6200EE')
        .position({ x: '85%', y: 16 })
        .onClick(() => {
          this.showRefreshBtn = false;
          this.controller.loadUrl(this.url);
        })
      }
    }
    .width('100%')
    .height('100%');
  }
}
