import { Course, CourseTableModel, courseTableModel, RawActivity, RawCourseTableData, getCurrentWeek, SECTION_TIMES } from '../model/classTableModel/CourseModel';
import { CourseRepository } from '../repository/CourseRepository';
import { calculateSemesterId } from '../model/classTableModel/ExamAccessRules';
import { AppConstants } from '../common/constants/AppConstants';
import dataPreferences from '@ohos.data.preferences';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Context } from '@kit.AbilityKit';

// 桌面卡片实例 ID 列表在偏好文件中的存储键。
// 注意：与 entryformability/EntryFormAbility.ets 中的同名常量保持成对一致（写入方在彼处）。
const WIDGET_FORM_IDS_KEY: string = 'widget_form_ids';
// formProvider.updateForm 错误码：目标卡片 ID 不存在（卡片已被用户移除）
const FORM_ID_NOT_EXIST_CODE: number = 16501001;

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

  static async saveCoursesForSemester(context: Object, semesterId: number, courses: Course[]): Promise<void> {
    const rawData = CourseService.coursesToRawData(courses);
    await CourseRepository.saveCourseDataBySemester(context, semesterId, JSON.stringify(rawData));
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
      let countdownText: string = '今日已无课';

      const currentMinutes: number = today.getHours() * 60 + today.getMinutes();
      for (let i = 0; i < todayCourses.length; i++) {
        const course: Course = todayCourses[i];
        const startSec: number = course.time.startSection;
        const endSec: number = course.time.startSection + course.time.duration - 1;
        if (startSec >= 1 && startSec <= SECTION_TIMES.length) {
          const secTime = SECTION_TIMES[startSec - 1];
          const endSecTime = (endSec >= 1 && endSec <= SECTION_TIMES.length) ? SECTION_TIMES[endSec - 1] : secTime;
          const startParts: string[] = secTime.startTime.split(':');
          const endParts: string[] = endSecTime.endTime.split(':');
          const startMin: number = parseInt(startParts[0]) * 60 + parseInt(startParts[1]);
          const endMin: number = parseInt(endParts[0]) * 60 + parseInt(endParts[1]);

          if (currentMinutes < startMin) {
            targetCourse = course;
            targetTime = secTime.startTime;
            const diff = startMin - currentMinutes;
            countdownText = diff <= 60 ? `距上课 ${diff} 分钟` : `今天 ${targetTime} 上课`;
            break;
          } else if (currentMinutes >= startMin && currentMinutes <= endMin) {
            targetCourse = course;
            targetTime = secTime.startTime;
            countdownText = `正在上课 (第${startSec}-${endSec}节)`;
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
            countdownText = `明日第 ${startSec} 节上课`;
          }
        }
      }

      const dayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
      const dateStr = `${today.getMonth() + 1}月${today.getDate()}日 ${dayNames[today.getDay()]} 第${week}周`;

      let cacheObj: Record<string, Object> = {
        'name': targetCourse ? targetCourse.name : '暂无待上课程',
        'courseName': targetCourse ? targetCourse.name : '暂无待上课程',
        'location': targetCourse ? (targetCourse.roomName || '教室未定') : '今日已无课',
        'room': targetCourse ? (targetCourse.roomName || '教室未定') : '',
        'time': targetTime,
        'countdownText': countdownText,
        'hasCourseToday': todayCourses.length > 0,
        'dateStr': dateStr,
        'courseCount': todayCourses.length
      };

      for (let idx = 0; idx < 3; idx++) {
        if (idx < todayCourses.length) {
          const c = todayCourses[idx];
          const startSec = c.time.startSection;
          const endSec = c.time.startSection + c.time.duration - 1;
          const secTime = (startSec >= 1 && startSec <= SECTION_TIMES.length) ? SECTION_TIMES[startSec - 1] : null;
          const endSecTime = (endSec >= 1 && endSec <= SECTION_TIMES.length) ? SECTION_TIMES[endSec - 1] : secTime;

          let status = '未开始';
          if (secTime && endSecTime) {
            const startMin = parseInt(secTime.startTime.split(':')[0]) * 60 + parseInt(secTime.startTime.split(':')[1]);
            const endMin = parseInt(endSecTime.endTime.split(':')[0]) * 60 + parseInt(endSecTime.endTime.split(':')[1]);
            if (currentMinutes >= startMin && currentMinutes <= endMin) {
              status = '上课中';
            } else if (currentMinutes > endMin) {
              status = '已结束';
            }
          }

          cacheObj[`course${idx + 1}_name`] = c.name;
          cacheObj[`course${idx + 1}_time`] = secTime ? secTime.startTime : `第${startSec}节`;
          cacheObj[`course${idx + 1}_room`] = c.roomName || '教室待定';
          cacheObj[`course${idx + 1}_status`] = status;
        } else {
          cacheObj[`course${idx + 1}_name`] = '';
          cacheObj[`course${idx + 1}_time`] = '';
          cacheObj[`course${idx + 1}_room`] = '';
          cacheObj[`course${idx + 1}_status`] = '';
        }
      }

      let pref = await dataPreferences.getPreferences(context as Context, AppConstants.PREF_COURSE_DB_NAME);
      await pref.put('next_course_cache', JSON.stringify(cacheObj));
      await pref.flush();

      // 缓存落盘成功后主动推送已添加的桌面卡片，弥补 30 分钟定时刷新的滞后
      await CourseService.pushWidgetUpdate(pref, cacheObj);
    } catch (e) {
      console.error('[CourseService] updateNextCourseCache error:', JSON.stringify(e));
    }
  }

  /**
   * 应用回到前台时校准卡片缓存：从磁盘重载课表数据后重建下一节课缓存
   * （内部会顺带主动推送已添加的卡片），保证用户切回应用时卡片立即正确。
   * 无课表数据时跳过，避免用「今日已无课」误覆盖既有缓存。
   */
  static async refreshCardCache(context: Object): Promise<void> {
    try {
      const jsonData: string = await CourseRepository.loadCourseData(context);
      if (!jsonData) {
        return;
      }
      courseServiceModel.loadFromJson(jsonData);
      await CourseService.updateNextCourseCache(context);
    } catch (e) {
      console.error('[CourseService] refreshCardCache error:', JSON.stringify(e));
    }
  }

  /**
   * 事件驱动的主动刷新：把最新缓存数据推送给本应用当前所有桌面卡片实例。
   * 卡片实例 ID 由 EntryFormAbility 在 onAddForm/onRemoveForm 时维护于偏好文件，
   * 此处仅读取；推送返回「ID 不存在」（卡片已被移除）时将该 ID 从列表中剔除。
   */
  private static async pushWidgetUpdate(
    pref: dataPreferences.Preferences,
    cacheObj: Record<string, Object>
  ): Promise<void> {
    try {
      const idsStr = pref.getSync(WIDGET_FORM_IDS_KEY, '[]') as string;
      const formIds: string[] = JSON.parse(idsStr) as string[];
      if (!formIds || formIds.length === 0) {
        return;
      }

      const bindingData = formBindingData.createFormBindingData(cacheObj);
      const aliveIds: string[] = [];
      for (let i = 0; i < formIds.length; i++) {
        const formId = formIds[i];
        try {
          await formProvider.updateForm(formId, bindingData);
          aliveIds.push(formId);
        } catch (err) {
          const be = err as BusinessError;
          if (be.code === FORM_ID_NOT_EXIST_CODE) {
            // 卡片已被移除，剔除失效 ID 即可，无需报错
            continue;
          }
          // 其他错误保留 ID 待下次重试
          aliveIds.push(formId);
          console.error(`[CourseService] pushWidgetUpdate failed for form ${formId}: code=${be.code}, message=${be.message}`);
        }
      }

      if (aliveIds.length !== formIds.length) {
        pref.putSync(WIDGET_FORM_IDS_KEY, JSON.stringify(aliveIds));
        pref.flushSync();
      }
    } catch (e) {
      console.error('[CourseService] pushWidgetUpdate error:', JSON.stringify(e));
    }
  }
}

