import { fileIo } from '@kit.CoreFileKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { cloudStorage } from '@kit.CloudFoundationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

const HILOG_DOMAIN = 0x0000;
const TAG = '[CloudStorage]';

const UPDATE_PROGRESS_MIN_VALUE = 0;
const UPDATE_PROGRESS_MAX_VALUE = 100;
const UPDATE_PROGRESS_LENGTH = 5;
const MAX_SELECT_NUMBER = 1;
const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();

type UploadCompleteCallback = (uploadSuccess: boolean) => void;

@Component
export struct CloudStorage {
  @State isUploading: boolean = false;
  @State showUpdateProgress: boolean = false;
  @State updateProgress: number = UPDATE_PROGRESS_MIN_VALUE;
  @State accessAddress: string = '';
  @State publicAddress: string = '';
  @State imageUrl: string | ResourceStr = $r('app.media.empty_image');

  @Builder
  getTitle() {
    Text($r('app.string.cloudStorage_label'))
      .fontSize($r('app.float.number_20'))
      .fontWeight(FontWeight.Bold)
      .margin({ left: $r('app.float.number_10') })
      .height('100%')
  }

  build() {
    NavDestination() {
      Column() {
        Column() {
          Row() {
            Text($r('app.string.cloudStorage_description')).fontSize($r('app.float.body_font_size'))
          }.margin({ bottom: $r('app.float.number_15') })

          Row() {
            Button($r('app.string.cloudStorage_uploadButton'), { type: ButtonType.Normal })
              .borderRadius($r('app.float.number_5'))
              .width('100%')
              .opacity(!this.isUploading ? $r('app.float.number_1') : $r('app.float.number_0_5'))
              .enabled(!this.isUploading)
              .height($r('app.float.number_40'))
              .onClick(() => {
                this.isUploading = true;
                this.upLoadImage();
              })
          }

          if (this.showUpdateProgress) {
            Row() {
              Text($r('app.string.cloudStorage_progressLabel')).fontSize($r('app.float.body_font_size'))
              Text(`: ${this.updateProgress.toString().substring(0, UPDATE_PROGRESS_LENGTH)} %`)
                .fontSize($r('app.float.body_font_size'))
            }.margin({ top: $r('app.float.number_10') })
          }
        }.alignItems(HorizontalAlign.Start).width('90%').margin({ bottom: $r('app.float.number_20') })

        Column() {
          Row() {
            Image(this.imageUrl)
              .objectFit(ImageFit.Contain)
              .height($r('app.float.number_250'))
              .backgroundColor($r('app.color.black'))
          }
        }.width('90%').margin({ bottom: $r('app.float.number_15') })

        if (this.accessAddress !== '' && this.publicAddress !== '') {
          Column({ space: 10 }) {
            Flex({ justifyContent: FlexAlign.SpaceBetween }) {
              Column() {
                Text($r('app.string.cloudStorage_accessAddressLabel'))
                  .fontSize($r('app.float.list_item_font_size'))
                  .fontWeight(FontWeight.Bold)
                  .textAlign(TextAlign.Start)
                  .width('100%')
                Text(this.accessAddress)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Start)
                  .wordBreak(WordBreak.BREAK_ALL)
                  .width('100%')
                  .maxLines(1)
                  .fontSize($r('app.float.list_item_font_size'))
              }.height($r('app.float.number_30'))
            }

            Flex({ justifyContent: FlexAlign.SpaceBetween }) {
              Column() {
                Text($r('app.string.cloudStorage_publicAccessAddressLabel'))
                  .fontSize($r('app.float.list_item_font_size'))
                  .fontWeight(FontWeight.Bold)
                  .textAlign(TextAlign.Start)
                  .width('100%')
                Text(this.publicAddress)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Start)
                  .wordBreak(WordBreak.BREAK_ALL)
                  .width('100%')
                  .maxLines(1)
                  .fontSize($r('app.float.list_item_font_size'))
              }.height($r('app.float.number_30'))
            }
          }.width('90%').margin({ right: $r('app.float.number_10') })
        }
      }.height('100%')
    }.title(this.getTitle())
  }

  private upLoadImage() {
    this.selectImage().then((selectImageUri: string) => {
      if (!selectImageUri) {
        hilog.info(HILOG_DOMAIN, TAG, 'cancel select image!');
        this.isUploading = false;
        return;
      }
      this.initStates();
      // copy select file to cache directory
      const fileName = selectImageUri.split('/').pop() as string;
      const cacheFilePath = `${this.getUIContext().getHostContext()?.cacheDir}/${fileName}`;
      this.copyFile(selectImageUri, cacheFilePath);

      const cloudPath = `test_cloud_storage/image_${new Date().getTime()}.jpg`;
      bucket.uploadFile(this.getUIContext().getHostContext(), {
        localPath: cacheFilePath,
        cloudPath: cloudPath
      }).then(task => {
        // add task event listener
        this.addEventListener(task, this.onUploadCompleted(cloudPath, cacheFilePath));
        // start task
        task.start().catch((err: BusinessError) => {
          hilog.error(HILOG_DOMAIN, TAG, 'uploadFile failed, error code: %{public}d, message: %{public}s',
            err.code, err.message);
        });
      }).catch((err: BusinessError) => {
        hilog.error(HILOG_DOMAIN, TAG, 'uploadFile failed, error code: %{public}d, message: %{public}s',
          err.code, err.message);
        this.isUploading = false;
        this.showUpdateProgress = false;
      });
    }).catch((err: Error) => {
      hilog.error(HILOG_DOMAIN, TAG, 'upLoadImage error %{public}s', JSON.stringify(err));
      this.isUploading = false;
      this.showUpdateProgress = false;
    });
  }

  private async selectImage(): Promise<string> {
    return new Promise((resolve: (selectUri: string) => void, reject: (err: Error) => void) => {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      // 过滤选择媒体文件类型为IMAGE
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = MAX_SELECT_NUMBER;
      new photoAccessHelper.PhotoViewPicker().select(photoSelectOptions)
        .then((photoSelectResult: photoAccessHelper.PhotoSelectResult) => {
          resolve(photoSelectResult.photoUris[0]);
        })
        .catch((err: Error) => {
          reject(err);
        });
    });
  }

  private addEventListener(task: request.agent.Task, completeCallback: UploadCompleteCallback) {
    task.on('progress', (progress) => {
      hilog.info(HILOG_DOMAIN, TAG, 'on progress %{public}s', JSON.stringify(progress));
      this.updateProgress = progress.processed / progress.sizes[0] * UPDATE_PROGRESS_MAX_VALUE;
    });
    task.on('completed', (progress) => {
      hilog.info(HILOG_DOMAIN, TAG, 'on completed %{public}s', JSON.stringify(progress));
      completeCallback(true);
    });
    task.on('response', (response) => {
      hilog.info(HILOG_DOMAIN, TAG, 'on response %{public}s', JSON.stringify(response));
    });
    task.on('failed', (progress) => {
      hilog.error(HILOG_DOMAIN, TAG, 'on failed %{public}s', JSON.stringify(progress));
      completeCallback(false);
    });
  }

  private onUploadCompleted(cloudPath: string, cacheFilePath: string) {
    return (uploadSuccess: boolean) => {
      if (uploadSuccess) {
        bucket.getDownloadURL(cloudPath).then((downloadURL: string) => {
          hilog.info(HILOG_DOMAIN, TAG, 'DownloadURL: %{public}s', downloadURL);
          this.accessAddress = downloadURL;
          this.publicAddress = downloadURL;
          this.imageUrl = downloadURL;
        }).catch((err: BusinessError) => {
          hilog.error(HILOG_DOMAIN, TAG, 'getDownloadURL fail, error code: %{public}d, message: %{public}s',
            err.code, err.message);
        });
      }
      // delete cache file when task finished
      hilog.info(HILOG_DOMAIN, TAG, 'delete cache file %{public}s', cacheFilePath);
      fileIo.unlink(cacheFilePath).catch((err: BusinessError) => {
        hilog.error(HILOG_DOMAIN, TAG, 'file unlink fail, error code: %{public}d, message: %{public}s',
          err.code, err.message);
      });
      this.isUploading = false;
      this.showUpdateProgress = false;
    };
  }

  private copyFile(src: string, dest: string) {
    const srcFile = fileIo.openSync(src);
    const dstFile = fileIo.openSync(dest, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    fileIo.copyFileSync(srcFile.fd, dstFile.fd);
    fileIo.closeSync(srcFile);
    fileIo.closeSync(dstFile);
  }

  private initStates() {
    this.showUpdateProgress = true;
    this.updateProgress = UPDATE_PROGRESS_MIN_VALUE;
    this.accessAddress = '';
    this.publicAddress = '';
    this.imageUrl = $r('app.media.empty_image');
  }
}