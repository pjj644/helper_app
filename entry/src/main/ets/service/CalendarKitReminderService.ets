import { calendarManager } from '@kit.CalendarKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { ScheduleEvent } from '../model/ScheduleModel';

const CALENDAR_ACCOUNT_NAME: string = 'HelperAppSchedule';
const CALENDAR_DISPLAY_NAME: string = '日程提醒';

export interface CalendarEventSummary {
  id: number;
  title: string;
  startTime: number;
  endTime: number;
  location: string;
}

export class CalendarKitReminderService {
  private static calendarMgr: calendarManager.CalendarManager | null = null;
  private static calendar: calendarManager.Calendar | null = null;

  static async requestCalendarPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const permissions: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
      const result = await atManager.requestPermissionsFromUser(context, permissions);
      let allGranted = true;
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) {
          allGranted = false;
          break;
        }
      }
      console.info(`[CalendarKit] requestCalendarPermission: granted=${allGranted}`);
      return allGranted;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[CalendarKit] requestCalendarPermission error: code=${err.code}, message=${err.message}`);
      return false;
    }
  }

  static async checkCalendarPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const grantStatus = await atManager.checkAccessToken(context.applicationInfo.accessTokenId, 'ohos.permission.WRITE_CALENDAR');
      const granted = grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      console.info(`[CalendarKit] checkCalendarPermission: ${granted}`);
      return granted;
    } catch (error) {
      console.error('[CalendarKit] checkCalendarPermission error:', JSON.stringify(error));
      return false;
    }
  }

  static async ensureCalendar(context: Context): Promise<calendarManager.Calendar | null> {
    try {
      if (CalendarKitReminderService.calendar) {
        return CalendarKitReminderService.calendar;
      }

      if (!CalendarKitReminderService.calendarMgr) {
        CalendarKitReminderService.calendarMgr = calendarManager.getCalendarManager(context);
      }

      const calendarAccount: calendarManager.CalendarAccount = {
        name: CALENDAR_ACCOUNT_NAME,
        type: calendarManager.CalendarType.LOCAL,
        displayName: CALENDAR_DISPLAY_NAME,
      };

      try {
        CalendarKitReminderService.calendar = await CalendarKitReminderService.calendarMgr.createCalendar(calendarAccount);
        const config: calendarManager.CalendarConfig = {
          enableReminder: true,
          color: '#FF6200EE',
        };
        await CalendarKitReminderService.calendar.setConfig(config);
        console.info('[CalendarKit] created new calendar account');
      } catch (createErr) {
        const err = createErr as BusinessError;
        if (err.code === 401) {
          const calendars: calendarManager.Calendar[] = await CalendarKitReminderService.calendarMgr.getAllCalendars();
          for (let i = 0; i < calendars.length; i++) {
            const cal = calendars[i];
            const account = cal.getAccount();
            if (account && account.name === CALENDAR_ACCOUNT_NAME) {
              CalendarKitReminderService.calendar = cal;
              console.info('[CalendarKit] found existing calendar account by name match');
              break;
            }
          }
          if (!CalendarKitReminderService.calendar && calendars.length > 0) {
            CalendarKitReminderService.calendar = calendars[0];
            console.info('[CalendarKit] fallback to first available calendar');
          }
        } else {
          console.error('[CalendarKit] createCalendar error:', JSON.stringify(createErr));
        }
      }

      return CalendarKitReminderService.calendar;
    } catch (error) {
      console.error('[CalendarKit] ensureCalendar error:', JSON.stringify(error));
      return null;
    }
  }

  private static calculateEndTime(event: ScheduleEvent, startDate: Date): Date {
    if (event.endTime) {
      const match = event.endTime.match(/^(\d{1,2}):(\d{2})$/);
      if (match) {
        return new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate(),
          parseInt(match[1]), parseInt(match[2]));
      }
    }
    if (event.timeRange && event.timeRange.includes('-')) {
      const parts = event.timeRange.split('-');
      if (parts.length >= 2) {
        const endPart = parts[parts.length - 1].trim();
        const match = endPart.match(/^(\d{1,2}):(\d{2})$/);
        if (match) {
          return new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate(),
            parseInt(match[1]), parseInt(match[2]));
        }
      }
    }
    return new Date(startDate.getTime() + 60 * 60 * 1000);
  }

  static async addEventReminder(context: Context, event: ScheduleEvent, remindMinutes: number): Promise<number> {
    try {
      const cal = await CalendarKitReminderService.ensureCalendar(context);
      if (!cal) {
        console.error('[CalendarKit] addEventReminder: calendar not available');
        return -1;
      }

      const dateParts = event.date.split('-').map(Number);
      const startHour = event.startTime ? parseInt(event.startTime.split(':')[0]) : 9;
      const startMinute = event.startTime ? parseInt(event.startTime.split(':')[1]) : 0;

      const startDate = new Date(dateParts[0], dateParts[1] - 1, dateParts[2], startHour, startMinute);
      const endDate = CalendarKitReminderService.calculateEndTime(event, startDate);

      const eventConfig: calendarManager.Event = {
        title: event.title,
        type: calendarManager.EventType.NORMAL,
        startTime: startDate.getTime(),
        endTime: endDate.getTime(),
        reminderTime: [remindMinutes],
        description: event.description || undefined,
      };

      if (event.location && event.location.length > 0) {
        eventConfig.location = { location: event.location };
      }

      const eventId = await cal.addEvent(eventConfig);
      console.info(`[CalendarKit] addEventReminder: eventId=${eventId}, title=${event.title}, remindMinutes=${remindMinutes}`);
      return eventId;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[CalendarKit] addEventReminder error: code=${err.code}, message=${err.message}`);
      return -1;
    }
  }

  static async upsertEventReminder(context: Context, event: ScheduleEvent, remindMinutes: number): Promise<number> {
    if (event.calendarEventId && event.calendarEventId > 0) {
      try {
        await CalendarKitReminderService.deleteEvent(context, event.calendarEventId);
        console.info(`[CalendarKit] upsertEventReminder: deleted old eventId=${event.calendarEventId}`);
      } catch (_err) {
        console.warn(`[CalendarKit] upsertEventReminder: failed to delete old eventId=${event.calendarEventId}`);
      }
    }
    return await CalendarKitReminderService.addEventReminder(context, event, remindMinutes);
  }

  static async deleteEvent(context: Context, eventId: number): Promise<boolean> {
    try {
      const cal = await CalendarKitReminderService.ensureCalendar(context);
      if (!cal) {
        return false;
      }
      await cal.deleteEvent(eventId);
      console.info(`[CalendarKit] deleteEvent: eventId=${eventId}`);
      return true;
    } catch (error) {
      console.error('[CalendarKit] deleteEvent error:', JSON.stringify(error));
      return false;
    }
  }

  static async clearAllEvents(context: Context): Promise<void> {
    try {
      const cal = await CalendarKitReminderService.ensureCalendar(context);
      if (!cal) {
        return;
      }
      const now = Date.now();
      const farFuture = now + 365 * 24 * 60 * 60 * 1000;
      const filter = calendarManager.EventFilter.filterByTime(now, farFuture);
      const events = await cal.getEvents(filter);
      for (let i = 0; i < events.length; i++) {
        try {
          await cal.deleteEvent(events[i].id);
        } catch (_err) {
          // skip
        }
      }
      console.info(`[CalendarKit] clearAllEvents: cleared ${events.length} events`);
    } catch (error) {
      console.error('[CalendarKit] clearAllEvents error:', JSON.stringify(error));
    }
  }

  static async listEvents(context: Context, startMs: number, endMs: number): Promise<CalendarEventSummary[]> {
    const result: CalendarEventSummary[] = [];
    try {
      const cal = await CalendarKitReminderService.ensureCalendar(context);
      if (!cal) {
        return result;
      }
      const filter = calendarManager.EventFilter.filterByTime(startMs, endMs);
      const events = await cal.getEvents(filter);
      for (let i = 0; i < events.length; i++) {
        const e = events[i];
        const loc = e.location;
        let locationStr: string = '';
        if (loc) {
          locationStr = loc.location || '';
        }
        result.push({
          id: e.id || 0,
          title: e.title || '',
          startTime: e.startTime || 0,
          endTime: e.endTime || 0,
          location: locationStr,
        });
      }
      console.info(`[CalendarKit] listEvents: returned ${result.length} events`);
    } catch (error) {
      console.error('[CalendarKit] listEvents error:', JSON.stringify(error));
    }
    return result;
  }

  static resetInstance(): void {
    CalendarKitReminderService.calendar = null;
    CalendarKitReminderService.calendarMgr = null;
  }
}
