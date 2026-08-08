import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_TAG = 'FeatureDetector';

export class FeatureDetector {
  private static instance: FeatureDetector;

  private static readonly IMMERSIVE_MATERIAL_MIN_API = 23;

  private constructor() {}

  public static getInstance(): FeatureDetector {
    if (!FeatureDetector.instance) {
      FeatureDetector.instance = new FeatureDetector();
    }
    return FeatureDetector.instance;
  }

  public getDeviceApiVersion(): number {
    try {
      if (deviceInfo.sdkApiVersion !== undefined && deviceInfo.sdkApiVersion !== null) {
        hilog.info(0x0001, LOG_TAG, `获取SDK API版本成功: ${deviceInfo.sdkApiVersion}`);
        return deviceInfo.sdkApiVersion;
      }

      if (deviceInfo.distributionOSApiVersion !== undefined && deviceInfo.distributionOSApiVersion !== null) {
        const version = Math.floor(deviceInfo.distributionOSApiVersion / 10000);
        hilog.info(0x0001, LOG_TAG, `通过distributionOSApiVersion获取API版本: ${version}`);
        return version;
      }

      if (deviceInfo.osFullName) {
        const version = parseInt(deviceInfo.osFullName.split('.')[0]);
        if (!isNaN(version)) {
          hilog.info(0x0001, LOG_TAG, `通过osFullName解析API版本: ${version}`);
          return version;
        }
      }

      hilog.warn(0x0001, LOG_TAG, '无法获取设备API版本，使用默认值22');
      return 22;

    } catch (error) {
      hilog.error(0x0001, LOG_TAG, `获取设备API版本失败: ${JSON.stringify(error)}`);
      return 22;
    }
  }

  public isImmersiveMaterialSupported(): boolean {
    try {
      const apiVersion = this.getDeviceApiVersion();
      const supported = apiVersion >= FeatureDetector.IMMERSIVE_MATERIAL_MIN_API;
      hilog.info(0x0001, LOG_TAG,
        `沉浸光感支持检测: API版本=${apiVersion}, 最低要求=${FeatureDetector.IMMERSIVE_MATERIAL_MIN_API}, 支持=${supported}`);
      return supported;
    } catch (error) {
      hilog.error(0x0001, LOG_TAG, `检测沉浸光感支持失败: ${JSON.stringify(error)}`);
      return false;
    }
  }

  public getFeatureSupportInfo(): string {
    try {
      const apiVersion = this.getDeviceApiVersion();
      const immersiveSupported = this.isImmersiveMaterialSupported();

      const deviceInfoStr = `
        设备类型: ${deviceInfo.deviceType || '未知'},
        品牌: ${deviceInfo.brand || '未知'},
        型号: ${deviceInfo.productModel || '未知'},
        系统版本: ${deviceInfo.osFullName || '未知'},
        SDK API版本: ${deviceInfo.sdkApiVersion || '未知'},
        发行版API版本: ${deviceInfo.distributionOSApiVersion || '未知'}
      `;

      hilog.info(0x0001, LOG_TAG, `设备详细信息: ${deviceInfoStr}`);

      return `API版本: ${apiVersion}, 沉浸光感: ${immersiveSupported ? '支持' : '不支持'}`;
    } catch (error) {
      hilog.error(0x0001, LOG_TAG, `获取功能支持信息失败: ${JSON.stringify(error)}`);
      return '获取设备信息失败';
    }
  }

  public getDeviceInfo(): string {
    try {
      return JSON.stringify({
        deviceType: deviceInfo.deviceType,
        brand: deviceInfo.brand,
        productModel: deviceInfo.productModel,
        osFullName: deviceInfo.osFullName,
        sdkApiVersion: deviceInfo.sdkApiVersion,
        distributionOSApiVersion: deviceInfo.distributionOSApiVersion,
        firstApiVersion: deviceInfo.firstApiVersion
      });
    } catch (error) {
      return `获取设备信息失败: ${JSON.stringify(error)}`;
    }
  }
}
