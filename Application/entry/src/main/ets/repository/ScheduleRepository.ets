import { preferences } from '@kit.ArkData';
import { ScheduleEvent } from '../model/ScheduleModel';
import { AppConstants } from '../common/constants/AppConstants';

export class ScheduleRepository {
  static async loadSchedules(context: Context): Promise<ScheduleEvent[]> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      const jsonStr = pref.getSync(AppConstants.SCHEDULE_DATA_KEY, '[]') as string;
      if (!jsonStr || jsonStr === '[]') {
        return [];
      }
      const parsed: ScheduleEvent[] = JSON.parse(jsonStr) as ScheduleEvent[];
      return parsed;
    } catch (error) {
      console.error('ScheduleRepository loadSchedules error:', JSON.stringify(error));
      return [];
    }
  }

  static async saveSchedules(context: Context, events: ScheduleEvent[]): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SCHEDULE_DATA_KEY, JSON.stringify(events));
      pref.flushSync();
    } catch (error) {
      console.error('ScheduleRepository saveSchedules error:', JSON.stringify(error));
    }
  }

  static async addSchedule(context: Context, event: ScheduleEvent): Promise<void> {
    const events: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
    const existingIdx: number = events.findIndex((e: ScheduleEvent) => e.id === event.id);
    if (existingIdx >= 0) {
      events[existingIdx] = event;
    } else {
      events.push(event);
    }
    await ScheduleRepository.saveSchedules(context, events);
  }

  static async updateSchedule(context: Context, event: ScheduleEvent): Promise<void> {
    const events: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
    const idx: number = events.findIndex((e: ScheduleEvent) => e.id === event.id);
    if (idx >= 0) {
      events[idx] = event;
      await ScheduleRepository.saveSchedules(context, events);
    }
  }

  static async deleteSchedule(context: Context, eventId: string): Promise<void> {
    const events: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
    const filtered: ScheduleEvent[] = events.filter((e: ScheduleEvent) => e.id !== eventId);
    await ScheduleRepository.saveSchedules(context, filtered);
  }

  static async clearSchedules(context: Context): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(context, { name: AppConstants.COURSE_TABLE_PREF_NAME });
      pref.putSync(AppConstants.SCHEDULE_DATA_KEY, '[]');
      pref.flushSync();
    } catch (error) {
      console.error('ScheduleRepository clearSchedules error:', JSON.stringify(error));
    }
  }
}
