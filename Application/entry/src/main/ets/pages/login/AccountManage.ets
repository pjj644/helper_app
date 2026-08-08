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
      console.error('AccountManage load error:', JSON.stringify(e));
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
          .backgroundColor('#D64545')
          .borderRadius(12)
          .margin({ top: 8 })
          .onClick(() => this.logout());
      }
      .width('100%')
      .padding(16);
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundColor());
  }
}
