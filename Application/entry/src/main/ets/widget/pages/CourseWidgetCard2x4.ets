let storage2x4 = new LocalStorage();

@Entry(storage2x4)
@Component
struct CourseWidgetCard2x4 {
  @LocalStorageProp('dateStr') dateStr: string = '今日课表';
  @LocalStorageProp('courseCount') courseCount: number = 0;
  @LocalStorageProp('course1_name') course1_name: string = '';
  @LocalStorageProp('course1_time') course1_time: string = '';
  @LocalStorageProp('course1_room') course1_room: string = '';
  @LocalStorageProp('course1_status') course1_status: string = '';
  @LocalStorageProp('course2_name') course2_name: string = '';
  @LocalStorageProp('course2_time') course2_time: string = '';
  @LocalStorageProp('course2_room') course2_room: string = '';
  @LocalStorageProp('course2_status') course2_status: string = '';
  @LocalStorageProp('course3_name') course3_name: string = '';
  @LocalStorageProp('course3_time') course3_time: string = '';
  @LocalStorageProp('course3_room') course3_room: string = '';
  @LocalStorageProp('course3_status') course3_status: string = '';

  build() {
    Column() {
      // 头部栏
      Row() {
        Row({ space: 6 }) {
          Image($r('app.media.startIcon'))
            .width(16)
            .height(16)
            .borderRadius(4)
          Text('成电课表')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
          Text(this.dateStr)
            .fontSize(11)
            .fontColor('#6B7280')
        }

        Blank()

        Text(this.courseCount > 0 ? `今日 ${this.courseCount} 节课` : '今日无课')
          .fontSize(11)
          .fontColor('#0A59F7')
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#EFF6FF')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(8)
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.courseCount === 0 || !this.course1_name) {
        // 无课状态
        Column({ space: 4 }) {
          Blank()
          Text('🎉')
            .fontSize(22)
          Text('今日暂无课程安排')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#374151')
          Text('享受自由学习与生活时光')
            .fontSize(11)
            .fontColor('#9CA3AF')
          Blank()
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 课程列表
        Column({ space: 6 }) {
          if (this.course1_name) {
            Row() {
              Text(this.course1_time)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.course1_status === '上课中' ? '#0A59F7' : '#4B5563')
                .width(42)

              Column({ space: 2 }) {
                Text(this.course1_name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#111827')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.course1_room)
                  .fontSize(10)
                  .fontColor('#6B7280')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.course1_status) {
                Text(this.course1_status)
                  .fontSize(10)
                  .fontColor(this.course1_status === '上课中' ? '#FFFFFF' : '#6B7280')
                  .backgroundColor(this.course1_status === '上课中' ? '#0A59F7' : '#F3F4F6')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
              }
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.course1_status === '上课中' ? '#F0F7FF' : '#F9FAFB')
            .borderRadius(8)
          }

          if (this.course2_name) {
            Row() {
              Text(this.course2_time)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.course2_status === '上课中' ? '#0A59F7' : '#4B5563')
                .width(42)

              Column({ space: 2 }) {
                Text(this.course2_name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#111827')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.course2_room)
                  .fontSize(10)
                  .fontColor('#6B7280')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.course2_status) {
                Text(this.course2_status)
                  .fontSize(10)
                  .fontColor(this.course2_status === '上课中' ? '#FFFFFF' : '#6B7280')
                  .backgroundColor(this.course2_status === '上课中' ? '#0A59F7' : '#F3F4F6')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
              }
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.course2_status === '上课中' ? '#F0F7FF' : '#F9FAFB')
            .borderRadius(8)
          }

          if (this.course3_name) {
            Row() {
              Text(this.course3_time)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.course3_status === '上课中' ? '#0A59F7' : '#4B5563')
                .width(42)

              Column({ space: 2 }) {
                Text(this.course3_name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#111827')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.course3_room)
                  .fontSize(10)
                  .fontColor('#6B7280')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.course3_status) {
                Text(this.course3_status)
                  .fontSize(10)
                  .fontColor(this.course3_status === '上课中' ? '#FFFFFF' : '#6B7280')
                  .backgroundColor(this.course3_status === '上课中' ? '#0A59F7' : '#F3F4F6')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
              }
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.course3_status === '上课中' ? '#F0F7FF' : '#F9FAFB')
            .borderRadius(8)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { targetPage: 'course_table' }
      });
    })
  }
}
