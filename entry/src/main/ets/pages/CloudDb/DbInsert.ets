import { cloudDatabase } from '@kit.CloudFoundationKit';
import { Post } from './Post';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RouterParamsType } from './CloudDb';

const MAX_ID = 100;
const HILOG_DOMAIN = 0x0000;
const TAG = '[CloudDBPage]';
// fixed userId
const userId: string = '9527';
// 'Demo' is the 'cloudDBZoneName' field defined in CloudProgram/clouddb/dataentry/d_Post.json
const agcDataBase: cloudDatabase.DatabaseZone = cloudDatabase.zone('Demo');

@Component
export struct DbInsert {
  @Consume('pathStack') pathStack: NavPathStack;
  @State content: string = '';
  private isEditing: boolean = false;
  private recordId: string | undefined = undefined;

  @Builder
  getTitle() {
    Text($r('app.string.cloudDB_label'))
      .fontSize($r('app.float.number_20'))
      .fontWeight(FontWeight.Bold)
      .margin({ left: $r('app.float.number_10') })
      .height('100%')
  }

  onWillShow() {
    const params = this.pathStack.getParamByName('DbInsert')[0] as RouterParamsType;
    this.content = params.content;
    this.isEditing = params.isEditing;
    this.recordId = params.recordId;
  }

  handleUpsert() {
    if (this.content !== '') {
      const post = new Post();
      if (this.isEditing) {
        post.id = Number(this.recordId);
      } else {
        post.id = Math.round(Math.random() * MAX_ID);
      }
      post.content = this.content;
      post.insertDate = new Date();
      post.userId = userId;

      agcDataBase.upsert(post).then(() => {
        this.getUIContext().showAlertDialog({
          title: $r('app.string.dialog_success_title'),
          message: $r('app.string.dialog_success_message'),
          cancel: () => {
            this.pathStack.pop();
          }
        });
      }).catch((err: BusinessError) => {
        hilog.error(HILOG_DOMAIN, TAG, 'upsert error %{public}s', JSON.stringify(err));
      });
    }
  }

  build() {
    NavDestination() {
      Column() {
        TextArea({ text: this.content })
          .height($r('app.float.number_100'))
          .margin({ top: $r('app.float.number_10') })
          .backgroundColor($r('app.color.start_window_background'))
          .border({
            color: $r('app.color.body_color'),
            width: $r('app.float.number_1'),
            radius: $r('app.float.number_5')
          })
          .onChange((event) => {
            this.content = event;
          })

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Text($r('app.string.publishButton_label'))
            .textAlign(TextAlign.Center)
            .fontSize($r('app.float.body_font_size'))
            .width('90%')
            .height($r('app.float.number_40'))
        }
        .margin({ top: $r('app.float.number_10') })
        .borderRadius($r('app.float.number_5'))
        .width('100%')
        .onClick(() => {
          this.handleUpsert();
        })
      }.margin({
        left: $r('app.float.number_20'),
        right: $r('app.float.number_20')
      })
      .height('100%')
    }.title(this.getTitle())
    .onWillShow(() => {
      this.onWillShow();
    })
  }
}