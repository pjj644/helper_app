import { Course, RawActivity, RawCourseTableData } from '../model/classTableModel/CourseModel';
import { ExamItem } from '../model/classTableModel/ExamModel';
import { CloudDbRepository } from '../repository/CloudDbRepository';
import { CourseRepository } from '../repository/CourseRepository';
import { ExamRepository } from '../repository/ExamRepository';
import { ClassCourse } from '../pages/CloudDb/ClassCourse';
import { ClassExam } from '../pages/CloudDb/ClassExam';
import { calculateSemesterId, getSemesterLabelById } from '../model/classTableModel/ExamAccessRules';

export interface SyncResult {
  success: boolean;
  courseCount?: number;
  examCount?: number;
  error?: string;
}

export interface DownloadResult {
  success: boolean;
  courseCount?: number;
  examCount?: number;
  error?: string;
}

export interface SyncAllResult {
  courses: SyncResult;
  exams: SyncResult;
}

export interface DownloadAllResult {
  courses: DownloadResult;
  exams: DownloadResult;
}

export class SyncService {
  static async initCloudDB(): Promise<void> {
    await CloudDbRepository.initCloudDB();
  }

  static async syncCoursesToCloud(context: Object, userId: string): Promise<SyncResult> {
    try {
      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }
      const semesterIds = await CourseRepository.getStoredSemesterIds(context);
      let totalCourseCount = 0;

      for (const semesterId of semesterIds) {
        const courseJson = await CourseRepository.loadCourseDataBySemester(context, semesterId);
        if (!courseJson) {
          continue;
        }

        const rawData: RawCourseTableData = JSON.parse(courseJson);
        const semesterLabel = getSemesterLabelById(semesterId);

        const courses = SyncService.extractCoursesFromRawData(rawData);
        const cloudCourses: ClassCourse[] = [];

        for (const course of courses) {
          const record = SyncService.toCloudCourse(course, userId, semesterId, semesterLabel);
          cloudCourses.push(record);
        }

        const existingCourses = await CloudDbRepository.queryCourses(userId, semesterId);
        const existingMap = new Map<number, ClassCourse>();
        for (const ec of existingCourses) {
          existingMap.set(ec.id, ec);
        }

        const toUpsert: ClassCourse[] = [];
        for (const cc of cloudCourses) {
          const existing = existingMap.get(cc.id);
          if (!existing || SyncService.courseChanged(existing, cc)) {
            toUpsert.push(cc);
          }
        }

        if (toUpsert.length > 0) {
          await SyncService.upsertCoursesInBatches(toUpsert);
          totalCourseCount += toUpsert.length;
        }
      }

      if (semesterIds.length === 0) {
        const courseJson = await CourseRepository.loadCourseData(context);
        if (courseJson) {
          const rawData: RawCourseTableData = JSON.parse(courseJson);
          const semesterId = calculateSemesterId();
          const semesterLabel = getSemesterLabelById(semesterId);

          const courses = SyncService.extractCoursesFromRawData(rawData);
          const cloudCourses: ClassCourse[] = [];

          for (const course of courses) {
            const record = SyncService.toCloudCourse(course, userId, semesterId, semesterLabel);
            cloudCourses.push(record);
          }

          const existingCourses = await CloudDbRepository.queryCourses(userId, semesterId);
          const existingMap = new Map<number, ClassCourse>();
          for (const ec of existingCourses) {
            existingMap.set(ec.id, ec);
          }

          const toUpsert: ClassCourse[] = [];
          for (const cc of cloudCourses) {
            const existing = existingMap.get(cc.id);
            if (!existing || SyncService.courseChanged(existing, cc)) {
              toUpsert.push(cc);
            }
          }

          if (toUpsert.length > 0) {
            await SyncService.upsertCoursesInBatches(toUpsert);
            totalCourseCount += toUpsert.length;
          }
        }
      }

      const result: SyncResult = {
        success: true,
        courseCount: totalCourseCount
      };
      return result;
    } catch (error) {
      console.error('[SyncService] 同步课表到云端失败:', error);
      const result: SyncResult = {
        success: false,
        error: String(error)
      };
      return result;
    }
  }

  static async downloadCoursesFromCloud(context: Object, userId: string): Promise<DownloadResult> {
    try {
      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }
      const cloudCourses = await CloudDbRepository.queryAllCourses(userId);

      if (cloudCourses.length === 0) {
        const result: DownloadResult = { success: true, courseCount: 0 };
        return result;
      }

      const bySemester = new Map<number, ClassCourse[]>();
      for (const cc of cloudCourses) {
        const sid = cc.semesterId || 0;
        if (!bySemester.has(sid)) {
          bySemester.set(sid, []);
        }
        bySemester.get(sid)!.push(cc);
      }

      const semesterIds = Array.from(bySemester.keys());
      for (let i = 0; i < semesterIds.length; i++) {
        const semesterId = semesterIds[i];
        const courses = bySemester.get(semesterId);
        if (!courses) {
          continue;
        }
        const rawData = SyncService.cloudCoursesToRawData(courses);
        await CourseRepository.saveCourseDataBySemester(context, semesterId, JSON.stringify(rawData));
      }

      const currentSemesterId = calculateSemesterId();
      const currentCourses = bySemester.get(currentSemesterId);
      if (currentCourses && currentCourses.length > 0) {
        const rawData = SyncService.cloudCoursesToRawData(currentCourses);
        await CourseRepository.saveCourseData(context, JSON.stringify(rawData));
      }

      const result: DownloadResult = {
        success: true,
        courseCount: cloudCourses.length
      };
      return result;
    } catch (error) {
      console.error('[SyncService] 从云端下载课表失败:', error);
      const result: DownloadResult = {
        success: false,
        error: String(error)
      };
      return result;
    }
  }

  static async syncExamsToCloud(context: Object, userId: string): Promise<SyncResult> {
    try {
      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }
      const examJson = await ExamRepository.loadExamData(context);
      if (!examJson) {
        const result: SyncResult = { success: true, examCount: 0 };
        return result;
      }

      const exams: ExamItem[] = JSON.parse(examJson);

      const bySemester = new Map<number, ExamItem[]>();
      for (const item of exams) {
        const semesterId = item.semesterId > 0 ? item.semesterId : calculateSemesterId();
        if (!bySemester.has(semesterId)) {
          bySemester.set(semesterId, []);
        }
        bySemester.get(semesterId)!.push(item);
      }

      let totalExamCount = 0;
      const semesterIdList = Array.from(bySemester.keys());
      for (let i = 0; i < semesterIdList.length; i++) {
        const semesterId = semesterIdList[i];
        const semesterExams = bySemester.get(semesterId);
        if (!semesterExams) {
          continue;
        }
        const cloudExams: ClassExam[] = [];
        for (const item of semesterExams) {
          const record = SyncService.toCloudExam(item, userId);
          cloudExams.push(record);
        }

        const existingExams = await CloudDbRepository.queryExams(userId, semesterId);
        const existingMap = new Map<number, ClassExam>();
        for (const ee of existingExams) {
          existingMap.set(ee.id, ee);
        }

        const toUpsert: ClassExam[] = [];
        for (const ce of cloudExams) {
          const existing = existingMap.get(ce.id);
          if (!existing || SyncService.examChanged(existing, ce)) {
            toUpsert.push(ce);
          }
        }

        if (toUpsert.length > 0) {
          await SyncService.upsertExamsInBatches(toUpsert);
          totalExamCount += toUpsert.length;
        }
      }

      const result: SyncResult = {
        success: true,
        examCount: totalExamCount
      };
      return result;
    } catch (error) {
      console.error('[SyncService] 同步考试到云端失败:', error);
      const result: SyncResult = {
        success: false,
        error: String(error)
      };
      return result;
    }
  }

  static async downloadExamsFromCloud(context: Object, userId: string): Promise<DownloadResult> {
    try {
      if (!CloudDbRepository.getZone()) {
        await SyncService.initCloudDB();
      }
      const cloudExams = await CloudDbRepository.queryAllExams(userId);

      if (cloudExams.length === 0) {
        const result: DownloadResult = { success: true, examCount: 0 };
        return result;
      }

      const examItems: ExamItem[] = [];
      for (const ce of cloudExams) {
        const item: ExamItem = {
          courseNo: ce.courseNo || '',
          courseName: ce.courseName || '',
          examDate: ce.examDate || '',
          examTimeRange: ce.examTimeRange || '',
          examLocation: ce.examLocation || '',
          seatNo: ce.seatNo || '',
          examStatus: ce.examStatus || '',
          examType: ce.examType || '',
          remark: ce.remark || '',
          semesterId: ce.semesterId || 0,
          semesterLabel: ce.semesterLabel || '',
          beginTime: ce.beginTime ? ce.beginTime.getTime() : 0,
          endTime: ce.endTime ? ce.endTime.getTime() : 0,
        };
        examItems.push(item);
      }

      await ExamRepository.saveExamData(context, JSON.stringify(examItems));

      const result: DownloadResult = {
        success: true,
        examCount: cloudExams.length
      };
      return result;
    } catch (error) {
      console.error('[SyncService] 从云端下载考试失败:', error);
      const result: DownloadResult = {
        success: false,
        error: String(error)
      };
      return result;
    }
  }

  private static async upsertCoursesInBatches(courses: ClassCourse[]): Promise<void> {
    const BATCH_SIZE = 50;
    for (let i = 0; i < courses.length; i += BATCH_SIZE) {
      const batch = courses.slice(i, i + BATCH_SIZE);
      await SyncService.retryOperation(() => CloudDbRepository.upsertCourses(batch));
      if (i + BATCH_SIZE < courses.length) {
        await SyncService.delay(500);
      }
    }
  }

  private static async upsertExamsInBatches(exams: ClassExam[]): Promise<void> {
    const BATCH_SIZE = 50;
    for (let i = 0; i < exams.length; i += BATCH_SIZE) {
      const batch = exams.slice(i, i + BATCH_SIZE);
      await SyncService.retryOperation(() => CloudDbRepository.upsertExams(batch));
      if (i + BATCH_SIZE < exams.length) {
        await SyncService.delay(500);
      }
    }
  }

  static async syncAllToCloud(context: Object, userId: string): Promise<SyncAllResult> {
    await SyncService.initCloudDB();
    const courses = await SyncService.syncCoursesToCloud(context, userId);
    await SyncService.delay(500);
    const exams = await SyncService.syncExamsToCloud(context, userId);
    const result: SyncAllResult = { courses, exams };
    return result;
  }

  static async downloadAllFromCloud(context: Object, userId: string): Promise<DownloadAllResult> {
    await SyncService.initCloudDB();
    const courses = await SyncService.downloadCoursesFromCloud(context, userId);
    await SyncService.delay(500);
    const exams = await SyncService.downloadExamsFromCloud(context, userId);
    const result: DownloadAllResult = { courses, exams };
    return result;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void) => setTimeout(() => resolve(), ms));
  }

  private static async retryOperation<T>(
    operation: () => Promise<T>,
    maxRetries: number = 3,
    baseDelay: number = 2000
  ): Promise<T> {
    let lastError: Error | null = null;
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error as Error;
        const errorStr = String(error);
        if (errorStr.includes('1004007') && attempt < maxRetries) {
          const delayMs = baseDelay * Math.pow(2, attempt);
          console.warn(`[SyncService] 请求被限流，${delayMs}ms后重试 (${attempt + 1}/${maxRetries})`);
          await SyncService.delay(delayMs);
        } else {
          throw new Error(String(error));
        }
      }
    }
    throw lastError!;
  }

  private static courseChanged(existing: ClassCourse, current: ClassCourse): boolean {
    return existing.courseName !== current.courseName ||
           existing.teacherName !== current.teacherName ||
           existing.roomName !== current.roomName ||
           existing.validWeeks !== current.validWeeks ||
           existing.dayOfWeek !== current.dayOfWeek ||
           existing.startSection !== current.startSection ||
           existing.duration !== current.duration;
  }

  private static examChanged(existing: ClassExam, current: ClassExam): boolean {
    return existing.examDate !== current.examDate ||
           existing.examTimeRange !== current.examTimeRange ||
           existing.examLocation !== current.examLocation ||
           existing.seatNo !== current.seatNo ||
           existing.examStatus !== current.examStatus;
  }

  private static buildId(seed: string): number {
    let hash: number = 0;
    for (let i = 0; i < seed.length; i++) {
      hash = ((hash << 5) - hash) + seed.charCodeAt(i);
      hash |= 0;
    }
    const value: number = Math.abs(hash % 2000000000);
    return value + 1;
  }

  private static toCloudCourse(course: Course, userId: string, semesterId: number, semesterLabel: string): ClassCourse {
    const record = new ClassCourse();
    record.id = SyncService.buildId(`${userId}|${semesterId}|${course.id}|${course.time.dayOfWeek}|${course.time.startSection}|${course.validWeeks}`);
    record.userId = userId;
    record.semesterId = semesterId;
    record.semesterLabel = semesterLabel;
    record.courseId = course.id;
    record.courseName = course.name;
    record.teacherName = course.teacherName || '';
    record.roomName = course.roomName || '';
    record.dayOfWeek = Number(course.time.dayOfWeek) || 1;
    record.startSection = Number(course.time.startSection) || 1;
    record.duration = Number(course.time.duration) || 1;
    record.validWeeks = course.validWeeks || '';
    record.colorIndex = Number(course.colorIndex) || 0;
    return record;
  }

  private static toCloudExam(item: ExamItem, userId: string): ClassExam {
    const semesterId: number = item.semesterId > 0 ? item.semesterId : calculateSemesterId();
    const semesterLabel: string = item.semesterLabel || getSemesterLabelById(semesterId);
    const record = new ClassExam();
    record.id = SyncService.buildId(`${userId}|${semesterId}|${item.courseNo}|${item.courseName}|${item.examDate}|${item.examTimeRange}|${item.examType}`);
    record.userId = userId;
    record.semesterId = semesterId;
    record.semesterLabel = semesterLabel;
    record.courseNo = item.courseNo;
    record.courseName = item.courseName;
    record.examDate = item.examDate;
    record.examTimeRange = item.examTimeRange;
    record.examLocation = item.examLocation;
    record.seatNo = item.seatNo;
    record.examStatus = item.examStatus;
    record.examType = item.examType;
    record.remark = item.remark;
    if (item.beginTime > 0) {
      record.beginTime = new Date(item.beginTime);
    }
    if (item.endTime > 0) {
      record.endTime = new Date(item.endTime);
    }
    record.updatedAt = new Date();
    return record;
  }

  private static extractCoursesFromRawData(rawData: RawCourseTableData): Course[] {
    const courses: Course[] = [];
    const activities = rawData.activities;

    if (!activities || !Array.isArray(activities)) {
      return courses;
    }

    const processed = new Set<string>();

    for (let i = 0; i < activities.length; i++) {
      const slotActivities = activities[i];
      if (!slotActivities || slotActivities.length === 0) {
        continue;
      }

      const dayOfWeek = Math.floor(i / 12) + 1;
      const startSection = (i % 12) + 1;

      for (const rawActivity of slotActivities) {
        const key = `${rawActivity.courseId}_${rawActivity.courseName}_${dayOfWeek}_${startSection}_${rawActivity.vaildWeeks}`;
        if (processed.has(key)) {
          continue;
        }

        const course: Course = {
          id: rawActivity.courseId || '',
          name: rawActivity.courseName,
          teacherName: rawActivity.teacherName || '',
          roomName: rawActivity.roomName || '',
          time: {
            dayOfWeek,
            startSection,
            duration: 1,
          },
          validWeeks: rawActivity.vaildWeeks || '',
          colorIndex: 0,
        };

        courses.push(course);
        processed.add(key);
      }
    }

    return courses;
  }

  private static cloudCoursesToRawData(cloudCourses: ClassCourse[]): RawCourseTableData {
    const rawActivities: RawActivity[][] = [];
    for (let i = 0; i < 84; i++) {
      rawActivities.push([]);
    }

    for (const cc of cloudCourses) {
      const dayIndex = (cc.dayOfWeek || 1) - 1;
      const sectionIndex = (cc.startSection || 1) - 1;
      const slotIndex = dayIndex * 12 + sectionIndex;
      if (slotIndex >= 0 && slotIndex < 84) {
        const activity: RawActivity = {
          teacherId: '',
          teacherName: cc.teacherName || '',
          courseId: cc.courseId || '',
          courseName: cc.courseName || '',
          roomId: '',
          roomName: cc.roomName || '',
          vaildWeeks: cc.validWeeks || '',
        };
        rawActivities[slotIndex].push(activity);
      }

      const dur = cc.duration || 1;
      for (let d = 1; d < dur; d++) {
        const extraIndex = dayIndex * 12 + sectionIndex + d;
        if (extraIndex < 84) {
          const activity: RawActivity = {
            teacherId: '',
            teacherName: cc.teacherName || '',
            courseId: cc.courseId || '',
            courseName: cc.courseName || '',
            roomId: '',
            roomName: cc.roomName || '',
            vaildWeeks: cc.validWeeks || '',
          };
          rawActivities[extraIndex].push(activity);
        }
      }
    }

    const result: RawCourseTableData = {
      unitCounts: 12,
      activities: rawActivities,
    };
    return result;
  }
}
