import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

export class PermissionHelper {
  /**
   * 检查是否已具有指定权限
   */
  static async checkPermission(context: Context, permission: Permissions): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const grantStatus = await atManager.checkAccessToken(context.applicationInfo.accessTokenId, permission);
      return grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (e) {
      console.error('[PermissionHelper] checkPermission error:', JSON.stringify(e));
      return false;
    }
  }

  /**
   * 动态按需请求权限，并在被拒绝时提供友好提示
   */
  static async requestPermissions(
    context: common.UIAbilityContext,
    permissions: Permissions[],
    rationaleTitle: string = '权限申请'
  ): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, permissions);
      let allGranted = true;
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) {
          allGranted = false;
          break;
        }
      }

      if (!allGranted) {
        promptAction.showToast({
          message: `${rationaleTitle}未授予，相关功能可能受限。如需使用请在系统「设置」中开启对应权限。`,
          duration: 3000
        });
      }

      return allGranted;
    } catch (error) {
      console.error('[PermissionHelper] requestPermissions error:', JSON.stringify(error));
      return false;
    }
  }
}
