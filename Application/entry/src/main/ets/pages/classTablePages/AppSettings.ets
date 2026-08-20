import { router } from '@kit.ArkUI';
import { MaterialLevel } from '../../common/HdsCompat';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { UISettings } from '../../common/UISettings';
import { AnimationSettings, AnimationSpeed, AnimationCurveType } from '../../common/AnimationSettings';
import { MaterialEffects, BlurIntensity, MaterialStyle, BorderStyle } from '../../common/MaterialEffects';
import { FeatureDetector } from '../../common/FeatureDetector';
import { DarkModeType } from '../../common/DarkModeType';
import { ImmersiveLightWrapper } from '../../common/ImmersiveLightWrapper';
import { PreferencesUtil } from '../../common/PreferencesUtil';
import { AnimatedCard } from '../../components/AnimatedComponents';
import { DisplaySettings } from '../../model/classTableModel/CourseTableStorage';
import { CourseTableStorage } from '../../model/classTableModel/CourseTableStorage';
import { SyncService } from '../../service/SyncService';
import { AuthService } from '../../service/AuthService';
import { AppConstants, RouterConstants } from '../../common/constants/AppConstants';
import { ReminderService } from '../../service/ReminderService';
import { ScheduleService } from '../../service/ScheduleService';
import { LoadingOverlay } from '../../components/LoadingOverlay';
import { SettingsRepository } from '../../repository/SettingsRepository';
import { FloatingWindowManager } from '../../common/agent/FloatingWindowManager';

@Entry
@Component
struct AppSettings {
  @State settings: DisplaySettings = {
    showToday: true,
    showTomorrow: true,
    showExamCountdown: true,
    examRemindMinutes: 30,
    courseRemindMinutes: 30,
  };
  @State autoSyncSchedule: boolean = true;
  @State isLoggedIn: boolean = false;
  @State loginEmail: string = '';
  @State syncingToCloud: boolean = false;
  @State downloadingFromCloud: boolean = false;

  @State immersiveEnabled: boolean = true;
  @State darkModeType: DarkModeType = DarkModeType.FOLLOW_SYSTEM;
  @State materialLevelText: string = '自适应';
  @State isImmersiveSupported: boolean = true;
  @State deviceApiVersion: number = 22;
  @State customBackgroundImage: string = '';
  @State customBackgroundEnabled: boolean = false;

  @State animationSpeed: AnimationSpeed = AnimationSpeed.NORMAL;
  @State animationCurve: AnimationCurveType = AnimationCurveType.SMOOTH;
  @State cardEnterEnabled: boolean = true;
  @State animationIntensity: number = 1.0;

  @State advancedBlurEnabled: boolean = true;
  @State blurIntensity: BlurIntensity = BlurIntensity.REGULAR;
  @State materialStyle: MaterialStyle = MaterialStyle.STANDARD;
  @State materialBorderStyle: BorderStyle = BorderStyle.NONE;
  @State customBlurRadius: number = 20;
  @State saturation: number = 1.0;
  @State materialBrightness: number = 1.0;
  @State backgroundOpacity: number = 0.8;
  @State shadowIntensity: number = 10;

  @State notificationEnabled: boolean = true;
  @State autoUpdateEnabled: boolean = false;
  @State agentBackendUrl: string = '';
  @State showAgentToolCalls: boolean = false;
  @State floatingBallEnabled: boolean = true;

  private appSettings: UISettings = UISettings.getInstance();
  private featureDetector: FeatureDetector = FeatureDetector.getInstance();
  private animationSettings: AnimationSettings = AnimationSettings.getInstance();
  private materialEffects: MaterialEffects = MaterialEffects.getInstance();

  aboutToAppear(): void {
    this.loadSettings();
    this.checkLoginStatus();
    this.loadUISettings();
    this.loadAnimationSettings();
    this.loadMaterialSettings();
    this.loadOtherSettings();
    this.loadAgentBackendUrl();
    this.loadAgentDisplaySettings();
  }

  onPageShow(): void {
    this.checkLoginStatus();
  }

  private async loadSettings(): Promise<void> {
    try {
      const context = getContext(this);
      this.settings = await CourseTableStorage.loadSettings(context);
      this.autoSyncSchedule = await ReminderService.getAutoSyncScheduleEnabled(context);
    } catch (error) {
      console.error(`加载设置失败: ${JSON.stringify(error)}`);
    }
  }

  private async checkLoginStatus(): Promise<void> {
    try {
      const userId: string | undefined = await AuthService.getLoginUserId(getContext(this));
      this.isLoggedIn = !!userId;
      this.loginEmail = userId || '';
    } catch (error) {
      this.isLoggedIn = false;
      this.loginEmail = '';
    }
  }

