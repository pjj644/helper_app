import { cloudDatabase } from '@kit.CloudFoundationKit';

export class ClassExam extends cloudDatabase.DatabaseObject {
  id: number = 0;
  userId: string = '';
  semesterId: number = 0;
  semesterLabel: string = '';
  courseNo: string = '';
  courseName: string = '';
  examDate: string = '';
  examTimeRange: string = '';
  examLocation: string = '';
  seatNo: string = '';
  examStatus: string = '';
  examType: string = '';
  remark: string = '';
  beginTime?: Date;
  endTime?: Date;
  updatedAt?: Date;
}
