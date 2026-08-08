import { Course } from '../model/classTableModel/CourseModel';
import { COURSE_COLORS, SECTION_TIMES } from '../model/classTableModel/CourseModel';
import { ThemeManager } from '../common/utils/ThemeManager';

@Component
export struct CourseCard {
  @Prop course: Course = {} as Course;
  @Prop isCompact: boolean = false;
  onClick?: () => void;

  private getCourseColor(): string {
    return COURSE_COLORS[this.course.colorIndex % COURSE_COLORS.length];
  }

  private formatCourseTime(): string {
    const startSection: number = this.course.time.startSection;
    const endSection: number = startSection + this.course.time.duration - 1;
    const startTime: string = SECTION_TIMES[startSection - 1]?.startTime || '';
    const endTime: string = SECTION_TIMES[endSection - 1]?.endTime || '';
    return `${startSection}-${endSection}节 ${startTime}-${endTime}`;
  }

  private extractCourseName(fullName: string): string {
    if (!fullName) return '';
    return fullName.replace(/\([^)]*\)/g, '').trim();
  }

  private getTitleMaxLines(): number {
    if (this.course.time.duration >= 4) {
      return 4;
    }
    if (this.course.time.duration >= 2) {
      return 3;
    }
    return 2;
  }

  build() {
    Column() {
      Text(this.extractCourseName(this.course.name))
        .fontSize(this.course.time.duration >= 3 ? 14 : 13)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeManager.getTextPrimaryColor())
        .maxLines(this.getTitleMaxLines())
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
        .lineHeight(this.course.time.duration >= 3 ? 18 : 16);

      if (this.course.roomName && !this.isCompact) {
        Text(`@${this.course.roomName}`)
          .fontSize(11)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .margin({ top: 6 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(14)
          .width('100%');
      }

      if (this.course.teacherName && !this.isCompact) {
        Text(this.course.teacherName)
          .fontSize(11)
          .fontColor(ThemeManager.getTextTertiaryColor())
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(14)
          .width('100%');
      }

      if (this.isCompact) {
        Text(this.formatCourseTime())
          .fontSize(10)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .margin({ top: 4 })
          .maxLines(1)
          .width('100%');
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(this.getCourseColor())
    .borderRadius(10)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (this.onClick) {
        this.onClick();
      }
    });
  }
}
