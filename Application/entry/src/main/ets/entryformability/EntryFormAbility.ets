import { formBindingData, formProvider, FormExtensionAbility } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import dataPreferences from '@ohos.data.preferences';
import { AppConstants } from '../common/constants/AppConstants';

interface NextCourseCacheData {
  name?: string;
  courseName?: string;
  location?: string;
  time?: string;
  room?: string;
  countdownText?: string;
  hasCourseToday?: boolean;
  dateStr?: string;
  courseCount?: number;
  course1_name?: string;
  course1_time?: string;
  course1_room?: string;
  course1_status?: string;
  course2_name?: string;
  course2_time?: string;
  course2_room?: string;
  course2_status?: string;
  course3_name?: string;
  course3_time?: string;
  course3_room?: string;
  course3_status?: string;
}

export default class EntryFormAbility extends FormExtensionAbility {
  private getFormData(): Record<string, string | number | boolean> {
    let formData: Record<string, string | number | boolean> = {
      'courseName': '暂无待上课程',
      'location': '教室未定',
      'time': '--:--',
      'room': '今日已无课',
      'countdownText': '今日已无课',
      'hasCourseToday': false,
      'dateStr': '今日课表',
      'courseCount': 0,
      'course1_name': '',
      'course1_time': '',
      'course1_room': '',
      'course1_status': '',
      'course2_name': '',
      'course2_time': '',
      'course2_room': '',
      'course2_status': '',
      'course3_name': '',
      'course3_time': '',
      'course3_room': '',
      'course3_status': ''
    };

    try {
      let pref = dataPreferences.getPreferencesSync(this.context, { name: AppConstants.PREF_COURSE_DB_NAME });
      let nextCourseStr = pref.getSync('next_course_cache', '') as string;
      if (nextCourseStr) {
        let parsed: NextCourseCacheData = JSON.parse(nextCourseStr) as NextCourseCacheData;
        formData = {
          'courseName': parsed.courseName || parsed.name || '暂无待上课程',
          'location': parsed.location || parsed.room || '教室未定',
          'time': parsed.time || '--:--',
          'room': parsed.room || '教室未定',
          'countdownText': parsed.countdownText || '今日已无课',
          'hasCourseToday': parsed.hasCourseToday !== undefined ? parsed.hasCourseToday : false,
          'dateStr': parsed.dateStr || '今日课表',
          'courseCount': parsed.courseCount !== undefined ? parsed.courseCount : 0,
          'course1_name': parsed.course1_name || '',
          'course1_time': parsed.course1_time || '',
          'course1_room': parsed.course1_room || '',
          'course1_status': parsed.course1_status || '',
          'course2_name': parsed.course2_name || '',
          'course2_time': parsed.course2_time || '',
          'course2_room': parsed.course2_room || '',
          'course2_status': parsed.course2_status || '',
          'course3_name': parsed.course3_name || '',
          'course3_time': parsed.course3_time || '',
          'course3_room': parsed.course3_room || '',
          'course3_status': parsed.course3_status || ''
        };
      }
    } catch (e) {
      console.error('[EntryFormAbility] getFormData error:', JSON.stringify(e));
    }

    return formData;
  }

  onAddForm(_want: Want): formBindingData.FormBindingData {
    const formData = this.getFormData();
    return formBindingData.createFormBindingData(formData);
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
