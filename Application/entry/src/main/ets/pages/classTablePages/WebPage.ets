import { webview } from '@kit.ArkWeb';
import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppConstants } from '../../common/constants/AppConstants';
import { VpnEncoder } from '../../common/utils/VpnEncoder';
import { ThemeManager } from '../../common/utils/ThemeManager';

@Entry
@Component
struct WebPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State pageTitle: string = '校园网页';
  @State url: string = AppConstants.UESTC_URL;
  @State progress: number = 0;
  @State isLoading: boolean = true;
  @State hasLoadError: boolean = false;
  @State errorMessage: string = '';
  @State isVpnMode: boolean = false;
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
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
    this.hasLoadError = false;
    this.isLoading = true;

    try {
      const vpnUrl = VpnEncoder.buildVpnUrlFromOriginal(this.originalUrl || this.url);
      this.url = vpnUrl;
      console.info('[WebPage] switchToVpnMode, target:', vpnUrl);
      this.controller.loadUrl(vpnUrl);
      promptAction.showToast({ message: '检测到校内服务，已自动为您切换 WebVPN 访问', duration: 2500 });
    } catch (e) {
      console.error('[WebPage] switchToVpnMode error:', e);
      this.hasLoadError = true;
      this.errorMessage = '切换 WebVPN 失败，请检查网络';
    }
  }

  private reloadPage(): void {
    this.hasLoadError = false;
    this.isLoading = true;
    this.controller.refresh();
  }

  private copyCurrentUrl(): void {
    try {
      const currentUrl: string = this.controller.getUrl() || this.url;
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, currentUrl);
      pasteboard.getSystemPasteboard().setDataSync(pasteData);
      promptAction.showToast({ message: '网页链接已复制到剪贴板', duration: 2000 });
    } catch (e) {
      console.error('[WebPage] copy url error:', e);
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

        if (this.isVpnMode) {
          Text('WebVPN')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getAccentColor())
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(ThemeManager.getAccentBgColor())
            .borderRadius(4)
            .margin({ right: 8 });
        }

        Image($r('app.media.refresh'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_primary'))
          .margin({ left: 4, right: 4 })
          .onClick(() => {
            this.reloadPage();
          });
      }
      .width('100%')
      .height(52)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.card_background'))
      .alignItems(VerticalAlign.Center);

      // 加载进度条
      if (this.isLoading && this.progress > 0 && this.progress < 100) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color($r('app.color.primary_color'));
      }

      Stack() {
        Web({ src: this.url, controller: this.controller })
          .width('100%')
          .height('100%')
          .domStorageAccess(true)
          .javaScriptAccess(true)
          .databaseAccess(true)
          .onlineImageAccess(true)
          .fileAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.Default)
          .overviewModeAccess(true)
          .onPageBegin(() => {
            this.isLoading = true;
            this.hasLoadError = false;
            console.info('[WebPage] onPageBegin, url:', this.url);
          })
          .onProgressChange((event) => {
            this.progress = event.newProgress;
          })
          .onHttpErrorReceive((event) => {
            const statusCode = event.response.getResponseCode();
            console.error('[WebPage] HTTP error, status:', statusCode);
            if (!this.hasSwitchedToVpn && (statusCode === 403 || statusCode === 502 || statusCode === 504)) {
              this.switchToVpnMode();
            } else if (statusCode >= 400) {
              this.hasLoadError = true;
              this.errorMessage = `页面响应异常 (HTTP ${statusCode})`;
            }
          })
          .onErrorReceive((event) => {
            const err = event.error.getErrorInfo();
            console.error('[WebPage] error:', err);
            const isConnIssue: boolean =
              err.includes('net::ERR_CONNECTION') ||
              err.includes('net::ERR_NAME_NOT_RESOLVED') ||
              err.includes('net::ERR_TIMED_OUT') ||
              err.includes('net::ERR_SOCKET_NOT_CONNECTED') ||
              err.includes('net::ERR_SSL_PROTOCOL_ERROR') ||
              err.includes('net::ERR_EMPTY_RESPONSE');

            if (!this.hasSwitchedToVpn && isConnIssue) {
              this.switchToVpnMode();
            } else {
              this.hasLoadError = true;
              this.errorMessage = '网页加载失败，该服务可能仅限校园网访问';
            }
          })
          .onPageEnd(() => {
            this.isLoading = false;
            const currentUrl = this.controller.getUrl();
            if (currentUrl && currentUrl.length > 0) {
              this.url = currentUrl;
            }
            const docTitle = this.controller.getTitle();
            if (docTitle && docTitle.trim().length > 0 && (this.pageTitle === '校园网页' || this.pageTitle === '一卡通余额')) {
              this.pageTitle = docTitle;
            }
          })
          .onSslErrorEvent((event) => {
            console.warn('[WebPage] SSL warning, confirming certificate:', event.error);
            // 校园网内网服务与 WebVPN 证书放行，避免 ArkWeb 校验阻断产生永久白屏
            event.handler.handleConfirm();
          })
          .onConsole((event) => {
            console.info('[WebPage] console:', event.message.getMessage());
            return true;
          });

        if (this.hasLoadError) {
          Column({ space: 14 }) {
            Text('🌐')
              .fontSize(42);

            Text('页面访问受限或加载失败')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeManager.getTextPrimaryColor());

            Text(this.errorMessage.length > 0 ? this.errorMessage : '一卡通及部分校内服务需在校园网或 WebVPN 环境下使用')
              .fontSize(13)
              .fontColor(ThemeManager.getTextSecondaryColor())
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24 });

            Row({ space: 12 }) {
              if (!this.isVpnMode) {
                Button('切换 WebVPN 访问')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .backgroundColor(ThemeManager.getAccentColor())
                  .borderRadius(18)
                  .height(36)
                  .padding({ left: 16, right: 16 })
                  .onClick(() => {
                    this.switchToVpnMode();
                  });
              }

              Button('重新加载')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeManager.getTextPrimaryColor())
                .backgroundColor(this.isDarkMode ? '#334155' : '#E2E8F0')
                .borderRadius(18)
                .height(36)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  this.reloadPage();
                });

              Button('复制链接')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeManager.getTextSecondaryColor())
                .backgroundColor(Color.Transparent)
                .borderRadius(18)
                .height(36)
                .border({ width: 1, color: this.isDarkMode ? '#475569' : '#CBD5E1' })
                .padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.copyCurrentUrl();
                });
            }
            .margin({ top: 8 });
          }
          .width('90%')
          .padding(24)
          .borderRadius(16)
          .backgroundColor(ThemeManager.getCardColor())
          .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
          .alignItems(HorizontalAlign.Center);
        }
      }
      .width('100%')
      .layoutWeight(1);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'));
  }
}
