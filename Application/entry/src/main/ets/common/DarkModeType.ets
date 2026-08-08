export enum DarkModeType {
  LIGHT = 'light',
  DARK = 'dark',
  FOLLOW_SYSTEM = 'follow_system'
}

export const DarkModeTypeNames: Record<string, string> = {
  [DarkModeType.LIGHT]: '浅色模式',
  [DarkModeType.DARK]: '深色模式',
  [DarkModeType.FOLLOW_SYSTEM]: '跟随系统'
};
