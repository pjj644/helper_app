import { ThemeManager } from '../common/utils/ThemeManager';

@Component
export struct WebScrapeTakeoverBar {
  @Prop isManualMode: boolean = false;
  @Prop promptMessage: string = '请在下方网页中完成登录或导航至目标页面';
  @Prop isExtracting: boolean = false;
  onScrape?: () => void;
  onRefresh?: () => void;
  onBack?: () => void;
  onToggleVpn?: () => void;
  onToggleManual?: () => void;

  build() {
    Column() {
      // 顶部指示条
      Row({ space: 8 }) {
        Row({ space: 4 }) {
          Circle({ width: 8, height: 8 })
            .fill(this.isManualMode ? '#F59E0B' : '#10B981');
          Text(this.isManualMode ? '手动接管中' : '自动抓取模式')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isManualMode ? '#F59E0B' : '#10B981');
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(this.isManualMode ? 'rgba(245, 158, 11, 0.15)' : 'rgba(16, 185, 129, 0.15)')
        .borderRadius(12);

        Text(this.promptMessage)
          .fontSize(12)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1);

        Button(this.isManualMode ? '退出接管' : '手动接管')
          .fontSize(12)
          .fontColor(this.isManualMode ? '#EF4444' : ThemeManager.getAccentColor())
          .backgroundColor(Color.Transparent)
          .height(28)
          .onClick(() => {
            if (this.onToggleManual) {
              this.onToggleManual();
            }
          });
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 6 });

      // 手动接管模式下的主要操作控制台
      if (this.isManualMode) {
        Row({ space: 8 }) {
          Button('◀ 后退')
            .fontSize(12)
            .height(34)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .backgroundColor(ThemeManager.isDarkMode() ? '#2D3748' : '#E2E8F0')
            .borderRadius(8)
            .onClick(() => {
              if (this.onBack) {
                this.onBack();
              }
            });

          Button('🔄 刷新')
            .fontSize(12)
            .height(34)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .backgroundColor(ThemeManager.isDarkMode() ? '#2D3748' : '#E2E8F0')
            .borderRadius(8)
            .onClick(() => {
              if (this.onRefresh) {
                this.onRefresh();
              }
            });

          if (this.onToggleVpn) {
            Button('🔐 VPN')
              .fontSize(12)
              .height(34)
              .fontColor(ThemeManager.getTextPrimaryColor())
              .backgroundColor(ThemeManager.isDarkMode() ? '#2D3748' : '#E2E8F0')
              .borderRadius(8)
              .onClick(() => {
                const cb = this.onToggleVpn;
                if (cb) {
                  cb();
                }
              });
          }

          Button() {
            if (this.isExtracting) {
              Row({ space: 4 }) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(Color.White);
                Text('抓取中...')
                  .fontSize(13)
                  .fontColor(Color.White);
              }
            } else {
              Text('📥 立即抓取当前页')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White);
            }
          }
          .layoutWeight(1)
          .height(36)
          .backgroundColor('#10B981')
          .borderRadius(8)
          .enabled(!this.isExtracting)
          .onClick(() => {
            if (this.onScrape) {
              this.onScrape();
            }
          });
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 8 });
      }
    }
    .width('100%')
    .backgroundColor(ThemeManager.getCardColor())
    .border({
      width: { bottom: 1 },
      color: ThemeManager.getBorderColor()
    })
    .shadow({
      radius: 8,
      color: 'rgba(0, 0, 0, 0.08)',
      offsetY: 2
    });
  }
}
