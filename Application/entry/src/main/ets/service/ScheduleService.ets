import { ScheduleEvent, ScheduleUtils, ScheduleEventType } from '../model/ScheduleModel';
import { ScheduleRepository } from '../repository/ScheduleRepository';
import { CourseService } from './CourseService';
import { ExamService } from './ExamService';
import { Course, SECTION_TIMES, courseTableModel, getWeekForDate } from '../model/classTableModel/CourseModel';
import { ExamItem } from '../model/classTableModel/ExamModel';
import { CalendarKitReminderService } from './CalendarKitReminderService';
import { ExamUtils } from '../common/utils/ExamUtils';
import { calculateSemesterId } from '../model/classTableModel/ExamAccessRules';
import { parseIsoDateToMidnight } from '../model/SemesterConfig';

export class ScheduleService {
  static async loadCustomSchedules(context: Context, syncWithCalendar: boolean = true): Promise<ScheduleEvent[]> {
    try {
      const rawEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      if (!syncWithCalendar || rawEvents.length === 0) {
        return rawEvents;
      }
      return await ScheduleService.syncAndPruneSchedulesWithCalendar(context, rawEvents);
    } catch (error) {
      console.error('[ScheduleService] loadCustomSchedules error:', JSON.stringify(error));
      return [];
    }
  }

  /**
   * 与系统日历双向对齐：若用户在系统日历中删除了某个绑定日历的日程，自动从本地移除
   */
  static async syncAndPruneSchedulesWithCalendar(context: Context, events: ScheduleEvent[]): Promise<ScheduleEvent[]> {
    try {
      const hasPerm = await CalendarKitReminderService.checkCalendarPermission(context);
      if (!hasPerm) {
        return events;
      }

      const validEvents: ScheduleEvent[] = [];
      let hasPruned: boolean = false;

      for (let i = 0; i < events.length; i++) {
        const evt = events[i];
        // 仅针对标记为写入系统日历且有 calendarEventId 的自定义日程进行存活性探测
        if ((evt.type === 'custom' || evt.type === 'assignment') && evt.addToCalendar === true && evt.calendarEventId && evt.calendarEventId > 0) {
          const exists = await CalendarKitReminderService.checkEventExists(context, evt.calendarEventId);
          if (!exists) {
            console.info(`[ScheduleService] schedule id=${evt.id} (${evt.title}) was deleted in system calendar, pruning from app repository`);
            hasPruned = true;
            continue;
          }
        }
        validEvents.push(evt);
      }

      if (hasPruned) {
        await ScheduleRepository.saveSchedules(context, validEvents);
      }
      return validEvents;
    } catch (error) {
      console.warn('[ScheduleService] syncAndPruneSchedulesWithCalendar error:', JSON.stringify(error));
      return events;
    }
  }

  static async saveSchedule(context: Context, event: ScheduleEvent): Promise<void> {
    try {
      if (!event.id) {
        event.id = ScheduleUtils.generateId();
      }
      event.createdAt = event.createdAt || Date.now();
      event.color = event.color || ScheduleUtils.getTypeColor(event.type);

      // 若需要同步写入系统日历且尚未分配 calendarEventId，主动调用 CalendarKit 写入
      if (event.addToCalendar === true && (!event.calendarEventId || event.calendarEventId <= 0)) {
        const hasPerm = await CalendarKitReminderService.checkCalendarPermission(context);
        if (hasPerm) {
          const calId = await CalendarKitReminderService.addEventReminder(context, event, event.remindMinutes || 30);
          if (calId >= 0) {
            event.calendarEventId = calId;
          }
        }
      }

      console.info(`[ReminderDebug] ScheduleService.saveSchedule: id=${event.id}, title=${event.title}, date=${event.date}, startTime=${event.startTime}, endTime=${event.endTime}, timeRange=${event.timeRange}, remindMinutes=${event.remindMinutes}, type=${event.type}, calId=${event.calendarEventId}`);
      await ScheduleRepository.addSchedule(context, event);
      console.info(`[ReminderDebug] ScheduleService.saveSchedule: saved successfully`);
      // 学期守卫：日程变更后顺手清理越界的自动日程（幂等；仓库无自动日程候选时零额外 IO）
      await ScheduleService.pruneNonCurrentSemesterAutoSchedules(context);
    } catch (error) {
      console.error('[ScheduleService] saveSchedule error:', JSON.stringify(error));
    }
  }

