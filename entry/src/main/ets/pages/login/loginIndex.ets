import { router } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import auth, { VerifyCodeAction } from '@hw-agconnect/auth';
import { AppConstants } from '../../common/constants/AppConstants';

interface HostContextProvider {
	getHostContext?: () => common.UIAbilityContext;
}

interface LoginSession {
	email: string;
	loginAt: number;
}

@Entry
@Component
struct LoginIndexPage {
	@State email: string = '';
	@State verifyCode: string = '';
	@State isEmailValid: boolean = false;
	@State isLoading: boolean = false;
	@State countdown: number = 0;
	@State hintText: string = '请输入邮箱并获取验证码';

	private readonly PREF_NAME: string = AppConstants.LOGIN_PREF_NAME;
  private readonly SESSION_KEY: string = AppConstants.LOGIN_SESSION_KEY;
	private readonly TARGET_URL: string = 'pages/home';
	private countdownTimer: number = -1;
	private isJumping: boolean = false;

	aboutToAppear(): void {
		this.checkLoginStatus();
	}

	aboutToDisappear(): void {
		this.clearTimer();
	}

	private getAbilityContext(): common.UIAbilityContext {
		const context = getContext(this) as HostContextProvider;
		if (context && context.getHostContext) {
			return context.getHostContext();
		}
		return getContext(this) as common.UIAbilityContext;
	}

	private async getPref(): Promise<preferences.Preferences> {
		const abilityContext: common.UIAbilityContext = this.getAbilityContext();
		return await preferences.getPreferences(abilityContext, this.PREF_NAME);
	}

	private validateEmail(value: string): boolean {
		const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
		return emailRegex.test(value);
	}

	private async checkLoginStatus(): Promise<void> {
		try {
			const pref = await this.getPref();
			const text = (await pref.get(this.SESSION_KEY, '')) as string;
			if (!text) {
				return;
			}

			const session = JSON.parse(text) as LoginSession;
			if (!session.email) {
				return;
			}

			const agcUser = auth.getCurrentUser();
			if (!agcUser) {
				await pref.delete(this.SESSION_KEY);
				await pref.flush();
				return;
			}

			this.jumpToHome();
		} catch (error) {
			console.error('读取登录状态失败:', error);
		}
	}

	private async saveSession(): Promise<void> {
		const pref = await this.getPref();
		const session: LoginSession = {
			email: this.email,
			loginAt: Date.now(),
		};
		await pref.put(this.SESSION_KEY, JSON.stringify(session));
		await pref.flush();
	}

	private clearTimer(): void {
		if (this.countdownTimer >= 0) {
			clearInterval(this.countdownTimer);
			this.countdownTimer = -1;
		}
	}

	private startCountDown(): void {
		this.clearTimer();
		this.countdown = 60;
		this.countdownTimer = setInterval(() => {
			if (this.countdown <= 1) {
				this.countdown = 0;
				this.clearTimer();
				return;
			}
			this.countdown--;
		}, 1000);
	}

	private sendVerifyCode(): void {
		if (!this.isEmailValid) {
			this.getUIContext().getPromptAction().showToast({ message: '请输入有效邮箱地址' });
			return;
		}

		this.startCountDown();
		auth.requestVerifyCode({
			action: VerifyCodeAction.REGISTER_LOGIN,
			lang: 'zh_CN',
			sendInterval: 60,
			verifyCodeType: {
				email: this.email,
				kind: 'email'
			}
		}).then(() => {
			this.hintText = '验证码已发送，请检查邮箱';
			this.getUIContext().getPromptAction().showToast({ message: '验证码已发送' });
		}).catch((error: BusinessError) => {
			console.error('发送验证码失败:', JSON.stringify(error));
			this.countdown = 0;
			this.clearTimer();
			this.getUIContext().getPromptAction().showToast({ message: `发送失败：${error.message}` });
		});
	}

	private jumpToHome(): void {
		if (this.isJumping) {
			return;
		}
		this.isJumping = true;
		router.replaceUrl({
			url: this.TARGET_URL,
		}).catch((error: Error) => {
			this.isJumping = false;
			console.error('跳转首页失败:', error);
		});
	}

	private async handleLogin(): Promise<void> {
		if (!this.email || !this.verifyCode) {
			this.getUIContext().getPromptAction().showToast({ message: '请填写邮箱和验证码' });
			return;
		}
		if (!this.isEmailValid) {
			this.getUIContext().getPromptAction().showToast({ message: '邮箱格式不正确' });
			return;
		}
		if (this.isLoading) {
			return;
		}

		this.isLoading = true;
		try {
			await auth.signIn({
				credentialInfo: {
					kind: 'email',
					email: this.email,
					verifyCode: this.verifyCode
				}
			});

			await this.saveSession();
			this.getUIContext().getPromptAction().showToast({ message: '登录成功' });
			this.jumpToHome();
		} catch (error) {
			const businessError = error as BusinessError;
			console.error('登录失败:', JSON.stringify(businessError));
			this.getUIContext().getPromptAction().showToast({ message: `登录失败：${businessError.message}` });
		} finally {
			this.isLoading = false;
		}
	}

