export interface ExamItem {
  courseNo: string;
  courseName: string;
  examDate: string;
  examTimeRange: string;
  examLocation: string;
  seatNo: string;
  examStatus: string;
  examType: string;
  remark: string;
  semesterId: number;
  semesterLabel: string;
  beginTime: number;
  endTime: number;
}

export function createEmptyExam(): ExamItem {
  return {
    courseNo: '',
    courseName: '',
    examDate: '',
    examTimeRange: '',
    examLocation: '',
    seatNo: '',
    examStatus: '',
    examType: '',
    remark: '',
    semesterId: 0,
    semesterLabel: '',
    beginTime: 0,
    endTime: 0,
  };
}

interface DateTimeRange {
  begin: number;
  end: number;
}

export interface ExamInput {
  courseNo?: string;
  courseName?: string;
  examDate?: string;
  examTimeRange?: string;
  examLocation?: string;
  seatNo?: string;
  examStatus?: string;
  examType?: string;
  remark?: string;
  semesterId?: number;
  semesterLabel?: string;
  beginTime?: number;
  endTime?: number;
}

function twoDigit(value: number): string {
  return value < 10 ? `0${value}` : String(value);
}

export function normalizeExamDate(dateText: string): string {
  const raw: string = (dateText || '').trim();
  if (!raw) {
    return '';
  }

  let matched: RegExpMatchArray | null = raw.match(/(\d{4})[\/.\-](\d{1,2})[\/.\-](\d{1,2})/);
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
  return `${year}-${twoDigit(month)}-${twoDigit(day)}`;
}

function parseDateTime(dateText: string, timeRange: string): DateTimeRange {
  const date: string = normalizeExamDate(dateText);
  const range: string = timeRange.replace(/\s+/g, '')
    .replace(/~/g, '-')
    .replace(/～/g, '-')
    .replace(/—/g, '-')
    .replace(/－/g, '-');
  const parts: string[] = range.split('-');
  if (parts.length !== 2) {
    const emptyRange: DateTimeRange = { begin: 0, end: 0 };
    return emptyRange;
  }

  const begin = new Date(`${date} ${parts[0]}`).getTime();
  const end = new Date(`${date} ${parts[1]}`).getTime();
  const rangeResult: DateTimeRange = {
    begin: Number.isNaN(begin) ? 0 : begin,
    end: Number.isNaN(end) ? 0 : end,
  };
  return rangeResult;
}

export function normalizeExam(input: ExamInput): ExamItem {
  const dateText: string = normalizeExamDate(input.examDate || '');
  const timeRange: string = input.examTimeRange || '';
  const parsed = parseDateTime(dateText, timeRange);
  return {
    courseNo: input.courseNo || '',
    courseName: input.courseName || '',
    examDate: dateText,
    examTimeRange: timeRange,
    examLocation: input.examLocation || '',
    seatNo: input.seatNo || '',
    examStatus: input.examStatus || '',
    examType: input.examType || '',
    remark: input.remark || '',
    semesterId: input.semesterId && input.semesterId > 0 ? input.semesterId : 0,
    semesterLabel: input.semesterLabel || '',
    beginTime: input.beginTime && input.beginTime > 0 ? input.beginTime : parsed.begin,
    endTime: input.endTime && input.endTime > 0 ? input.endTime : parsed.end,
  };
}

export function sortExams(items: ExamItem[]): ExamItem[] {
  const copied: ExamItem[] = [...items];
  copied.sort((a, b) => {
    if (a.beginTime === 0 && b.beginTime === 0) {
      return a.courseName.localeCompare(b.courseName);
    }
    if (a.beginTime === 0) {
      return 1;
    }
    if (b.beginTime === 0) {
      return -1;
    }
    return a.beginTime - b.beginTime;
  });
  return copied;
}

export function formatCountDown(now: number, beginTime: number): string {
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