  static async updateSchedule(context: Context, event: ScheduleEvent): Promise<void> {
    try {
      if (event.addToCalendar === true) {
        const hasPerm = await CalendarKitReminderService.checkCalendarPermission(context);
        if (hasPerm) {
          const calId = await CalendarKitReminderService.upsertEventReminder(context, event, event.remindMinutes || 30);
          if (calId >= 0) {
            event.calendarEventId = calId;
          }
        }
      } else if (event.addToCalendar === false && event.calendarEventId && event.calendarEventId > 0) {
        await CalendarKitReminderService.deleteEvent(context, event.calendarEventId);
        event.calendarEventId = 0;
      }
      await ScheduleRepository.updateSchedule(context, event);
      // 学期守卫：日程变更后顺手清理越界的自动日程（幂等）
      await ScheduleService.pruneNonCurrentSemesterAutoSchedules(context);
    } catch (error) {
      console.error('[ScheduleService] updateSchedule error:', JSON.stringify(error));
    }
  }

  static async deleteSchedule(context: Context, eventId: string): Promise<void> {
    try {
      const events: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const target: ScheduleEvent | undefined = events.find((e: ScheduleEvent) => e.id === eventId);
      if (target) {
        await CalendarKitReminderService.deleteEventBySchedule(context, target);
        console.info(`[ScheduleService] deleted calendar event for schedule=${eventId}`);
      }
      await ScheduleRepository.deleteSchedule(context, eventId);
      // 学期守卫：删除后顺手清理剩余越界的自动日程（被删条目已不在仓库，与上方日历清理天然不冲突）
      await ScheduleService.pruneNonCurrentSemesterAutoSchedules(context);
    } catch (error) {
      console.error('[ScheduleService] deleteSchedule error:', JSON.stringify(error));
    }
  }

  /**
   * 课程日程事件 id 统一拼装（日历页与实时构建共用，避免两处规则分叉）：
   * 课程id + 日期 + 起止节次，保证同日多时段同一课程（如 1-2 节与 5-6 节）
   * 以及不同日期的事件 id 互不相同。
   */
  static buildCourseEventId(courseId: string, dateStr: string, startSection: number, endSection: number): string {
    return 'course_' + courseId + '_' + dateStr + '_' + startSection + '_' + endSection;
  }

  static async buildCourseEvents(context: Context): Promise<ScheduleEvent[]> {
    const events: ScheduleEvent[] = [];
    try {
      const courses: Course[] = await CourseService.loadCourses(context);
      const now: Date = new Date();
      const monday: Date = ScheduleService.getMonday(now);
      // 与首页/桌面卡片口径对齐：仅当前教学周（validWeeks 命中）的课程生成日程
      const currentWeek: number = getWeekForDate(now);
      for (let i = 0; i < courses.length; i++) {
        const c: Course = courses[i];
        if (!courseTableModel.isValidForWeek(c, currentWeek)) {
          continue;
        }
        const targetDate: Date = new Date(monday.getTime() + (c.time.dayOfWeek - 1) * 24 * 60 * 60 * 1000);
        const dateStr: string = ScheduleUtils.formatDate(targetDate.getFullYear(), targetDate.getMonth() + 1, targetDate.getDate());
        const endSection: number = c.time.startSection + c.time.duration - 1;
        const startTime: string = SECTION_TIMES[c.time.startSection - 1]?.startTime || '8:30';
        const endTime: string = SECTION_TIMES[endSection - 1]?.endTime || '9:15';
        const timeStr: string = `${startTime}-${endTime}`;
        const evt: ScheduleEvent = {
          id: ScheduleService.buildCourseEventId(c.id, dateStr, c.time.startSection, endSection),
          title: c.name,
          date: dateStr,
          timeRange: timeStr,
          location: c.roomName,
          type: 'course' as ScheduleEventType,
          color: '#2196F3',
          sourceId: c.id,
          description: c.teacherName || '',
          createdAt: Date.now(),
        };
        events.push(evt);
      }
    } catch (error) {
      console.error('[ScheduleService] buildCourseEvents error:', JSON.stringify(error));
    }
    return events;
  }

