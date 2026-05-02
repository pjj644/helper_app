import { cloudDatabase } from '@kit.CloudFoundationKit';

class ClassCourse extends cloudDatabase.DatabaseObject {
  id: number;
  userId = '';
  semesterId = 0;
  semesterLabel = '';
  courseId = '';
  courseName = '';
  teacherName = '';
  roomName = '';
  dayOfWeek = 1;
  startSection = 1;
  duration = 1;
  validWeeks = '';
  colorIndex = 0;
  updatedAt?: Date;
}

export { ClassCourse };
