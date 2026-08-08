import { hilog } from '@kit.PerformanceAnalysisKit';
import { cloudDatabase } from '@kit.CloudFoundationKit';
import { Post } from './Post';

const HILOG_DOMAIN = 0x0000;
const TAG = '[CloudDBPage]';
const CONTENT_MAX_LINE = 2;
// fixed userId
const userId = '9527';
// 'Demo' is the 'cloudDBZoneName' field defined in CloudProgram/clouddb/dataentry/d_Post.json
const agcDataBase: cloudDatabase.DatabaseZone = cloudDatabase.zone('Demo');

export interface RouterParamsType {
  isEditing: boolean;
  checkBoxStatus: boolean;
  recordId?: string;
  content: string;
}

@Component
export struct CloudDb {
  @Consume('pathStack') pathStack: NavPathStack;
  @State isSelected: boolean = false;
  @State allRecords: Post[] = [];

  @Builder
  getTitle() {
    Text($r('app.string.cloudDB_label'))
      .fontSize($r('app.float.number_20'))
      .fontWeight(FontWeight.Bold)
      .margin({ left: $r('app.float.number_10') })
      .height('100%')
  }

  onWillShow() {
    this.orderByDate();
  }

  getPostList() {
    this.queryRecord(new cloudDatabase.DatabaseQuery(Post).orderByDesc('insertDate'));
  }

  orderByMostLiked() {
    this.queryRecord(new cloudDatabase.DatabaseQuery(Post).orderByDesc('likeCount'));
  }

  getMyPosts(uid: string) {
    this.queryRecord(new cloudDatabase.DatabaseQuery(Post).equalTo('userId', uid).orderByDesc('insertDate'));
  }

  getMyPostsByLike(uid: string) {
    this.queryRecord(new cloudDatabase.DatabaseQuery(Post).equalTo('userId', uid).orderByDesc('likeCount'));
  }

  queryRecord(condition: cloudDatabase.DatabaseQuery<Post>) {
    agcDataBase.query(condition).then(result => {
      hilog.info(HILOG_DOMAIN, TAG, 'query success : %{public}s', JSON.stringify(result));
      this.allRecords = result;
    }).catch((err: Error) => {
      hilog.error(HILOG_DOMAIN, TAG, 'queryRecord err %{public}s', JSON.stringify(err));
    });
  }

  deleteRecord(post: Post) {
    agcDataBase.delete(post).then(record => {
      hilog.info(HILOG_DOMAIN, TAG, 'delete success: %{public}d', record);
      this.onCheckboxToggle();
    }).catch((err: Error) => {
      hilog.error(HILOG_DOMAIN, TAG, 'delete err %{public}s', JSON.stringify(err));
    });
  }

  updateLikeCount(item: Post) {
    let likes: string[] = JSON.parse(item.likes);
    if (likes.includes(userId)) {
      likes = likes.filter(i => i !== userId);
    } else {
      likes.push(userId);
    }
    item.likeCount = likes.length;
    item.likes = JSON.stringify(likes);

    agcDataBase.upsert(item).then(() => {
      this.allRecords = this.allRecords.map((record: Post) => {
        if (record.id === item.id) {
          hilog.info(HILOG_DOMAIN, TAG, 'record: %{public}s', JSON.stringify(record));
          record.likeCount = item.likeCount;
          record.likes = item.likes;
        }
        return record;
      });
    }).catch((err: Error) => {
      hilog.error(HILOG_DOMAIN, TAG, 'upsert err %{public}s', JSON.stringify(err));
    });
  }

  orderByDate() {
    if (this.isSelected) {
      this.getMyPosts(userId);
    } else {
      this.getPostList();
    }
  }

  orderByLikes() {
    if (this.isSelected) {
      this.getMyPostsByLike(userId);
    } else {
      this.orderByMostLiked();
    }
  }

  onCheckboxToggle() {
    if (this.isSelected) {
      this.getMyPosts(userId);
    } else {
      this.getPostList();
    }
  }