  static async buildExamEvents(context: Context): Promise<ScheduleEvent[]> {
    const events: ScheduleEvent[] = [];
    try {
      const exams: ExamItem[] = await ExamService.loadExams(context);
      console.info(`[ExamDebug] buildExamEvents: loaded ${exams.length} exams from ExamService`);
      const currentSemesterId: number = calculateSemesterId();
      let skippedZeroTime = 0;
      let skippedOtherSemester = 0;
      let builtEvents = 0;
      for (let i = 0; i < exams.length; i++) {
        const e: ExamItem = exams[i];
        if (e.beginTime <= 0) {
          skippedZeroTime++;
          continue;
        }
        // 仅当前学期的考试自动生成日程（与展示侧 getAllEvents / 日历页口径一致）
        if (ExamUtils.resolveSemesterId(e) !== currentSemesterId) {
          skippedOtherSemester++;
          continue;
        }
        const examDate: Date = new Date(e.beginTime);
        const evt: ScheduleEvent = {
          id: 'exam_' + e.courseNo + '_' + e.beginTime,
          title: e.courseName + ' 考试',
          date: ScheduleUtils.formatDate(examDate.getFullYear(), examDate.getMonth() + 1, examDate.getDate()),
          timeRange: e.examTimeRange,
          location: e.examLocation,
          type: 'exam' as ScheduleEventType,
          color: '#F44336',
          sourceId: e.courseNo,
          description: e.seatNo || '',
          createdAt: Date.now(),
        };
        events.push(evt);
        builtEvents++;
      }
      console.info(`[ExamDebug] buildExamEvents: built=${builtEvents} skippedZeroTime=${skippedZeroTime} skippedOtherSemester=${skippedOtherSemester}`);
    } catch (error) {
      console.error('[ScheduleService] buildExamEvents error:', JSON.stringify(error));
    }
    return events;
  }

  static async checkTimeConflict(context: Context, newEvent: ScheduleEvent, excludeEventId?: string): Promise<boolean> {
    try {
      const allEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const newStartParts = newEvent.startTime?.split(':').map(Number);
      const newEndParts = newEvent.endTime?.split(':').map(Number);
      if (!newStartParts || !newEndParts) {
        return false;
      }
      const newStartMinutes: number = newStartParts[0] * 60 + newStartParts[1];
      const newEndMinutes: number = newEndParts[0] * 60 + newEndParts[1];
      if (newEndMinutes <= newStartMinutes) {
        return false;
      }
      for (let i = 0; i < allEvents.length; i++) {
        const evt = allEvents[i];
        if (evt.date !== newEvent.date) {
          continue;
        }
        if (excludeEventId && evt.id === excludeEventId) {
          continue;
        }
        const evtStartParts = evt.startTime?.split(':').map(Number);
        const evtEndParts = evt.endTime?.split(':').map(Number);
        if (!evtStartParts || !evtEndParts) {
          continue;
        }
        const evtStartMinutes: number = evtStartParts[0] * 60 + evtStartParts[1];
        const evtEndMinutes: number = evtEndParts[0] * 60 + evtEndParts[1];
        if (newStartMinutes < evtEndMinutes && newEndMinutes > evtStartMinutes) {
          return true;
        }
      }
      return false;
    } catch (error) {
      console.error('[ScheduleService] checkTimeConflict error:', JSON.stringify(error));
      return false;
    }
  }

