import { router } from '@kit.ArkUI';
import { AuthService } from '../../service/AuthService';
import { ThemeManager } from '../../common/utils/ThemeManager';

@Entry
@Component
struct AccountManage {
  @State currentEmail: string = '';
  @State loginTime: string = '';

  async aboutToAppear(): Promise<void> {
    try {
      const context = getContext(this);
      const session = await AuthService.getLoginSession(context);
      if (session) {
        this.currentEmail = session.email || '';
        if (session.loginAt) {
          const d = new Date(session.loginAt);
          this.loginTime = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')} ${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
        } else {
          this.loginTime = '未知';
        }
      }
    } catch (e) {
      console.error('[AccountManage] load error:', JSON.stringify(e));
    }
  }

  private async logout(): Promise<void> {
    try {
      const context = getContext(this);
      await AuthService.clearSession(context);
      this.getUIContext().getPromptAction().showToast({ message: '已登出' });
      router.back();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '登出失败' });
    }
  }

  private async deleteAccount(): Promise<void> {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '注销账号警告',
        message: '注销账号将永久删除您的所有本地与云端数据（包括课表、考试、成绩、日程及 AI 历史会话），该操作不可恢复！是否确认注销？',
        buttons: [
          { text: '取消', color: '#888888' },
          { text: '确认注销', color: '#D64545' }
        ]
      }, async (err, data) => {
        if (!err && data.index === 1) {
          const context = getContext(this);
          const success = await AuthService.deleteAccount(context);
          if (success) {
            this.getUIContext().getPromptAction().showToast({ message: '账号已注销，所有数据已清理' });
            router.back();
          } else {
            this.getUIContext().getPromptAction().showToast({ message: '注销失败，请稍后再试' });
          }
        }
      });
    } catch (e) {
      console.error('[AccountManage] deleteAccount dialog error:', JSON.stringify(e));
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .fontSize(14)
          .fontColor(ThemeManager.getAccentColor())
          .backgroundColor(ThemeManager.getCardColor())
          .borderRadius(8)
          .onClick(() => router.back());
        Blank();
      }
      .width('100%')
      .padding(12);

      Column({ space: 16 }) {
        Column({ space: 8 }) {
          Text('当前登录账号')
            .fontSize(13)
            .fontColor(ThemeManager.getTextSecondaryColor());
          Text(this.currentEmail || '未登录')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getTextPrimaryColor());
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);

        Column({ space: 8 }) {
          Text('最近登录时间')
            .fontSize(13)
            .fontColor(ThemeManager.getTextSecondaryColor());
          Text(this.loginTime || '未知')
            .fontSize(16)
            .fontColor(ThemeManager.getTextPrimaryColor());
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);

        Button('退出登录')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor('#F59E0B')
          .borderRadius(12)
          .margin({ top: 12 })
          .onClick(() => this.logout());

        Button('注销账号')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor('#D64545')
          .borderRadius(12)
          .margin({ top: 4 })
          .onClick(() => this.deleteAccount());

        Text('注销账号将永久销毁所有本地数据与关联的云端信息')
          .fontSize(12)
          .fontColor(ThemeManager.getTextTertiaryColor())
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 4 });
      }
      .width('100%')
      .padding(16);
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundColor());
  }
}
