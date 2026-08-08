import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IdGenerator, importObject } from 'cloud_objects';

const HILOG_DOMAIN = 0x0000;
const TAG = '[CloudFunction]';

@Component
export struct CloudFunction {
  @State globalId: string = '';

  @Builder
  getTitle() {
      Text($r('app.string.cloud_function_title'))
        .fontSize($r('app.float.number_20'))
        .fontWeight(FontWeight.Bold)
        .margin({left: $r('app.float.number_10')})
        .height('100%')
  }

  build() {
    NavDestination() {
      Column({ space: 20 }) {
        Text($r('app.string.cloud_function_description'))
          .width('90%')
          .textAlign(TextAlign.Center)
          .fontSize($r('app.float.body_font_size'))
        Button($r('app.string.cloud_function_button_text'), { type: ButtonType.Normal })
          .width('90%')
          .height($r('app.float.number_40'))
          .borderRadius($r('app.float.number_5'))
          .onClick(() => {
            this.callIdGenerator();
          })

        Column() {
          Text(this.globalId).fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.body_color'))
            .height('100%')
        }
        .width('90%')
        .height($r('app.float.number_40'))
        .borderWidth($r('app.float.number_1'))
        .borderRadius($r('app.float.number_5'))
        .borderColor($r('app.color.body_color'))
      }
    }.title(this.getTitle());
  }

  private callIdGenerator() {
    const idGenerator = importObject(IdGenerator);
    idGenerator.randomUUID().then(result => {
      this.globalId = result.uuid;
    }).catch((err: BusinessError) => {
      hilog.error(HILOG_DOMAIN, TAG, 'call id-generator exception, ErrCode: %{public}d ErrMessage: %{public}s',
        err.code, err.message);
    });
  }
}
