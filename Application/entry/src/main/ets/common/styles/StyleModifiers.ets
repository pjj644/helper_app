import { CardStyle, TextStyle, ButtonStyle, ShadowStyle } from './StyleConfigs';

export class StyleModifiers {
  static applyCardStyle<T extends CommonAttribute>(component: T, style: CardStyle): T {
    return component
      .backgroundColor(style.backgroundColor)
      .borderRadius(style.radius)
      .padding(style.padding)
      .shadow({
        radius: style.shadowRadius,
        color: style.shadowColor,
        offsetX: 0,
        offsetY: 2
      });
  }

  static applyTextStyle<T extends TextAttribute>(component: T, style: TextStyle): T {
    let result = component
      .fontSize(style.fontSize)
      .fontColor(style.fontColor)
      .fontWeight(style.fontWeight)
      .maxLines(style.maxLines);

    if (style.textOverflow !== TextOverflow.Clip) {
      result = result.textOverflow({ overflow: style.textOverflow });
    }

    return result;
  }

  static applyButtonStyle<T extends ButtonAttribute>(component: T, style: ButtonStyle): T {
    return component
      .height(style.height)
      .borderRadius(style.borderRadius)
      .backgroundColor(style.backgroundColor)
      .fontSize(style.fontSize)
      .fontColor(style.fontColor);
  }
}

export class StyleBuilder {
  private styles: Map<string, Object> = new Map();

  card(style: CardStyle): StyleBuilder {
    this.styles.set('card', style);
    return this;
  }

  text(style: TextStyle): StyleBuilder {
    this.styles.set('text', style);
    return this;
  }

  shadow(style: ShadowStyle): StyleBuilder {
    this.styles.set('shadow', style);
    return this;
  }

  build(): Map<string, Object> {
    return this.styles;
  }
}