	@Builder
	private HeaderSection(): void {
		Column({ space: 10 }) {
			Text('ClassTable')
				.fontSize(34)
				.fontWeight(FontWeight.Bold)
				.fontColor('#1A2A42');

			Text('邮箱验证码登录')
				.fontSize(15)
				.fontColor('#5A6B84');
		}
		.width('100%')
		.alignItems(HorizontalAlign.Start)
		.padding({ top: 20, bottom: 10 });
	}

	@Builder
	private EmailInputSection(): void {
		Column({ space: 8 }) {
			Text('邮箱')
				.fontSize(14)
				.fontColor('#263852')
				.fontWeight(FontWeight.Medium)
				.width('100%');

			TextInput({
				placeholder: '请输入邮箱，例如 name@uestc.edu.cn',
				text: this.email,
			})
				.type(InputType.Email)
				.fontSize(15)
				.backgroundColor('#FFFFFF')
				.borderRadius(12)
				.border({ width: 1.2, color: this.isEmailValid || this.email.length === 0 ? '#DCE4F3' : '#E25252' })
				.padding({ left: 14, right: 14, top: 12, bottom: 12 })
				.onChange((value: string) => {
					this.email = value;
					this.isEmailValid = this.validateEmail(value);
				});
		}
		.width('100%');
	}

	@Builder
	private VerifyCodeSection(): void {
		Column({ space: 8 }) {
			Text('验证码')
				.fontSize(14)
				.fontColor('#263852')
				.fontWeight(FontWeight.Medium)
				.width('100%');

			Row({ space: 10 }) {
				TextInput({
					placeholder: '请输入验证码',
					text: this.verifyCode,
				})
					.type(InputType.Number)
					.layoutWeight(1)
					.fontSize(15)
					.backgroundColor('#FFFFFF')
					.borderRadius(12)
					.border({ width: 1.2, color: '#DCE4F3' })
					.padding({ left: 14, right: 14, top: 12, bottom: 12 })
					.onChange((value: string) => {
						this.verifyCode = value;
					});

				Text(this.countdown > 0 ? `${this.countdown}s` : '获取验证码')
					.fontSize(13)
					.fontColor(this.countdown > 0 ? '#8A95A8' : '#FFFFFF')
					.fontWeight(FontWeight.Medium)
					.padding({ left: 16, right: 16, top: 12, bottom: 12 })
					.backgroundColor(this.countdown > 0 ? '#E7ECF5' : '#2F6DFF')
					.borderRadius(12)
					.onClick(() => {
						if (this.countdown > 0) {
							return;
						}
						this.sendVerifyCode();
					});
			}
			.width('100%');
		}
		.width('100%');
	}

	@Builder
	private LoginButtonSection(): void {
		Text('登录')
			.width('100%')
			.textAlign(TextAlign.Center)
			.fontSize(16)
			.fontWeight(FontWeight.Bold)
			.fontColor('#FFFFFF')
			.padding({ top: 14, bottom: 14 })
			.backgroundColor('#244B9A')
			.borderRadius(12)
			.onClick(() => {
				this.handleLogin();
			});
	}

	build() {
		Stack() {
			Column() {
				Scroll() {
					Column({ space: 20 }) {
						this.HeaderSection();
						this.EmailInputSection();
						this.VerifyCodeSection();
						this.LoginButtonSection();

						Text(this.hintText)
							.width('100%')
							.fontSize(12)
							.fontColor('#73829A')
							.lineHeight(18);
					}
					.width('100%')
					.padding({ left: 24, right: 24, top: 36, bottom: 28 });
				}
				.scrollBar(BarState.Off)
				.layoutWeight(1);
			}
			.width('100%')
			.height('100%')
			.backgroundColor('#F2F5FB');

			if (this.isLoading) {
				Column({ space: 12 }) {
					LoadingProgress()
						.width(42)
						.height(42)
						.color('#2F6DFF');

					Text('登录中...')
						.fontSize(14)
						.fontColor('#FFFFFF');
				}
				.width('100%')
				.height('100%')
				.backgroundColor('rgba(0,0,0,0.35)')
				.justifyContent(FlexAlign.Center)
				.alignItems(HorizontalAlign.Center);
			}
		}
		.width('100%')
		.height('100%');
	}
}

export { LoginIndexPage };
