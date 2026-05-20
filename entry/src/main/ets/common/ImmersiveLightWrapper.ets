import { hdsEffect } from '@kit.UIDesignKit';
import { curves, RectShape } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { UISettings } from './UISettings';
import { MaterialEffects, MaterialParams } from './MaterialEffects';

@Component
export struct ImmersiveLightWrapper {
  @BuilderParam content: () => void;
  @Prop lightHeight: number = 100;
  @Prop lightColor: ResourceColor = Color.White;
  @Prop radius: number = 16;
  @Prop lightIntensity: number = 2.5;
  @Prop noBackground: boolean = false;
  @State currentIntensity: number = 0;
  @State private fingerX: number = 0;
  @State private fingerY: number = 0;
  @State isDark: boolean = false;

  @State blurRadius: number = 20;
  @State shadowRadius: number = 10;
  @State materialBorderWidth: number = 1;
  @State advancedBlurEnabled: boolean = true;

  private appSettings: UISettings = UISettings.getInstance();
  private materialEffects: MaterialEffects = MaterialEffects.getInstance();
  private darkModeListener: (isDark: boolean) => void = (isDark: boolean) => {
    this.isDark = isDark;
  };
  private materialListener: () => void = () => {
    console.log('[ImmersiveLightWrapper] materialListener 被调用');
    try {
      this.updateMaterialParams();
    } catch (error) {
      console.error(`[ImmersiveLightWrapper] 更新材质参数失败: ${error}`);
    }
  };

  aboutToAppear(): void {
    console.log('[ImmersiveLightWrapper] aboutToAppear - 初始化组件');
    this.isDark = this.appSettings.darkMode;
    this.appSettings.addDarkModeListener(this.darkModeListener);
    this.materialEffects.addListener(this.materialListener);
    this.updateMaterialParams();
  }

  aboutToDisappear(): void {
    this.appSettings.removeDarkModeListener(this.darkModeListener);
    this.materialEffects.removeListener(this.materialListener);
  }

  private updateMaterialParams(): void {
    this.advancedBlurEnabled = this.materialEffects.advancedBlurEnabled;
    const params = this.materialEffects.getStyleAdjustedParams();
    this.blurRadius = params.radius;
    this.shadowRadius = this.materialEffects.shadowIntensity;
    this.materialBorderWidth = this.materialEffects.getBorderWidth();
    console.log(`[ImmersiveLightWrapper] 材质参数已更新: blurRadius=${this.blurRadius}, shadowRadius=${this.shadowRadius}, borderWidth=${this.materialBorderWidth}, advancedBlur=${this.advancedBlurEnabled}`);
  }

  @Builder lightTracker() {
    Stack() {
      Flex()
        .size(this.currentIntensity ? { width: 1, height: 1 } : { width: 0, height: 0 })
        .backgroundColor(Color.Transparent)
        .visualEffect(
          new hdsEffect.HdsEffectBuilder()
            .pointLight({
              options: {
                color: this.lightColor,
                intensity: this.currentIntensity,
                height: this.lightHeight
              }
            })
            .buildEffect()
        )
        .position({ x: this.fingerX, y: this.fingerY })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      this.content()
    }
    .clip(true)
    .clipShape(new RectShape({ width: '100%', height: '100%', radius: this.radius }))
    .shadow({ radius: this.shadowRadius, color: $r('app.color.shadow_color') })
    .backgroundColor(this.noBackground ? Color.Transparent : $r('app.color.card_background'))
    .visualEffect(
      new hdsEffect.HdsEffectBuilder().pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      }).buildEffect()
    )
    .backdropBlur(this.noBackground || !this.advancedBlurEnabled ? 0 : this.blurRadius)
    .borderRadius(this.radius)
    .border({
      width: this.noBackground ? 0 : (this.isDark ? 0.5 : this.materialBorderWidth),
      color: $r('app.color.card_border')
    })
    .overlay(this.lightTracker())
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
          this.currentIntensity = this.lightIntensity;
        });
        this.fingerX = event.touches[0].x;
        this.fingerY = event.touches[0].y;
      } else if (event.type === TouchType.Move) {
        animateTo({ curve: curves.responsiveSpringMotion(0.5, 0.5) }, () => {
          this.fingerX = event.touches[0].x;
          this.fingerY = event.touches[0].y;
        });
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.currentIntensity = 0;
        });
      }
    })
  }
}
