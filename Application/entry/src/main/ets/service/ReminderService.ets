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

export class ReminderService {
  private static agentReminderAvailable: boolean | null = null;

  static async checkNotificationEnabled(): Promise<boolean> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      console.info(`[ReminderDebug] checkNotificationEnabled: ${enabled}`);
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
    console.info('[ReminderDebug] refreshAllReminders called');
    try {
      await ScheduleService.syncCoursesToSchedule(context);
      await ScheduleService.syncExamsToSchedule(context);

      await ReminderService.refreshScheduleReminders(context);
    } catch (error) {
      console.error('[ReminderDebug] refreshAllReminders error:', JSON.stringify(error));
    }
  }

  static async refreshScheduleReminders(context: Context): Promise<void> {
    console.info('[ReminderDebug] refreshScheduleReminders called');
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
        console.info('[ReminderDebug] Notification permission granted!');
      }

      const masterEnabled = await ReminderService.getGlobalScheduleReminderEnabled(context);
      console.info(`[ReminderDebug] masterEnabled=${masterEnabled}`);
      if (!masterEnabled) {
        console.info('[ReminderDebug] master disabled, skipping');
        return;
      }

      await ReminderService.clearAgentReminders();

      // 先加载并与系统日历双向对齐（若用户在系统日历中已删除，在此步自动完成本地清理）
      const rawEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const allEvents: ScheduleEvent[] = await ScheduleService.syncAndPruneSchedulesWithCalendar(context, rawEvents);
      console.info(`[ReminderDebug] loaded and aligned ${allEvents.length} events from repository`);

      if (allEvents.length === 0) {
        console.info('[ReminderDebug] no events, skipping');
        return;
      }

      const now = Date.now();
      const maxFutureTime = now + 7 * 24 * 60 * 60 * 1000;
      console.info(`[ReminderDebug] now=${new Date(now).toISOString()}, maxFuture=${new Date(maxFutureTime).toISOString()}`);
      let createdCount = 0;
      const MAX_REMINDERS = 30;

      for (let i = 0; i < allEvents.length; i++) {
        const event = allEvents[i];

        if (createdCount >= MAX_REMINDERS) {
          console.info(`[ReminderDebug] reached MAX_REMINDERS=${MAX_REMINDERS}, stopping`);
          break;
        }

        console.info(`[ReminderDebug] processing event[${i}]: id=${event.id}, title=${event.title}, date=${event.date}, timeRange=${event.timeRange}, startTime=${event.startTime}, type=${event.type}, remindMinutes=${event.remindMinutes}`);

        const categoryEnabled = await ReminderService.getCategoryReminderEnabled(context, event.type);
        console.info(`[ReminderDebug]   categoryEnabled(${event.type})=${categoryEnabled}`);
        if (!categoryEnabled) {
          console.info(`[ReminderDebug]   SKIP: category disabled`);
          continue;
        }

        const remindMinutes = await ReminderService.getEffectiveRemindMinutes(context, event);
        console.info(`[ReminderDebug]   effectiveRemindMinutes=${remindMinutes}`);
        if (remindMinutes <= 0) {
          console.info(`[ReminderDebug]   SKIP: remindMinutes <= 0`);
          continue;
        }

        const dateParts = event.date.split('-').map(Number);
        const eventDate = new Date(dateParts[0], dateParts[1] - 1, dateParts[2]);
        console.info(`[ReminderDebug]   base date=${eventDate.toISOString()}`);
        ReminderService.applyEventTime(eventDate, event);
        console.info(`[ReminderDebug]   after applyEventTime=${eventDate.toISOString()}`);

        const triggerTime = eventDate.getTime() - remindMinutes * 60 * 1000;
        console.info(`[ReminderDebug]   triggerTime=${new Date(triggerTime).toISOString()}, now=${new Date(now).toISOString()}, diff=${triggerTime - now}ms`);
        if (triggerTime <= now) {
          console.info(`[ReminderDebug]   SKIP: triggerTime <= now (already past)`);
          continue;
        }
        if (triggerTime > maxFutureTime) {
          console.info(`[ReminderDebug]   SKIP: triggerTime > maxFutureTime (more than 7 days ahead)`);
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

        console.info(`[ReminderDebug]   publishing reminder: id=${notificationId}, title=${title}, content=${content}`);

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
            console.info(`[ReminderDebug]   SUCCESS: agent reminder published`);
            ReminderService.agentReminderAvailable = true;
            published = true;
          } catch (err) {
            const be = err as BusinessError;
            console.warn(`[ReminderDebug]   agent reminder failed (code=${be.code})`);
            if (be.code === 1700002) {
              ReminderService.agentReminderAvailable = false;
              console.info(`[ReminderDebug]   agent reminder not available (1700002), switching to Calendar Kit`);
            }
          }
        }

        // 系统日历写入与防重复同步
        if (event.addToCalendar === true) {
          try {
            const uiContext = context as common.UIAbilityContext;
            const hasCalendarPerm = await CalendarKitReminderService.checkCalendarPermission(uiContext);
            if (!hasCalendarPerm) {
              console.info(`[ReminderDebug]   requesting calendar permission...`);
              await CalendarKitReminderService.requestCalendarPermission(uiContext);
            }

            // 若已有有效的 calendarEventId 且在系统日历中真实存在，直接复用，杜绝重复插入
            let existsInCal = false;
            if (event.calendarEventId && event.calendarEventId > 0) {
              existsInCal = await CalendarKitReminderService.checkEventExists(context, event.calendarEventId);
            }

            if (existsInCal) {
              console.info(`[ReminderDebug]   calendar event already uniquely exists (id=${event.calendarEventId}), skipping duplicate insert`);
              published = true;
            } else {
              const calEventId = await CalendarKitReminderService.addEventReminder(context, event, remindMinutes);
              if (calEventId >= 0) {
                console.info(`[ReminderDebug]   SUCCESS: Calendar Kit reminder added, calEventId=${calEventId}`);
                event.calendarEventId = calEventId;
                published = true;
              } else {
                console.error(`[ReminderDebug]   FAILED: Calendar Kit reminder returned -1`);
              }
            }
          } catch (calErr) {
            console.error(`[ReminderDebug]   FAILED: Calendar Kit error:`, JSON.stringify(calErr));
          }
        }

        if (published) {
          createdCount++;
        }
      }

      console.info(`[ReminderDebug] total reminders processed: ${createdCount}`);
      await ScheduleRepository.saveSchedules(context, allEvents);
      console.info(`[ReminderDebug] saved calendarEventId mappings to repository`);
    } catch (error) {
      console.error('[ReminderDebug] refreshScheduleReminders error:', JSON.stringify(error));
    }
  }

  private static async clearAgentReminders(): Promise<void> {
    try {
      if (ReminderService.agentReminderAvailable !== false) {
        await reminderAgentManager.cancelAllReminders();
        console.info('[ReminderDebug] cleared existing agent reminders');
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
      console.error('ReminderService saveGlobalScheduleReminderEnabled error:', JSON.stringify(e));
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
      console.error('ReminderService saveCategoryReminderEnabled error:', JSON.stringify(e));
    }
  }

  static getCategoryRemindMinutesKey(type: ScheduleEventType): string {
    switch (type) {
      case 'exam':
        return AppConstants.SETTING_SCHEDULE_REMIND_MINUTES_EXAM_KEY;
      case 'course':
        return AppConstants.SETTING_SCHEDULE_REMINDER_COURSE_KEY;
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
      console.error('ReminderService saveCategoryRemindMinutes error:', JSON.stringify(e));
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
      console.error('ReminderService saveAutoSyncScheduleEnabled error:', JSON.stringify(e));
    }
  }

  static async getEffectiveRemindMinutes(context: Context, event: ScheduleEvent): Promise<number> {
    console.info(`[ReminderDebug] getEffectiveRemindMinutes: remindMinutes=${event.remindMinutes}, type=${event.type}`);
    if (event.remindMinutes === undefined || event.remindMinutes === null) {
      const defaultMinutes = await ReminderService.getCategoryRemindMinutes(context, event.type);
      console.info(`[ReminderDebug]   undefined/null -> category default=${defaultMinutes}`);
      return defaultMinutes;
    }
    if (event.remindMinutes > 0) {
      console.info(`[ReminderDebug]   >0 -> use self=${event.remindMinutes}`);
      return event.remindMinutes;
    }
    if (event.remindMinutes === -1) {
      const defaultMinutes = await ReminderService.getCategoryRemindMinutes(context, event.type);
      console.info(`[ReminderDebug]   -1 -> category default=${defaultMinutes}`);
      return defaultMinutes;
    }
    console.info(`[ReminderDebug]   0 -> disabled`);
    return 0;
  }

  private static applyEventTime(date: Date, event: ScheduleEvent): void {
    console.info(`[ReminderDebug] applyEventTime: startTime=${event.startTime}, timeRange=${event.timeRange}`);
    if (event.startTime) {
      const match = event.startTime.match(/^(\d{1,2}):(\d{2})$/);
      if (match) {
        date.setHours(parseInt(match[1]), parseInt(match[2]), 0, 0);
        console.info(`[ReminderDebug]   used startTime: ${match[1]}:${match[2]}`);
        return;
      }
    }
    if (event.timeRange) {
      const match = event.timeRange.match(/^(\d{1,2}):(\d{2})/);
      if (match) {
        date.setHours(parseInt(match[1]), parseInt(match[2]), 0, 0);
        console.info(`[ReminderDebug]   used timeRange start: ${match[1]}:${match[2]}`);
        return;
      }
    }
    date.setHours(9, 0, 0, 0);
    console.info(`[ReminderDebug]   fallback to 9:00`);
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