  getFormattedDate(date: Date) {
    return new Intl.DateTimeFormat('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
      hour12: false
    }).format(date);
  }

  build() {
    NavDestination() {
      Column() {
        Flex({ justifyContent: FlexAlign.SpaceBetween }) {
          Row() {
            Row() {
              Text($r('app.string.cloudDB_Publications'))
                .fontSize($r('app.float.list_item_font_size'))
                .onClick(() => {
                  this.orderByDate();
                })
              Text('|').fontSize($r('app.float.list_item_font_size')).margin({ left: $r('app.float.number_5') })
              Text($r('app.string.cloudDB_HighestHit'))
                .fontSize($r('app.float.list_item_font_size'))
                .margin({ left: $r('app.float.number_5') })
                .onClick(() => {
                  this.orderByLikes();
                })
            }
            .border({ radius: $r('app.float.number_5'), width: $r('app.float.number_1') })
            .padding($r('app.float.number_5'))

            Row() {
              Checkbox()
                .width($r('app.float.number_15'))
                .height($r('app.float.number_15'))
                .select(this.isSelected)
                .onChange((value: boolean) => {
                  this.isSelected = value;
                  this.onCheckboxToggle();
                })
                .onAppear(() => {
                  this.onCheckboxToggle();
                })
              Text($r('app.string.cloudDB_SeeOnly'))
                .fontSize($r('app.float.list_item_font_size'))
            }
          }.margin({ left: $r('app.float.number_5') })

          Row() {
            Button({ type: ButtonType.Normal, stateEffect: true }) {
              Text($r('app.string.cloudDB_new_record'))
                .fontSize($r('app.float.list_item_font_size'))
                .textAlign(TextAlign.Center)
                .margin($r('app.float.number_5'))
                .fontColor($r('app.color.white'))
            }
            .width($r('app.float.number_70'))
            .height($r('app.float.number_25'))
            .borderRadius($r('app.float.number_5'))
            .onClick(() => {
              this.pathStack.pushPathByName('DbInsert', {
                isEditing: false,
                checkBoxStatus: this.isSelected,
                content: ''
              } as RouterParamsType);
            })
          }
        }.margin({ top: $r('app.float.number_10'), bottom: $r('app.float.number_10') })

        Column() {
          List({ initialIndex: 0, scroller: new Scroller() }) {
            ForEach(this.allRecords, (item: Post) => {
              ListItem() {
                Column() {
                  Flex({ justifyContent: FlexAlign.SpaceBetween }) {
                    Image($r('app.media.window')).width($r('app.float.number_15')).height($r('app.float.number_15'))
                    Text(this.getFormattedDate(item.insertDate))
                      .fontSize($r('app.float.list_item_font_size'))
                  }.margin({ bottom: $r('app.float.number_15') })

                  Row() {
                    Text(item.content)
                      .fontSize($r('app.float.list_item_font_size'))
                      .width('100%')
                      .maxLines(CONTENT_MAX_LINE)
                  }.margin({ bottom: $r('app.float.number_15') })

                  Flex({ justifyContent: FlexAlign.SpaceBetween }) {
                    if (item.userId === userId) {
                      Row() {
                        Image($r('app.media.ic_public_delete_filled_red'))
                          .width($r('app.float.number_20'))
                          .height($r('app.float.number_20'))
                          .margin({ right: $r('app.float.number_10') })
                          .onClick(() => {
                            this.getUIContext().showAlertDialog({
                              title: $r('app.string.deleteButton_label'),
                              message: $r('app.string.popUpDesc_label'),
                              primaryButton: {
                                value: $r('app.string.deleteButton_label'),
                                action: () => {
                                  this.deleteRecord(item);
                                },
                                backgroundColor: $r('app.color.dialog_cancel_background'),
                                fontColor: $r('app.color.white')
                              },
                              secondaryButton: {
                                value: $r('app.string.cancelButton_label'),
                                action: () => {
                                  // do nothing
                                },
                                fontColor: $r('app.color.action_button_background')
                              },
                              autoCancel: true
                            });
                          })
                        Image($r('app.media.ic_public_edit_outline'))
                          .width($r('app.float.number_20'))
                          .height($r('app.float.number_20'))
                          .onClick(() => {
                            this.pathStack.pushPathByName('DbInsert', {
                              isEditing: true,
                              recordId: item.id.toString(),
                              content: item.content,
                              checkBoxStatus: this.isSelected
                            } as RouterParamsType);
                          })
                      }
                    }
                    Row() {
                      Text(item.likeCount.toString()).fontSize($r('app.float.list_item_font_size'))
                      Image(item.likes.includes(userId) ? $r('app.media.ic_public_thumb_sup_filled') :
                      $r('app.media.ic_public_thumb_sup'))
                        .width($r('app.float.number_20'))
                        .height($r('app.float.number_20'))
                        .margin({ left: $r('app.float.number_5') })
                        .onClick(() => {
                          this.updateLikeCount(item);
                        })
                    }
                  }
                }
              }
              .padding($r('app.float.number_10'))
              .border({
                color: $r('app.color.black'),
                width: $r('app.float.number_1'),
                radius: $r('app.float.number_5')
              })
              .margin({ top: $r('app.float.number_10') })
            }, (item: Post) => JSON.stringify(item))
          }
          .height('85%')
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }.alignItems(HorizontalAlign.Start).margin({
        left: $r('app.float.number_20'),
        right: $r('app.float.number_20')
      })
    }.title(this.getTitle())
    .onWillShow(() => {
      this.onWillShow();
    })
  }
}