  static async clearAutoGeneratedSchedules(context: Context): Promise<void> {
    try {
      const allEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const filtered: ScheduleEvent[] = [];
      let removedCount: number = 0;
      for (let i = 0; i < allEvents.length; i++) {
        const evt = allEvents[i];
        if ((evt.type === 'course' || evt.type === 'exam') && evt.sourceId && evt.sourceId.length > 0) {
          removedCount++;
          continue;
        }
        filtered.push(evt);
      }
      console.info(`[ReminderDebug] clearAutoGeneratedSchedules: removed ${removedCount} auto-generated schedules`);
      await ScheduleRepository.saveSchedules(context, filtered);
    } catch (error) {
      console.error('[ScheduleService] clearAutoGeneratedSchedules error:', JSON.stringify(error));
    }
  }

  /**
   * 学期守卫清理：剔除仓库中不属于当前学期的自动课程/考试日程，并联动清理其系统日历残留。
   * 保留口径与构建侧（buildCourseEvents / buildExamEvents）完全一致，避免清理比构建更严/更松造成互搏：
   * - course：sourceId 命中当前学期课程 id 集合，且事件日期教学周 ∈ [1, maxWeek]
   *   （maxWeek 与 CourseModel.getMaxWeekNumber 同公式：validWeeks.length - 1 的最大值。
   *   不额外做「日期不早于学期锚点」判断：开学前窗口内 getWeekForDate 钳位为第 1 周，
   *   buildCourseEvents 在该窗口同样会生成第 1 周日程，清理侧若更严会导致每次进入应用先删后建的互搏）；
   * - exam：事件 id ∈ 当前学期考试事件 id 集合（loadExams 过滤 resolveSemesterId === 当前学期
   *   且 beginTime > 0，按 exam_<courseNo>_<beginTime> 拼装，与 buildExamEvents 同规则）。
   * 幂等：可安全反复调用；无候选或无剔除时尽早返回，避免无谓 IO。
   */
  static async pruneNonCurrentSemesterAutoSchedules(context: Context): Promise<void> {
    try {
      const allEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const hasCandidates: boolean = allEvents.some((evt: ScheduleEvent) => ScheduleService.isAutoGeneratedSchedule(evt));
      if (!hasCandidates) {
        return;
      }

      // 课程保留集合：当前学期课程 id + 有效教学周上限（与 getMaxWeekNumber 同公式）
      const courses: Course[] = await CourseService.loadCourses(context);
      const courseIds: Set<string> = new Set<string>();
      let maxWeek: number = 1;
      for (let i = 0; i < courses.length; i++) {
        courseIds.add(courses[i].id);
        const validWeeks: string = courses[i].validWeeks;
        if (validWeeks && validWeeks.length > 1) {
          maxWeek = Math.max(maxWeek, validWeeks.length - 1);
        }
      }

      // 考试保留集合：当前学期且 beginTime 有效的考试事件 id
      const exams: ExamItem[] = await ExamService.loadExams(context);
      const currentSemesterId: number = calculateSemesterId();
      const examEventIds: Set<string> = new Set<string>();
      for (let i = 0; i < exams.length; i++) {
        const e: ExamItem = exams[i];
        if (e.beginTime <= 0 || ExamUtils.resolveSemesterId(e) !== currentSemesterId) {
          continue;
        }
        examEventIds.add('exam_' + e.courseNo + '_' + e.beginTime);
      }

      const kept: ScheduleEvent[] = [];
      const removed: ScheduleEvent[] = [];
      for (let i = 0; i < allEvents.length; i++) {
        const evt = allEvents[i];
        if (ScheduleService.isAutoGeneratedSchedule(evt)
          && !ScheduleService.belongsToCurrentSemester(evt, courseIds, maxWeek, examEventIds)) {
          removed.push(evt);
        } else {
          kept.push(evt);
        }
      }

      if (removed.length === 0) {
        return;
      }

      // 先联动清理系统日历残留（按 id 删 + 标题/时间窗兜底删），再从本地仓库剔除写回
      for (let i = 0; i < removed.length; i++) {
        await CalendarKitReminderService.deleteEventBySchedule(context, removed[i]);
      }
      await ScheduleRepository.saveSchedules(context, kept);
      console.info(`[ScheduleService] pruneNonCurrentSemesterAutoSchedules: pruned=${removed.length} kept=${kept.length}`);
    } catch (error) {
      console.error('[ScheduleService] pruneNonCurrentSemesterAutoSchedules error:', JSON.stringify(error));
    }
  }

