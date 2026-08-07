// 课程数据模型 - 与UI解耦的数据层

// 原始活动数据接口（从教务系统获取的原始格式）
export interface RawActivity {
  teacherId: string;
  teacherName: string;
  courseId: string;
  courseName: string;
  roomId: string;
  roomName: string;
  vaildWeeks: string;
}

// 原始课表数据接口
export interface RawCourseTableData {
  unitCounts: number;
  activities: RawActivity[][];
}

// 课程时间信息
export interface CourseTime {
  dayOfWeek: number;      // 星期几 (1-7, 1=周一)
  startSection: number;   // 开始节次 (1-12)
  duration: number;       // 持续节数
}

// 课程信息接口
export interface Course {
  id: string;             // 课程ID
  name: string;           // 课程名称
  teacherName: string;    // 教师姓名
  roomName: string;       // 教室名称
  time: CourseTime;       // 课程时间
  validWeeks: string;     // 有效周次字符串
  colorIndex: number;     // 颜色索引，用于UI显示
}

// 时间段信息接口
export interface SectionTime {
  section: number;
  startTime: string;
  endTime: string;
}

// 时间段定义（12节课的时间安排）
export const SECTION_TIMES: SectionTime[] = [
  { section: 1, startTime: '8:30', endTime: '9:15' },
  { section: 2, startTime: '9:20', endTime: '10:05' },
  { section: 3, startTime: '10:20', endTime: '11:05' },
  { section: 4, startTime: '11:10', endTime: '11:55' },
  { section: 5, startTime: '14:30', endTime: '15:15' },
  { section: 6, startTime: '15:20', endTime: '16:05' },
  { section: 7, startTime: '16:20', endTime: '17:05' },
  { section: 8, startTime: '17:10', endTime: '17:55' },
  { section: 9, startTime: '19:30', endTime: '20:15' },
  { section: 10, startTime: '20:20', endTime: '21:05' },
  { section: 11, startTime: '21:10', endTime: '21:55' },
  { section: 12, startTime: '22:00', endTime: '22:45' },
];

// 课程颜色配置（柔和色调）
export const COURSE_COLORS: string[] = [
  '#FFB6C1', // 浅粉色
  '#87CEEB', // 浅蓝色
  '#98FB98', // 浅绿色
  '#FFD700', // 金黄色
  '#DDA0DD', // 梅花色
  '#F0A0A0', // 浅红色
  '#B0E0E6', // 粉蓝色
  '#FFE4B5', // 桃色
  '#E6E6FA', // 薰衣草色
  '#F5DEB3', // 小麦色
  '#AFEEEE', // 绿松石色
  '#FFB347', // 橙色
];

// 课表数据管理类
export class CourseTableModel {
  private courses: Course[] = [];
  private courseColorMap: Map<string, number> = new Map();
  private colorCounter: number = 0;

  // 解析原始数据
  parseRawData(rawData: RawCourseTableData): void {
    this.courses = [];
    this.courseColorMap.clear();
    this.colorCounter = 0;

    const activities = rawData.activities;
    if (!activities || !Array.isArray(activities)) {
      return;
    }

    // 每天12节课，一周7天
    // activities数组的索引对应：dayIndex * 12 + sectionIndex
    // dayIndex: 0-6 (周一到周日)
    // sectionIndex: 0-11 (第1-12节)

    for (let i = 0; i < activities.length; i++) {
      const slotActivities = activities[i];
      if (!slotActivities || slotActivities.length === 0) {
        continue;
      }

      // 计算星期几和第几节
      const dayOfWeek = Math.floor(i / 12) + 1; // 1-7
      const startSection = (i % 12) + 1; // 1-12

      for (const rawActivity of slotActivities) {
        const course = this.createCourse(rawActivity, dayOfWeek, startSection);
        if (course) {
          this.courses.push(course);
        }
      }
    }

    // 合并连续节次的同一课程
    this.mergeContinuousCourses();
  }

  // 创建课程对象
  private createCourse(
    rawActivity: RawActivity,
    dayOfWeek: number,
    startSection: number
  ): Course | null {
    if (!rawActivity || !rawActivity.courseName) {
      return null;
    }

    // 为课程分配颜色
    const colorIndex = this.getColorIndexForCourse(rawActivity.courseId);

    return {
      id: rawActivity.courseId || '',
      name: rawActivity.courseName,
      teacherName: rawActivity.teacherName || '',
      roomName: rawActivity.roomName || '',
      time: {
        dayOfWeek,
        startSection,
        duration: 1, // 默认1节，后续合并
      },
      validWeeks: rawActivity.vaildWeeks || '',
      colorIndex,
    };
  }

  // 获取课程的颜色索引
  private getColorIndexForCourse(courseId: string): number {
    if (this.courseColorMap.has(courseId)) {
      return this.courseColorMap.get(courseId)!;
    }

    const colorIndex = this.colorCounter % COURSE_COLORS.length;
    this.courseColorMap.set(courseId, colorIndex);
    this.colorCounter++;
    return colorIndex;
  }

  // 合并连续节次的同一课程
  private mergeContinuousCourses(): void {
    const mergedCourses: Course[] = [];
    const processed = new Set<string>();

    for (const course of this.courses) {
      const key = this.getCourseSlotKey(course, course.time.startSection);
      if (processed.has(key)) {
        continue;
      }

      // 查找连续的相同课程
      let duration = 1;
      for (let i = course.time.startSection + 1; i <= 12; i++) {
        const nextKey = this.getCourseSlotKey(course, i);
        const nextCourse = this.courses.find(
          c =>
            c.time.startSection === i &&
            this.isSameCourseForMerge(course, c)
        );
        if (nextCourse) {
          duration++;
          processed.add(nextKey);
        } else {
          break;
        }
      }

      course.time.duration = duration;
      mergedCourses.push(course);
      processed.add(key);
    }

    this.courses = mergedCourses;
  }