  private loadUISettings(): void {
    this.immersiveEnabled = this.appSettings.immersiveEnabled;
    this.darkModeType = this.appSettings.darkModeType;
    this.isImmersiveSupported = this.appSettings.isImmersiveSupported;
    this.deviceApiVersion = this.featureDetector.getDeviceApiVersion();
    this.customBackgroundImage = this.appSettings.customBackgroundImage;
    this.customBackgroundEnabled = this.appSettings.customBackgroundEnabled;
    this.updateMaterialLevelText();
  }

  private loadAnimationSettings(): void {
    this.animationSpeed = this.animationSettings.speed;
    this.animationCurve = this.animationSettings.curve;
    this.cardEnterEnabled = this.animationSettings.cardEnterEnabled;
    this.animationIntensity = this.animationSettings.intensity;
  }

  private loadMaterialSettings(): void {
    this.advancedBlurEnabled = this.materialEffects.advancedBlurEnabled;
    this.blurIntensity = this.materialEffects.blurIntensity;
    this.materialStyle = this.materialEffects.materialStyle;
    this.materialBorderStyle = this.materialEffects.borderStyle;
    this.customBlurRadius = this.materialEffects.customBlurRadius;
    this.saturation = this.materialEffects.saturation;
    this.materialBrightness = this.materialEffects.brightness;
    this.backgroundOpacity = this.materialEffects.backgroundOpacity;
    this.shadowIntensity = this.materialEffects.shadowIntensity;
  }

  private loadOtherSettings(): void {
    this.notificationEnabled = PreferencesUtil.getInstance().getBoolean('notification_enabled', true);
    this.autoUpdateEnabled = PreferencesUtil.getInstance().getBoolean('auto_update_enabled', false);
  }

  private async loadAgentBackendUrl(): Promise<void> {
    try {
      this.agentBackendUrl = await SettingsRepository.getAgentBackendUrl(getContext(this));
    } catch (error) {
      this.agentBackendUrl = AppConstants.AI_AGENT_URL;
    }
  }

  private loadAgentDisplaySettings(): void {
    this.showAgentToolCalls = PreferencesUtil.getInstance().getBoolean(AppConstants.SETTING_AI_SHOW_TOOL_CALLS_KEY, false);
    this.floatingBallEnabled = FloatingWindowManager.getInstance().getIsEnabled();
  }

  private updateMaterialLevelText(): void {
    switch (this.appSettings.materialLevel) {
      case MaterialLevel.EXQUISITE:
        this.materialLevelText = '精致';
        break;
      case MaterialLevel.GENTLE:
        this.materialLevelText = '轻柔';
        break;
      case MaterialLevel.SMOOTH:
        this.materialLevelText = '流畅';
        break;
      case MaterialLevel.ADAPTIVE:
      default:
        this.materialLevelText = '自适应';
        break;
    }
  }

