import { common } from '@kit.AbilityKit';
import { ThemeManager } from '../common/utils/ThemeManager';
import { PreferencesUtil } from '../common/PreferencesUtil';
import { AuthService } from '../service/AuthService';

@CustomDialog
export struct PrivacyDialogComponent {
  controller: CustomDialogController;
  onAgree?: () => void;
  @State showDetail: boolean = false;
  @State detailType: string = 'privacy'; // 'privacy' | 'user_agreement'

  build() {
    Column() {
      // 头部标题
      Row() {
        Text(this.showDetail ? (this.detailType === 'privacy' ? '隐私政策' : '用户协议') : '欢迎使用成电助手')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor());
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 20, bottom: 12 });

      if (this.showDetail) {
        // 详情长文本
        Scroll() {
          Column({ space: 12 }) {
            if (this.detailType === 'privacy') {
              Text('成电助手隐私政策')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeManager.getTextPrimaryColor());
              Text('1. 我们如何收集和使用信息\n' +
                '• 课程与考试数据：仅保存在您的设备本地 ArkData 数据库中，用于课程表展示、智能提醒及离线查看，我们不会在未经您允许的情况下上传到非官方服务器。\n' +
                '• 教务认证信息：在教务系统导入数据时，账号密码仅用于在本地 WebView 中与学校统一身份认证系统交互，本应用不保存您的教务登录密码。\n' +
                '• AI 助手对话：当您使用 AI 智能问答功能时，您的提问文本及必要的脱敏上下文将发送至 AI 代理服务用于生成回复。\n' +
                '• 麦克风权限：仅在您主动点击语音输入按钮时请求，用于语音转文字，不会在后台录音。')
                .fontSize(13)
                .lineHeight(20)
                .fontColor(ThemeManager.getTextSecondaryColor());

              Text('2. 权限使用说明\n' +
                '• 读取/写入日历：用于将课表与考试日程一键同步至系统日历。\n' +
                '• 通知发布：用于上课前与考试前向您发送系统横幅提醒。\n' +
                '• 存储权限：用于保存自定义课表背景图及数据导出备份。')
                .fontSize(13)
                .lineHeight(20)
                .fontColor(ThemeManager.getTextSecondaryColor());

              Text('3. 账号注销与数据清理\n' +
                '您随时可以在「我的」或「账号管理」中选择注销账号，注销后将彻底清除您在本地及云端的所有存储数据。')
                .fontSize(13)
                .lineHeight(20)
                .fontColor(ThemeManager.getTextSecondaryColor());
            } else {
              Text('成电助手用户服务协议')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeManager.getTextPrimaryColor());
              Text('1. 软件使用准则\n' +
                '成电助手是一款专为电子科技大学在校师生设计的校园生活与日程辅助工具。用户在使用本应用时应当遵守相关法律法规及学校网络管理规定。\n\n' +
                '2. 免责声明\n' +
                '• 本应用数据来源于学校教务系统与公开校园服务，教务排课、考试安排及成绩等核心信息均以教务处官方系统为准。\n' +
                '• 生成式 AI 助手输出的信息由大语言模型生成，仅供参考，不代表学校官方立场。\n\n' +
                '3. 服务变更与终止\n' +
                '开发者保留根据校园教务系统升级对接口和功能进行维护调整的权利。')
                .fontSize(13)
                .lineHeight(20)
                .fontColor(ThemeManager.getTextSecondaryColor());
            }

            Button('返回授权概览')
              .fontSize(13)
              .fontColor(ThemeManager.getAccentColor())
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.showDetail = false;
              })
              .margin({ top: 8, bottom: 8 });
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16 });
        }
        .height(280)
        .scrollable(ScrollDirection.Vertical);
      } else {
        // 概览摘要
        Scroll() {
          Column({ space: 10 }) {
            Text('为了向您提供课程表展示、考试与成绩查询、日程提醒及校园 AI 问答等服务，我们需要依据《用户协议》和《隐私政策》收集并处理相关必要信息：')
              .fontSize(14)
              .lineHeight(20)
              .fontColor(ThemeManager.getTextPrimaryColor());

            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text('📅').fontSize(16);
                Text('日历与通知：将课程与考试同步至系统日历并发送临近提醒；')
                  .fontSize(13)
                  .fontColor(ThemeManager.getTextSecondaryColor())
                  .layoutWeight(1);
              }
              Row({ space: 8 }) {
                Text('🔒').fontSize(16);
                Text('本地安全存储：课表及个人数据默认保存在本地，保障数据安全；')
                  .fontSize(13)
                  .fontColor(ThemeManager.getTextSecondaryColor())
                  .layoutWeight(1);
              }
              Row({ space: 8 }) {
                Text('🤖').fontSize(16);
                Text('校园 AI 助手：提供智能日程规划与校园问答，内容由大模型生成；')
                  .fontSize(13)
                  .fontColor(ThemeManager.getTextSecondaryColor())
                  .layoutWeight(1);
              }
            }
            .padding(10)
            .backgroundColor(ThemeManager.isDarkMode() ? '#1A202C' : '#F1F5F9')
            .borderRadius(8)
            .width('100%');

            Flex({ wrap: FlexWrap.Wrap }) {
              Text('点击“同意并继续”即表示您已阅读并同意')
                .fontSize(12)
                .fontColor(ThemeManager.getTextSecondaryColor());
              Text('《用户协议》')
                .fontSize(12)
                .fontColor(ThemeManager.getAccentColor())
                .onClick(() => {
                  this.detailType = 'user_agreement';
                  this.showDetail = true;
                });
              Text('与')
                .fontSize(12)
                .fontColor(ThemeManager.getTextSecondaryColor());
              Text('《隐私政策》')
                .fontSize(12)
                .fontColor(ThemeManager.getAccentColor())
                .onClick(() => {
                  this.detailType = 'privacy';
                  this.showDetail = true;
                });
            }
            .margin({ top: 4 });
          }
          .padding({ left: 16, right: 16 });
        }
        .height(240);
      }

      // 底部操作按钮
      Row({ space: 12 }) {
        Button('不同意并退出')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .backgroundColor(ThemeManager.isDarkMode() ? '#2D3748' : '#E2E8F0')
          .borderRadius(10)
          .onClick(() => {
            const context = getContext(this) as common.UIAbilityContext;
            if (context && typeof context.terminateSelf === 'function') {
              context.terminateSelf();
            }
            this.controller.close();
          });

        Button('同意并继续')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeManager.getAccentColor())
          .borderRadius(10)
          .onClick(() => {
            const context = getContext(this);
            PreferencesUtil.getInstance().setAgreedPrivacy(true);
            AuthService.initSDK(context);
            if (this.onAgree) {
              this.onAgree();
            }
            this.controller.close();
          });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 });
    }
    .width('90%')
    .backgroundColor(ThemeManager.getCardColor())
    .borderRadius(16)
    .padding({ top: 4, bottom: 4 });
  }
}
