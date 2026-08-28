import { formBindingData, formProvider, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { AppConstants } from '../common/constants/AppConstants';
import { WidgetDataModel } from '../model/widget/WidgetDataModel';

export default class EntryFormAbility extends FormExtensionAbility {
  /**
   * 构建卡片绑定数据：课程 / 考试 / 班车三张卡片共用同一份全量 formData
   * （构建逻辑收敛于 model/widget/WidgetDataModel，与 service/WidgetUpdateService
   * 的事件驱动推送保持同一口径）。
   */
  private getFormData(): Record<string, Object> {
    try {
      const pref = dataPreferences.getPreferencesSync(this.context, { name: AppConstants.PREF_COURSE_DB_NAME });
      const courseCacheJson = pref.getSync(AppConstants.NEXT_COURSE_CACHE_KEY, '') as string;
      const examDataJson = pref.getSync(AppConstants.EXAM_DATA_KEY, '') as string;
      const remoteBusJson = pref.getSync(AppConstants.PREF_BUS_SCHEDULE_JSON_KEY, '') as string;
      return WidgetDataModel.buildFullWidgetData(courseCacheJson, examDataJson, remoteBusJson, new Date());
    } catch (e) {
      console.error('[EntryFormAbility] getFormData error:', JSON.stringify(e));
      return WidgetDataModel.buildFullWidgetData('', '', '', new Date());
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    // 记录卡片实例 ID：应用侧事件驱动主动刷新（WidgetUpdateService.pushAllFromCaches）
    // 依赖该列表定位需要推送的卡片
    const params: Record<string, Object> | undefined = want.parameters;
    if (params) {
      const identity = params[formInfo.FormParam.IDENTITY_KEY];
      if (typeof identity === 'string' && identity.length > 0) {
        this.rememberFormId(identity);
      }
    }
    const formData = this.getFormData();
    return formBindingData.createFormBindingData(formData);
  }

  onRemoveForm(formId: string): void {
    this.forgetFormId(formId);
  }

  /** 将新添加的卡片实例 ID 追加进持久化列表（去重）。 */
  private rememberFormId(formId: string): void {
    try {
      const pref = dataPreferences.getPreferencesSync(this.context, { name: AppConstants.PREF_COURSE_DB_NAME });
      const idsStr = pref.getSync(AppConstants.WIDGET_FORM_IDS_KEY, '[]') as string;
      const ids: string[] = JSON.parse(idsStr) as string[];
      if (ids.indexOf(formId) < 0) {
        ids.push(formId);
        pref.putSync(AppConstants.WIDGET_FORM_IDS_KEY, JSON.stringify(ids));
        pref.flushSync();
      }
    } catch (e) {
      console.error('[EntryFormAbility] rememberFormId error:', JSON.stringify(e));
    }
  }

  /** 从持久化列表中移除已被删除的卡片实例 ID。 */
  private forgetFormId(formId: string): void {
    try {
      const pref = dataPreferences.getPreferencesSync(this.context, { name: AppConstants.PREF_COURSE_DB_NAME });
      const idsStr = pref.getSync(AppConstants.WIDGET_FORM_IDS_KEY, '[]') as string;
      const ids: string[] = JSON.parse(idsStr) as string[];
      const remaining: string[] = [];
      for (let i = 0; i < ids.length; i++) {
        if (ids[i] !== formId) {
          remaining.push(ids[i]);
        }
      }
      if (remaining.length !== ids.length) {
        pref.putSync(AppConstants.WIDGET_FORM_IDS_KEY, JSON.stringify(remaining));
        pref.flushSync();
      }
    } catch (e) {
      console.error('[EntryFormAbility] forgetFormId error:', JSON.stringify(e));
    }
  }

  onUpdateForm(formId: string) {
    try {
      const formData = this.getFormData();
      const bindingData = formBindingData.createFormBindingData(formData);
      formProvider.updateForm(formId, bindingData);
    } catch (e) {
      console.error('[EntryFormAbility] onUpdateForm error:', JSON.stringify(e));
    }
  }

  onFormEvent(formId: string, message: string) {
    console.info(`[EntryFormAbility] onFormEvent: ${formId}, message: ${message}`);
  }
}
