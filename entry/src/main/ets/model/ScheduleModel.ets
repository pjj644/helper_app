export interface ScheduleEvent {
  id: string;
  title: string;
  date: string;
  timeRange: string;
  startTime?: string;
  endTime?: string;
  location: string;
  type: ScheduleEventType;
  color: string;
  sourceId: string;
  description: string;
  createdAt: number;
  remindMinutes?: number;
  addToCalendar?: boolean;
  calendarEventId?: number;
}

export type ScheduleEventType = 'course' | 'exam' | 'custom' | 'assignment';

export interface DayInfo {
  date: string;
  year: number;
  month: number;
  day: number;
  isToday: boolean;
  isCurrentMonth: boolean;
  events: ScheduleEvent[];
  markers: ScheduleEventType[];
}

export interface CalendarMonth {
  year: number;
  month: number;
  days: DayInfo[];
}

export class ScheduleUtils {
  static generateId(): string {
    return 'sch_' + Date.now().toString(36) + '_' + Math.random().toString(36).substring(2, 8);
  }

  static createEmptyEvent(): ScheduleEvent {
    const now = new Date();
    const hh = ScheduleUtils.twoDigit(now.getHours());
    const mm = ScheduleUtils.twoDigit(now.getMinutes());
    const time = `${hh}:${mm}`;
    return {
      id: '',
      title: '',
      date: '',
      timeRange: '',
      startTime: time,
      endTime: time,
      location: '',
      type: 'custom' as ScheduleEventType,
      color: '#FF9800',
      sourceId: '',
      description: '',
      createdAt: 0,
      remindMinutes: 0,
      addToCalendar: false,
    };
  }

  static getTypeColor(type: ScheduleEventType): string {
    switch (type) {
      case 'course':
        return '#2196F3';
      case 'exam':
        return '#F44336';
      case 'custom':
        return '#FF9800';
      case 'assignment':
        return '#9C27B0';
      default:
        return '#9E9E9E';
    }
  }

  static getTypeLabel(type: ScheduleEventType): string {
    switch (type) {
      case 'course':
        return '课程';
      case 'exam':
        return '考试';
      case 'custom':
        return '自定义';
      case 'assignment':
        return '作业';
      default:
        return '其他';
    }
  }

  static groupByDate(events: ScheduleEvent[]): Record<string, ScheduleEvent[]> {
    const map: Record<string, ScheduleEvent[]> = {};
    for (let i = 0; i < events.length; i++) {
      const evt: ScheduleEvent = events[i];
      if (!map[evt.date]) {
        map[evt.date] = [];
      }
      map[evt.date].push(evt);
    }
    return map;
  }

  static getUniqueDates(events: ScheduleEvent[]): Set<string> {
    const dates: Set<string> = new Set<string>();
    for (let i = 0; i < events.length; i++) {
      dates.add(events[i].date);
    }
    return dates;
  }

  static parseTimeRange(timeRange: string): string[] {
    const parts: string[] = timeRange.split('-');
    return [parts[0] ? parts[0].trim() : '', parts[1] ? parts[1].trim() : ''];
  }

  static formatTimeRange(start: string, end: string): string {
    return `${start}-${end}`;
  }

  static getDisplayTimeRange(event: ScheduleEvent): string {
    if (event.startTime && event.endTime) {
      return ScheduleUtils.formatTimeRange(event.startTime, event.endTime);
    }
    if (event.timeRange && event.timeRange.includes('-')) {
      return event.timeRange;
    }
    return '';
  }

  static twoDigit(n: number): string {
    return n < 10 ? '0' + String(n) : String(n);
  }

  static formatDate(year: number, month: number, day: number): string {
    return `${year}-${ScheduleUtils.twoDigit(month)}-${ScheduleUtils.twoDigit(day)}`;
  }

  static getEventMarkers(events: ScheduleEvent[]): ScheduleEventType[] {
    const types: ScheduleEventType[] = [];
    for (let i = 0; i < events.length; i++) {
      const t: ScheduleEventType = events[i].type;
      let found: boolean = false;
      for (let j = 0; j < types.length; j++) {
        if (types[j] === t) {
          found = true;
          break;
        }
      }
      if (!found) {
        types.push(t);
        if (types.length >= 3) {
          break;
        }
      }
    }
    return types;
  }
}
