import { ConfigurationConstant, UIAbility, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeManager } from '../common/utils/ThemeManager';
import { UISettings } from '../common/UISettings';
import { PreferencesUtil } from '../common/PreferencesUtil';
import { AuthService } from '../service/AuthService';
import { CourseService } from '../service/CourseService';
import { AppConfigRepository } from '../repository/AppConfigRepository';
import { FloatingWindowManager } from '../common/agent/FloatingWindowManager';

const HILOG_DOMAIN = 0x0000;
const TAG = '[EntryAbility]';

export default class EntryAbility extends UIAbility {
  onCreate() {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      PreferencesUtil.getInstance().init(this.context);
      UISettings.getInstance().initDarkMode(this.context);
      // 学期参数云端配置预热：异步拉取 app-config 并落 last-good 缓存（读取侧走同步通道，失败静默用内置兜底）
      AppConfigRepository.warmUp(this.context);

      // 合规要求：仅在用户已授权隐私政策后才初始化 AGC 等第三方/云端 SDK
      if (PreferencesUtil.getInstance().hasAgreedPrivacy()) {
        AuthService.initSDK(this.context);
      } else {
        hilog.info(HILOG_DOMAIN, TAG, 'Privacy not agreed yet, delaying AGC SDK initialization.');
      }
    } catch (err) {
      hilog.error(HILOG_DOMAIN, TAG, 'Failed in onCreate. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    if (newConfig.colorMode !== undefined) {
      ThemeManager.syncWithSystem(newConfig.colorMode.toString());
      hilog.info(HILOG_DOMAIN, TAG, 'Color mode changed: %{public}s', newConfig.colorMode.toString());
    }
  }

  onDestroy(): void {
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(HILOG_DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(HILOG_DOMAIN, TAG, 'Succeeded in loading the content.');
      // 初始化全局悬浮窗管理器
      FloatingWindowManager.getInstance().init(windowStage, this.context);
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onForeground');
    // 回前台即时校准桌面卡片：重载课表数据并重建下一节课缓存（内部主动推送已添加的卡片），
    // 保证后台期间课程时间流逝后，用户切回应用时卡片立即显示正确内容
    CourseService.refreshCardCache(this.context);
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
