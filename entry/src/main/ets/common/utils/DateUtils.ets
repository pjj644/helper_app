export interface DateTimeRange {
  begin: number;
  end: number;
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
      return { begin: 0, end: 0 };
    }

    const begin = new Date(`${date} ${parts[0]}`).getTime();
    const end = new Date(`${date} ${parts[1]}`).getTime();
    return {
      begin: Number.isNaN(begin) ? 0 : begin,
      end: Number.isNaN(end) ? 0 : end,
    };
  }

  static formatCountDown(now: number, beginTime: number): string {
    if (beginTime <= 0) {
      return '时间未知';
    }
    const diff = beginTime - now;
    if (diff <= 0) {
      return '进行中或已结束';
    }
    const day = Math.floor(diff / (24 * 60 * 60 * 1000));
    const hour = Math.floor((diff % (24 * 60 * 60 * 1000)) / (60 * 60 * 1000));
    const minute = Math.floor((diff % (60 * 60 * 1000)) / (60 * 1000));
    if (day > 0) {
      return `${day}天${hour}小时${minute}分钟`;
    }
    return `${hour}小时${minute}分钟`;
  }
}
