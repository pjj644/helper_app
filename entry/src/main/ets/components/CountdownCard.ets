import { CountdownParts } from '../common/utils/DateUtils';
import { DateUtils } from '../common/utils/DateUtils';
import { ThemeManager } from '../common/utils/ThemeManager';

@Component
export struct CountdownCard {
  @Prop examName: string = '';
  @Prop examDate: string = '';
  @Prop examTimeRange: string = '';
  @Prop beginTime: number = 0;
  @Prop compact: boolean = false;
  @State parts: CountdownParts = { days: 0, hours: 0, minutes: 0, seconds: 0, totalSeconds: 0, isExpired: false, isUnknown: false, urgency: 0 };
  @State pulsePhase: number = 0;
  private timer: number = -1;
  private pulseTimer: number = -1;

  aboutToAppear(): void {
    this.tick();
    this.timer = setInterval(() => this.tick(), 1000);
    if (this.beginTime > 0 && this.beginTime - Date.now() < 3600000) {
      this.pulseTimer = setInterval(() => {
        this.pulsePhase = (this.pulsePhase + 1) % 2;
      }, 800);
    }
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    if (this.pulseTimer >= 0) {
      clearInterval(this.pulseTimer);
      this.pulseTimer = -1;
    }
  }

  private tick(): void {
    this.parts = DateUtils.getCountdownParts(Date.now(), this.beginTime);
  }

  private getGradient(): [string, string] {
    switch (this.parts.urgency) {
      case 3: return ['#DC2626', '#991B1B'];
      case 2: return ['#EF4444', '#B91C1C'];
      case 1: return ['#F59E0B', '#D97706'];
      default: return ['#3B82FF', '#1D4ED8'];
    }
  }

  private getDigitBgColor(): string {
    switch (this.parts.urgency) {
      case 3: return 'rgba(255,255,255,0.18)';
      case 2: return 'rgba(255,255,255,0.16)';
      case 1: return 'rgba(255,255,255,0.16)';
      default: return 'rgba(255,255,255,0.14)';
    }
  }

  @Builder
  private DigitBox(value: number, label: string, showPulse: boolean): void {
    Column({ space: 2 }) {
      Text(DateUtils.twoDigit(value))
        .fontSize(this.compact ? 22 : 32)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .fontFamily('monospace')
        .width(this.compact ? 48 : 60)
        .height(this.compact ? 40 : 52)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor(this.getDigitBgColor())
        .opacity(showPulse && this.pulsePhase === 1 ? 0.6 : 1.0);

      Text(label)
        .fontSize(this.compact ? 9 : 11)
        .fontColor('rgba(255,255,255,0.7)')
        .textAlign(TextAlign.Center);
    }
  }

  @Builder
  private Separator(): void {
    Text(':')
      .fontSize(this.compact ? 18 : 24)
      .fontWeight(FontWeight.Bold)
      .fontColor('rgba(255,255,255,0.5)')
      .margin({ left: 2, right: 2 });
  }

  build() {
    if (this.parts.isUnknown || this.parts.isExpired) {
      if (this.compact) {
        Column() {
          Text(this.parts.isExpired ? '考试已开始' : '时间未知')
            .fontSize(12)
            .fontColor(ThemeManager.getTextTertiaryColor());
        };
      } else {
        Column() {
          Text(this.parts.isExpired ? '考试已进行中' : '时间未知')
            .fontSize(14)
            .fontColor(ThemeManager.getTextTertiaryColor());
        }
        .width('100%')
        .padding(12)
        .borderRadius(18)
        .backgroundColor(ThemeManager.getCardColor());
      }
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

        Row({ space: 4 }) {
          if (this.parts.days > 0) {
            this.DigitBox(this.parts.days, '天', false);
            this.Separator();
          }
          this.DigitBox(this.parts.hours, '时', this.parts.urgency >= 3);
          this.Separator();
          this.DigitBox(this.parts.minutes, '分', this.parts.urgency >= 3);
          this.Separator();
          this.DigitBox(this.parts.seconds, '秒', this.parts.urgency >= 3);
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
      .linearGradient({
        angle: 135,
        colors: [
          [this.getGradient()[0], 0.0],
          [this.getGradient()[1], 1.0]
        ]
      })
      .shadow({
        radius: 20,
        color: this.parts.urgency >= 2
          ? 'rgba(239,68,68,0.25)'
          : this.parts.urgency >= 1
            ? 'rgba(245,158,11,0.25)'
            : 'rgba(59,130,255,0.2)',
        offsetY: 6
      });
    }
  }
}
