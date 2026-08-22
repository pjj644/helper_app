export class Logger {
  private static debugEnabled: boolean = false;

  static setDebugEnabled(enabled: boolean): void {
    Logger.debugEnabled = enabled;
  }

  private static formatTag(tag: string): string {
    if (tag.startsWith('[') && tag.endsWith(']')) {
      return tag;
    }
    return `[${tag}]`;
  }

  static debug(tag: string, message: string): void {
    if (Logger.debugEnabled) {
      console.info(Logger.formatTag(tag), message);
    }
  }

  static info(tag: string, message: string): void {
    console.info(Logger.formatTag(tag), message);
  }

  static warn(tag: string, message: string): void {
    console.warn(Logger.formatTag(tag), message);
  }

  static error(tag: string, message: string): void {
    console.error(Logger.formatTag(tag), message);
  }
}
