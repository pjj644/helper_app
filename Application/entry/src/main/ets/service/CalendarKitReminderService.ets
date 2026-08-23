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

  static async checkCalendarPermission(context: Context): Promise<boolean> {
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

      const hasPerm = await CalendarKitReminderService.checkCalendarPermission(context);
      if (!hasPerm) {
        console.warn('[CalendarKit] ensureCalendar: no calendar permission');
        return null;
      }

      if (!CalendarKitReminderService.calendarMgr) {
        CalendarKitReminderService.calendarMgr = calendarManager.getCalendarManager(context);
      }

      const calendarAccount: calendarManager.CalendarAccount = {
        name: CALENDAR_ACCOUNT_NAME,
        type: calendarManager.CalendarType.LOCAL,
        displayName: CALENDAR_DISPLAY_NAME,
      };

      // 1. 先检索已存在的所有日历账户
      try {
        const calendars: calendarManager.Calendar[] = await CalendarKitReminderService.calendarMgr.getAllCalendars();
        for (let i = 0; i < calendars.length; i++) {
          const cal = calendars[i];
          const account = cal.getAccount();
          if (account && account.name === CALENDAR_ACCOUNT_NAME) {
            CalendarKitReminderService.calendar = cal;
            console.info('[CalendarKit] found existing calendar account by name match');
            return CalendarKitReminderService.calendar;
          }
        }
      } catch (getErr) {
        console.warn('[CalendarKit] getAllCalendars warning:', JSON.stringify(getErr));
      }

      // 2. 若不存在则尝试创建
      try {
        CalendarKitReminderService.calendar = await CalendarKitReminderService.calendarMgr.createCalendar(calendarAccount);
        const config: calendarManager.CalendarConfig = {
          enableReminder: true,
          color: '#FF4F46E5',
        };
        await CalendarKitReminderService.calendar.setConfig(config);
        console.info('[CalendarKit] created new calendar account');
        return CalendarKitReminderService.calendar;
      } catch (createErr) {
        console.warn('[CalendarKit] createCalendar warning:', JSON.stringify(createErr));
      }

      // 3. 回退策略：再次尝试获取任意可用日历或系统默认日历
      try {
        const calendars: calendarManager.Calendar[] = await CalendarKitReminderService.calendarMgr.getAllCalendars();
        if (calendars.length > 0) {
          CalendarKitReminderService.calendar = calendars[0];
          console.info('[CalendarKit] fallback to first available calendar');
          return CalendarKitReminderService.calendar;
        }
        CalendarKitReminderService.calendar = await CalendarKitReminderService.calendarMgr.getCalendar();
        console.info('[CalendarKit] fallback to default calendar');
      } catch (fallbackErr) {
        console.error('[CalendarKit] fallback getCalendar error:', JSON.stringify(fallbackErr));
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

  /**
   * 清理日历中与指定日程匹配的所有历史/重复事件，保证唯一性
   */
  private static async deleteExistingDuplicates(
    cal: calendarManager.Calendar,
    event: ScheduleEvent,
    startDate: Date,
    endDate: Date,
    excludeId?: number
  ): Promise<void> {
    // 1. 若已有 calendarEventId，直接先删
    if (event.calendarEventId && event.calendarEventId > 0 && event.calendarEventId !== excludeId) {
      try {
        await cal.deleteEvent(event.calendarEventId);
        console.info(`[CalendarKit] deleteExistingDuplicates: deleted by calendarEventId=${event.calendarEventId}`);
      } catch (_e) {
        // ignore if already deleted
      }
    }

    // 2. 按时间窗口和标题模糊检索并清理同名同时间段残留
    try {
      const toleranceMs = 24 * 60 * 60 * 1000;
      const filter = calendarManager.EventFilter.filterByTime(
        startDate.getTime() - toleranceMs,
        endDate.getTime() + toleranceMs
      );
      const events = await cal.getEvents(filter);
      for (let i = 0; i < events.length; i++) {
        const e = events[i];
        if (excludeId && e.id === excludeId) {
          continue;
        }
        if ((e.title || '') === event.title) {
          const diff = Math.abs((e.startTime || 0) - startDate.getTime());
          if (diff <= 15 * 60 * 1000) {
            try {
              await cal.deleteEvent(e.id);
              console.info(`[CalendarKit] deleteExistingDuplicates: purged duplicate event id=${e.id}, title=${e.title}`);
            } catch (_err) {
              // ignore
            }
          }
        }
      }
    } catch (error) {
      console.warn('[CalendarKit] deleteExistingDuplicates query warning:', JSON.stringify(error));
    }
  }

  /**
   * 写入系统日历并确保单一日程在日历中的唯一性
   */
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

      // 写入前强力去重
      await CalendarKitReminderService.deleteExistingDuplicates(cal, event, startDate, endDate);

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
      console.info(`[CalendarKit] addEventReminder: success new eventId=${eventId}, title=${event.title}, remindMinutes=${remindMinutes}`);
      return eventId;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[CalendarKit] addEventReminder error: code=${err.code}, message=${err.message}`);
      return -1;
    }
  }

  static async upsertEventReminder(context: Context, event: ScheduleEvent, remindMinutes: number): Promise<number> {
    return await CalendarKitReminderService.addEventReminder(context, event, remindMinutes);
  }

  /**
   * 检查指定 calendarEventId 是否在系统日历中仍然存在
   */
  static async checkEventExists(context: Context, eventId: number): Promise<boolean> {
    if (!eventId || eventId <= 0) {
      return false;
    }
    try {
      const cal = await CalendarKitReminderService.ensureCalendar(context);
      if (!cal) {
        return false;
      }
      const now = Date.now();
      const past = now - 90 * 24 * 60 * 60 * 1000;
      const future = now + 365 * 24 * 60 * 60 * 1000;
      const filter = calendarManager.EventFilter.filterByTime(past, future);
      const events = await cal.getEvents(filter);
      for (let i = 0; i < events.length; i++) {
        if (events[i].id === eventId) {
          return true;
        }
      }
      return false;
    } catch (error) {
      console.warn('[CalendarKit] checkEventExists error:', JSON.stringify(error));
      return false;
    }
  }

  /**
   * 删除指定 ID 的日历事件
   */
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
      console.warn('[CalendarKit] deleteEvent warning:', JSON.stringify(error));
      return false;
    }
  }

  /**
   * 根据日程对象彻底清理系统日历中的所有对应事件（包括 ID 及特征匹配）
   */
  static async deleteEventBySchedule(context: Context, event: ScheduleEvent): Promise<void> {
    try {
      const cal = await CalendarKitReminderService.ensureCalendar(context);
      if (!cal) {
        return;
      }
      if (event.calendarEventId && event.calendarEventId > 0) {
        try {
          await cal.deleteEvent(event.calendarEventId);
          console.info(`[CalendarKit] deleteEventBySchedule: deleted eventId=${event.calendarEventId}`);
        } catch (_err) {
          // ignore
        }
      }
      if (event.date && event.title) {
        const dateParts = event.date.split('-').map(Number);
        const startHour = event.startTime ? parseInt(event.startTime.split(':')[0]) : 9;
        const startMinute = event.startTime ? parseInt(event.startTime.split(':')[1]) : 0;
        const startDate = new Date(dateParts[0], dateParts[1] - 1, dateParts[2], startHour, startMinute);
        const endDate = CalendarKitReminderService.calculateEndTime(event, startDate);
        await CalendarKitReminderService.deleteExistingDuplicates(cal, event, startDate, endDate);
      }
    } catch (error) {
      console.warn('[CalendarKit] deleteEventBySchedule error:', JSON.stringify(error));
    }
  }

  static async clearAllEvents(context: Context): Promise<void> {
    try {
      const cal = await CalendarKitReminderService.ensureCalendar(context);
      if (!cal) {
        return;
      }
      const now = Date.now();
      const past = now - 30 * 24 * 60 * 60 * 1000;
      const farFuture = now + 365 * 24 * 60 * 60 * 1000;
      const filter = calendarManager.EventFilter.filterByTime(past, farFuture);
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

  /**
   * 写入班车发车提醒到系统日历（提前 15 分钟），按发车点与时间强力去重
   */
  static async createBusReminder(
    context: Context,
    departureName: string,
    destinationName: string,
    busTime: string,
    targetDate?: Date
  ): Promise<number> {
    try {
      const cal = await CalendarKitReminderService.ensureCalendar(context);
      if (!cal) {
        console.error('[CalendarKit] createBusReminder: calendar not available');
        return -1;
      }

      const now = targetDate || new Date();
      const timeParts = busTime.split(':').map(Number);
      const startHour = timeParts[0] || 0;
      const startMinute = timeParts[1] || 0;

      const startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate(), startHour, startMinute);
      if (!targetDate && startDate.getTime() < Date.now() - 10 * 60 * 1000) {
        startDate.setDate(startDate.getDate() + 1);
      }

      const endDate = new Date(startDate.getTime() + 45 * 60 * 1000);
      const title = `成电班车：${departureName} ➔ ${destinationName}`;
      const location = `${departureName}主楼班车站`;
      const description = `发车时间：${busTime}，请提前到达上车站台。`;

      try {
        const toleranceMs = 12 * 60 * 60 * 1000;
        const filter = calendarManager.EventFilter.filterByTime(
          startDate.getTime() - toleranceMs,
          endDate.getTime() + toleranceMs
        );
        const events = await cal.getEvents(filter);
        for (let i = 0; i < events.length; i++) {
          const e = events[i];
          if ((e.title || '').includes('成电班车') && Math.abs((e.startTime || 0) - startDate.getTime()) < 10 * 60 * 1000) {
            try {
              await cal.deleteEvent(e.id);
              console.info(`[CalendarKit] createBusReminder: purged duplicate bus event id=${e.id}`);
            } catch (_err) {
              // ignore
            }
          }
        }
      } catch (err) {
        console.warn('[CalendarKit] createBusReminder purge warning:', JSON.stringify(err));
      }

      const eventConfig: calendarManager.Event = {
        title: title,
        type: calendarManager.EventType.NORMAL,
        startTime: startDate.getTime(),
        endTime: endDate.getTime(),
        reminderTime: [15],
        description: description,
        location: { location: location },
      };

      const eventId = await cal.addEvent(eventConfig);
      console.info(`[CalendarKit] createBusReminder: success eventId=${eventId}, title=${title}`);
      return eventId;
    } catch (error) {
      console.error('[CalendarKit] createBusReminder error:', JSON.stringify(error));
      return -1;
    }
  }

  static resetInstance(): void {
    CalendarKitReminderService.calendar = null;
    CalendarKitReminderService.calendarMgr = null;
  }
}

