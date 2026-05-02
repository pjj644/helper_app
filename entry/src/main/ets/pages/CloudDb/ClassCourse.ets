import { cloudDatabase } from '@kit.CloudFoundationKit';

export class ClassCourse extends cloudDatabase.DatabaseObject {
  id: number = 0;
  userId: string = '';
  semesterId: number = 0;
  semesterLabel: string = '';
  courseId: string = '';
  courseName: string = '';
  teacherName: string = '';
  roomName: string = '';
  dayOfWeek: number = 1;
  startSection: number = 1;
  duration: number = 1;
  validWeeks: string = '';
  colorIndex: number = 0;
  updatedAt?: Date;
}
