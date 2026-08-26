import { CountdownParts, DateUtils } from '../common/utils/DateUtils';
import { ThemeManager } from '../common/utils/ThemeManager';

@Component
export struct CountdownCard {
  @Prop examName: string = '';
  @Prop examDate: string = '';
  @Prop examTimeRange: string = '';
  @Prop beginTime: number = 0;
  @Prop compact: boolean = false;
  @State private parts: CountdownParts = {
    days: 0, hours: 0, minutes: 0, seconds: 0,
    totalSeconds: 0, isExpired: false, isUnknown: true, urgency: 0
  };
  private timer: number = -1;

  aboutToAppear(): void {
    this.parts = DateUtils.getCountdownParts(Date.now(), this.beginTime);
    this.timer = setInterval(() => {
      const now = Date.now();
      this.parts = DateUtils.getCountdownParts(now, this.beginTime);
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private formatNumber(n: number): string {
    return DateUtils.twoDigit(n);
  }

  private getGradientStart(): string {
    switch (this.parts.urgency) {
      case 3: return '#DC2626';
      case 2: return '#EF4444';
      case 1: return '#F59E0B';
      default: return '#3B82FF';
    }
  }

  private getGradientEnd(): string {
    switch (this.parts.urgency) {
      case 3: return '#991B1B';
      case 2: return '#B91C1C';
      case 1: return '#D97706';
      default: return '#1D4ED8';
    }
  }

  private getDigitBgColor(): string {
    switch (this.parts.urgency) {
      case 3: case 2: return 'rgba(255,255,255,0.18)';
      case 1: return 'rgba(255,255,255,0.16)';
      default: return 'rgba(255,255,255,0.14)';
    }
  }

  private getShadowColor(): string {
    if (this.parts.urgency >= 2) {
      return 'rgba(239,68,68,0.25)';
    }
    if (this.parts.urgency >= 1) {
      return 'rgba(245,158,11,0.25)';
    }
    return 'rgba(59,130,255,0.2)';
  }

  build() {
    if (this.beginTime <= 0 || this.parts.isExpired) {
      Column() {
        Text(this.beginTime <= 0 ? '时间未知' : '考试已进行中')
          .fontSize(this.compact ? 12 : 14)
          .fontColor(ThemeManager.getTextTertiaryColor());
      }
      .width('100%')
      .padding(this.compact ? 10 : 16)
      .borderRadius(18)
      .backgroundColor(ThemeManager.getBackgroundSecondaryColor());
    } else {
      Column({ space: this.compact ? 6 : 10 }) {
        if (!this.compact && this.examName) {
          Row() {
            Text('距')
              .fontSize(13)
              .fontColor('rgba(255,255,255,0.6)');
            Text(this.examName)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text('还有')
              .fontSize(13)
              .fontColor('rgba(255,255,255,0.6)');
          }
          .width('100%');
        }

        Row({ space: 0 }) {
          if (this.parts.days > 0) {
            Column({ space: 2 }) {
              Text(this.formatNumber(this.parts.days))
                .fontSize(this.compact ? 22 : 32)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .fontFamily('monospace')
                .width(this.compact ? 48 : 60)
                .height(this.compact ? 40 : 52)
                .textAlign(TextAlign.Center)
                .borderRadius(10)
                .backgroundColor(this.getDigitBgColor());

              Text('天')
                .fontSize(this.compact ? 9 : 11)
                .fontColor('rgba(255,255,255,0.7)')
                .textAlign(TextAlign.Center);
            }

            Text(':')
              .fontSize(this.compact ? 18 : 24)
              .fontWeight(FontWeight.Bold)
              .fontColor('rgba(255,255,255,0.5)')
              .margin({ left: 2, right: 2 });
          }

          Column({ space: 2 }) {
            Text(this.formatNumber(this.parts.hours))
              .fontSize(this.compact ? 22 : 32)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .fontFamily('monospace')
              .width(this.compact ? 48 : 60)
              .height(this.compact ? 40 : 52)
              .textAlign(TextAlign.Center)
              .borderRadius(10)
              .backgroundColor(this.getDigitBgColor());

            Text('时')
              .fontSize(this.compact ? 9 : 11)
              .fontColor('rgba(255,255,255,0.7)')
              .textAlign(TextAlign.Center);
          }

          Text(':')
            .fontSize(this.compact ? 18 : 24)
            .fontWeight(FontWeight.Bold)
            .fontColor('rgba(255,255,255,0.5)')
            .margin({ left: 2, right: 2 });

          Column({ space: 2 }) {
            Text(this.formatNumber(this.parts.minutes))
              .fontSize(this.compact ? 22 : 32)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .fontFamily('monospace')
              .width(this.compact ? 48 : 60)
              .height(this.compact ? 40 : 52)
              .textAlign(TextAlign.Center)
              .borderRadius(10)
              .backgroundColor(this.getDigitBgColor());

            Text('分')
              .fontSize(this.compact ? 9 : 11)
              .fontColor('rgba(255,255,255,0.7)')
              .textAlign(TextAlign.Center);
          }

          Text(':')
            .fontSize(this.compact ? 18 : 24)
            .fontWeight(FontWeight.Bold)
            .fontColor('rgba(255,255,255,0.5)')
            .margin({ left: 2, right: 2 });

          Column({ space: 2 }) {
            Text(this.formatNumber(this.parts.seconds))
              .fontSize(this.compact ? 22 : 32)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .fontFamily('monospace')
              .width(this.compact ? 48 : 60)
              .height(this.compact ? 40 : 52)
              .textAlign(TextAlign.Center)
              .borderRadius(10)
              .backgroundColor(this.getDigitBgColor());

            Text('秒')
              .fontSize(this.compact ? 9 : 11)
              .fontColor('rgba(255,255,255,0.7)')
              .textAlign(TextAlign.Center);
          }
        }
        .justifyContent(FlexAlign.Center);

        if (!this.compact && this.examDate) {
          Text(`${this.examDate}  ${this.examTimeRange}`)
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.5)');
        }
      }
      .width('100%')
      .padding(this.compact ? 10 : 16)
      .borderRadius(18)
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [
          [this.getGradientStart(), 0.0],
          [this.getGradientEnd(), 1.0]
        ]
      })
      .shadow({
        radius: 20,
        color: this.getShadowColor(),
        offsetY: 6
      });
    }
  }
}
