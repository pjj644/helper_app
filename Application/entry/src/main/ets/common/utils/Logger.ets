export class Logger {
  private static debugEnabled: boolean = false;

  static setDebugEnabled(enabled: boolean): void {
    Logger.debugEnabled = enabled;
  }

  static debug(tag: string, message: string): void {
    if (Logger.debugEnabled) {
      console.info(tag, message);
    }
  }

  static info(tag: string, message: string): void {
    console.info(tag, message);
  }

  static warn(tag: string, message: string): void {
    console.warn(tag, message);
  }

  static error(tag: string, message: string): void {
    console.error(tag, message);
  }
}
