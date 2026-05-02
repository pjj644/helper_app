import { Course } from '../../model/classTableModel/CourseModel';

export class ReminderUtils {
  static buildReminderTitle(course: Course): string {
    let location: string = course.roomName.trim();
    if (location) {
      return `【${course.name}】即将开始 - ${location}`;
    }
    return `【${course.name}】即将开始`;
  }

  static isSchoolDay(date: Date): boolean {
    const day: number = date.getDay();
    return day >= 1 && day <= 5;
  }

  static getSchoolDaysForWeek(courses: Course[]): Set<number> {
    const days: Set<number> = new Set<number>();
    for (let i = 0; i < courses.length; i++) {
      days.add(courses[i].time.dayOfWeek);
    }
    return days;
  }

  static minutesToMillis(minutes: number): number {
    return minutes * 60 * 1000;
  }
}
