import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { AppConstants } from '../../common/constants/AppConstants';
import { VpnEncoder } from '../../common/utils/VpnEncoder';
import { SettingsRepository } from '../../repository/SettingsRepository';

@Entry
@Component
struct WebPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State url: string = AppConstants.UESTC_URL;
  @State progress: number = 0;
  @State message: string = '加载中...';
  @State isVpnMode: boolean = false;
  private originalUrl: string = '';
  private vpnAutoDetected: boolean = false;
  private hasSwitchedToVpn: boolean = false;
  private pageLoadCount: number = 0;

  aboutToAppear(): void {
    console.info('[WebPage] aboutToAppear start');
    const params = router.getParams() as Record<string, string>;
    console.info('[WebPage] router params:', JSON.stringify(params));
    if (params && params['url']) {
      this.url = params['url'];
      this.originalUrl = params['url'];
      console.info('[WebPage] set url from params:', this.url);
    } else {
      console.warn('[WebPage] no url param, using default:', this.url);
    }
    this.initVpnMode();
    console.info('[WebPage] aboutToAppear end');
  }

  private async initVpnMode(): Promise<void> {
    console.info('[WebPage] initVpnMode start');
    try {
      const settings = await SettingsRepository.loadSettings(getContext(this));
      this.isVpnMode = settings.vpnMode;
      console.info('[WebPage] VPN mode from settings:', this.isVpnMode);
    } catch (e) {
      console.error('[WebPage] 读取VPN设置失败:', e);
    }
    console.info('[WebPage] initVpnMode end');
  }

  private switchToVpnMode(): void {
    console.info('[WebPage] switchToVpnMode called, hasSwitchedToVpn:', this.hasSwitchedToVpn);
    if (this.hasSwitchedToVpn) {
      console.info('[WebPage] VPN already switched, skip');
      return;
    }
    this.hasSwitchedToVpn = true;
    this.isVpnMode = true;
    this.message = '检测到非校园网环境，正在切换VPN...';
    console.info('[WebPage] originalUrl:', this.originalUrl);

    try {
      const vpnUrl = VpnEncoder.buildVpnUrlFromOriginal(this.originalUrl);
      console.info('[WebPage] generated VPN URL:', vpnUrl);
      this.url = vpnUrl;
      console.info('[WebPage] calling controller.loadUrl...');
      this.controller.loadUrl(vpnUrl);
      console.info('[WebPage] controller.loadUrl called');
    } catch (e) {
      console.error('[WebPage] switchToVpnMode error:', e);
    }
  }

  build() {
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
          console.info('[WebPage] onPageBegin, current url:', this.url);
        })
        .onProgressChange((event) => {
          this.progress = event.newProgress;
          if (event.newProgress % 10 === 0) {
            console.info('[WebPage] progress:', event.newProgress, '%');
          }
        })
        .onHttpErrorReceive((event) => {
          const statusCode = event.response.getResponseCode();
          const url = event.request.getRequestUrl();
          console.error('[WebPage] HTTP error, status:', statusCode, 'url:', url);
          console.error('[WebPage] hasSwitchedToVpn:', this.hasSwitchedToVpn, 'isVpnMode:', this.isVpnMode);
          if (!this.hasSwitchedToVpn && statusCode === 403) {
            console.info('[WebPage] detected 403, will switch to VPN mode');
            this.switchToVpnMode();
          }
        })
        .onErrorReceive((event) => {
          const err = event.error.getErrorInfo();
          const url = event.request.getRequestUrl();
          console.error('[WebPage] error receive, url:', url, 'error:', err);
          console.error('[WebPage] hasSwitchedToVpn:', this.hasSwitchedToVpn);
          if (!this.hasSwitchedToVpn &&
              (err.includes('net::ERR_CONNECTION') ||
               err.includes('net::ERR_NAME_NOT_RESOLVED'))) {
            console.info('[WebPage] detected connection error, will switch to VPN');
            this.switchToVpnMode();
          }
        })
        .onPageEnd(() => {
          this.pageLoadCount++;
          const currentUrl = this.controller.getUrl();
          this.url = currentUrl;
          console.info('[WebPage] onPageEnd #', this.pageLoadCount, 'url:', currentUrl);
          console.info('[WebPage] isVpnMode:', this.isVpnMode, 'hasSwitchedToVpn:', this.hasSwitchedToVpn);

          if (this.isVpnMode && VpnEncoder.isLoginPage(currentUrl)) {
            this.message = '请完成统一身份认证登录';
            console.info('[WebPage] detected login page (VPN mode)');
          } else if (!this.isVpnMode && VpnEncoder.isLoginPage(currentUrl)) {
            this.message = '请先登录';
            console.info('[WebPage] detected login page (normal mode)');
          } else {
            this.message = '正在加载...';
          }
        })
        .onSslErrorEvent((event) => {
          console.error('[WebPage] SSL error:', event.error);
        })
        .onConsole((event) => {
          console.info('[WebPage] console from web:', event.message.getMessage());
          return true;
        });
    }
    .width('100%')
    .height('100%');
  }
}
