import { formBindingData, formProvider, FormExtensionAbility } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { AppConstants } from '../common/constants/AppConstants';

interface NextCourseCacheData {
  name?: string;
  location?: string;
  time?: string;
  room?: string;
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formData: Record<string, string | number> = {
      'courseName': '暂无待上课程',
      'location': '无',
      'time': '--:--',
      'room': '今日已无课'
    };

    try {
      let pref = dataPreferences.getPreferencesSync(this.context, { name: AppConstants.PREF_COURSE_DB_NAME });
      let nextCourseStr = pref.getSync('next_course_cache', '') as string;
      if (nextCourseStr) {
        let parsed: NextCourseCacheData = JSON.parse(nextCourseStr) as NextCourseCacheData;
        formData = {
          'courseName': parsed.name || '今日课程',
          'location': parsed.location || parsed.room || '教室未定',
          'time': parsed.time || '--:--',
          'room': parsed.room || ''
        };
      }
    } catch (e) {
      console.error('[EntryFormAbility] onAddForm error:', JSON.stringify(e));
    }

    return formBindingData.createFormBindingData(formData);
  }

  onUpdateForm(formId: string) {
    try {
      let pref = dataPreferences.getPreferencesSync(this.context, { name: AppConstants.PREF_COURSE_DB_NAME });
      let nextCourseStr = pref.getSync('next_course_cache', '') as string;
      let formData: Record<string, string | number> = {
        'courseName': '暂无待上课程',
        'location': '无',
        'time': '--:--',
        'room': '今日已无课'
      };
      if (nextCourseStr) {
        let parsed: NextCourseCacheData = JSON.parse(nextCourseStr) as NextCourseCacheData;
        formData = {
          'courseName': parsed.name || '今日课程',
          'location': parsed.location || parsed.room || '教室未定',
          'time': parsed.time || '--:--',
          'room': parsed.room || ''
        };
      }
      let bindingData = formBindingData.createFormBindingData(formData);
      formProvider.updateForm(formId, bindingData);
    } catch (e) {
      console.error('[EntryFormAbility] onUpdateForm error:', JSON.stringify(e));
    }
  }

  onFormEvent(formId: string, message: string) {
    console.info(`[EntryFormAbility] onFormEvent: ${formId}, message: ${message}`);
  }
}
