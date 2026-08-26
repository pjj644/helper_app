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
  // P2-7b：本地最后变更时间（epoch ms），由 ExamRepository 集中盖章维护；缺失/0 表示未知（旧数据）
  updatedAt?: number;
}

// ==================== 条目级 LWW / 盖章共用工具（P2-7b，纯 TS） ====================

/**
 * 考试业务键。任务口径为 (courseNo, examDate, examTimeRange, examType)；
 * 额外并入 normalizedSemesterId：云端记录 ID 的确定性哈希含学期维度，
 * 不同学期可能出现同 (courseNo+日期+时段+类型) 的两场考试，不并学期会互相误覆盖。
 */
export function getExamBizKey(
  semesterId: number,
  courseNo: string,
  examDate: string,
  examTimeRange: string,
  examType: string
): string {
  return `${semesterId}|${courseNo}|${examDate}|${examTimeRange}|${examType}`;
}

/**
 * 考试内容比较键：与 SyncService.examChanged 的比较维度对齐
 * （examDate/examTimeRange 属业务键维度不重复参与；courseName/remark 虽不在
 * examChanged 中，但属于用户可见内容，变化也应触发盖章/LWW）。
 */
export function getExamContentKey(
  courseName: string,
  examLocation: string,
  seatNo: string,
  examStatus: string,
  remark: string
): string {
  return [courseName, examLocation, seatNo, examStatus, remark].join('#@#');
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

  const timeMatch: RegExpMatchArray | null = range.match(/(\d{1,2}:\d{2})-(\d{1,2}:\d{2})/);
  if (timeMatch) {
    const begin = new Date(`${date} ${timeMatch[1]}`).getTime();
    const end = new Date(`${date} ${timeMatch[2]}`).getTime();
    return {
      begin: Number.isNaN(begin) ? 0 : begin,
      end: Number.isNaN(end) ? 0 : end,
    };
  }

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

export function normalizeExam(input: ExamInput): ExamItem {
  const dateText: string = normalizeExamDate(input.examDate || '');
  const timeRange: string = input.examTimeRange || '未知';
  const parsed = parseDateTime(dateText, timeRange);
  return {
    courseNo: input.courseNo || '未知',
    courseName: input.courseName || '',
    examDate: dateText,
    examTimeRange: timeRange,
    examLocation: input.examLocation || '未知',
    seatNo: input.seatNo || '未知',
    examStatus: input.examStatus || '未知',
    examType: input.examType || '未知',
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