  /** 是否为自动生成的课程/考试日程（带 sourceId），与 clearAutoGeneratedSchedules / pushUniqueEvent 同口径 */
  private static isAutoGeneratedSchedule(evt: ScheduleEvent): boolean {
    const hasSourceId: boolean = evt.sourceId !== undefined && evt.sourceId.length > 0;
    return (evt.type === 'course' || evt.type === 'exam') && hasSourceId;
  }

  /** 判定自动日程是否属于当前学期（保留口径与构建侧一致，见 pruneNonCurrentSemesterAutoSchedules 注释） */
  private static belongsToCurrentSemester(evt: ScheduleEvent, courseIds: Set<string>, maxWeek: number, examEventIds: Set<string>): boolean {
    if (evt.type === 'exam') {
      return examEventIds.has(evt.id);
    }
    // course：sourceId 命中当前学期课程，且事件日期教学周落在 [1, maxWeek]
    const evtDate: Date | null = parseIsoDateToMidnight(evt.date);
    if (evtDate === null) {
      // 非法日期不可能由构建侧产生，剔除不会与构建互搏
      return false;
    }
    const week: number = getWeekForDate(evtDate);
    return week >= 1 && week <= maxWeek && courseIds.has(evt.sourceId);
  }

  static async getAllEvents(context: Context): Promise<ScheduleEvent[]> {
    const all: ScheduleEvent[] = [];
    const seenIds: Set<string> = new Set<string>();
    const seenAutoKeys: Set<string> = new Set<string>();
    try {
      const courseEvents: ScheduleEvent[] = await ScheduleService.buildCourseEvents(context);
      const examEvents: ScheduleEvent[] = await ScheduleService.buildExamEvents(context);
      const customEvents: ScheduleEvent[] = await ScheduleService.loadCustomSchedules(context);
      for (let i = 0; i < courseEvents.length; i++) {
        ScheduleService.pushUniqueEvent(all, seenIds, seenAutoKeys, courseEvents[i]);
      }
      for (let i = 0; i < examEvents.length; i++) {
        ScheduleService.pushUniqueEvent(all, seenIds, seenAutoKeys, examEvents[i]);
      }
      for (let i = 0; i < customEvents.length; i++) {
        ScheduleService.pushUniqueEvent(all, seenIds, seenAutoKeys, customEvents[i]);
      }
    } catch (error) {
      console.error('[ScheduleService] getAllEvents error:', JSON.stringify(error));
    }
    return all;
  }

  /**
   * getAllEvents 去重入队：
   * - 所有事件先按 id 去重，实时构建的课程/考试事件排在前、优先保留，
   *   丢弃仓库遗留的同 id 自动事件（syncCourses/syncExams 每次回前台都会持久化一份，
   *   不去重会导致发现页今日日程数与 AI 查询计数偏大）；
   * - 仓库侧自动课程/考试事件（type 为 course/exam 且带 sourceId）额外按
   *   「类型|日期|时间段|标题」语义键兜底去重，兼容历史版本持久化的旧 id 格式遗留数据；
   * - 用户手动创建的 sch_/custom/assignment 事件（无 sourceId）不受影响。
   */
  private static pushUniqueEvent(all: ScheduleEvent[], seenIds: Set<string>, seenAutoKeys: Set<string>, evt: ScheduleEvent): void {
    if (seenIds.has(evt.id)) {
      return;
    }
    const hasSourceId: boolean = evt.sourceId !== undefined && evt.sourceId.length > 0;
    const isAutoGenerated: boolean = (evt.type === 'course' || evt.type === 'exam') && hasSourceId;
    if (isAutoGenerated) {
      const semanticKey: string = evt.type + '|' + evt.date + '|' + evt.timeRange + '|' + evt.title;
      if (seenAutoKeys.has(semanticKey)) {
        return;
      }
      seenAutoKeys.add(semanticKey);
    }
    seenIds.add(evt.id);
    all.push(evt);
  }

