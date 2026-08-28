import { ExamItem } from '../classTableModel/ExamModel';
import { BusItem, BusScheduleModel, NextBusInfo } from '../BusScheduleModel';

/** preferences 中 next_course_cache 的存储形态（与 CourseService.updateNextCourseCache 写入对齐） */
interface NextCourseCacheData {
  name?: string;
  courseName?: string;
  location?: string;
  time?: string;
  room?: string;
  countdownText?: string;
  hasCourseToday?: boolean;
  dateStr?: string;
  courseCount?: number;
  course1_name?: string;
  course1_time?: string;
  course1_room?: string;
  course1_status?: string;
  course2_name?: string;
  course2_time?: string;
  course2_room?: string;
  course2_status?: string;
  course3_name?: string;
  course3_time?: string;
  course3_room?: string;
  course3_status?: string;
}

/** BusDataService 持久化的班车 last-good 数据包（与 service/BusDataService 写入对齐） */
interface BusScheduleEnvelope {
  updatedAt?: number;
  generatedAt?: string;
  items?: BusItem[];
}

/**
 * 桌面卡片统一数据模型（纯 TS，严禁 @kit 导入）。
 *
 * 三张卡片（课程/考试/班车）的全部展示字段在此一次性构建：
 * - 课程卡片沿用 CourseService 预计算的 next_course_cache（时间敏感，事件驱动更新）；
 * - 考试/班车数据量小且变动低频，改为「读取时基于原始存储数据 + 当前时间实时计算」，
 *   每次卡片定时刷新（updateDuration）都会拿到准确的倒计时，无需额外的缓存失效钩子。
 */
export class WidgetDataModel {
  /**
   * 构建所有卡片共用的一份 formData。
   * 各卡片组件只通过 @LocalStorageProp 订阅自己关心的键，多余键会被忽略。
   */
  static buildFullWidgetData(
    courseCacheJson: string,
    examDataJson: string,
    remoteBusJson: string,
    now: Date
  ): Record<string, Object> {
    const data: Record<string, Object> = {};
    WidgetDataModel.copyInto(data, WidgetDataModel.buildCourseSection(courseCacheJson));
    WidgetDataModel.copyInto(data, WidgetDataModel.buildExamSection(examDataJson, now.getTime()));
    WidgetDataModel.copyInto(data, WidgetDataModel.buildBusSection(remoteBusJson, now));
    return data;
  }

