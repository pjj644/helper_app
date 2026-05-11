export interface DateTimeRange {
  begin: number;
  end: number;
}

export interface CountdownParts {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
  totalSeconds: number;
  isExpired: boolean;
  isUnknown: boolean;
  urgency: number;
}

export class DateUtils {
  static twoDigit(value: number): string {
    return value < 10 ? `0${value}` : String(value);
  }

  static normalizeExamDate(dateText: string): string {
    const raw: string = (dateText || '').trim();
    if (!raw) {
      return '';
    }

    let matched: RegExpMatchArray | null = raw.match(/(\d{4})[\/\.\-](\d{1,2})[\/\.\-](\d{1,2})/);
    if (!matched) {
      matched = raw.match(/(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?/);
    }
    if (!matched) {
      return raw;
    }

    const year: number = Number.parseInt(matched[1], 10);
    const month: number = Number.parseInt(matched[2], 10);
    const day: number = Number.parseInt(matched[3], 10);
    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
      return raw;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return raw;
    }
    return `${year}-${DateUtils.twoDigit(month)}-${DateUtils.twoDigit(day)}`;
  }

  static parseExamDate(dateText: string): Date | undefined {
    const normalized: string = DateUtils.normalizeExamDate(dateText);
    const matched: RegExpMatchArray | null = normalized.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!matched) {
      return undefined;
    }
    const year: number = Number.parseInt(matched[1], 10);
    const month: number = Number.parseInt(matched[2], 10);
    const day: number = Number.parseInt(matched[3], 10);
    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
      return undefined;
    }
    return new Date(year, month - 1, day);
  }

  static parseDateTime(dateText: string, timeRange: string): DateTimeRange {
    const date: string = DateUtils.normalizeExamDate(dateText);
    const range: string = timeRange.replace(/\s+/g, '')
      .replace(/~/g, '-')
      .replace(/～/g, '-')
      .replace(/—/g, '-')
      .replace(/－/g, '-');
    const parts: string[] = range.split('-');
    if (parts.length !== 2) {
      console.info(`[ExamDebug] parseDateTime FAILED: dateText="${dateText}" timeRange="${timeRange}" normalizedDate="${date}" normalizedRange="${range}" parts=${parts.length}`);
      return { begin: 0, end: 0 };
    }

    const begin = new Date(`${date} ${parts[0]}`).getTime();
    const end = new Date(`${date} ${parts[1]}`).getTime();
    const result: DateTimeRange = {
      begin: Number.isNaN(begin) ? 0 : begin,
      end: Number.isNaN(end) ? 0 : end,
    };
    if (result.begin === 0) {
      console.info(`[ExamDebug] parseDateTime NaN: date="${date}" timeRange="${timeRange}" parts=[${parts[0]}, ${parts[1]}]`);
    }
    return result;
  }

  static getCountdownParts(now: number, beginTime: number): CountdownParts {
    if (beginTime <= 0) {
      return { days: 0, hours: 0, minutes: 0, seconds: 0, totalSeconds: 0, isExpired: false, isUnknown: true, urgency: 0 };
    }
    const diff = beginTime - now;
    if (diff <= 0) {
      return { days: 0, hours: 0, minutes: 0, seconds: 0, totalSeconds: 0, isExpired: true, isUnknown: false, urgency: 0 };
    }
    const totalSeconds = Math.floor(diff / 1000);
    const days = Math.floor(totalSeconds / 86400);
    const hours = Math.floor((totalSeconds % 86400) / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    let urgency = 0;
    if (totalSeconds < 3600) {
      urgency = 3;
    } else if (totalSeconds < 86400) {
      urgency = 2;
    } else if (totalSeconds < 604800) {
      urgency = 1;
    }
    return { days, hours, minutes, seconds, totalSeconds, isExpired: false, isUnknown: false, urgency };
  }

  static formatCountDown(now: number, beginTime: number): string {
    const parts = DateUtils.getCountdownParts(now, beginTime);
    if (parts.isUnknown) {
      return '时间未知';
    }
    if (parts.isExpired) {
      return '进行中或已结束';
    }
    if (parts.days > 0) {
      return `${parts.days}天${DateUtils.twoDigit(parts.hours)}时${DateUtils.twoDigit(parts.minutes)}分${DateUtils.twoDigit(parts.seconds)}秒`;
    }
    return `${DateUtils.twoDigit(parts.hours)}时${DateUtils.twoDigit(parts.minutes)}分${DateUtils.twoDigit(parts.seconds)}秒`;
  }
}
