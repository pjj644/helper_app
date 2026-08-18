let storage = new LocalStorage();

@Entry(storage)
@Component
struct CourseWidgetCard2x2 {
  @LocalStorageProp('courseName') courseName: string = '高等数学';
  @LocalStorageProp('location') location: string = '品学楼 A101';
  @LocalStorageProp('time') time: string = '10:20';

  build() {
    Column() {
      Row() {
        Image($r('app.media.startIcon'))
          .width(16)
          .height(16)
          .borderRadius(4)
        Text('下一节课')
          .fontSize(12)
          .fontColor('#666666')
          .margin({ left: 6 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Blank()

      Text(this.courseName)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row() {
        Text(this.location)
          .fontSize(12)
          .fontColor('#0A59F7')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .margin({ top: 4 })

      Blank()

      Row() {
        Text(`开始时间: ${this.time}`)
          .fontSize(11)
          .fontColor('#999999')
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .backgroundColor('#F5F7FA')
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { targetPage: 'course_table' }
      });
    })
  }
}
