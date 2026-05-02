import { ScheduleEvent, ScheduleUtils, ScheduleEventType } from '../model/ScheduleModel';
import { ScheduleRepository } from '../repository/ScheduleRepository';
import { CourseService } from './CourseService';
import { ExamService } from './ExamService';
import { Course } from '../model/classTableModel/CourseModel';
import { ExamItem } from '../model/classTableModel/ExamModel';

export class ScheduleService {
  static async loadCustomSchedules(context: Context): Promise<ScheduleEvent[]> {
    try {
      return await ScheduleRepository.loadSchedules(context);
    } catch (error) {
      console.error('ScheduleService loadCustomSchedules error:', JSON.stringify(error));
      return [];
    }
  }

  static async saveSchedule(context: Context, event: ScheduleEvent): Promise<void> {
    try {
      if (!event.id) {
        event.id = ScheduleUtils.generateId();
      }
      event.createdAt = event.createdAt || Date.now();
      event.color = event.color || ScheduleUtils.getTypeColor(event.type);
      console.info(`[ReminderDebug] ScheduleService.saveSchedule: id=${event.id}, title=${event.title}, date=${event.date}, startTime=${event.startTime}, endTime=${event.endTime}, timeRange=${event.timeRange}, remindMinutes=${event.remindMinutes}, type=${event.type}`);
      await ScheduleRepository.addSchedule(context, event);
      console.info(`[ReminderDebug] ScheduleService.saveSchedule: saved successfully`);
    } catch (error) {
      console.error('ScheduleService saveSchedule error:', JSON.stringify(error));
    }
  }

  static async updateSchedule(context: Context, event: ScheduleEvent): Promise<void> {
    try {
      await ScheduleRepository.updateSchedule(context, event);
    } catch (error) {
      console.error('ScheduleService updateSchedule error:', JSON.stringify(error));
    }
  }

  static async deleteSchedule(context: Context, eventId: string): Promise<void> {
    try {
      await ScheduleRepository.deleteSchedule(context, eventId);
    } catch (error) {
      console.error('ScheduleService deleteSchedule error:', JSON.stringify(error));
    }
  }

  static async buildCourseEvents(context: Context): Promise<ScheduleEvent[]> {
    const events: ScheduleEvent[] = [];
    try {
      const courses: Course[] = await CourseService.loadCourses(context);
      const monday: Date = ScheduleService.getMonday(new Date());
      for (let i = 0; i < courses.length; i++) {
        const c: Course = courses[i];
        const targetDate: Date = new Date(monday);
        targetDate.setDate(monday.getDate() + c.time.dayOfWeek - 1);
        const sectionMins: number = (c.time.startSection - 1) * 45 + Math.floor((c.time.startSection - 1) / 2) * 10;
        const startMins: number = 8 * 60 + sectionMins;
        const startHour: number = Math.floor(startMins / 60);
        const startMin: number = startMins % 60;
        const endMins: number = startMins + c.time.duration * 45 + Math.floor(c.time.duration / 2) * 10;
        const endHour: number = Math.floor(endMins / 60);
        const endMin: number = endMins % 60;
        const timeStr: string = `${ScheduleUtils.twoDigit(startHour)}:${ScheduleUtils.twoDigit(startMin)}-${ScheduleUtils.twoDigit(endHour)}:${ScheduleUtils.twoDigit(endMin)}`;
        const evt: ScheduleEvent = {
          id: 'course_' + c.id,
          title: c.name,
          date: ScheduleUtils.formatDate(targetDate.getFullYear(), targetDate.getMonth() + 1, targetDate.getDate()),
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
      console.error('ScheduleService buildCourseEvents error:', JSON.stringify(error));
    }
    return events;
  }

  static async buildExamEvents(context: Context): Promise<ScheduleEvent[]> {
    const events: ScheduleEvent[] = [];
    try {
      const exams: ExamItem[] = await ExamService.loadExams(context);
      for (let i = 0; i < exams.length; i++) {
        const e: ExamItem = exams[i];
        if (e.beginTime <= 0) {
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
      }
    } catch (error) {
      console.error('ScheduleService buildExamEvents error:', JSON.stringify(error));
    }
    return events;
  }

  static async getAllEvents(context: Context): Promise<ScheduleEvent[]> {
    const all: ScheduleEvent[] = [];
    try {
      const courseEvents: ScheduleEvent[] = await ScheduleService.buildCourseEvents(context);
      const examEvents: ScheduleEvent[] = await ScheduleService.buildExamEvents(context);
      const customEvents: ScheduleEvent[] = await ScheduleService.loadCustomSchedules(context);
      for (let i = 0; i < courseEvents.length; i++) {
        all.push(courseEvents[i]);
      }
      for (let i = 0; i < examEvents.length; i++) {
        all.push(examEvents[i]);
      }
      for (let i = 0; i < customEvents.length; i++) {
        all.push(customEvents[i]);
      }
    } catch (error) {
      console.error('ScheduleService getAllEvents error:', JSON.stringify(error));
    }
    return all;
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
      console.error('ScheduleService removeExpiredSchedules error:', JSON.stringify(error));
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
      console.error('ScheduleService syncCoursesToSchedule error:', JSON.stringify(error));
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
      let nearestExamDate: string = '';
      for (let i = 0; i < examEvents.length; i++) {
        if (examEvents[i].date >= todayStr) {
          if (nearestExamDate === '' || examEvents[i].date < nearestExamDate) {
            nearestExamDate = examEvents[i].date;
          }
        }
      }
      console.info(`[ReminderDebug] syncExamsToSchedule: today=${todayStr}, nearestExamDate=${nearestExamDate}`);
      if (nearestExamDate !== '') {
        for (let i = 0; i < examEvents.length; i++) {
          if (examEvents[i].date === nearestExamDate) {
            filtered.push(examEvents[i]);
          }
        }
      }
      await ScheduleRepository.saveSchedules(context, filtered);
    } catch (error) {
      console.error('ScheduleService syncExamsToSchedule error:', JSON.stringify(error));
    }
  }
}
