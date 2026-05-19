export class ThemeColors {
  static readonly LIGHT_BG: string = '#F6F8FC';
  static readonly LIGHT_BG_SECONDARY: string = '#FFFFFF';
  static readonly LIGHT_TEXT_PRIMARY: string = '#1D2A3A';
  static readonly LIGHT_TEXT_SECONDARY: string = '#607088';
  static readonly LIGHT_TEXT_TERTIARY: string = '#8A95A8';
  static readonly LIGHT_CARD: string = '#FFFFFF';
  static readonly LIGHT_BORDER: string = '#E6EAF2';
  static readonly LIGHT_ACCENT: string = '#2457D6';
  static readonly LIGHT_HERO_PANEL: string = '#3B82FF';
  static readonly DARK_HERO_PANEL: string = '#182338';
  static readonly LIGHT_ACCENT_BG: string = '#E8F0FF';

  static readonly DARK_BG: string = '#121212';
  static readonly DARK_BG_SECONDARY: string = '#1E1E1E';
  static readonly DARK_TEXT_PRIMARY: string = '#E0E0E0';
  static readonly DARK_TEXT_SECONDARY: string = '#B0B0B0';
  static readonly DARK_TEXT_TERTIARY: string = '#808080';
  static readonly DARK_CARD: string = '#2D2D2D';
  static readonly DARK_BORDER: string = '#3D3D3D';
  static readonly DARK_ACCENT: string = '#5B8DEF';
  static readonly DARK_ACCENT_BG: string = '#1A3A6B';
}

export class ThemeManager {
  static readonly THEME_STORAGE_KEY: string = 'app_theme_dark';

  static isDarkMode(): boolean {
    return AppStorage.get(ThemeManager.THEME_STORAGE_KEY) as boolean || false;
  }

  static setDarkMode(isDark: boolean): void {
    AppStorage.setOrCreate(ThemeManager.THEME_STORAGE_KEY, isDark);
  }

  static syncWithSystem(colorMode: string): void {
    const isDark = colorMode === 'dark';
    ThemeManager.setDarkMode(isDark);
  }

  static getBackgroundColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_BG : ThemeColors.LIGHT_BG;
  }

  static getBackgroundSecondaryColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_BG_SECONDARY : ThemeColors.LIGHT_BG_SECONDARY;
  }

  static getTextPrimaryColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_TEXT_PRIMARY : ThemeColors.LIGHT_TEXT_PRIMARY;
  }

  static getTextSecondaryColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_TEXT_SECONDARY : ThemeColors.LIGHT_TEXT_SECONDARY;
  }

  static getTextTertiaryColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_TEXT_TERTIARY : ThemeColors.LIGHT_TEXT_TERTIARY;
  }

  static getCardColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_CARD : ThemeColors.LIGHT_CARD;
  }

  static getBorderColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_BORDER : ThemeColors.LIGHT_BORDER;
  }

  static getAccentColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_ACCENT : ThemeColors.LIGHT_ACCENT;
  }

  static getAccentBgColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_ACCENT_BG : ThemeColors.LIGHT_ACCENT_BG;
  }

  static getHeroPanelColor(): string {
    return ThemeManager.isDarkMode() ? ThemeColors.DARK_HERO_PANEL : ThemeColors.LIGHT_HERO_PANEL;
  }

  static getShadowColor(): string {
    return ThemeManager.isDarkMode() ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.04)';
  }
}
