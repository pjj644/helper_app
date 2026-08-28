import { ConfigurationConstant, UIAbility, Configuration, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeManager } from '../common/utils/ThemeManager';
import { UISettings } from '../common/UISettings';
import { PreferencesUtil } from '../common/PreferencesUtil';
import { AuthService } from '../service/AuthService';
import { CourseService } from '../service/CourseService';
import { SyncService } from '../service/SyncService';
import { BackendNoticeService } from '../service/BackendNoticeService';
import { AppConfigRepository } from '../repository/AppConfigRepository';
import { CloudDbRepository } from '../repository/CloudDbRepository';
import { FloatingWindowManager } from '../common/agent/FloatingWindowManager';
import { AppConstants, RouterConstants } from '../common/constants/AppConstants';

const HILOG_DOMAIN = 0x0000;
const TAG = '[EntryAbility]';

export default class EntryAbility extends UIAbility {
  /** 桌面卡片点击带来的待消费路由目标（exam_page / bus_schedule 等，见 AppConstants.WIDGET_TARGET_*） */
  private pendingWidgetTarget: string = '';
  private mainWindowStage: window.WindowStage | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      PreferencesUtil.getInstance().init(this.context);
      UISettings.getInstance().initDarkMode(this.context);
      // 学期参数云端配置预热：异步拉取 app-config 并落 last-good 缓存（读取侧走同步通道，失败静默用内置兜底）
      AppConfigRepository.warmUp(this.context);

      // 冷启动时记录桌面卡片点击目标，待 onWindowStageCreate 加载主页后消费
      this.pendingWidgetTarget = EntryAbility.readWidgetTarget(want);

      // 合规要求：仅在用户已授权隐私政策后才初始化 AGC 等第三方/云端 SDK
      if (PreferencesUtil.getInstance().hasAgreedPrivacy()) {
        AuthService.initSDK(this.context);
        CloudDbRepository.initCloudDB().catch((err: Object) => {
          hilog.warn(HILOG_DOMAIN, TAG, 'CloudDbRepository.initCloudDB async failed: %{public}s', JSON.stringify(err));
        });
      } else {
        hilog.info(HILOG_DOMAIN, TAG, 'Privacy not agreed yet, delaying AGC SDK initialization.');
      }
    } catch (err) {
      hilog.error(HILOG_DOMAIN, TAG, 'Failed in onCreate. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 应用已在后台时再次被桌面卡片拉起：记录目标并立即路由
    const target = EntryAbility.readWidgetTarget(want);
    if (target) {
      this.pendingWidgetTarget = target;
      this.routePendingWidgetTarget();
    }
  }

  /** 从 want 中提取桌面卡片 postCardAction 传入的 targetPage 参数 */
  private static readWidgetTarget(want: Want): string {
    const params: Record<string, Object> | undefined = want?.parameters;
    if (!params) {
      return '';
    }
    const target = params['targetPage'];
    return typeof target === 'string' ? target : '';
  }

  /** 消费待处理的卡片路由目标；仅考试/班车卡片有专属落地页，其余维持主页面默认行为 */
  private routePendingWidgetTarget(): void {
    if (!this.pendingWidgetTarget || !this.mainWindowStage) {
      return;
    }
    let url: string = '';
    if (this.pendingWidgetTarget === AppConstants.WIDGET_TARGET_EXAM) {
      url = RouterConstants.PAGE_EXAM;
    } else if (this.pendingWidgetTarget === AppConstants.WIDGET_TARGET_BUS) {
      url = RouterConstants.PAGE_BUS_SCHEDULE;
    }
    this.pendingWidgetTarget = '';
    if (!url) {
      return;
    }
    try {
      const router = this.mainWindowStage.getMainWindowSync().getUIContext().getRouter();
      router.pushUrl({ url: url }).catch((error: Error) => {
        hilog.error(HILOG_DOMAIN, TAG, 'routePendingWidgetTarget pushUrl failed: %{public}s', JSON.stringify(error));
      });
    } catch (err) {
      hilog.error(HILOG_DOMAIN, TAG, 'routePendingWidgetTarget error: %{public}s', JSON.stringify(err));
    }
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
    hilog.info(HILOG_DOMAIN, TAG, 'Ability onWindowStageCreate');
    this.mainWindowStage = windowStage;

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(HILOG_DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(HILOG_DOMAIN, TAG, 'Succeeded in loading the content.');
      // 初始化全局悬浮窗管理器
      FloatingWindowManager.getInstance().init(windowStage, this.context);
      // 主页加载完成后消费桌面卡片点击目标（考试卡 → 考试页，班车卡 → 班车页）
      this.routePendingWidgetTarget();
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
    this.mainWindowStage = undefined;
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(HILOG_DOMAIN, TAG, 'Ability onForeground');
    // 回前台即时校准桌面卡片：重载课表数据并重建下一节课缓存（内部把课程/考试/班车
    // 全量数据主动推送已添加的卡片），保证后台期间时间流逝后，用户切回应用时卡片立即正确
    CourseService.refreshCardCache(this.context);
    // 云端自动同步补偿（P2-7a）：启动/回前台时若有待同步条目且已过退避窗口则补传一次
    SyncService.flushPendingAutoSync(this.context);
    // 「消息通知」开启时到点拉取后端发布的简单通知（内部有 1 小时节流与开关判断，失败静默）
    BackendNoticeService.pollIfDue(this.context);
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(HILOG_DOMAIN, TAG, 'Ability onBackground');
  }
}
