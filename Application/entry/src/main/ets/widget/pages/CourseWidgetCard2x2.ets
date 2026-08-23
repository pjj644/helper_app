let storage2x2 = new LocalStorage();

@Entry(storage2x2)
@Component
struct CourseWidgetCard2x2 {
  @LocalStorageProp('courseName') courseName: string = '高等数学';
  @LocalStorageProp('location') location: string = '品学楼 A101';
  @LocalStorageProp('time') time: string = '10:20';
  @LocalStorageProp('countdownText') countdownText: string = '距上课 30 分钟';
  @LocalStorageProp('hasCourseToday') hasCourseToday: boolean = true;

  build() {
    Column() {
      // 头部
      Row() {
        Row({ space: 4 }) {
          Image($r('app.media.startIcon'))
            .width(16)
            .height(16)
            .borderRadius(4)
          Text('下一节课')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4B5563')
        }

        Blank()

        Text(this.time)
          .fontSize(11)
          .fontColor('#0A59F7')
          .fontWeight(FontWeight.Bold)
          .backgroundColor('#EFF6FF')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
      .width('100%')

      Blank()

      // 核心课程信息
      Column({ space: 4 }) {
        Text(this.courseName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 4 }) {
          Text('📍')
            .fontSize(10)
          Text(this.location)
            .fontSize(12)
            .fontColor('#4B5563')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Blank()

      // 底部状态提示
      Row() {
        Text(this.countdownText)
          .fontSize(11)
          .fontColor(this.courseName === '今日已无课' || this.courseName === '暂无待上课程' ? '#9CA3AF' : '#059669')
          .fontWeight(FontWeight.Medium)

        Blank()

        Text('详情 ›')
          .fontSize(11)
          .fontColor('#9CA3AF')
      }
      .width('100%')
    }
    .padding(14)
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
