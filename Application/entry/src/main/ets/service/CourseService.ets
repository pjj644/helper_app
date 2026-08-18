import { Course, CourseTableModel, courseTableModel, RawActivity, RawCourseTableData, getCurrentWeek, SECTION_TIMES } from '../model/classTableModel/CourseModel';
import { CourseRepository } from '../repository/CourseRepository';
import { calculateSemesterId } from '../model/classTableModel/ExamAccessRules';
import { AppConstants } from '../common/constants/AppConstants';
import dataPreferences from '@ohos.data.preferences';
import { Context } from '@kit.AbilityKit';

let courseServiceModel: CourseTableModel = courseTableModel;

export class CourseService {
  static async loadCourses(context: Object): Promise<Course[]> {
    const jsonData = await CourseRepository.loadCourseData(context);
    if (!jsonData) {
      return [];
    }
    courseServiceModel.loadFromJson(jsonData);
    CourseService.updateNextCourseCache(context).catch(() => {});
    return courseServiceModel.getAllCourses();
  }

  static async loadCoursesForSemester(context: Object, semesterId: number): Promise<Course[]> {
    const jsonData = await CourseRepository.loadCourseDataBySemester(context, semesterId);
    if (!jsonData) {
      return [];
    }
    courseServiceModel.loadFromJson(jsonData);
    CourseService.updateNextCourseCache(context).catch(() => {});
    return courseServiceModel.getAllCourses();
  }

  static async saveCourses(context: Object, courses: Course[]): Promise<void> {
    const rawData = CourseService.coursesToRawData(courses);
    await CourseRepository.saveCourseData(context, JSON.stringify(rawData));
    CourseService.updateNextCourseCache(context).catch(() => {});
  }

  static async saveRawCourseData(context: Object, rawData: RawCourseTableData): Promise<void> {
    await CourseRepository.saveCourseData(context, JSON.stringify(rawData));
    CourseService.updateNextCourseCache(context).catch(() => {});
  }

  static async hasCourseData(context: Object): Promise<boolean> {
    return await CourseRepository.hasCourseData(context);
  }

  static async clearCourseData(context: Object): Promise<void> {
    await CourseRepository.clearCourseData(context);
    courseServiceModel.clear();
  }

  static getAllCourses(): Course[] {
    return courseServiceModel.getAllCourses();
  }

  static getCoursesForWeek(weekNumber: number): Course[] {
    return courseServiceModel.getCoursesForWeek(weekNumber);
  }

  static getCoursesForDay(dayOfWeek: number): Course[] {
    return courseServiceModel.getCoursesForDay(dayOfWeek);
  }

  static getCoursesForDayAndWeek(dayOfWeek: number, weekNumber: number): Course[] {
    return courseServiceModel.getCoursesForDayAndWeek(dayOfWeek, weekNumber);
  }

  static getMaxWeekNumber(): number {
    return courseServiceModel.getMaxWeekNumber();
  }

  static loadFromJson(jsonString: string): void {
    courseServiceModel.loadFromJson(jsonString);
  }

  static addCourse(course: Course): void {
    courseServiceModel.getAllCourses().push(course);
  }

  static updateCourse(index: number, course: Course): void {
    const courses = courseServiceModel.getAllCourses();
    if (index >= 0 && index < courses.length) {
      courses[index] = course;
    }
  }

  static deleteCourse(index: number): void {
    const courses = courseServiceModel.getAllCourses();
    if (index >= 0 && index < courses.length) {
      courses.splice(index, 1);
    }
  }

  private static coursesToRawData(courses: Course[]): RawCourseTableData {
    const emptyActivities: RawActivity[][] = [];
    for (let i = 0; i < 84; i++) {
      emptyActivities.push([]);
    }

    for (const course of courses) {
      for (let offset = 0; offset < course.time.duration; offset++) {
        const section: number = course.time.startSection + offset;
        if (section < 1 || section > 12) {
          continue;
        }
        const slotIndex: number = (course.time.dayOfWeek - 1) * 12 + (section - 1);
        if (slotIndex < 0 || slotIndex >= 84) {
          continue;
        }
        const activity: RawActivity = {
          teacherId: '0',
          teacherName: course.teacherName,
          courseId: course.id || course.name,
          courseName: course.name,
          roomId: '0',
          roomName: course.roomName,
          vaildWeeks: course.validWeeks,
        };
        emptyActivities[slotIndex].push(activity);
      }
    }

    const result: RawCourseTableData = {
      unitCounts: 84,
      activities: emptyActivities
    };
    return result;
  }

  static async updateNextCourseCache(context: Object): Promise<void> {
    try {
      const week: number = getCurrentWeek();
      const today: Date = new Date();
      const todayDay: number = today.getDay() || 7;
      const todayCourses: Course[] = courseServiceModel.getCoursesForDayAndWeek(todayDay, week);
      todayCourses.sort((a: Course, b: Course) => a.time.startSection - b.time.startSection);

      let targetCourse: Course | null = null;
      let targetTime: string = '--:--';

      const currentMinutes: number = today.getHours() * 60 + today.getMinutes();
      for (let i = 0; i < todayCourses.length; i++) {
        const course: Course = todayCourses[i];
        const startSec: number = course.time.startSection;
        if (startSec >= 1 && startSec <= SECTION_TIMES.length) {
          const secTime = SECTION_TIMES[startSec - 1];
          const parts: string[] = secTime.startTime.split(':');
          const courseMinutes: number = parseInt(parts[0]) * 60 + parseInt(parts[1]);
          if (courseMinutes >= currentMinutes - 45) {
            targetCourse = course;
            targetTime = secTime.startTime;
            break;
          }
        }
      }

      if (!targetCourse) {
        const tomorrowDay: number = todayDay === 7 ? 1 : todayDay + 1;
        const tomorrowWeek: number = todayDay === 7 ? week + 1 : week;
        const tomorrowCourses: Course[] = courseServiceModel.getCoursesForDayAndWeek(tomorrowDay, tomorrowWeek);
        tomorrowCourses.sort((a: Course, b: Course) => a.time.startSection - b.time.startSection);
        if (tomorrowCourses.length > 0) {
          targetCourse = tomorrowCourses[0];
          const startSec: number = targetCourse.time.startSection;
          if (startSec >= 1 && startSec <= SECTION_TIMES.length) {
            targetTime = `明日 ${SECTION_TIMES[startSec - 1].startTime}`;
          }
        }
      }

      let cacheObj: Record<string, string> = {
        'name': targetCourse ? targetCourse.name : '暂无待上课程',
        'location': targetCourse ? (targetCourse.roomName || '教室未定') : '今日已无课',
        'time': targetTime,
        'room': targetCourse ? targetCourse.roomName : ''
      };

      let pref = await dataPreferences.getPreferences(context as Context, AppConstants.PREF_COURSE_DB_NAME);
      await pref.put('next_course_cache', JSON.stringify(cacheObj));
      await pref.flush();
    } catch (e) {
      console.error('[CourseService] updateNextCourseCache error:', JSON.stringify(e));
    }
  }
}

