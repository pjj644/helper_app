import { Course, CourseTableModel, courseTableModel, RawActivity, RawCourseTableData } from '../model/classTableModel/CourseModel';
import { CourseRepository } from '../repository/CourseRepository';
import { calculateSemesterId } from '../model/classTableModel/ExamAccessRules';

let courseServiceModel: CourseTableModel = courseTableModel;

export class CourseService {
  static async loadCourses(context: Object): Promise<Course[]> {
    const jsonData = await CourseRepository.loadCourseData(context);
    if (!jsonData) {
      return [];
    }
    courseServiceModel.loadFromJson(jsonData);
    return courseServiceModel.getAllCourses();
  }

  static async loadCoursesForSemester(context: Object, semesterId: number): Promise<Course[]> {
    const jsonData = await CourseRepository.loadCourseDataBySemester(context, semesterId);
    if (!jsonData) {
      return [];
    }
    courseServiceModel.loadFromJson(jsonData);
    return courseServiceModel.getAllCourses();
  }

  static async saveCourses(context: Object, courses: Course[]): Promise<void> {
    const rawData = CourseService.coursesToRawData(courses);
    await CourseRepository.saveCourseData(context, JSON.stringify(rawData));
  }

  static async saveRawCourseData(context: Object, rawData: RawCourseTableData): Promise<void> {
    await CourseRepository.saveCourseData(context, JSON.stringify(rawData));
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
}
