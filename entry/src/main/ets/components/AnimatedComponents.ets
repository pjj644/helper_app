import { curves } from '@kit.ArkUI';
import { AnimationSettings, AnimationSpeed, AnimationCurveType } from '../common/AnimationSettings';

@Component
export struct AnimatedCard {
  @BuilderParam content: () => void = () => {};

  @Prop delay: number = 0;

  @Prop animationEnabled: boolean = true;

  @State private cardScale: number = 0.8;

  @State private cardOpacity: number = 0;

  @State private translateY: number = 30;

  private hasAnimated: boolean = false;

  private animationSettings: AnimationSettings = AnimationSettings.getInstance();

  aboutToAppear(): void {
    if (this.animationEnabled && this.animationSettings.cardEnterEnabled && !this.hasAnimated) {
      this.hasAnimated = true;
      setTimeout(() => {
        this.playEnterAnimation();
      }, this.delay);
    } else {
      this.cardScale = 1;
      this.cardOpacity = 1;
      this.translateY = 0;
    }
  }

  private playEnterAnimation(): void {
    const params = this.animationSettings.getCardEnterParams();
    this.getUIContext().animateTo({
      duration: params.duration,
      curve: params.curve
    }, () => {
      this.cardScale = 1;
      this.cardOpacity = 1;
      this.translateY = 0;
    });
  }

  build() {
    Column() {
      this.content();
    }
    .scale({ x: this.cardScale, y: this.cardScale })
    .opacity(this.cardOpacity)
    .translate({ y: this.translateY })
  }
}

@Component
export struct AnimatedListItem {
  @BuilderParam content: () => void = () => {};

  @Prop delay: number = 0;

  @Prop animationEnabled: boolean = true;

  @State private itemOpacity: number = 0;

  @State private translateX: number = -20;

  private hasAnimated: boolean = false;

  private animationSettings: AnimationSettings = AnimationSettings.getInstance();

  aboutToAppear(): void {
    if (this.animationEnabled && this.animationSettings.listItemAnimationEnabled && !this.hasAnimated) {
      this.hasAnimated = true;
      setTimeout(() => {
        this.playEnterAnimation();
      }, this.delay);
    } else {
      this.itemOpacity = 1;
      this.translateX = 0;
    }
  }

  private playEnterAnimation(): void {
    const duration = this.animationSettings.getEnterDuration() * 0.6;
    this.getUIContext().animateTo({
      duration: duration,
      curve: Curve.Smooth
    }, () => {
      this.itemOpacity = 1;
      this.translateX = 0;
    });
  }

  build() {
    Column() {
      this.content();
    }
    .opacity(this.itemOpacity)
    .translate({ x: this.translateX })
  }
}

@Component
export struct PageTransitionWrapper {
  @BuilderParam content: () => void = () => {};

  @State private pageScale: number = 0.95;

  @State private pageOpacity: number = 0;

  private hasAnimated: boolean = false;

  private animationSettings: AnimationSettings = AnimationSettings.getInstance();

  aboutToAppear(): void {
    if (this.animationSettings.pageTransitionEnabled && !this.hasAnimated) {
      this.hasAnimated = true;
      this.playEnterAnimation();
    } else {
      this.pageScale = 1;
      this.pageOpacity = 1;
    }
  }

  private playEnterAnimation(): void {
    const params = this.animationSettings.getCardEnterParams();
    this.getUIContext().animateTo({
      duration: params.duration,
      curve: params.curve
    }, () => {
      this.pageScale = 1;
      this.pageOpacity = 1;
    });
  }

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .height('100%')
    .scale({ x: this.pageScale, y: this.pageScale })
    .opacity(this.pageOpacity)
  }
}

@Component
export struct SpringButton {
  @BuilderParam content: () => void = () => {};

  onButtonClick?: () => void;

  @State private buttonScale: number = 1;

  private animationSettings: AnimationSettings = AnimationSettings.getInstance();

  private handlePress(): void {
    const duration = this.animationSettings.getBaseDuration() * 0.3;
    this.getUIContext().animateTo({
      duration: duration,
      curve: curves.responsiveSpringMotion(0.5, 0.8)
    }, () => {
      this.buttonScale = 0.95;
    });
  }

  private handleRelease(): void {
    const duration = this.animationSettings.getBaseDuration() * 0.5;
    this.getUIContext().animateTo({
      duration: duration,
      curve: curves.responsiveSpringMotion(0.3, 0.6)
    }, () => {
      this.buttonScale = 1;
    });
  }

  build() {
    Column() {
      this.content();
    }
    .scale({ x: this.buttonScale, y: this.buttonScale })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.handlePress();
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.handleRelease();
        if (event.type === TouchType.Up && this.onButtonClick) {
          this.onButtonClick();
        }
      }
    })
  }
}
