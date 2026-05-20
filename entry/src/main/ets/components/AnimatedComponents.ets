import { AnimationSettings, AnimationSpeed, AnimationCurveType } from '../common/AnimationSettings';

@Component
export struct AnimatedCard {
  @BuilderParam content: () => void = () => {};

  @Prop delay: number = 0;

  @Prop animationEnabled: boolean = true;

  @State private scale: number = 0.8;

  @State private opacity: number = 0;

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
      this.scale = 1;
      this.opacity = 1;
      this.translateY = 0;
    }
  }

  private playEnterAnimation(): void {
    const params = this.animationSettings.getCardEnterParams();
    this.getUIContext().animateTo({
      duration: params.duration,
      curve: params.curve
    }, () => {
      this.scale = 1;
      this.opacity = 1;
      this.translateY = 0;
    });
  }

  build() {
    Column() {
      this.content();
    }
    .scale({ x: this.scale, y: this.scale })
    .opacity(this.opacity)
    .translate({ y: this.translateY })
  }
}

@Component
export struct AnimatedListItem {
  @BuilderParam content: () => void = () => {};

  @Prop delay: number = 0;

  @Prop animationEnabled: boolean = true;

  @State private opacity: number = 0;

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
      this.opacity = 1;
      this.translateX = 0;
    }
  }

  private playEnterAnimation(): void {
    const duration = this.animationSettings.getEnterDuration() * 0.6;
    this.getUIContext().animateTo({
      duration: duration,
      curve: Curve.Smooth
    }, () => {
      this.opacity = 1;
      this.translateX = 0;
    });
  }

  build() {
    Column() {
      this.content();
    }
    .opacity(this.opacity)
    .translate({ x: this.translateX })
  }
}

@Component
export struct PageTransitionWrapper {
  @BuilderParam content: () => void = () => {};

  @State private scale: number = 0.95;

  @State private opacity: number = 0;

  private hasAnimated: boolean = false;

  private animationSettings: AnimationSettings = AnimationSettings.getInstance();

  aboutToAppear(): void {
    if (this.animationSettings.pageTransitionEnabled && !this.hasAnimated) {
      this.hasAnimated = true;
      this.playEnterAnimation();
    } else {
      this.scale = 1;
      this.opacity = 1;
    }
  }

  private playEnterAnimation(): void {
    const params = this.animationSettings.getCardEnterParams();
    this.getUIContext().animateTo({
      duration: params.duration,
      curve: params.curve
    }, () => {
      this.scale = 1;
      this.opacity = 1;
    });
  }

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .height('100%')
    .scale({ x: this.scale, y: this.scale })
    .opacity(this.opacity)
  }
}

@Component
export struct SpringButton {
  @BuilderParam content: () => void = () => {};

  onButtonClick?: () => void;

  @State private scale: number = 1;

  private animationSettings: AnimationSettings = AnimationSettings.getInstance();

  private handlePress(): void {
    const duration = this.animationSettings.getBaseDuration() * 0.3;
    this.getUIContext().animateTo({
      duration: duration,
      curve: curves.responsiveSpringMotion(0.5, 0.8)
    }, () => {
      this.scale = 0.95;
    });
  }

  private handleRelease(): void {
    const duration = this.animationSettings.getBaseDuration() * 0.5;
    this.getUIContext().animateTo({
      duration: duration,
      curve: curves.responsiveSpringMotion(0.3, 0.6)
    }, () => {
      this.scale = 1;
    });
  }

  build() {
    Column() {
      this.content();
    }
    .scale({ x: this.scale, y: this.scale })
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
