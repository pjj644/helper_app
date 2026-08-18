import { Course, SECTION_TIMES } from '../../model/classTableModel/CourseModel';
import { ImmersiveLightWrapper } from '../../common/ImmersiveLightWrapper';
import { AnimatedListItem } from '../AnimatedComponents';

@Component
export struct NextCourseCardComponent {
  @Prop title: string = '今日课程';
  @Prop courses: Course[] = [];
  @Prop isToday: boolean = true;
  onSwitchToExam: () => void = () => {};

  private formatCourseTime(course: Course): string {
    const startSection: number = course.time.startSection;
    const endSection: number = startSection + course.time.duration - 1;
    if (startSection < 1 || startSection > SECTION_TIMES.length) {
      return `第${startSection}-${endSection}节`;
    }
    const startTime: string = SECTION_TIMES[startSection - 1].startTime;
    const endSecIdx = Math.min(SECTION_TIMES.length - 1, endSection - 1);
    const endTime: string = SECTION_TIMES[endSecIdx].endTime;
    return `${startSection}-${endSection}节 ${startTime}-${endTime}`;
  }

  build() {
    ImmersiveLightWrapper({ radius: 20, lightIntensity: 2.0 }) {
      Column() {
        Row() {
          if (this.isToday) {
            Row({ space: 8 }) {
              Text(this.title)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'));

              Text(`${this.courses.length}门课程`)
                .fontSize(12)
                .fontColor($r('app.color.primary_color'));
            }

            Blank();

            Image($r('app.media.switch'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.primary_color'))
              .onClick(() => {
                this.onSwitchToExam();
              });
          } else {
            Text(this.title)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'));

            Blank();

            Text(`${this.courses.length}门`)
              .fontSize(12)
              .fontColor($r('app.color.primary_color'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.accent_bg_color'))
              .borderRadius(12);
          }
        }
        .width('100%')
        .margin({ bottom: 8 });

        if (this.courses.length === 0) {
          Text('暂无课程')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor($r('app.color.page_background'));
        } else {
          ForEach(this.courses, (course: Course, index: number) => {
            AnimatedListItem({ delay: index * 50 }) {
              Row({ space: 10 }) {
                Column()
                  .width(4)
                  .height(50)
                  .borderRadius(3)
                  .backgroundColor($r('app.color.primary_color'));

                Column({ space: 3 }) {
                  Text(course.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });

                  Text(this.formatCourseTime(course))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%');

                  Text(`${course.roomName || '地点未知'} · ${course.teacherName || '教师未知'}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_tertiary'))
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start);
              }
              .width('100%')
              .padding(12)
              .margin({ bottom: 8 })
              .borderRadius(12)
              .backgroundColor($r('app.color.page_background'));
            }
          });
        }
      }
      .width('100%')
      .padding(12);
    }
  }
}
