import { AppConstants } from '../constants/AppConstants';

export class CardStyle {
  radius: number = AppConstants.CARD_RADIUS;
  backgroundColor: ResourceColor = $r('app.color.card_background');
  padding: number = AppConstants.PAGE_PADDING;
  shadowRadius: number = AppConstants.SHADOW_SMALL;
  shadowColor: ResourceColor = $r('app.color.shadow_color');

  static small(): CardStyle {
    const style = new CardStyle();
    style.radius = AppConstants.SMALL_RADIUS;
    style.padding = AppConstants.LIST_ITEM_SPACE;
    return style;
  }

  static large(): CardStyle {
    const style = new CardStyle();
    style.shadowRadius = AppConstants.SHADOW_LARGE;
    return style;
  }
}

export class TextStyle {
  fontSize: number = AppConstants.FONT_BODY;
  fontColor: ResourceColor = $r('app.color.text_primary');
  fontWeight: FontWeight = FontWeight.Normal;
  maxLines: number = AppConstants.SINGLE_LINE;
  textOverflow: TextOverflow = TextOverflow.Ellipsis;

  static title(): TextStyle {
    const style = new TextStyle();
    style.fontSize = AppConstants.FONT_TITLE;
    style.fontWeight = FontWeight.Bold;
    return style;
  }

  static subtitle(): TextStyle {
    const style = new TextStyle();
    style.fontSize = AppConstants.FONT_SUBTITLE;
    style.fontWeight = FontWeight.Medium;
    return style;
  }

  static caption(): TextStyle {
    const style = new TextStyle();
    style.fontSize = AppConstants.FONT_CAPTION;
    style.fontColor = $r('app.color.text_tertiary');
    return style;
  }
}

export class ButtonStyle {
  height: number = 44;
  borderRadius: number = AppConstants.SMALL_RADIUS;
  backgroundColor: ResourceColor = $r('app.color.primary_color');
  fontColor: ResourceColor = $r('app.color.text_white');
  fontSize: number = AppConstants.FONT_BODY;

  static primary(): ButtonStyle {
    return new ButtonStyle();
  }

  static secondary(): ButtonStyle {
    const style = new ButtonStyle();
    style.backgroundColor = $r('app.color.button_background');
    style.fontColor = $r('app.color.text_primary');
    return style;
  }

  static small(): ButtonStyle {
    const style = new ButtonStyle();
    style.height = 36;
    style.fontSize = AppConstants.FONT_CAPTION;
    return style;
  }
}

export class ShadowStyle {
  radius: number = AppConstants.SHADOW_MEDIUM;
  color: ResourceColor = 'rgba(0, 0, 0, 0.1)';
  offsetX: number = 0;
  offsetY: number = 2;

  static small(): ShadowStyle {
    const style = new ShadowStyle();
    style.radius = AppConstants.SHADOW_SMALL;
    style.color = 'rgba(0, 0, 0, 0.05)';
    return style;
  }

  static large(): ShadowStyle {
    const style = new ShadowStyle();
    style.radius = AppConstants.SHADOW_LARGE;
    style.color = 'rgba(0, 0, 0, 0.15)';
    style.offsetY = 6;
    return style;
  }
}

export class GradientStyle {
  angle: number = 135;
  colors: Array<[string, number]> = [];

  static primary(): GradientStyle {
    const style = new GradientStyle();
    style.colors = [['#667eea', 0], ['#764ba2', 0.5], ['#f093fb', 1]];
    return style;
  }

  static blue(): GradientStyle {
    const style = new GradientStyle();
    style.colors = [['#4facfe', 0], ['#00f2fe', 1]];
    return style;
  }

  static green(): GradientStyle {
    const style = new GradientStyle();
    style.colors = [['#43e97b', 0], ['#38f9d7', 1]];
    return style;
  }
}
