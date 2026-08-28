import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Context } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { AppConstants } from '../common/constants/AppConstants';
import { WidgetDataModel } from '../model/widget/WidgetDataModel';

// formProvider.updateForm 错误码：目标卡片 ID 不存在（卡片已被用户移除）
const FORM_ID_NOT_EXIST_CODE: number = 16501001;

/**
 * 桌面卡片统一推送服务。
 *
 * 课程 / 考试 / 班车三张卡片共用一份 formData（由 WidgetDataModel 基于偏好文件
 * 中的原始数据构建），任何一类数据变化都从这里把全量数据推送给所有卡片实例，
 * 保证不同卡片间不会因部分更新而丢失彼此的字段。
 *
 * 卡片实例 ID 由 EntryFormAbility 在 onAddForm/onRemoveForm 时维护于偏好文件，
 * 此处仅读取；推送返回「ID 不存在」时将该 ID 从列表中剔除。
 */
export class WidgetUpdateService {
  /** 事件驱动的统一刷新入口：从偏好文件重建全量卡片数据并推送（供各 Service 在数据变更后调用） */
  static async pushAllFromCaches(context: Object): Promise<void> {
    try {
      const pref = await dataPreferences.getPreferences(context as Context, AppConstants.PREF_COURSE_DB_NAME);
      const formData = WidgetUpdateService.buildFormData(pref);

      const idsStr = pref.getSync(AppConstants.WIDGET_FORM_IDS_KEY, '[]') as string;
      const formIds: string[] = JSON.parse(idsStr) as string[];
      if (!formIds || formIds.length === 0) {
        return;
      }

      const bindingData = formBindingData.createFormBindingData(formData);
      const aliveIds: string[] = [];
      for (let i = 0; i < formIds.length; i++) {
        const formId = formIds[i];
        try {
          await formProvider.updateForm(formId, bindingData);
          aliveIds.push(formId);
        } catch (err) {
          const be = err as BusinessError;
          if (be.code === FORM_ID_NOT_EXIST_CODE) {
            // 卡片已被移除，剔除失效 ID 即可，无需报错
            continue;
          }
          // 其他错误保留 ID 待下次重试
          aliveIds.push(formId);
          console.error(`[WidgetUpdateService] updateForm failed for form ${formId}: code=${be.code}, message=${be.message}`);
        }
      }

      if (aliveIds.length !== formIds.length) {
        pref.putSync(AppConstants.WIDGET_FORM_IDS_KEY, JSON.stringify(aliveIds));
        pref.flushSync();
      }
    } catch (e) {
      console.error('[WidgetUpdateService] pushAllFromCaches error:', JSON.stringify(e));
    }
  }

  /** 事件触发的免异常推送：失败静默（数据变更主流程不应被卡片刷新阻断） */
  static pushAllFromCachesSilently(context: Object): void {
    WidgetUpdateService.pushAllFromCaches(context).catch(() => {});
  }

  /** 从偏好文件构建全量卡片数据（EntryFormAbility 定时刷新也走 WidgetDataModel 的同一构建逻辑） */
  static buildFormData(pref: dataPreferences.Preferences): Record<string, Object> {
    const courseCacheJson = pref.getSync(AppConstants.NEXT_COURSE_CACHE_KEY, '') as string;
    const examDataJson = pref.getSync(AppConstants.EXAM_DATA_KEY, '') as string;
    const remoteBusJson = pref.getSync(AppConstants.PREF_BUS_SCHEDULE_JSON_KEY, '') as string;
    return WidgetDataModel.buildFullWidgetData(courseCacheJson, examDataJson, remoteBusJson, new Date());
  }
}