  private async saveSettings(): Promise<void> {
    try {
      const context = getContext(this);
      await CourseTableStorage.saveSettings(context, this.settings);
      await ReminderService.saveAutoSyncScheduleEnabled(context, this.autoSyncSchedule);

      if (this.autoSyncSchedule) {
        await ScheduleService.syncCoursesToSchedule(context);
        await ScheduleService.syncExamsToSchedule(context);
      }

      this.getUIContext().getPromptAction().showToast({ message: '设置已保存' });
      router.back();
    } catch (error) {
      console.error(`保存设置失败: ${JSON.stringify(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败' });
    }
  }

  private login(): void {
    router.pushUrl({ url: RouterConstants.PAGE_LOGIN })
      .catch((error: Error) => console.error('跳转登录页面失败:', error));
  }

  private accountManage(): void {
    router.pushUrl({ url: RouterConstants.PAGE_ACCOUNT_MANAGE })
      .catch((error: Error) => console.error('跳转账号管理失败:', error));
  }

  private async syncLocalDataToCloud(): Promise<void> {
    if (this.syncingToCloud) { return; }
    this.syncingToCloud = true;
    try {
      const userId: string | undefined = await AuthService.getLoginUserId(getContext(this));
      if (!userId) {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录后再同步' });
        return;
      }
      const result = await SyncService.syncAllToCloud(getContext(this), userId);
      if (result.courses.success && result.exams.success) {
        const courseCount: number = result.courses.courseCount || 0;
        const examCount: number = result.exams.examCount || 0;
        this.getUIContext().getPromptAction().showToast({
          message: `云端同步完成：课表${courseCount}条，考试${examCount}条`
        });
        ReminderService.refreshAllReminders(getContext(this));
      } else {
        const errorMsg: string = result.courses.error || result.exams.error || '未知错误';
        this.getUIContext().getPromptAction().showToast({ message: `云端同步失败: ${errorMsg}` });
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `云端同步失败: ${String(error)}` });
    } finally {
      this.syncingToCloud = false;
    }
  }

  private async downloadFromCloud(): Promise<void> {
    if (this.downloadingFromCloud) { return; }
    this.downloadingFromCloud = true;
    try {
      const userId: string | undefined = await AuthService.getLoginUserId(getContext(this));
      if (!userId) {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录后再下载' });
        return;
      }
      const result = await SyncService.downloadAllFromCloud(getContext(this), userId);
      if (result.courses.success && result.exams.success) {
        const courseCount: number = result.courses.courseCount || 0;
        const examCount: number = result.exams.examCount || 0;
        this.getUIContext().getPromptAction().showToast({
          message: `云端下载完成：课表${courseCount}条，考试${examCount}条`
        });
        ReminderService.refreshAllReminders(getContext(this));
      } else {
        const errorMsg: string = result.courses.error || result.exams.error || '未知错误';
        this.getUIContext().getPromptAction().showToast({ message: `云端下载失败: ${errorMsg}` });
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `云端下载失败: ${String(error)}` });
    } finally {
      this.downloadingFromCloud = false;
    }
  }

  private async selectBackgroundImage(): Promise<void> {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const photoSelectResult = await photoPicker.select(photoSelectOptions);

      if (photoSelectResult.photoUris && photoSelectResult.photoUris.length > 0) {
        const imageUri = photoSelectResult.photoUris[0];
        this.customBackgroundImage = imageUri;
        this.appSettings.customBackgroundImage = imageUri;
      }
    } catch (error) {
      console.error(`选择图片失败: ${JSON.stringify(error)}`);
    }
  }

  private clearBackgroundImage(): void {
    this.customBackgroundImage = '';
    this.appSettings.clearCustomBackground();
  }

  build() {
    Stack() {
      Column() {
        this.TopBar()

        Scroll() {
          Column({ space: 16 }) {
            AnimatedCard({ delay: 0 }) {
              ImmersiveLightWrapper({ radius: 16, lightIntensity: 2.5 }) {
                this.AccountCard()
              }
            }

            AnimatedCard({ delay: 80 }) {
              ImmersiveLightWrapper({ radius: 16, lightIntensity: 2.5 }) {
                this.SyncCard()
              }
            }

            AnimatedCard({ delay: 120 }) {
              ImmersiveLightWrapper({ radius: 16, lightIntensity: 2.5 }) {
                this.AgentBackendCard()
              }
            }

            AnimatedCard({ delay: 160 }) {
              ImmersiveLightWrapper({ radius: 16, lightIntensity: 2.5 }) {
                this.ImmersiveSettingsCard()
              }
            }

            AnimatedCard({ delay: 240 }) {
              ImmersiveLightWrapper({ radius: 16, lightIntensity: 2.5 }) {
                this.AnimationSettingsCard()
              }
            }

            AnimatedCard({ delay: 320 }) {
              ImmersiveLightWrapper({ radius: 16, lightIntensity: 2.5 }) {
                this.BackgroundImageCard()
              }
            }

            AnimatedCard({ delay: 400 }) {
              ImmersiveLightWrapper({ radius: 16, lightIntensity: 2.5 }) {
                this.DisplaySettingsCard()
              }
            }

            AnimatedCard({ delay: 480 }) {
              ImmersiveLightWrapper({ radius: 16, lightIntensity: 2.5 }) {
                this.OtherSettingsCard()
              }
            }

            Button('保存设置')
              .width('92%')
              .height(48)
              .fontSize(16)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.primary_color'))
              .borderRadius(12)
              .margin({ top: 8, bottom: 24 })
              .onClick(() => this.saveSettings());
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 30 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      LoadingOverlay({
        isVisible: this.syncingToCloud || this.downloadingFromCloud,
        message: this.syncingToCloud ? '正在上传到云端...' : '正在从云端下载...'
      });
    }
    .width('100%')
    .height('100%')
  }

  @Builder TopBar() {
    Row({ space: 12 }) {
      Image($r('app.media.back'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.text_primary'))
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })

      Text('应用设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .flexGrow(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16, top: 16 })
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder AccountCard() {
    Column({ space: 0 }) {
      Row() {
        Text('账号管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ bottom: 16 })

      if (this.isLoggedIn) {
        Row() {
          Column({ space: 4 }) {
            Text(this.loginEmail)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('已登录')
              .fontSize(12)
              .fontColor($r('app.color.success_color'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('账号管理')
            .height(32)
            .fontSize(13)
            .fontColor($r('app.color.primary_color'))
            .backgroundColor($r('app.color.primary_light_color'))
            .borderRadius(16)
            .onClick(() => this.accountManage());
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor($r('app.color.button_background'))
      } else {
        Row() {
          Text('未登录，部分功能不可用')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)

          Button('登录')
            .height(32)
            .fontSize(13)
            .fontColor($r('app.color.primary_color'))
            .backgroundColor($r('app.color.primary_light_color'))
            .borderRadius(16)
            .onClick(() => this.login());
        }
        .width('100%')
        .padding(12)
        .borderRadius(10)
        .backgroundColor($r('app.color.button_background'))
      }
    }
    .width('100%')
    .padding(16)
  }

  @Builder SyncCard() {
    Column({ space: 0 }) {
      Row() {
        Text('数据同步')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ bottom: 16 })

      Row({ space: 12 }) {
        Button() {
          Text(this.syncingToCloud ? '上传中...' : '上传到云端')
            .fontSize(14)
            .fontColor('#FFFFFF')
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor(this.syncingToCloud ? $r('app.color.text_tertiary') : $r('app.color.primary_color'))
        .borderRadius(12)
        .enabled(!this.syncingToCloud && !this.downloadingFromCloud)
        .onClick(() => this.syncLocalDataToCloud())

        Button() {
          Text(this.downloadingFromCloud ? '下载中...' : '从云端下载')
            .fontSize(14)
            .fontColor('#FFFFFF')
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor(this.downloadingFromCloud ? $r('app.color.text_tertiary') : $r('app.color.success_color'))
        .borderRadius(12)
        .enabled(!this.syncingToCloud && !this.downloadingFromCloud)
        .onClick(() => this.downloadFromCloud())
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }

  @Builder AgentBackendCard() {
    Column({ space: 0 }) {
      Row() {
        Text('助手后端')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ bottom: 16 })

      Column({ space: 4 }) {
        Text('后端地址')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Text('本地 LangGraph 后端的局域网地址（电脑 IP:端口）。AI 助手依赖此地址，需与电脑在同一 WiFi。')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 8 })

      TextInput({ text: this.agentBackendUrl, placeholder: 'http://192.168.1.100:3000' })
        .width('100%')
        .height(48)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.button_background'))
        .borderRadius(10)
        .onChange((value: string) => {
          this.agentBackendUrl = value;
          SettingsRepository.saveAgentBackendUrl(getContext(this), value);
        })

      Divider().color($r('app.color.divider_color'))

      Row() {
        Column({ space: 4 }) {
          Text('显示AI工具调用')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('开启后，AI助手回复中展示所用工具的过程信息（默认关闭）')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.showAgentToolCalls })
          .selectedColor($r('app.color.primary_color'))
          .onChange((isOn: boolean) => {
            this.showAgentToolCalls = isOn;
            PreferencesUtil.getInstance().putBoolean(AppConstants.SETTING_AI_SHOW_TOOL_CALLS_KEY, isOn);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color($r('app.color.divider_color'))

      Row() {
        Column({ space: 4 }) {
          Text('开启全局 AI 悬浮球')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('在非 AI 助手页面显示可拖拽悬浮球，支持展开 Mini 助手与当前页面感知')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.floatingBallEnabled })
          .selectedColor($r('app.color.primary_color'))
          .onChange((isOn: boolean) => {
            this.floatingBallEnabled = isOn;
            FloatingWindowManager.getInstance().setEnabled(isOn);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
    }
    .width('100%')
    .padding(16)
  }

  @Builder ImmersiveSettingsCard() {
    Column({ space: 0 }) {
      Row() {
        Text('沉浸光感效果')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ bottom: 16 })

      Row() {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text('设备API版本:')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(`${this.deviceApiVersion}`)
              .fontSize(13)
              .fontColor($r('app.color.primary_color'))
              .fontWeight(FontWeight.Medium)
          }
          Row({ space: 8 }) {
            Text('沉浸光感支持:')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(this.isImmersiveSupported ? '✓ 支持' : '✗ 不支持')
              .fontSize(13)
              .fontColor(this.isImmersiveSupported ? $r('app.color.success_color') : $r('app.color.danger_color'))
              .fontWeight(FontWeight.Medium)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ bottom: 12 })

      Divider().color($r('app.color.divider_color'))

      Row() {
        Column({ space: 4 }) {
          Text('启用沉浸光感')
            .fontSize(15)
            .fontColor(this.isImmersiveSupported ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
          Text(this.isImmersiveSupported ? '为卡片和导航栏添加沉浸光感材质效果' : '当前设备不支持沉浸光感功能')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .flexGrow(1)

        Toggle({ type: ToggleType.Switch, isOn: this.immersiveEnabled })
          .selectedColor($r('app.color.primary_color'))
          .enabled(this.isImmersiveSupported)
          .onChange((isOn: boolean) => {
            this.immersiveEnabled = isOn;
            this.appSettings.immersiveEnabled = isOn;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color($r('app.color.divider_color'))

      Row() {
        Text('当前材质级别')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .flexGrow(1)

        Text(this.materialLevelText)
          .fontSize(14)
          .fontColor($r('app.color.primary_color'))
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color($r('app.color.divider_color'))

      Row() {
        Column({ space: 4 }) {
          Text('高级模糊效果')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('为卡片背景添加高斯模糊材质效果')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .flexGrow(1)

        Toggle({ type: ToggleType.Switch, isOn: this.advancedBlurEnabled })
          .selectedColor($r('app.color.primary_color'))
          .onChange((isOn: boolean) => {
            this.advancedBlurEnabled = isOn;
            this.materialEffects.advancedBlurEnabled = isOn;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      if (this.advancedBlurEnabled) {
        Divider().color($r('app.color.divider_color'))

        Column({ space: 12 }) {
          Row() {
            Text('模糊强度')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')

          Row({ space: 6 }) {
            Button('自定义')
              .fontSize(12)
              .fontColor(this.blurIntensity === BlurIntensity.CUSTOM ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.blurIntensity === BlurIntensity.CUSTOM ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.blurIntensity = BlurIntensity.CUSTOM;
                this.materialEffects.blurIntensity = BlurIntensity.CUSTOM;
              })

            Button('轻薄')
              .fontSize(12)
              .fontColor(this.blurIntensity === BlurIntensity.THIN ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.blurIntensity === BlurIntensity.THIN ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.blurIntensity = BlurIntensity.THIN;
                this.materialEffects.blurIntensity = BlurIntensity.THIN;
              })

            Button('普通')
              .fontSize(12)
              .fontColor(this.blurIntensity === BlurIntensity.REGULAR ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.blurIntensity === BlurIntensity.REGULAR ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.blurIntensity = BlurIntensity.REGULAR;
                this.materialEffects.blurIntensity = BlurIntensity.REGULAR;
              })

            Button('厚重')
              .fontSize(12)
              .fontColor(this.blurIntensity === BlurIntensity.THICK ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.blurIntensity === BlurIntensity.THICK ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.blurIntensity = BlurIntensity.THICK;
                this.materialEffects.blurIntensity = BlurIntensity.THICK;
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })

        if (this.blurIntensity === BlurIntensity.CUSTOM) {
          Divider().color($r('app.color.divider_color'))

          Column({ space: 8 }) {
            Row() {
              Text('模糊半径')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text(`${Math.round(this.customBlurRadius)}px`)
                .fontSize(14)
                .fontColor($r('app.color.primary_color'))
                .fontWeight(FontWeight.Medium)
                .margin({ left: 8 })
            }
            .width('100%')

            Slider({
              value: this.customBlurRadius,
              min: 5,
              max: 80,
              step: 1
            })
              .blockColor($r('app.color.primary_color'))
              .trackColor($r('app.color.divider_color'))
              .selectedColor($r('app.color.primary_color'))
              .width('100%')
              .onChange((value: number) => {
                this.customBlurRadius = value;
                this.materialEffects.customBlurRadius = value;
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
        }

        Divider().color($r('app.color.divider_color'))

        Column({ space: 12 }) {
          Row() {
            Text('材质样式')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')

          Row({ space: 6 }) {
            Button('标准')
              .fontSize(12)
              .fontColor(this.materialStyle === MaterialStyle.STANDARD ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialStyle === MaterialStyle.STANDARD ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialStyle = MaterialStyle.STANDARD;
                this.materialEffects.materialStyle = MaterialStyle.STANDARD;
              })

            Button('毛玻璃')
              .fontSize(12)
              .fontColor(this.materialStyle === MaterialStyle.FROSTED_GLASS ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialStyle === MaterialStyle.FROSTED_GLASS ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialStyle = MaterialStyle.FROSTED_GLASS;
                this.materialEffects.materialStyle = MaterialStyle.FROSTED_GLASS;
              })

            Button('磨砂')
              .fontSize(12)
              .fontColor(this.materialStyle === MaterialStyle.MATTE ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialStyle === MaterialStyle.MATTE ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialStyle = MaterialStyle.MATTE;
                this.materialEffects.materialStyle = MaterialStyle.MATTE;
              })
          }
          .width('100%')

          Row({ space: 6 }) {
            Button('晶莹')
              .fontSize(12)
              .fontColor(this.materialStyle === MaterialStyle.CRYSTAL ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialStyle === MaterialStyle.CRYSTAL ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialStyle = MaterialStyle.CRYSTAL;
                this.materialEffects.materialStyle = MaterialStyle.CRYSTAL;
              })

            Button('雾化')
              .fontSize(12)
              .fontColor(this.materialStyle === MaterialStyle.MIST ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialStyle === MaterialStyle.MIST ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialStyle = MaterialStyle.MIST;
                this.materialEffects.materialStyle = MaterialStyle.MIST;
              })

            Blank().layoutWeight(1)
            Blank().layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })

        Divider().color($r('app.color.divider_color'))

        Column({ space: 12 }) {
          Row() {
            Text('边框样式')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')

          Row({ space: 6 }) {
            Button('无边框')
              .fontSize(12)
              .fontColor(this.materialBorderStyle === BorderStyle.NONE ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialBorderStyle === BorderStyle.NONE ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialBorderStyle = BorderStyle.NONE;
                this.materialEffects.borderStyle = BorderStyle.NONE;
              })

            Button('细线')
              .fontSize(12)
              .fontColor(this.materialBorderStyle === BorderStyle.THIN ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialBorderStyle === BorderStyle.THIN ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialBorderStyle = BorderStyle.THIN;
                this.materialEffects.borderStyle = BorderStyle.THIN;
              })

            Button('标准')
              .fontSize(12)
              .fontColor(this.materialBorderStyle === BorderStyle.STANDARD ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialBorderStyle === BorderStyle.STANDARD ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialBorderStyle = BorderStyle.STANDARD;
                this.materialEffects.borderStyle = BorderStyle.STANDARD;
              })

            Button('发光')
              .fontSize(12)
              .fontColor(this.materialBorderStyle === BorderStyle.GLOW ?
                $r('app.color.primary_color') :
                $r('app.color.text_primary'))
              .backgroundColor(this.materialBorderStyle === BorderStyle.GLOW ?
                $r('app.color.primary_light_color') :
                $r('app.color.button_background'))
              .borderRadius(8)
              .height(32)
              .layoutWeight(1)
              .onClick(() => {
                this.materialBorderStyle = BorderStyle.GLOW;
                this.materialEffects.borderStyle = BorderStyle.GLOW;
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })

        Divider().color($r('app.color.divider_color'))

        Column({ space: 8 }) {
          Row() {
            Text('饱和度')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text(`${this.saturation.toFixed(1)}`)
              .fontSize(14)
              .fontColor($r('app.color.primary_color'))
              .fontWeight(FontWeight.Medium)
              .margin({ left: 8 })
          }
          .width('100%')

          Slider({
            value: this.saturation * 100,
            min: 0,
            max: 200,
            step: 5
          })
            .blockColor($r('app.color.primary_color'))
            .trackColor($r('app.color.divider_color'))
            .selectedColor($r('app.color.primary_color'))
            .width('100%')
            .onChange((value: number) => {
              this.saturation = value / 100;
              this.materialEffects.saturation = value / 100;
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })

        Divider().color($r('app.color.divider_color'))

        Column({ space: 8 }) {
          Row() {
            Text('亮度')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text(`${this.materialBrightness.toFixed(1)}`)
              .fontSize(14)
              .fontColor($r('app.color.primary_color'))
              .fontWeight(FontWeight.Medium)
              .margin({ left: 8 })
          }
          .width('100%')

          Slider({
            value: this.materialBrightness * 100,
            min: 50,
            max: 150,
            step: 5
          })
            .blockColor($r('app.color.primary_color'))
            .trackColor($r('app.color.divider_color'))
            .selectedColor($r('app.color.primary_color'))
            .width('100%')
            .onChange((value: number) => {
              this.materialBrightness = value / 100;
              this.materialEffects.brightness = value / 100;
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })

        Divider().color($r('app.color.divider_color'))

        Column({ space: 8 }) {
          Row() {
            Text('背景透明度')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text(`${Math.round(this.backgroundOpacity * 100)}%`)
              .fontSize(14)
              .fontColor($r('app.color.primary_color'))
              .fontWeight(FontWeight.Medium)
              .margin({ left: 8 })
          }
          .width('100%')

          Slider({
            value: this.backgroundOpacity * 100,
            min: 20,
            max: 100,
            step: 5
          })
            .blockColor($r('app.color.primary_color'))
            .trackColor($r('app.color.divider_color'))
            .selectedColor($r('app.color.primary_color'))
            .width('100%')
            .onChange((value: number) => {
              this.backgroundOpacity = value / 100;
              this.materialEffects.backgroundOpacity = value / 100;
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })

        Divider().color($r('app.color.divider_color'))

        Column({ space: 8 }) {
          Row() {
            Text('阴影强度')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text(`${Math.round(this.shadowIntensity)}`)
              .fontSize(14)
              .fontColor($r('app.color.primary_color'))
              .fontWeight(FontWeight.Medium)
              .margin({ left: 8 })
          }
          .width('100%')

          Slider({
            value: this.shadowIntensity,
            min: 0,
            max: 30,
            step: 1
          })
            .blockColor($r('app.color.primary_color'))
            .trackColor($r('app.color.divider_color'))
            .selectedColor($r('app.color.primary_color'))
            .width('100%')
            .onChange((value: number) => {
              this.shadowIntensity = value;
              this.materialEffects.shadowIntensity = value;
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })
      }
    }
    .width('100%')
    .padding(16)
  }

  @Builder AnimationSettingsCard() {
    Column({ space: 0 }) {
      Row() {
        Text('动画效果')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ bottom: 16 })

      Row() {
        Column({ space: 4 }) {
          Text('启用入场动画')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('卡片和页面元素以Q弹动画效果出现')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .flexGrow(1)

        Toggle({ type: ToggleType.Switch, isOn: this.cardEnterEnabled })
          .selectedColor($r('app.color.primary_color'))
          .onChange((isOn: boolean) => {
            this.cardEnterEnabled = isOn;
            this.animationSettings.cardEnterEnabled = isOn;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color($r('app.color.divider_color'))

      Column({ space: 12 }) {
        Row() {
          Text('动画速度')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')

        Row({ space: 8 }) {
          Button('快速')
            .fontSize(14)
            .fontColor(this.animationSpeed === AnimationSpeed.FAST ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.animationSpeed === AnimationSpeed.FAST ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.animationSpeed = AnimationSpeed.FAST;
              this.animationSettings.speed = AnimationSpeed.FAST;
            })

          Button('标准')
            .fontSize(14)
            .fontColor(this.animationSpeed === AnimationSpeed.NORMAL ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.animationSpeed === AnimationSpeed.NORMAL ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.animationSpeed = AnimationSpeed.NORMAL;
              this.animationSettings.speed = AnimationSpeed.NORMAL;
            })

          Button('慢速')
            .fontSize(14)
            .fontColor(this.animationSpeed === AnimationSpeed.SLOW ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.animationSpeed === AnimationSpeed.SLOW ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.animationSpeed = AnimationSpeed.SLOW;
              this.animationSettings.speed = AnimationSpeed.SLOW;
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .alignItems(HorizontalAlign.Start)

      Divider().color($r('app.color.divider_color'))

      Column({ space: 12 }) {
        Row() {
          Text('动画曲线')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')

        Row({ space: 8 }) {
          Button('线性')
            .fontSize(13)
            .fontColor(this.animationCurve === AnimationCurveType.LINEAR ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.animationCurve === AnimationCurveType.LINEAR ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.animationCurve = AnimationCurveType.LINEAR;
              this.animationSettings.curve = AnimationCurveType.LINEAR;
            })

          Button('平滑')
            .fontSize(13)
            .fontColor(this.animationCurve === AnimationCurveType.SMOOTH ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.animationCurve === AnimationCurveType.SMOOTH ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.animationCurve = AnimationCurveType.SMOOTH;
              this.animationSettings.curve = AnimationCurveType.SMOOTH;
            })

          Button('弹性')
            .fontSize(13)
            .fontColor(this.animationCurve === AnimationCurveType.BOUNCY ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.animationCurve === AnimationCurveType.BOUNCY ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.animationCurve = AnimationCurveType.BOUNCY;
              this.animationSettings.curve = AnimationCurveType.BOUNCY;
            })

          Button('Q弹')
            .fontSize(13)
            .fontColor(this.animationCurve === AnimationCurveType.SPRING ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.animationCurve === AnimationCurveType.SPRING ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.animationCurve = AnimationCurveType.SPRING;
              this.animationSettings.curve = AnimationCurveType.SPRING;
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .alignItems(HorizontalAlign.Start)

      Divider().color($r('app.color.divider_color'))

      Column({ space: 8 }) {
        Row() {
          Text('动画强度')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.animationIntensity.toFixed(1))
            .fontSize(14)
            .fontColor($r('app.color.primary_color'))
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')

        Slider({
          value: this.animationIntensity,
          min: 0.5,
          max: 1.5,
          step: 0.1
        })
          .blockColor($r('app.color.primary_color'))
          .trackColor($r('app.color.divider_color'))
          .selectedColor($r('app.color.primary_color'))
          .width('100%')
          .onChange((value: number) => {
            this.animationIntensity = value;
            this.animationSettings.intensity = value;
          })

        Row() {
          Text('轻柔')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
          Blank()
          Text('强烈')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
    }
    .width('100%')
    .padding(16)
  }

  @Builder BackgroundImageCard() {
    Column({ space: 0 }) {
      Row() {
        Text('背景图片')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ bottom: 16 })

      Row() {
        Column({ space: 4 }) {
          Text('自定义背景')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('使用自定义图片作为页面背景')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .flexGrow(1)

        Toggle({ type: ToggleType.Switch, isOn: this.customBackgroundEnabled })
          .selectedColor($r('app.color.primary_color'))
          .onChange((isOn: boolean) => {
            this.customBackgroundEnabled = isOn;
            this.appSettings.customBackgroundEnabled = isOn;
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      if (this.customBackgroundEnabled) {
        Divider().color($r('app.color.divider_color'))

        Column({ space: 12 }) {
          Row() {
            Text('背景预览')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .padding({ top: 12 })

          if (this.customBackgroundImage) {
            Stack() {
              Image(this.customBackgroundImage)
                .width('100%')
                .height(150)
                .objectFit(ImageFit.Cover)
                .borderRadius(12)

              Button() {
                Text('×')
                  .fontSize(20)
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Bold)
              }
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor('#80000000')
              .position({ x: '100%', y: 0 })
              .translate({ x: -18, y: 18 })
              .onClick(() => {
                this.clearBackgroundImage();
              })
            }
            .width('100%')
            .height(150)
          } else {
            Column() {
              Image($r('app.media.startIcon'))
                .width(48)
                .height(48)
                .fillColor($r('app.color.text_tertiary'))

              Text('未设置背景图片')
                .fontSize(14)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 8 })
            }
            .width('100%')
            .height(150)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.page_background'))
            .borderRadius(12)
          }

          Button('选择图片')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.primary_color'))
            .borderRadius(12)
            .onClick(() => {
              this.selectBackgroundImage();
            })
        }
        .width('100%')
        .padding({ bottom: 12 })
      }
    }
    .width('100%')
    .padding(16)
  }

  @Builder DisplaySettingsCard() {
    Column({ space: 0 }) {
      Row() {
        Text('显示设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ bottom: 16 })

      Row() {
        Text('首页显示今日课程')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.showToday })
          .selectedColor($r('app.color.primary_color'))
          .onChange((value: boolean) => this.settings.showToday = value)
      }
      .width('100%')
      .padding(12)
      .borderRadius(10)
      .backgroundColor($r('app.color.button_background'))

      Row() {
        Text('首页显示明日课程')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.showTomorrow })
          .selectedColor($r('app.color.primary_color'))
          .onChange((value: boolean) => this.settings.showTomorrow = value)
      }
      .width('100%')
      .padding(12)
      .borderRadius(10)
      .backgroundColor($r('app.color.button_background'))
      .margin({ top: 8 })

      Row() {
        Text('首页显示考试倒计时')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.showExamCountdown })
          .selectedColor($r('app.color.primary_color'))
          .onChange((value: boolean) => this.settings.showExamCountdown = value)
      }
      .width('100%')
      .padding(12)
      .borderRadius(10)
      .backgroundColor($r('app.color.button_background'))
      .margin({ top: 8 })

      Row() {
        Text('自动创建相关日程')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.autoSyncSchedule })
          .selectedColor($r('app.color.primary_color'))
          .onChange((value: boolean) => {
            this.autoSyncSchedule = value;
            ReminderService.saveAutoSyncScheduleEnabled(getContext(this), value);
            if (value) {
              ScheduleService.syncCoursesToSchedule(getContext(this));
              ScheduleService.syncExamsToSchedule(getContext(this));
            } else {
              ScheduleService.clearAutoGeneratedSchedules(getContext(this));
            }
          })
      }
      .width('100%')
      .padding(12)
      .borderRadius(10)
      .backgroundColor($r('app.color.button_background'))
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
  }

  @Builder OtherSettingsCard() {
    Column({ space: 0 }) {
      Row() {
        Text('其他设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ bottom: 16 })

      Row() {
        Text('消息通知')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .flexGrow(1)
        Toggle({ type: ToggleType.Switch, isOn: this.notificationEnabled })
          .selectedColor($r('app.color.primary_color'))
          .onChange((isOn: boolean) => {
            this.notificationEnabled = isOn;
            PreferencesUtil.getInstance().putBoolean('notification_enabled', isOn);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color($r('app.color.divider_color'))

      Row() {
        Text('自动更新')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .flexGrow(1)
        Toggle({ type: ToggleType.Switch, isOn: this.autoUpdateEnabled })
          .selectedColor($r('app.color.primary_color'))
          .onChange((isOn: boolean) => {
            this.autoUpdateEnabled = isOn;
            PreferencesUtil.getInstance().putBoolean('auto_update_enabled', isOn);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider().color($r('app.color.divider_color'))

      Column({ space: 12 }) {
        Row() {
          Text('深色模式')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')

        Row({ space: 8 }) {
          Button('浅色')
            .fontSize(14)
            .fontColor(this.darkModeType === DarkModeType.LIGHT ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.darkModeType === DarkModeType.LIGHT ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.darkModeType = DarkModeType.LIGHT;
              this.appSettings.darkModeType = DarkModeType.LIGHT;
            })

          Button('深色')
            .fontSize(14)
            .fontColor(this.darkModeType === DarkModeType.DARK ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.darkModeType === DarkModeType.DARK ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.darkModeType = DarkModeType.DARK;
              this.appSettings.darkModeType = DarkModeType.DARK;
            })

          Button('跟随系统')
            .fontSize(14)
            .fontColor(this.darkModeType === DarkModeType.FOLLOW_SYSTEM ?
              $r('app.color.primary_color') :
              $r('app.color.text_primary'))
            .backgroundColor(this.darkModeType === DarkModeType.FOLLOW_SYSTEM ?
              $r('app.color.primary_light_color') :
              $r('app.color.button_background'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.darkModeType = DarkModeType.FOLLOW_SYSTEM;
              this.appSettings.darkModeType = DarkModeType.FOLLOW_SYSTEM;
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
  }
}
