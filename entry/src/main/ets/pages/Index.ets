import { CloudDb } from './CloudDb/CloudDb';
import { DbInsert } from './CloudDb/DbInsert';
import { CloudFunction } from './CloudFunction';
import { CloudStorage } from './CloudStorage';

@Entry
@Component
struct Index {
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();

  @Builder
  pathMap(routeName: string) {
    if (routeName === 'CloudFunction') {
      CloudFunction();
    } else if (routeName === 'CloudDb') {
      CloudDb();
    } else if (routeName === 'CloudStorage') {
      CloudStorage();
    } else if (routeName === 'DbInsert') {
      DbInsert();
    }
  }

  @Builder
  homeButton(title: Resource, description: Resource, routeName: string) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column() {
        Text(title)
          .fontSize($r('app.float.body_font_size'))
          .margin({ bottom: $r('app.float.number_5'), top: $r('app.float.number_5') })
          .fontWeight(FontWeight.Bold)
        Text(description)
          .textAlign(TextAlign.Center)
          .fontSize($r('app.float.body_font_size'))
          .margin({ bottom: $r('app.float.number_5') })
      }
      .width('100%')
    }
    .borderRadius($r('app.float.number_5'))
    .margin($r('app.float.number_10'))
    .borderWidth($r('app.float.number_1'))
    .borderColor($r('app.color.body_color'))
    .fontColor($r('app.color.body_color'))
    .backgroundColor($r('app.color.start_window_background'))
    .width('96%')
    .onClick(() => {
      this.pathStack.pushPathByName(routeName, null);
    })
  }

  build() {
    Navigation(this.pathStack) {
      Flex({ direction: FlexDirection.Column, justifyContent: FlexAlign.Center }) {
        Text($r('app.string.main_page_title'))
          .width('100%')
          .fontSize($r('app.float.main_title_font_size'))
          .textAlign(TextAlign.Center)
          .fontColor($r('app.color.body_color'))
          .margin({ bottom: $r('app.float.number_10') })
        this.homeButton($r('app.string.cloud_function_title'), $r('app.string.cloud_function_description_main'),
          'CloudFunction');
        this.homeButton($r('app.string.cloudDB_label'), $r('app.string.cloud_db_description_main'),
          'CloudDb');
        this.homeButton($r('app.string.cloudStorage_label'), $r('app.string.cloud_storage_description_main'),
          'CloudStorage');
      }
      .height('100%')
      .width('100%')
      .padding($r('app.float.number_10'))
      .backgroundColor($r('app.color.start_window_background'))
    }
    .hideTitleBar(true)
    .navDestination(this.pathMap)
  }
}