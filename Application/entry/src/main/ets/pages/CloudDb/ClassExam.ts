import { cloudDatabase } from '@kit.CloudFoundationKit';

class ClassExam extends cloudDatabase.DatabaseObject {
  id: number;
  userId = '';
  semesterId = 0;
  semesterLabel = '';
  courseNo = '';
  courseName = '';
  examDate = '';
  examTimeRange = '';
  examLocation = '';
  seatNo = '';
  examStatus = '';
  examType = '';
  remark = '';
  beginTime?: Date;
  endTime?: Date;
  updatedAt?: Date;
}

export { ClassExam };