  /** 逐键拷贝（ArkTS 限制使用 Object.assign） */
  private static copyInto(target: Record<string, Object>, source: Record<string, Object>): void {
    const keys: string[] = Object.keys(source);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      target[key] = source[key];
    }
  }

  // ==================== 课程卡片（沿用预计算缓存） ====================

  private static buildCourseSection(courseCacheJson: string): Record<string, Object> {
    const data: Record<string, Object> = {
      'courseName': '暂无待上课程',
      'location': '教室未定',
      'time': '--:--',
      'room': '今日已无课',
      'countdownText': '今日已无课',
      'hasCourseToday': false,
      'dateStr': '今日课表',
      'courseCount': 0,
      'course1_name': '',
      'course1_time': '',
      'course1_room': '',
      'course1_status': '',
      'course2_name': '',
      'course2_time': '',
      'course2_room': '',
      'course2_status': '',
      'course3_name': '',
      'course3_time': '',
      'course3_room': '',
      'course3_status': ''
    };
    if (!courseCacheJson) {
      return data;
    }
    try {
      const parsed = JSON.parse(courseCacheJson) as NextCourseCacheData;
      data['courseName'] = parsed.courseName || parsed.name || '暂无待上课程';
      data['location'] = parsed.location || parsed.room || '教室未定';
      data['time'] = parsed.time || '--:--';
      data['room'] = parsed.room || '教室未定';
      data['countdownText'] = parsed.countdownText || '今日已无课';
      data['hasCourseToday'] = parsed.hasCourseToday !== undefined ? parsed.hasCourseToday : false;
      data['dateStr'] = parsed.dateStr || '今日课表';
      data['courseCount'] = parsed.courseCount !== undefined ? parsed.courseCount : 0;
      for (let idx = 1; idx <= 3; idx++) {
        const suffix = `course${idx}`;
        const keyed = parsed as Record<string, string | undefined>;
        data[`${suffix}_name`] = keyed[`${suffix}_name`] || '';
        data[`${suffix}_time`] = keyed[`${suffix}_time`] || '';
        data[`${suffix}_room`] = keyed[`${suffix}_room`] || '';
        data[`${suffix}_status`] = keyed[`${suffix}_status`] || '';
      }
    } catch (e) {
      // 缓存 JSON 非法时保留默认值，不让单张卡片的数据异常影响其他卡片
    }
    return data;
  }

  // ==================== 考试卡片（读取时实时计算） ====================

  private static buildExamSection(examDataJson: string, now: number): Record<string, Object> {
    const data: Record<string, Object> = {
      'examHasUpcoming': false,
      'examUrgent': false,
      'examCount': 0,
      'examName': '暂无考试安排',
      'examDate': '',
      'examTime': '',
      'examLocation': '',
      'examCountdown': '好好休息',
      'exam1_name': '',
      'exam1_date': '',
      'exam1_time': '',
      'exam1_location': '',
      'exam1_countdown': '',
      'exam2_name': '',
      'exam2_date': '',
      'exam2_time': '',
      'exam2_location': '',
      'exam2_countdown': '',
      'exam3_name': '',
      'exam3_date': '',
      'exam3_time': '',
      'exam3_location': '',
      'exam3_countdown': ''
    };
    if (!examDataJson) {
      return data;
    }
    let exams: ExamItem[];
    try {
      exams = JSON.parse(examDataJson) as ExamItem[];
    } catch (e) {
      return data;
    }
    if (!exams || exams.length === 0) {
      return data;
    }

    const upcoming: ExamItem[] = [];
    for (let i = 0; i < exams.length; i++) {
      const item = exams[i];
      if (item && item.beginTime > now) {
        upcoming.push(item);
      }
    }
    upcoming.sort((a: ExamItem, b: ExamItem) => a.beginTime - b.beginTime);

    data['examCount'] = upcoming.length;
    if (upcoming.length === 0) {
      return data;
    }

    const first = upcoming[0];
    data['examHasUpcoming'] = true;
    data['examUrgent'] = WidgetDataModel.isExamUrgent(first, now);
    data['examName'] = first.courseName || '未命名考试';
    data['examDate'] = WidgetDataModel.formatExamDate(first.examDate);
    data['examTime'] = first.examTimeRange || '';
    data['examLocation'] = first.examLocation || '地点待定';
    data['examCountdown'] = WidgetDataModel.examCountdownText(first, now);

    for (let idx = 1; idx <= 3; idx++) {
      const exam = upcoming[idx - 1];
      if (!exam) {
        break;
      }
      data[`exam${idx}_name`] = exam.courseName || '未命名考试';
      data[`exam${idx}_date`] = WidgetDataModel.formatExamDate(exam.examDate);
      data[`exam${idx}_time`] = exam.examTimeRange || '';
      data[`exam${idx}_location`] = exam.examLocation || '地点待定';
      data[`exam${idx}_countdown`] = WidgetDataModel.examCountdownText(exam, now);
    }
    return data;
  }

  /** 距考试 3 天内（含今天/明天/进行中）视为紧急，卡片用强调色渲染 */
  private static isExamUrgent(exam: ExamItem, now: number): boolean {
    const dayMs = 24 * 60 * 60 * 1000;
    const beginDay = Math.floor(exam.beginTime / dayMs);
    const todayDay = Math.floor(now / dayMs);
    if (beginDay <= todayDay) {
      return true;
    }
    return beginDay - todayDay <= 3;
  }

  /** 天粒度倒计时文案：进行中 / 今天 / 明天 / N 天后 */
  private static examCountdownText(exam: ExamItem, now: number): string {
    const end = exam.endTime > exam.beginTime ? exam.endTime : exam.beginTime;
    if (now >= exam.beginTime && now < end) {
      return '进行中';
    }
    const dayMs = 24 * 60 * 60 * 1000;
    const beginDay = Math.floor(exam.beginTime / dayMs);
    const todayDay = Math.floor(now / dayMs);
    if (beginDay === todayDay) {
      return '今天';
    }
    if (beginDay === todayDay + 1) {
      return '明天';
    }
    return `${beginDay - todayDay} 天后`;
  }

  /** 'YYYY-MM-DD' → 'M月D日'；其他格式原样返回 */
  private static formatExamDate(examDate: string): string {
    const text = examDate.trim();
    const match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(text);
    if (match && match[2] !== undefined && match[3] !== undefined) {
      return `${Number.parseInt(match[2], 10)}月${Number.parseInt(match[3], 10)}日`;
    }
    return text;
  }

  // ==================== 班车卡片（读取时实时计算） ====================

  private static buildBusSection(remoteBusJson: string, now: Date): Record<string, Object> {
    const isWeekend = BusScheduleModel.isWeekendDay(now);
    const data: Record<string, Object> = {
      'busDayType': isWeekend ? '周末' : '工作日',
      'busHasSchedule': false,
      'bus1_label': '清水河 ➔ 沙河',
      'bus1_time': '--:--',
      'bus1_countdown': '暂无班次',
      'bus1_type': '',
      'bus2_label': '沙河 ➔ 清水河',
      'bus2_time': '--:--',
      'bus2_countdown': '暂无班次',
      'bus2_type': ''
    };

    const remoteItems: BusItem[] = WidgetDataModel.parseRemoteBusItems(remoteBusJson);
    const tomorrowIsWeekend = BusScheduleModel.isWeekendDay(new Date(now.getTime() + 24 * 60 * 60 * 1000));
    const directions: ('qsh' | 'sh')[] = ['qsh', 'sh'];

    for (let i = 0; i < directions.length; i++) {
      const departure = directions[i];
      const idx = i + 1;
      const todayList = WidgetDataModel.effectiveBusList(remoteItems, departure, isWeekend);
      const tomorrowList = WidgetDataModel.effectiveBusList(remoteItems, departure, tomorrowIsWeekend);
      const next: NextBusInfo | null = BusScheduleModel.getNextBusInfo(todayList, tomorrowList, now);
      if (next === null) {
        continue;
      }
      data['busHasSchedule'] = true;
      data[`bus${idx}_label`] = `${WidgetDataModel.campusShort(next.busItem.departure)} ➔ ${WidgetDataModel.campusShort(next.busItem.destination)}`;
      data[`bus${idx}_time`] = next.time;
      data[`bus${idx}_type`] = next.busItem.busType || '';
      data[`bus${idx}_countdown`] = next.isTomorrow
        ? `明日首班 ${next.time}`
        : (next.minutesLeft <= 0 ? '即将发车' : `${next.minutesLeft} 分钟后`);
    }
    return data;
  }

  private static campusShort(code: string): string {
    return code === 'qsh' ? '清水河' : '沙河';
  }

  /** 班次生效列表：远端 last-good 命中该方向则用远端，否则回退内置兜底表（与 BusDataService 同口径） */
  private static effectiveBusList(remoteItems: BusItem[], departure: 'qsh' | 'sh', isWeekend: boolean): BusItem[] {
    const filtered: BusItem[] = [];
    for (let i = 0; i < remoteItems.length; i++) {
      const item = remoteItems[i];
      if (item.departure === departure && item.isWeekend === isWeekend) {
        filtered.push(item);
      }
    }
    return filtered.length > 0 ? filtered : BusScheduleModel.getBusList(departure, isWeekend);
  }

  /** 解析 BusDataService 持久化的 last-good 信封；结构非法时返回空数组（走内置兜底） */
  private static parseRemoteBusItems(remoteBusJson: string): BusItem[] {
    if (!remoteBusJson) {
      return [];
    }
    try {
      const envelope = JSON.parse(remoteBusJson) as BusScheduleEnvelope;
      const items = envelope.items;
      if (!items || !Array.isArray(items)) {
        return [];
      }
      const valid: BusItem[] = [];
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (item && /^\d{2}:\d{2}$/.test(item.time)
          && (item.departure === 'qsh' || item.departure === 'sh')
          && (item.destination === 'qsh' || item.destination === 'sh')
          && item.departure !== item.destination) {
          valid.push(item);
        }
      }
      return valid;
    } catch (e) {
      return [];
    }
  }
}
