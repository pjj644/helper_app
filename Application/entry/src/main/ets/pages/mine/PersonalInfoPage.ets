import { router } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AuthService } from '../../service/AuthService';
import { ExamService } from '../../service/ExamService';
import { CourseRepository } from '../../repository/CourseRepository';
import { ScheduleRepository } from '../../repository/ScheduleRepository';
import { ExamItem } from '../../model/classTableModel/ExamModel';
import { RawCourseTableData } from '../../model/classTableModel/CourseModel';
import { RouterConstants } from '../../common/constants/AppConstants';

/** 统计一段时间内互不重复的课程名数量（原始数据按 84 槽位活动矩阵存储） */
function countDistinctCourses(rawJson: string): number {
  if (!rawJson) {
    return 0;
  }
  try {
    const data = JSON.parse(rawJson) as RawCourseTableData;
    if (!data.activities || !Array.isArray(data.activities)) {
      return 0;
    }
    const names = new Set<string>();
    for (let i = 0; i < data.activities.length; i++) {
      const slot = data.activities[i];
      if (!slot || !Array.isArray(slot)) {
        continue;
      }
      for (let j = 0; j < slot.length; j++) {
        const activity = slot[j];
        if (activity && activity.courseName) {
          names.add(activity.courseName);
        }
      }
    }
    return names.size;
  } catch (e) {
    return 0;
  }
}

@Entry
@Component
struct PersonalInfoPage {
  @State email: string = '';
  @State userId: string = '';
  @State loginAtText: string = '';
  @State courseCount: number = 0;
  @State upcomingExamCount: number = 0;
  @State scheduleCount: number = 0;
  @State loading: boolean = true;

  async aboutToAppear(): Promise<void> {
    try {
      const context = getContext(this);
      const session = await AuthService.getLoginSession(context);
      if (session) {
        this.email = session.email || '';
        this.userId = session.userId || '';
        if (session.loginAt) {
          const d = new Date(session.loginAt);
          this.loginAtText =
            `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')} ` +
            `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
        } else {
          this.loginAtText = '未知';
        }
      }

      const rawCourseJson = await CourseRepository.loadCourseData(context);
      this.courseCount = countDistinctCourses(rawCourseJson);

      const exams: ExamItem[] = await ExamService.loadExams(context);
      this.upcomingExamCount = ExamService.getUpcomingExams(exams).length;

      const schedules = await ScheduleRepository.loadSchedules(context);
      this.scheduleCount = schedules.length;
    } catch (e) {
      console.error('[PersonalInfo] load error:', JSON.stringify(e));
    } finally {
      this.loading = false;
    }
  }

  private copyUserId(): void {
    if (!this.userId) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.userId);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.getUIContext().getPromptAction().showToast({ message: '用户 ID 已复制' });
      }).catch((error: Error) => {
        console.error('[PersonalInfo] copy failed:', JSON.stringify(error));
      });
    } catch (error) {
      console.error('[PersonalInfo] copy exception:', JSON.stringify(error));
    }
  }

  private avatarText(): string {
    if (this.email && this.email.length > 0) {
      return this.email.substring(0, 1).toUpperCase();
    }
    return '?';
  }

  build() {
    Column() {
      // 顶栏
      Row() {
        Button('返回')
          .fontSize(14)
          .backgroundColor($r('app.color.button_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => router.back());
        Text('个人信息')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 64 });
      }
      .width('92%')
      .height(52)
      .margin({ top: 8 });

      Scroll() {
        Column({ space: 12 }) {
          // 账号信息卡
          Column({ space: 12 }) {
            Text('账号信息')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%');

            Row({ space: 12 }) {
              Text(this.avatarText())
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .width(52)
                .height(52)
                .textAlign(TextAlign.Center)
                .borderRadius(26)
                .backgroundColor($r('app.color.primary_color'));

              Column({ space: 4 }) {
                Text(this.email ? this.email : '未登录')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
                Row({ space: 4 }) {
                  Circle()
                    .width(6)
                    .height(6)
                    .fill(this.email ? $r('app.color.success_color') : $r('app.color.warning_color'));
                  Text(this.email ? '已登录' : '未登录，请先在「我的」页登录')
                    .fontSize(12)
                    .fontColor(this.email ? $r('app.color.success_color') : $r('app.color.text_tertiary'));
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1);
            }
            .width('100%');

            if (this.email) {
              Column({ space: 8 }) {
                this.InfoRow('用户 ID', this.userId ? this.userId : '未知', this.userId ? '点击复制' : '');
                this.InfoRow('登录时间', this.loginAtText, '');
              }
              .width('100%');
            } else {
              Button('去登录')
                .fontSize(14)
                .fontColor($r('app.color.primary_color'))
                .backgroundColor($r('app.color.accent_bg_color'))
                .width('100%')
                .onClick(() => {
                  router.pushUrl({ url: RouterConstants.PAGE_LOGIN }).catch((error: Error) => {
                    console.error('[PersonalInfo] 跳转登录失败:', error);
                  });
                });
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.card_background'))
          .alignItems(HorizontalAlign.Start);

          // 校园数据概况卡
          Column({ space: 12 }) {
            Text('校园数据概况')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%');

            this.InfoRow('本机课表课程', this.loading ? '统计中…' : (this.courseCount > 0 ? `${this.courseCount} 门` : '未导入'), '');
            this.InfoRow('待考考试', this.loading ? '统计中…' : `${this.upcomingExamCount} 场`, '');
            this.InfoRow('自定义日程', this.loading ? '统计中…' : `${this.scheduleCount} 条`, '');
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.card_background'))
          .alignItems(HorizontalAlign.Start);

          // 数据与隐私说明卡
          Column({ space: 8 }) {
            Text('数据与隐私')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%');
            Text('本应用的课表、考试、成绩与日程数据默认仅存储在本机；只有在您开启同步功能后，数据才会上传至您本人登录的华为云账号空间。' +
              'AI 对话历史在开启会话云同步时会以 AES-GCM 加密后存储。您可以随时在「账号管理」中退出登录或注销账号并彻底清除全部数据。')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(20);
          }
          .width('100%')
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.card_background'))
          .alignItems(HorizontalAlign.Start);

          // 账号操作入口
          Column() {
            Row() {
              Text('账号管理')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'));
              Blank();
              Text('退出登录 / 注销账号 ›')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'));
            }
            .width('100%')
            .padding(16)
            .onClick(() => {
              router.pushUrl({ url: RouterConstants.PAGE_ACCOUNT_MANAGE }).catch((error: Error) => {
                console.error('[PersonalInfo] 跳转账号管理失败:', error);
              });
            });
          }
          .width('100%')
          .borderRadius(14)
          .backgroundColor($r('app.color.card_background'));
        }
        .width('92%')
        .padding({ top: 12, bottom: 24 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring);
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'));
  }

  @Builder
  private InfoRow(label: string, value: string, hint: string): void {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'));
      Blank();
      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      if (hint) {
        Text(hint)
          .fontSize(12)
          .fontColor($r('app.color.primary_color'))
          .margin({ left: 8 });
      }
    }
    .width('100%')
    .onClick(() => {
      if (hint && label === '用户 ID') {
        this.copyUserId();
      }
    });
  }
}
