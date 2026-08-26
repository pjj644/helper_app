import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { AppConstants } from '../common/constants/AppConstants';
import { preferences } from '@kit.ArkData';
import { ScheduleEvent, ScheduleEventType, ScheduleUtils } from '../model/ScheduleModel';
import { ScheduleRepository } from '../repository/ScheduleRepository';
import { ScheduleService } from './ScheduleService';
import { CalendarKitReminderService } from './CalendarKitReminderService';

const SCHEDULE_REMINDER_PREFIX: string = 'schedule_remind_';
const REMIND_MINUTES_DEFAULT: number = 30;

// 单个日程类别的提醒配置快照（循环前一次性预载，避免循环内逐条读偏好）
interface CategoryReminderSetting {
  enabled: boolean;
  defaultMinutes: number;
}

export class ReminderService {
  private static agentReminderAvailable: boolean | null = null;

  static async checkNotificationEnabled(): Promise<boolean> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      return enabled;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[ReminderDebug] checkNotificationEnabled error: code=${err.code}, message=${err.message}`);
      return false;
    }
  }

  static async requestNotificationPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      console.info('[ReminderDebug] requestNotificationPermission: requesting...');
      await notificationManager.requestEnableNotification(context);
      const enabled = await ReminderService.checkNotificationEnabled();
      console.info(`[ReminderDebug] requestNotificationPermission: result=${enabled}`);
      return enabled;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[ReminderDebug] requestNotificationPermission error: code=${err.code}, message=${err.message}`);
      return false;
    }
  }

  static async refreshAllReminders(context: Context): Promise<void> {
    try {
      await ScheduleService.syncCoursesToSchedule(context);
      await ScheduleService.syncExamsToSchedule(context);

      await ReminderService.refreshScheduleReminders(context);
    } catch (error) {
      console.error('[ReminderDebug] refreshAllReminders error:', JSON.stringify(error));
    }
  }

  static async refreshScheduleReminders(context: Context): Promise<void> {
    try {
      let hasNotification = await ReminderService.checkNotificationEnabled();
      if (!hasNotification) {
        console.warn('[ReminderDebug] Notification is NOT enabled! Attempting to request...');
        const uiContext = context as common.UIAbilityContext;
        hasNotification = await ReminderService.requestNotificationPermission(uiContext);
        if (!hasNotification) {
          console.error('[ReminderDebug] Notification permission denied! Reminders will not work.');
          return;
        }
      }

      const masterEnabled = await ReminderService.getGlobalScheduleReminderEnabled(context);
      if (!masterEnabled) {
        return;
      }

      await ReminderService.clearAgentReminders();

      // 先加载并与系统日历双向对齐（若用户在系统日历中已删除，在此步自动完成本地清理）
      const rawEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const allEvents: ScheduleEvent[] = await ScheduleService.syncAndPruneSchedulesWithCalendar(context, rawEvents);

      if (allEvents.length === 0) {
        return;
      }

      // 批量预载各类别提醒配置：旧实现在循环内逐条读偏好，事件多时开销随事件数放大；
      // 现改为循环外一次读取，循环内仅做纯内存计算。
      const categorySettings: Map<string, CategoryReminderSetting> = ReminderService.loadCategorySettings(context);

      const now = Date.now();
      const maxFutureTime = now + 7 * 24 * 60 * 60 * 1000;
      let createdCount = 0;
      const MAX_REMINDERS = 30;

      for (let i = 0; i < allEvents.length; i++) {
        const event = allEvents[i];

        if (createdCount >= MAX_REMINDERS) {
          break;
        }

        const setting = categorySettings.get(event.type);
        const categoryEnabled = setting ? setting.enabled : true;
        const categoryDefaultMinutes = setting ? setting.defaultMinutes : REMIND_MINUTES_DEFAULT;
        if (!categoryEnabled) {
          continue;
        }

        const remindMinutes = ReminderService.resolveEffectiveRemindMinutes(event, categoryDefaultMinutes);
        if (remindMinutes <= 0) {
          continue;
        }

        const dateParts = event.date.split('-').map(Number);
        const eventDate = new Date(dateParts[0], dateParts[1] - 1, dateParts[2]);
        ReminderService.applyEventTime(eventDate, event);

        const triggerTime = eventDate.getTime() - remindMinutes * 60 * 1000;
        if (triggerTime <= now) {
          continue;
        }
        if (triggerTime > maxFutureTime) {
          continue;
        }

        const title = `【${event.title}】即将开始`;
        const notificationId = ReminderService.hashCode(SCHEDULE_REMINDER_PREFIX + event.id) % 100000;

        const contentParts: string[] = [event.date, ScheduleUtils.getTypeLabel(event.type)];
        if (event.timeRange) {
          contentParts.push(event.timeRange);
        }
        if (event.location) {
          contentParts.push(event.location);
        }
        const content = contentParts.join(' ');

        let published = false;

        if (ReminderService.agentReminderAvailable !== false) {
          try {
            const reminderRequest: reminderAgentManager.ReminderRequestCalendar = {
              reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
              dateTime: {
                year: eventDate.getFullYear(),
                month: eventDate.getMonth() + 1,
                day: eventDate.getDate(),
                hour: eventDate.getHours(),
                minute: eventDate.getMinutes(),
              },
              title: title,
              content: content,
              notificationId: notificationId,
            };
            await reminderAgentManager.publishReminder(reminderRequest);
            ReminderService.agentReminderAvailable = true;
            published = true;
          } catch (err) {
            const be = err as BusinessError;
            console.warn(`[ReminderDebug] agent reminder failed for "${event.title}" (code=${be.code})`);
            if (be.code === 1700002) {
              ReminderService.agentReminderAvailable = false;
            }
          }
        }

        // 系统日历写入与防重复同步
        if (event.addToCalendar === true) {
          try {
            const uiContext = context as common.UIAbilityContext;
            const hasCalendarPerm = await CalendarKitReminderService.checkCalendarPermission(uiContext);
            if (!hasCalendarPerm) {
              await CalendarKitReminderService.requestCalendarPermission(uiContext);
            }

            // 若已有有效的 calendarEventId 且在系统日历中真实存在，直接复用，杜绝重复插入
            let existsInCal = false;
            if (event.calendarEventId && event.calendarEventId > 0) {
              existsInCal = await CalendarKitReminderService.checkEventExists(context, event.calendarEventId);
            }

            if (existsInCal) {
              published = true;
            } else {
              const calEventId = await CalendarKitReminderService.addEventReminder(context, event, remindMinutes);
              if (calEventId >= 0) {
                event.calendarEventId = calEventId;
                published = true;
              } else {
                console.error(`[ReminderDebug] FAILED: Calendar Kit reminder returned -1 for "${event.title}"`);
              }
            }
          } catch (calErr) {
            console.error(`[ReminderDebug] FAILED: Calendar Kit error:`, JSON.stringify(calErr));
          }
        }

        if (published) {
          createdCount++;
        }
      }

      console.info(`[ReminderDebug] refreshed reminders: published=${createdCount}, totalEvents=${allEvents.length}`);
      await ScheduleRepository.saveSchedules(context, allEvents);
    } catch (error) {
      console.error('[ReminderDebug] refreshScheduleReminders error:', JSON.stringify(error));
    }
  }

  /**
   * 一次性预载四类日程的提醒开关与默认提前分钟数。
   * 键值语义与 getCategoryReminderEnabled / getCategoryRemindMinutes 完全一致：
   * 未配置或读取失败时开关默认开、分钟数取 REMIND_MINUTES_DEFAULT。
   */
  private static loadCategorySettings(context: Context): Map<string, CategoryReminderSetting> {
    const settings: Map<string, CategoryReminderSetting> = new Map();
    let pref: preferences.Preferences | null = null;
    try {
      pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
    } catch (e) {
      console.error('[ReminderService] loadCategorySettings error:', JSON.stringify(e));
    }

    const types: ScheduleEventType[] = ['course', 'exam', 'custom', 'assignment'];
    for (let i = 0; i < types.length; i++) {
      const type = types[i];
      const enabledKey = ReminderService.getCategoryReminderKey(type);
      const minutesKey = ReminderService.getCategoryRemindMinutesKey(type);
      let enabled = true;
      let defaultMinutes = REMIND_MINUTES_DEFAULT;
      if (pref !== null && enabledKey && minutesKey) {
        enabled = pref.getSync(enabledKey, true) as boolean;
        defaultMinutes = pref.getSync(minutesKey, REMIND_MINUTES_DEFAULT) as number;
      }
      settings.set(type, { enabled: enabled, defaultMinutes: defaultMinutes });
    }
    return settings;
  }

  /** 单条事件实际生效的提前提醒分钟数（纯内存版本，供批量预载后的循环内使用）。 */
  private static resolveEffectiveRemindMinutes(event: ScheduleEvent, categoryDefaultMinutes: number): number {
    const selfMinutes: number | undefined = event.remindMinutes;
    if (selfMinutes === undefined || selfMinutes === null) {
      return categoryDefaultMinutes;
    }
    if (selfMinutes > 0) {
      return selfMinutes;
    }
    if (selfMinutes === -1) {
      return categoryDefaultMinutes;
    }
    return 0;
  }

  private static async clearAgentReminders(): Promise<void> {
    try {
      if (ReminderService.agentReminderAvailable !== false) {
        await reminderAgentManager.cancelAllReminders();
      }
    } catch (error) {
      console.warn('[ReminderDebug] cancelAllReminders error:', JSON.stringify(error));
    }
  }

  static async getGlobalScheduleReminderEnabled(context: Context): Promise<boolean> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const value = pref.getSync(AppConstants.SETTING_SCHEDULE_REMINDER_MASTER_KEY, true);
      return value as boolean;
    } catch {
      return true;
    }
  }

  static async saveGlobalScheduleReminderEnabled(context: Context, enabled: boolean): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SETTING_SCHEDULE_REMINDER_MASTER_KEY, enabled);
      pref.flushSync();
    } catch (e) {
      console.error('[ReminderService] saveGlobalScheduleReminderEnabled error:', JSON.stringify(e));
    }
  }

  static getCategoryReminderKey(type: ScheduleEventType): string {
    switch (type) {
      case 'exam':
        return AppConstants.SETTING_SCHEDULE_REMINDER_EXAM_KEY;
      case 'course':
        return AppConstants.SETTING_SCHEDULE_REMINDER_COURSE_KEY;
      case 'custom':
        return AppConstants.SETTING_SCHEDULE_REMINDER_CUSTOM_KEY;
      case 'assignment':
        return AppConstants.SETTING_SCHEDULE_REMINDER_ASSIGNMENT_KEY;
      default:
        return '';
    }
  }

  static async getCategoryReminderEnabled(context: Context, type: ScheduleEventType): Promise<boolean> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const key = ReminderService.getCategoryReminderKey(type);
      if (!key) {
        return true;
      }
      const value = pref.getSync(key, true);
      return value as boolean;
    } catch {
      return true;
    }
  }

  static async saveCategoryReminderEnabled(context: Context, type: ScheduleEventType, enabled: boolean): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const key = ReminderService.getCategoryReminderKey(type);
      if (!key) {
        return;
      }
      pref.putSync(key, enabled);
      pref.flushSync();
    } catch (e) {
      console.error('[ReminderService] saveCategoryReminderEnabled error:', JSON.stringify(e));
    }
  }

  static getCategoryRemindMinutesKey(type: ScheduleEventType): string {
    switch (type) {
      case 'exam':
        return AppConstants.SETTING_SCHEDULE_REMIND_MINUTES_EXAM_KEY;
      case 'course':
        return AppConstants.SETTING_SCHEDULE_REMIND_MINUTES_COURSE_KEY;
      case 'custom':
        return AppConstants.SETTING_SCHEDULE_REMIND_MINUTES_CUSTOM_KEY;
      case 'assignment':
        return AppConstants.SETTING_SCHEDULE_REMIND_MINUTES_ASSIGNMENT_KEY;
      default:
        return '';
    }
  }

  static async getCategoryRemindMinutes(context: Context, type: ScheduleEventType): Promise<number> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const key = ReminderService.getCategoryRemindMinutesKey(type);
      if (!key) {
        return REMIND_MINUTES_DEFAULT;
      }
      const value = pref.getSync(key, REMIND_MINUTES_DEFAULT);
      return value as number;
    } catch {
      return REMIND_MINUTES_DEFAULT;
    }
  }

  static async saveCategoryRemindMinutes(context: Context, type: ScheduleEventType, minutes: number): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const key = ReminderService.getCategoryRemindMinutesKey(type);
      if (!key) {
        return;
      }
      pref.putSync(key, minutes);
      pref.flushSync();
    } catch (e) {
      console.error('[ReminderService] saveCategoryRemindMinutes error:', JSON.stringify(e));
    }
  }

  static async getAutoSyncScheduleEnabled(context: Context): Promise<boolean> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const value = pref.getSync(AppConstants.SETTING_AUTO_SYNC_SCHEDULE_KEY, true);
      return value as boolean;
    } catch {
      return true;
    }
  }

  static async saveAutoSyncScheduleEnabled(context: Context, enabled: boolean): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SETTING_AUTO_SYNC_SCHEDULE_KEY, enabled);
      pref.flushSync();
    } catch (e) {
      console.error('[ReminderService] saveAutoSyncScheduleEnabled error:', JSON.stringify(e));
    }
  }

  /** 云端自动同步主开关（P2-7a）：默认关闭，用户显式开启后才自动上传课表/考试到云端 */
  static async getCloudAutoSyncEnabled(context: Context): Promise<boolean> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const value = pref.getSync(AppConstants.SETTING_CLOUD_AUTO_SYNC_KEY, false);
      return value as boolean;
    } catch {
      return false;
    }
  }

  static async saveCloudAutoSyncEnabled(context: Context, enabled: boolean): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SETTING_CLOUD_AUTO_SYNC_KEY, enabled);
      pref.flushSync();
    } catch (e) {
      console.error('[ReminderService] saveCloudAutoSyncEnabled error:', JSON.stringify(e));
    }
  }

  /** 允许蜂窝网络自动同步的副开关：默认关闭，仅 WiFi 自动上传时不受影响 */
  static async getCloudSyncCellularEnabled(context: Context): Promise<boolean> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const value = pref.getSync(AppConstants.SETTING_CLOUD_SYNC_CELLULAR_KEY, false);
      return value as boolean;
    } catch {
      return false;
    }
  }

  static async saveCloudSyncCellularEnabled(context: Context, enabled: boolean): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SETTING_CLOUD_SYNC_CELLULAR_KEY, enabled);
      pref.flushSync();
    } catch (e) {
      console.error('[ReminderService] saveCloudSyncCellularEnabled error:', JSON.stringify(e));
    }
  }

  private static applyEventTime(date: Date, event: ScheduleEvent): void {
    if (event.startTime) {
      const match = event.startTime.match(/^(\d{1,2}):(\d{2})$/);
      if (match) {
        date.setHours(parseInt(match[1]), parseInt(match[2]), 0, 0);
        return;
      }
    }
    if (event.timeRange) {
      const match = event.timeRange.match(/^(\d{1,2}):(\d{2})/);
      if (match) {
        date.setHours(parseInt(match[1]), parseInt(match[2]), 0, 0);
        return;
      }
    }
    date.setHours(9, 0, 0, 0);
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
