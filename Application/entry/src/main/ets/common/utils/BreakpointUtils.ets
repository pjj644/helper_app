import { window, display } from '@kit.ArkUI';
import { Context } from '@kit.AbilityKit';

export class BreakpointUtils {
  private static getBreakpointFromWidth(widthVp: number): string {
    if (widthVp < 600) {
      return 'sm'; // 手机竖屏
    } else if (widthVp < 840) {
      return 'md'; // 折叠屏展开态
    } else {
      return 'lg'; // 平板/PC宽屏
    }
  }

  static registerBreakpoint(context: Context, callback: (breakpoint: string) => void): void {
    try {
      window.getLastWindow(context, (err, win) => {
        if (!err && win) {
          // 初始化即计算一次当前断点
          try {
            const properties = win.getWindowProperties();
            const density = display.getDefaultDisplaySync().densityPixels || 1;
            const initialWidthVp = properties.windowRect.width / density;
            callback(BreakpointUtils.getBreakpointFromWidth(initialWidthVp));
          } catch (e) {
            callback('sm');
          }

          // 监听窗口尺寸变化
          win.on('windowSizeChange', (size) => {
            try {
              const density = display.getDefaultDisplaySync().densityPixels || 1;
              const widthVp = size.width / density;
              callback(BreakpointUtils.getBreakpointFromWidth(widthVp));
            } catch (e) {
              callback('sm');
            }
          });
        }
      });
    } catch (e) {
      callback('sm');
    }
  }
}