  static getMonday(date: Date): Date {
    const d: Date = new Date(date);
    const day: number = d.getDay();
    const diff: number = day === 0 ? -6 : 1 - day;
    d.setDate(d.getDate() + diff);
    d.setHours(0, 0, 0, 0);
    return d;
  }

  static async removeExpiredSchedules(context: Context): Promise<void> {
    try {
      const existingEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const todayStr: string = ScheduleUtils.formatDate(new Date().getFullYear(), new Date().getMonth() + 1, new Date().getDate());
      const valid: ScheduleEvent[] = [];
      for (let i = 0; i < existingEvents.length; i++) {
        if (existingEvents[i].date >= todayStr) {
          valid.push(existingEvents[i]);
        }
      }
      const removedCount: number = existingEvents.length - valid.length;
      if (removedCount > 0) {
        console.info(`[ReminderDebug] removeExpiredSchedules: removed ${removedCount} expired schedules`);
        await ScheduleRepository.saveSchedules(context, valid);
      }
    } catch (error) {
      console.error('[ScheduleService] removeExpiredSchedules error:', JSON.stringify(error));
    }
  }

  static async syncCoursesToSchedule(context: Context): Promise<void> {
    try {
      await ScheduleService.removeExpiredSchedules(context);
      const existingEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const filtered: ScheduleEvent[] = [];
      for (let i = 0; i < existingEvents.length; i++) {
        if (existingEvents[i].type !== 'course' || !existingEvents[i].sourceId) {
          filtered.push(existingEvents[i]);
        }
      }
      const courseEvents: ScheduleEvent[] = await ScheduleService.buildCourseEvents(context);
      const todayStr: string = ScheduleUtils.formatDate(new Date().getFullYear(), new Date().getMonth() + 1, new Date().getDate());
      for (let i = 0; i < courseEvents.length; i++) {
        if (courseEvents[i].date === todayStr) {
          filtered.push(courseEvents[i]);
        }
      }
      await ScheduleRepository.saveSchedules(context, filtered);
    } catch (error) {
      console.error('[ScheduleService] syncCoursesToSchedule error:', JSON.stringify(error));
    }
  }

  static async syncExamsToSchedule(context: Context): Promise<void> {
    try {
      await ScheduleService.removeExpiredSchedules(context);
      const existingEvents: ScheduleEvent[] = await ScheduleRepository.loadSchedules(context);
      const filtered: ScheduleEvent[] = [];
      for (let i = 0; i < existingEvents.length; i++) {
        if (existingEvents[i].type !== 'exam' || !existingEvents[i].sourceId) {
          filtered.push(existingEvents[i]);
        }
      }
      const examEvents: ScheduleEvent[] = await ScheduleService.buildExamEvents(context);
      const todayStr: string = ScheduleUtils.formatDate(new Date().getFullYear(), new Date().getMonth() + 1, new Date().getDate());
      let addedCount: number = 0;
      let skippedPastCount: number = 0;
      for (let i = 0; i < examEvents.length; i++) {
        if (examEvents[i].date >= todayStr) {
          filtered.push(examEvents[i]);
          addedCount++;
        } else {
          skippedPastCount++;
          console.info(`[ExamDebug] syncExamsToSchedule: SKIPPED past exam date=${examEvents[i].date} title=${examEvents[i].title} today=${todayStr}`);
        }
      }
      console.info(`[ExamDebug] syncExamsToSchedule: today=${todayStr} built=${examEvents.length} added=${addedCount} skippedPast=${skippedPastCount}`);
      await ScheduleRepository.saveSchedules(context, filtered);
    } catch (error) {
      console.error('[ScheduleService] syncExamsToSchedule error:', JSON.stringify(error));
    }
  }
}
