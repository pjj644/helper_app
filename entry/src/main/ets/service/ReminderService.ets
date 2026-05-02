import { Course } from '../model/classTableModel/CourseModel';
import { ReminderUtils } from '../common/utils/ReminderUtils';
import { CourseService } from './CourseService';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants } from '../common/constants/AppConstants';
import { preferences } from '@kit.ArkData';

const REMINDER_PREFIX: string = 'course_remind_';

export class ReminderService {
  static async getEnabledPref(context: Context): Promise<boolean> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const value = pref.getSync(AppConstants.SETTING_REMINDER_ENABLED_KEY, false);
      return value as boolean;
    } catch {
      return false;
    }
  }

  static async saveEnabledPref(context: Context, enabled: boolean): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SETTING_REMINDER_ENABLED_KEY, enabled);
      pref.flushSync();
    } catch (e) {
      console.error('ReminderService saveEnabledPref error:', JSON.stringify(e));
    }
  }

  static async getAdvanceMinutes(context: Context): Promise<number> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const value = pref.getSync(AppConstants.SETTING_COURSE_REMIND_MINUTES_KEY, 30);
      return value as number;
    } catch {
      return 30;
    }
  }

  static async requestPermission(context: Context): Promise<boolean> {
    try {
      return true;
    } catch (error) {
      return false;
    }
  }

  static async refreshAllReminders(context: Context): Promise<void> {
    try {
      await ReminderService.clearAllReminders();

      const enabled: boolean = await ReminderService.getEnabledPref(context);
      if (!enabled) {
        return;
      }
      const courses: Course[] = await CourseService.loadCourses(context);
      if (courses.length === 0) {
        return;
      }
      const advanceMinutes: number = await ReminderService.getAdvanceMinutes(context);
      if (advanceMinutes <= 0) {
        return;
      }

      const now: Date = new Date();
      const currentDayOfWeek: number = now.getDay();
      const mondayDate: Date = new Date(now);
      const diffToMonday: number = currentDayOfWeek === 0 ? -6 : 1 - currentDayOfWeek;
      mondayDate.setDate(now.getDate() + diffToMonday);
      mondayDate.setHours(0, 0, 0, 0);

      let createdCount: number = 0;
      for (let i = 0; i < courses.length; i++) {
        const course: Course = courses[i];
        const dayOfWeek: number = course.time.dayOfWeek;
        const targetDate: Date = new Date(mondayDate);
        targetDate.setDate(mondayDate.getDate() + dayOfWeek - 1);
        const sectionMins: number = (course.time.startSection - 1) * 45 + Math.floor((course.time.startSection - 1) / 2) * 10;
        const startMins: number = 8 * 60 + sectionMins;
        const reminderMins: number = startMins - advanceMinutes;
        if (reminderMins <= 0) {
          continue;
        }
        targetDate.setHours(Math.floor(reminderMins / 60));
        targetDate.setMinutes(reminderMins % 60);
        targetDate.setSeconds(0);
        targetDate.setMilliseconds(0);
        const title: string = ReminderUtils.buildReminderTitle(course);

        if (targetDate.getTime() <= Date.now()) {
          continue;
        }
        const notificationId: number = ReminderService.hashCode(REMINDER_PREFIX + course.id || course.name) % 100000;

        try {
          const reminderRequest: reminderAgentManager.ReminderRequestTimer = {
            reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
            title: title,
            content: course.name,
            triggerTimeInSeconds: Math.floor(targetDate.getTime() / 1000),
            notificationId: notificationId,
          };
          await reminderAgentManager.publishReminder(reminderRequest);
          createdCount++;
        } catch (err) {
          const be = err as BusinessError;
          console.error('ReminderService publishReminder error:', be.message);
        }
      }

      if (createdCount > 0) {
        console.info(`ReminderService created ${createdCount} reminders`);
      }
    } catch (error) {
      console.error('ReminderService refreshAllReminders error:', JSON.stringify(error));
    }
  }

  static async clearAllReminders(): Promise<void> {
    try {
      const allReminders = await reminderAgentManager.getAllValidReminders();
      if (allReminders && allReminders.length > 0) {
        for (let i = 0; i < allReminders.length; i++) {
          await reminderAgentManager.cancelReminder(allReminders[i].reminderId);
        }
      }
    } catch (error) {
      const err = error as BusinessError;
      console.error('ReminderService clearAllReminders error:', err.message || String(error));
    }
  }

  private static hashCode(str: string): number {
    let hash: number = 0;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash);
  }
}
