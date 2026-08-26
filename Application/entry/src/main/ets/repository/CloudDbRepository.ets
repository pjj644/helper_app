import { cloudDatabase, cloudCommon } from '@kit.CloudFoundationKit';
import auth from '@hw-agconnect/auth';
import { AppConstants } from '../common/constants/AppConstants';
import { ClassCourse } from '../pages/CloudDb/ClassCourse';
import { ClassExam } from '../pages/CloudDb/ClassExam';

let classDatabaseZone: cloudDatabase.DatabaseZone | null = null;

export class CloudDbRepository {
  static async initCloudDB(forceRefresh: boolean = false): Promise<void> {
    if (classDatabaseZone && !forceRefresh) {
      return;
    }
    const cloudDbAuthProvider = auth.getAuthProvider();
    if (cloudDbAuthProvider) {
      try {
        cloudCommon.init({
          region: cloudCommon.CloudRegion.CHINA,
          authProvider: cloudDbAuthProvider,
          databaseOptions: {
            schema: "schema.json",
          }
        });
      } catch (authInitErr) {
        console.error('[CloudDbRepository] 带 authProvider 初始化失败:', JSON.stringify(authInitErr));
        cloudCommon.init({
          region: cloudCommon.CloudRegion.CHINA,
          databaseOptions: {
            schema: "schema.json",
          }
        });
      }
    } else {
      cloudCommon.init({
        region: cloudCommon.CloudRegion.CHINA,
        databaseOptions: {
          schema: "schema.json",
        }
      });
    }

    try {
      classDatabaseZone = cloudDatabase.zone(AppConstants.CLOUD_DB_ZONE_NAME);
      console.info('[CloudDbRepository] CloudDB Zone 初始化成功:', AppConstants.CLOUD_DB_ZONE_NAME);
    } catch (zoneErr) {
      console.error('[CloudDbRepository] 获取 CloudDB Zone 失败:', JSON.stringify(zoneErr));
    }
  }

  static getZone(): cloudDatabase.DatabaseZone | null {
    return classDatabaseZone;
  }

  static async queryCourses(userId: string, semesterId: number): Promise<ClassCourse[]> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    const query = new cloudDatabase.DatabaseQuery(ClassCourse);
    query.equalTo('userId', userId);
    query.equalTo('semesterId', semesterId);
    return await classDatabaseZone.query(query);
  }

  static async queryAllCourses(userId: string): Promise<ClassCourse[]> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    const query = new cloudDatabase.DatabaseQuery(ClassCourse);
    query.equalTo('userId', userId);
    return await classDatabaseZone.query(query);
  }

  static async upsertCourse(course: ClassCourse): Promise<void> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    await classDatabaseZone.upsert(course);
  }

  static async upsertCourses(courses: ClassCourse[]): Promise<void> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    await classDatabaseZone.upsert(courses);
  }

  static async deleteCoursesByUserAndSemester(userId: string, semesterId: number): Promise<number> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    const query = new cloudDatabase.DatabaseQuery(ClassCourse);
    query.equalTo('userId', userId);
    query.equalTo('semesterId', semesterId);
    const courses = await classDatabaseZone.query(query);
    if (courses.length === 0) {
      return 0;
    }
    await classDatabaseZone.delete(courses);
    return courses.length;
  }

  static async queryExams(userId: string, semesterId: number): Promise<ClassExam[]> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    const query = new cloudDatabase.DatabaseQuery(ClassExam);
    query.equalTo('userId', userId);
    query.equalTo('semesterId', semesterId);
    return await classDatabaseZone.query(query);
  }

  static async queryAllExams(userId: string): Promise<ClassExam[]> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    const query = new cloudDatabase.DatabaseQuery(ClassExam);
    query.equalTo('userId', userId);
    return await classDatabaseZone.query(query);
  }

  static async upsertExam(exam: ClassExam): Promise<void> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    await classDatabaseZone.upsert(exam);
  }

  static async upsertExams(exams: ClassExam[]): Promise<void> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    await classDatabaseZone.upsert(exams);
  }

  static async deleteExamsByUserAndSemester(userId: string, semesterId: number): Promise<number> {
    if (!classDatabaseZone) {
      throw new Error('CloudDB zone not initialized');
    }
    const query = new cloudDatabase.DatabaseQuery(ClassExam);
    query.equalTo('userId', userId);
    query.equalTo('semesterId', semesterId);
    const exams = await classDatabaseZone.query(query);
    if (exams.length === 0) {
      return 0;
    }
    await classDatabaseZone.delete(exams);
    return exams.length;
  }
}