  private isSameCourseForMerge(base: Course, target: Course): boolean {
    return (
      base.id === target.id &&
      base.name === target.name &&
      base.teacherName === target.teacherName &&
      base.roomName === target.roomName &&
      base.validWeeks === target.validWeeks &&
      base.time.dayOfWeek === target.time.dayOfWeek
    );
  }

  private getCourseSlotKey(course: Course, section: number): string {
    return [
      course.id,
      course.name,
      course.teacherName,
      course.roomName,
      course.validWeeks,
      `${course.time.dayOfWeek}`,
      `${section}`,
    ].join('_');
  }

  // 获取所有课程
  getAllCourses(): Course[] {
    return this.courses;
  }

  // 获取数据中的最大周数
  getMaxWeekNumber(): number {
    let maxWeek = 1;
    for (const course of this.courses) {
      if (course.validWeeks) {
        // validWeeks 第一位是0，不计，之后的位数对应周数
        maxWeek = Math.max(maxWeek, course.validWeeks.length - 1);
      }
    }
    return maxWeek;
  }

  // 获取指定周的课程
  getCoursesForWeek(weekNumber: number): Course[] {
    return this.courses.filter(course => this.isValidForWeek(course, weekNumber));
  }

  // 获取指定天的课程
  getCoursesForDay(dayOfWeek: number): Course[] {
    return this.courses.filter(course => course.time.dayOfWeek === dayOfWeek);
  }

  // 获取指定周和指定天的课程
  getCoursesForDayAndWeek(dayOfWeek: number, weekNumber: number): Course[] {
    return this.courses.filter(
      course =>
        course.time.dayOfWeek === dayOfWeek &&
        this.isValidForWeek(course, weekNumber)
    );
  }

  // 判断课程在指定周是否有效
  // vaildWeeks: 第一个0不计，之后第几位是1代表第几周有课
  // 例如: "01111101111111111000..." 第2位(index1)=1表示第1周有课
  isValidForWeek(course: Course, weekNumber: number): boolean {
    if (!course.validWeeks || weekNumber < 1 || weekNumber > course.validWeeks.length - 1) {
      return false;
    }
    return course.validWeeks.charAt(weekNumber) === '1';
  }

  // 获取指定位置（星期几、第几节）的课程
  getCourseAt(dayOfWeek: number, section: number): Course | undefined {
    return this.courses.find(
      course =>
        course.time.dayOfWeek === dayOfWeek &&
        course.time.startSection <= section &&
        course.time.startSection + course.time.duration > section
    );
  }

  // 获取课程颜色
  getCourseColor(course: Course): string {
    return COURSE_COLORS[course.colorIndex % COURSE_COLORS.length];
  }

  // 清空数据
  clear(): void {
    this.courses = [];
    this.courseColorMap.clear();
    this.colorCounter = 0;
  }

  // 从JSON字符串加载数据
  loadFromJson(jsonString: string): void {
    try {
      const rawData = JSON.parse(jsonString) as RawCourseTableData;
      this.parseRawData(rawData);
    } catch (e) {
      console.error('解析课表数据失败:', e);
      this.clear();
    }
  }
}

// 单例实例
export const courseTableModel = new CourseTableModel();

// 计算指定日期是第几教学周
// 2026-2027学年第一学期行课首日为 2026-09-01（周二）。
// 周次按周一~周日对齐 validWeeks，故锚定到含 2026-09-01 的那周的周一 2026-08-31。
export function getWeekForDate(date: Date): number {
  const termStart: Date = new Date(2026, 7, 31); // month从0开始，7表示8月
  termStart.setHours(0, 0, 0, 0);

  const d: Date = new Date(date);
  d.setHours(0, 0, 0, 0);

  const diffMs: number = d.getTime() - termStart.getTime();
  if (diffMs < 0) {
    return 1;
  }

  const week: number = Math.floor(diffMs / (7 * 24 * 60 * 60 * 1000)) + 1;
  return Math.max(1, week);
}

// 获取当前是第几周
export function getCurrentWeek(): number {
  return getWeekForDate(new Date());
}

// 日期信息接口
export interface DateInfo {
  year: number;
  month: number;
  date: number;
  dayOfWeek: number;
}

// 获取当前日期信息
export function getCurrentDateInfo(): DateInfo {
  const now = new Date();
  return {
    year: now.getFullYear(),
    month: now.getMonth() + 1,
    date: now.getDate(),
    dayOfWeek: now.getDay() || 7, // 0转换为7（周日）
  };
}

// 周日期信息接口
export interface WeekDateInfo {
  month: number;
  date: number;
  dayOfWeek: number;
}

// 获取本周日期数组（周一到周日）
export function getWeekDates(): WeekDateInfo[] {
  const dates: WeekDateInfo[] = [];
  const now = new Date();
  const currentDay = now.getDay() || 7; // 1-7

  // 计算本周一的日期
  const monday = new Date(now);
  monday.setDate(now.getDate() - currentDay + 1);

  for (let i = 0; i < 7; i++) {
    const date = new Date(monday);
    date.setDate(monday.getDate() + i);
    dates.push({
      month: date.getMonth() + 1,
      date: date.getDate(),
      dayOfWeek: i + 1,
    });
  }

  return dates;
}
