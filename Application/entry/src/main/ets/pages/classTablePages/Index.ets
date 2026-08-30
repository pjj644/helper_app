import { AppConstants } from '../../common/constants/AppConstants';
import { webview } from '@kit.ArkWeb';
import { buffer } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { WebScrapeService } from '../../service/WebScrapeService';
import { CourseService } from '../../service/CourseService';
import { CourseRepository } from '../../repository/CourseRepository';
import { VpnEncoder } from '../../common/utils/VpnEncoder';
import { PageContextTracker } from '../../common/agent/PageContextTracker';
import { LoadingOverlay } from '../../components/LoadingOverlay';
import { calculateSemesterId } from '../../model/classTableModel/ExamAccessRules';
import { WebScrapeTakeoverBar } from '../../components/WebScrapeTakeoverBar';
import { SyncService } from '../../service/SyncService';

interface CourseActivity {
  teacherId: string;
  teacherName: string;
  courseId: string;
  courseName: string;
  roomId: string;
  roomName: string;
  vaildWeeks: string;
}

interface CourseTableData {
  unitCounts: number;
  activities: CourseActivity[][];
  error?: string;
  source?: string;
  /** 抽取脚本读取的页面真实学期标识（表单 hidden input / 学期下拉），读不到为空串 */
  semesterId?: string;
}

interface LinkInfo {
  type?: string;
  href?: string;
  text?: string;
  onclick?: string;
  error?: string;
}

interface LoginStatus {
  status: string;
  user?: string;
  location?: string;
  error?: string;
  reason?: string;
  href?: string;
}

@Entry
@Component
struct Index {
  @State message: string = '正在加载...';
  @State currentUrl: string = AppConstants.EAMS_PORTAL_URL;
  @State isLoggedIn: boolean = false;
  @State needManualClick: boolean = false;
  @State autoNavigateTriggered: boolean = false;
  @State showWebView: boolean = true;
  @State manualMode: boolean = false;
  @State isProcessing: boolean = true;
  @State isVpnMode: boolean = false;
  @State showRefreshBtn: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();

  private loginUrlPattern: string = 'idas.uestc.edu.cn/authserver/login';
  private readonly MAX_FETCH_RETRY: number = 2;
  private readonly MAX_PAGE_RETRY: number = 2;
  private fetchRetryCount: number = 0;
  private pageRetryCount: number = 0;
  private hasRefreshedAfterFetchFail: boolean = false;
  private hasRefreshedAfterLoadFail: boolean = false;
  private isExtracting: boolean = false;
  private returnToHome: boolean = false;
  private lastCourseData: string = '';
  private currentActivities: CourseActivity[][] = [];
  private courseTableTargetSemesterId: number = calculateSemesterId();
  private isPageActive: boolean = false;
  private vpnAutoDetected: boolean = false;
  private vpnNavigatedFromPortal: boolean = false;
  /** 学期校验重试计数（跨整页重载持续累计，闸门通过或手动刷新时归零） */
  private semesterVerifyRetryCount: number = 0;
  private readonly MAX_SEMESTER_VERIFY_RETRY: number = 3;
  private semesterVerifyInFlight: boolean = false;
  private table0NotFoundCount: number = 0;
  private readonly MAX_TABLE0_NOT_FOUND: number = 5;
  private http500RetryCount: number = 0;
  private readonly MAX_HTTP_500_RETRY: number = 2;

  aboutToAppear(): void {
    this.isPageActive = true;
    this.courseTableTargetSemesterId = calculateSemesterId();
    const params = router.getParams() as Record<string, string>;
    this.returnToHome = !!(params && params['returnHome'] === '1');
    if (params && params['semesterId']) {
      const parsed = Number.parseInt(params['semesterId'], 10);
      if (Number.isFinite(parsed) && parsed > 0) {
        this.courseTableTargetSemesterId = parsed;
      }
    }
    // 上报页面感知快照，供 AI 助手识别当前所在页面
    PageContextTracker.getInstance().updateSnapshot(
      'course_import',
      '课表导入',
      '从教务系统在线导入课表数据',
      { 'semesterId': this.courseTableTargetSemesterId },
      []
    );
    this.initVpnMode();
  }

  private async initVpnMode(): Promise<void> {
    this.isVpnMode = false;
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
  }

  build() {
    Stack() {
      Column() {
        WebScrapeTakeoverBar({
          isManualMode: this.manualMode,
          promptMessage: this.message,
          isExtracting: this.isExtracting,
          onScrape: () => {
            this.extractCourseData(true);
          },
          onRefresh: () => {
            this.reloadCurrentPage();
          },
          onBack: () => {
            try {
              if (this.controller.accessBackward()) {
                this.controller.backward();
              }
            } catch (e) {}
          },
          onToggleVpn: () => {
            this.switchToVpnMode();
          },
          onToggleManual: () => {
            this.manualMode = !this.manualMode;
            if (this.manualMode) {
              this.isProcessing = false;
              this.message = '已开启手动接管模式：请在网页中完成登录或跳转，随后点击“立即抓取当前页”';
            } else {
              this.isProcessing = true;
              this.message = '正在自动处理中...';
            }
          }
        })

        Web({ src: this.currentUrl, controller: this.controller })
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .opacity(1)
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .fileAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .mixedMode(MixedMode.All)
        .zoomAccess(true)
        .geolocationAccess(true)
        .mediaPlayGestureAccess(true)
        .databaseAccess(true)
        .cacheMode(CacheMode.Default)
        .overviewModeAccess(true)
        .textZoomRatio(100)
        .darkMode(WebDarkMode.Auto)
        .forceDarkAccess(true)
        .onPageBegin(() => {
          console.info('[ClassTableScrape] 页面开始加载');
        })
        .onPageEnd(() => {
          console.info('[ClassTableScrape] 页面加载完成');
          this.pageRetryCount = 0;
          this.hasRefreshedAfterLoadFail = false;
          this.showRefreshBtn = false;
          this.table0NotFoundCount = 0;
          this.checkCurrentPage();

          if (this.manualMode) {
            return;
          }

          const url: string = this.controller.getUrl();
          console.info('[ClassTableScrape] 页面加载完成:', url);

          if (VpnEncoder.isLoginPage(url) || url.includes(this.loginUrlPattern)) {
            return;
          }

          if (!url.includes('courseTableForStd')) {
            console.info('[ClassTableScrape] 当前非课表页面，执行登录检测与导航');
            this.checkLoginStatusAndNavigate();
            return;
          }

          if (url.includes('courseTableForStd') && !this.autoNavigateTriggered) {
            console.info('[ClassTableScrape] 检测到课表页面，延迟2秒等待渲染稳定后校验学期');
            setTimeout(() => {
              if (!this.isPageActive) {
                console.info('[ClassTableScrape] 页面已离开，跳过学期校验');
                return;
              }
              try {
                const stableUrl: string = this.controller.getUrl();
                console.info('[ClassTableScrape] 延迟后当前URL:', stableUrl);
                if (stableUrl.includes('courseTableForStd') && !this.autoNavigateTriggered) {
                  this.verifySemesterAndExtract(stableUrl);
                }
              } catch (e) {
                console.error('[ClassTableScrape] 获取URL失败，页面可能已销毁:', e);
              }
            }, 2000);
          }
        })
        .onHttpErrorReceive((event) => {
          const statusCode = event.response.getResponseCode();
          console.error('[ClassTableScrape] HTTP错误状态码:', statusCode);
          if (!this.vpnAutoDetected && statusCode === 403) {
            console.info('[ClassTableScrape] 检测到HTTP 403，切换到VPN模式');
            this.switchToVpnMode();
            return;
          }
          if (statusCode === 500 && this.http500RetryCount < this.MAX_HTTP_500_RETRY) {
            this.http500RetryCount++;
            this.message = `教务会话初始化中，正在通过主页激活(${this.http500RetryCount}/${this.MAX_HTTP_500_RETRY})...`;
            console.info(`[ClassTableScrape] Index HTTP 500, navigating to home.action to restore session (attempt ${this.http500RetryCount})`);
            const homeUrl: string = this.isVpnMode ?
              VpnEncoder.buildVpnHomeUrl() :
              'https://eams.uestc.edu.cn/eams/home.action';
            setTimeout(() => {
              if (!this.isPageActive) {
                return;
              }
              this.controller.loadUrl(homeUrl);
            }, 1000);
            return;
          }
          this.showRefreshBtn = true;
        })
        .onErrorReceive((error) => {
          console.error('[ClassTableScrape] 页面加载错误:', error.error.getErrorInfo());
          const errorInfo = error.error.getErrorInfo();
          if (!this.isVpnMode && !this.vpnAutoDetected &&
              (errorInfo.includes('net::ERR_CONNECTION') ||
               errorInfo.includes('net::ERR_NAME_NOT_RESOLVED'))) {
            this.switchToVpnMode();
            return;
          }
          this.handlePageLoadFailure('页面加载失败');
        });
    }
    .width('100%')
    .height('100%');

      LoadingOverlay({ isVisible: this.isProcessing, message: this.message });

      if (this.showRefreshBtn) {
        Button() {
          Text('↻')
            .fontSize(22)
            .fontColor('#FFFFFF')
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor('#FF6200EE')
        .position({ x: '85%', y: 16 })
        .onClick(() => {
          this.showRefreshBtn = false;
          this.pageRetryCount = 0;
          this.hasRefreshedAfterLoadFail = false;
          this.table0NotFoundCount = 0;
          this.semesterVerifyRetryCount = 0;
          this.reloadCurrentPage();
        })
      }
    }
    .width('100%')
    .height('100%');
  }

  private switchToVpnMode(): void {
    if (this.vpnAutoDetected) {
      console.info('[ClassTableScrape] VPN mode already switched, skip');
      return;
    }
    console.info('[ClassTableScrape] 检测到非校园网环境，自动切换VPN模式');
    this.vpnAutoDetected = true;
    this.isVpnMode = true;
    this.pageRetryCount = 0;
    this.hasRefreshedAfterLoadFail = false;
    this.vpnNavigatedFromPortal = false;
    this.message = '检测到非校园网环境，已切换到VPN模式，正在加载WebVPN...';
    this.currentUrl = AppConstants.WEBVPN_LOGIN_URL;
    this.controller.loadUrl(AppConstants.WEBVPN_LOGIN_URL);
  }

  checkCurrentPage(): void {
    const url: string = this.controller.getUrl();
    console.info('[ClassTableScrape] 当前页面URL:', url);

    if (VpnEncoder.isLoginPage(url) || url.includes(this.loginUrlPattern)) {
      this.message = this.isVpnMode ? 'VPN模式：请完成统一身份认证登录' : '请完成统一身份认证登录';
      this.isLoggedIn = false;
      this.needManualClick = false;
      this.manualMode = false;
      this.vpnNavigatedFromPortal = false;
      this.isProcessing = false;
      return;
    }

    if (url.includes('courseTableForStd')) {
      this.message = '已进入课表页面';
      this.isLoggedIn = true;
      if (!this.manualMode) {
        this.needManualClick = false;
      }
      return;
    }

    if (this.isVpnMode) {
      if (VpnEncoder.isWebvpnPortal(url)) {
        if (this.manualMode) {
          return;
        }
        if (this.vpnNavigatedFromPortal) {
          console.info('[ClassTableScrape] VPN模式：已从门户导航过，跳过重复导航');
          return;
        }
        console.info('[ClassTableScrape] VPN模式：检测到WebVPN门户页，等待加载教务系统...');
        this.vpnNavigatedFromPortal = true;
        this.message = 'VPN登录成功，等待加载教务系统...';
        setTimeout(() => {
          this.controller.loadUrl(VpnEncoder.buildVpnEamsPortalUrl());
        }, 1000);
        return;
      }
    }
  }

  checkLoginStatusAndNavigate(): void {
    if (this.manualMode) {
      return;
    }

    const currentUrl: string = this.controller.getUrl();
    console.info('[ClassTableScrape] 检查登录状态，当前URL:', currentUrl);

    if (VpnEncoder.isLoginPage(currentUrl) || currentUrl.includes(this.loginUrlPattern)) {
      console.info('[ClassTableScrape] 当前在登录页面，需要登录');
      this.message = this.isVpnMode ? 'VPN模式：请完成统一身份认证登录' : '请完成统一身份认证登录';
      this.isLoggedIn = false;
      this.isProcessing = false;
      return;
    }

    if (this.isVpnMode && VpnEncoder.isWebvpnPortal(currentUrl)) {
      console.info('[ClassTableScrape] VPN模式：在WebVPN门户页，导航到EAMS...');
      this.message = 'VPN登录成功，正在跳转教务系统...';
      setTimeout(() => {
        this.controller.loadUrl(VpnEncoder.buildVpnEamsPortalUrl());
      }, 1000);
      return;
    }

    const checkLoginJs: string = WebScrapeService.buildLoginCheckScript();

    this.controller.runJavaScript(checkLoginJs, (error: Error | null, result: string) => {
      if (error) {
        console.error('[ClassTableScrape] 检查登录状态失败:', error);
        return;
      }

      try {
        let loginResult: string = result;
        if (result.trim().startsWith('"')) {
          const inner: string = JSON.parse(result);
          if (typeof inner === 'string') {
            loginResult = inner;
            console.info('[ClassTableScrape] 登录状态双重JSON编码，取内部字符串');
          }
        }
        const loginStatus: LoginStatus = JSON.parse(loginResult) as LoginStatus;
        console.info('[ClassTableScrape] 登录状态:', loginStatus);

        if (loginStatus.status === 'repeat_login_prompt') {
          console.info('[ClassTableScrape] 检测到重复登录踢出确认页，执行自动确认');
          this.message = '检测到多设备登录提示，正在自动确认...';
          const confirmUrl: string = (loginStatus.href && loginStatus.href.length > 0) ?
            loginStatus.href :
            (this.isVpnMode ? VpnEncoder.buildVpnHomeUrl() : 'https://eams.uestc.edu.cn/eams/home.action');
          setTimeout(() => {
            if (!this.isPageActive) {
              return;
            }
            console.info('[ClassTableScrape] loadUrl confirm repeat login:', confirmUrl);
            this.controller.loadUrl(confirmUrl);
          }, 300);
          return;
        }

        if (loginStatus.status === 'logged_in') {
          console.info('[ClassTableScrape] 检测到已登录，原因:', loginStatus.reason || 'unknown');
          this.isLoggedIn = true;
          this.message = '已登录，正在跳转课表...';
          setTimeout(() => {
            this.navigateToCourseTable();
          }, 800);
        } else if (loginStatus.status === 'not_logged_in') {
          console.info('[ClassTableScrape] 未登录，等待用户输入凭据');
          this.isLoggedIn = false;
          this.isProcessing = false;
          this.message = '请完成统一身份认证登录';
        }
      } catch (e) {
        console.error('[ClassTableScrape] 解析登录状态失败:', e);
      }
    });
  }

  navigateToCourseTable(): void {
    if (this.manualMode) {
      return;
    }

    this.message = '正在查找课表链接...';
    console.info('[ClassTableScrape] 开始查找课表链接并准备跳转');

    setTimeout(() => {
      if (!this.isPageActive) {
        return;
      }
      this.doNavigateToCourseTable();
    }, 800);
  }

  doNavigateToCourseTable(): void {
    const currentUrl: string = this.controller.getUrl();
    const onCampusNetwork: boolean = currentUrl.includes('eams.uestc.edu.cn');

    if (currentUrl.includes('courseTableForStd')) {
      console.info('[ClassTableScrape] 已在课表页面，无需再次导航');
      return;
    }

    if (this.isVpnMode && !onCampusNetwork) {
      console.info('[ClassTableScrape] VPN模式：直接导航到VPN代理的课表URL');
      this.message = '正在跳转到课表页面...';
      const vpnCourseTableUrl = VpnEncoder.buildVpnCourseTableUrl();
      setTimeout(() => {
        this.controller.loadUrl(vpnCourseTableUrl);
      }, 500);
      return;
    }

    const findCourseTableJs: string = WebScrapeService.buildFindCourseTableLinkScript();

    this.controller.runJavaScript(findCourseTableJs, (error: Error | null, result: string) => {
      if (error) {
        console.error('[ClassTableScrape] 查找课表链接失败:', error);
        this.message = '查找课表链接失败，请手动点击';
        this.needManualClick = true;
        return;
      }

      try {
        console.info('[ClassTableScrape] 准备解析result:', result);
        let parsedResult: object | string;
        if (result.trim().startsWith('"')) {
          const inner: string = JSON.parse(result);
          if (typeof inner === 'string' && (inner.trim().startsWith('{') || inner.trim().startsWith('['))) {
            parsedResult = JSON.parse(inner);
            console.info('[ClassTableScrape] 双重JSON编码，解析内部JSON');
          } else {
            parsedResult = inner;
          }
        } else {
          parsedResult = JSON.parse(result);
        }
        const linkInfo: LinkInfo = parsedResult as LinkInfo;
        console.info('[ClassTableScrape] 查找结果:', JSON.stringify(linkInfo));

        if (linkInfo && linkInfo.href && linkInfo.href.length > 0) {
          this.message = '正在跳转到课表页面...';
          console.info('[ClassTableScrape] 正在导航到:', linkInfo.href);
          const targetUrl: string = linkInfo.href;
          setTimeout(() => {
            console.info('[ClassTableScrape] 执行loadUrl:', targetUrl);
            this.controller.loadUrl(targetUrl);
            console.info('[ClassTableScrape] loadUrl已执行');
          }, 500);
        } else {
          console.error('[ClassTableScrape] 未找到有效的课表链接，linkInfo:', linkInfo);
          const fallbackUrl: string = AppConstants.EAMS_COURSE_TABLE_URL;
          console.info('[ClassTableScrape] 使用回退URL导航:', fallbackUrl);
          this.message = '正在跳转到课表页面...';
          setTimeout(() => {
            this.controller.loadUrl(fallbackUrl);
          }, 500);
        }
      } catch (e) {
        console.error('[ClassTableScrape] 解析链接信息失败:', e);
        this.message = '解析失败，请手动点击"我的课表"';
        this.needManualClick = true;
      }
    });
  }

  /**
   * 学期校验闸门（校验驱动）：读取课表页表单的真实学期，与目标学期一致才放行抽取。
   * 不一致或表单未就绪时走 handleSemesterVerifyFailure（写 cookie + 整页重载 + 重试）。
   */
  private verifySemesterAndExtract(pageUrl: string): void {
    if (!this.isPageActive || this.autoNavigateTriggered || this.manualMode || this.semesterVerifyInFlight) {
      return;
    }
    this.semesterVerifyInFlight = true;
    const getParamsJs: string = WebScrapeService.buildGetFormParamsScript();
    this.controller.runJavaScript(getParamsJs, (paramsError: Error | null, paramsResult: string) => {
      this.semesterVerifyInFlight = false;
      if (!this.isPageActive || this.autoNavigateTriggered || this.manualMode) {
        return;
      }
      if (paramsError) {
        console.error('[ClassTableScrape] 读取页面学期参数失败:', paramsError);
        this.handleSemesterVerifyFailure(pageUrl);
        return;
      }
      try {
        let paramsInner: string = paramsResult;
        if (paramsResult.trim().startsWith('"')) {
          const decoded: string = JSON.parse(paramsResult);
          if (typeof decoded === 'string') {
            paramsInner = decoded;
          }
        }
        const paramsObj: Record<string, Object> = JSON.parse(paramsInner) as Record<string, Object>;
        const pageSemesterId: number = (paramsObj['semesterId'] as number) || 0;
        console.info('[ClassTableScrape] 学期校验: 页面学期=', pageSemesterId,
          '目标学期=', this.courseTableTargetSemesterId);
        if (pageSemesterId > 0 && pageSemesterId === this.courseTableTargetSemesterId) {
          // 校验通过：归零重试计数后放行抽取（抽取结果仍受 semesterId 二次闸门保护）
          this.semesterVerifyRetryCount = 0;
          this.extractCourseData();
          return;
        }
        this.handleSemesterVerifyFailure(pageUrl);
      } catch (e) {
        console.error('[ClassTableScrape] 解析学期参数失败:', e);
        this.handleSemesterVerifyFailure(pageUrl);
      }
    });
  }

  /**
   * 校验未通过（页面学期与目标不一致，或表单未就绪读不到学期）：
   * 写目标学期 cookie 后整页重载课表 URL，让服务端按 cookie 重新渲染（window.table0 随之重建），
   * onPageEnd 后将再次校验；超过最大重试次数则停止自动流程并明确提示，绝不入库。
   */
  private handleSemesterVerifyFailure(pageUrl: string): void {
    if (this.semesterVerifyRetryCount >= this.MAX_SEMESTER_VERIFY_RETRY) {
      console.error('[ClassTableScrape] 学期校验连续失败，停止自动抓取（绝不入库）');
      this.semesterVerifyRetryCount = 0;
      this.enableManualMode('教务返回学期与目标不一致，请重试');
      this.showRefreshBtn = true;
      return;
    }
    this.semesterVerifyRetryCount++;
    this.message = `正在切换到目标学期(${this.semesterVerifyRetryCount}/${this.MAX_SEMESTER_VERIFY_RETRY})...`;
    const onCampus: boolean = pageUrl.includes('eams.uestc.edu.cn');
    const useVpn: boolean = this.isVpnMode && !onCampus;
    try {
      const cookieDomain = useVpn ? AppConstants.WEBVPN_BASE_URL : 'https://eams.uestc.edu.cn';
      webview.WebCookieManager.configCookieSync(cookieDomain,
        'semester.id=' + this.courseTableTargetSemesterId);
      console.info('[ClassTableScrape] 已设置Cookie semester.id=', this.courseTableTargetSemesterId, 'useVpn=', useVpn);
    } catch (cookieErr) {
      console.error('[ClassTableScrape] 设置Cookie失败:', cookieErr);
    }
    setTimeout(() => {
      if (!this.isPageActive) {
        return;
      }
      console.info('[ClassTableScrape] 整页重载课表以应用目标学期:', pageUrl);
      this.controller.loadUrl(pageUrl);
    }, 500);
  }

  extractCourseData(isManualTrigger: boolean = false): void {
    if ((this.manualMode && !isManualTrigger) || this.isExtracting || this.autoNavigateTriggered) {
      return;
    }

    this.isExtracting = true;
    this.message = '正在获取课表数据...';

    const jsCode: string = WebScrapeService.buildCourseTableScrapeScript();

    this.controller.runJavaScript(jsCode, (error: Error | null, result: string) => {
      this.isExtracting = false;
      if (error) {
        console.error('[ClassTableScrape] 执行JavaScript失败:', error);
        this.handleCourseFetchFailure('脚本执行失败');
        return;
      }

      console.info('[ClassTableScrape] JavaScript执行结果:', result);

      if (result) {
        try {
          console.info('[ClassTableScrape] 原始result长度:', result.length);
          console.info('[ClassTableScrape] 原始result前200字符:', result.substring(0, 200));

          let inner: string = '';
          if (result.trim().startsWith('"')) {
            inner = JSON.parse(result);
            console.info('[ClassTableScrape] JSON.parse后长度:', inner.length);
            console.info('[ClassTableScrape] JSON.parse后前100字符:', inner.substring(0, 100));
          } else {
            inner = result;
          }

          let courseData: CourseTableData;

          if (inner.trim().startsWith('{')) {
            courseData = JSON.parse(inner) as CourseTableData;
            console.info('[ClassTableScrape] direct JSON parse');
          } else {
            const decodedBuf: buffer.Buffer = buffer.from(inner, 'base64');
            const jsonStr: string = decodedBuf.toString('utf-8');
            console.info('[ClassTableScrape] Base64解码后JSON长度:', jsonStr.length);
            console.info('[ClassTableScrape] Base64解码后JSON前200字符:', jsonStr.substring(0, 200));
            courseData = JSON.parse(jsonStr) as CourseTableData;
            console.info('[ClassTableScrape] Base64 decode and JSON parse OK');
          }

          if (courseData.error) {
            console.error('[ClassTableScrape] 获取数据错误:', courseData.error);
            if (courseData.error.includes('未找到table0')) {
              this.table0NotFoundCount++;
              if (this.table0NotFoundCount >= this.MAX_TABLE0_NOT_FOUND) {
                console.error('[ClassTableScrape] 未找到table0次数过多，停止自动重试');
                this.enableManualMode('课表数据加载异常，请点击刷新重试');
                this.showRefreshBtn = true;
                return;
              }
            }
            this.handleCourseFetchFailure('返回错误: ' + courseData.error);
            return;
          }

          this.table0NotFoundCount = 0;

          if (!courseData.activities) {
            console.error('[ClassTableScrape] activities为undefined, courseData:', JSON.stringify(courseData).substring(0, 500));
            this.handleCourseFetchFailure('数据格式错误');
            return;
          }

          console.info('[ClassTableScrape] activities长度:', courseData.activities.length);

          // 学期二次闸门：抽取脚本带回的页面真实学期与目标不一致时绝不入库
          const scrapedSemesterId: string = courseData.semesterId || '';
          if (scrapedSemesterId.length > 0) {
            const scrapedId: number = Number.parseInt(scrapedSemesterId, 10);
            if (Number.isFinite(scrapedId) && scrapedId > 0 && scrapedId !== this.courseTableTargetSemesterId) {
              console.error('[ClassTableScrape] 抽取结果学期(' + scrapedId + ')与目标学期(' +
                this.courseTableTargetSemesterId + ')不一致，拒绝入库');
              if (isManualTrigger) {
                this.message = '教务返回学期与目标不一致，请重试';
                this.isProcessing = false;
              } else {
                this.handleSemesterVerifyFailure(this.controller.getUrl());
              }
              return;
            }
          }

          let hasCourseData: boolean = false;
          for (let i: number = 0; i < courseData.activities.length; i++) {
            const slotActivities: CourseActivity[] = courseData.activities[i];
            if (slotActivities && slotActivities.length > 0) {
              hasCourseData = true;
              break;
            }
          }

          if (hasCourseData) {
            this.fetchRetryCount = 0;
            this.hasRefreshedAfterFetchFail = false;
            this.parseAndPrintCourses(courseData);
            this.message = '课表数据已获取，正在跳转...';
            this.isProcessing = false;
            if (!this.autoNavigateTriggered) {
              this.autoNavigateTriggered = true;
              const latestCourseData: string = JSON.stringify({
                unitCounts: courseData.unitCounts || 84,
                activities: courseData.activities
              });
              this.lastCourseData = latestCourseData;
              this.persistAndNavigateToTableUI(latestCourseData);
            }
          } else {
            console.info('[ClassTableScrape] 未获取到课程数据，页面可能尚未完全加载');
            this.handleCourseFetchFailure('课表数据为空');
          }
        } catch (e) {
          console.error('[ClassTableScrape] 解析课程数据失败:', e);
          this.handleCourseFetchFailure('数据解析失败');
        }
      } else {
        console.info('[ClassTableScrape] JavaScript执行结果为空');
        this.handleCourseFetchFailure('执行结果为空');
      }
    });
  }

  private handleCourseFetchFailure(reason: string): void {
    console.info('[ClassTableScrape] 自动获取失败原因:', reason);
    if (this.fetchRetryCount < this.MAX_FETCH_RETRY) {
      this.fetchRetryCount++;
      this.message = `获取失败，正在重试(${this.fetchRetryCount}/${this.MAX_FETCH_RETRY})...`;
      setTimeout(() => {
        this.extractCourseData();
      }, 1500);
      return;
    }

    if (!this.hasRefreshedAfterFetchFail) {
      this.hasRefreshedAfterFetchFail = true;
      this.fetchRetryCount = 0;
      this.message = '重试失败，正在刷新页面后重试...';
      setTimeout(() => {
        this.reloadCurrentPage();
      }, 1200);
      return;
    }

    if (!this.isVpnMode && !this.vpnAutoDetected) {
      console.info('[ClassTableScrape] Course fetch failed, switching to VPN mode');
      this.switchToVpnMode();
      return;
    }

    this.enableManualMode('自动获取失败，请手动操作');
  }

  private handlePageLoadFailure(reason: string): void {
    console.info('[ClassTableScrape] 页面加载失败:', reason);
    if (this.pageRetryCount < this.MAX_PAGE_RETRY) {
      this.pageRetryCount++;
      this.message = `页面加载失败，重试(${this.pageRetryCount}/${this.MAX_PAGE_RETRY})...`;
      setTimeout(() => {
        this.reloadCurrentPage();
      }, 1000);
      return;
    }

    if (!this.hasRefreshedAfterLoadFail) {
      this.hasRefreshedAfterLoadFail = true;
      this.pageRetryCount = 0;
      this.message = '页面加载异常，正在刷新...';
      setTimeout(() => {
        this.reloadCurrentPage();
      }, 1000);
      return;
    }

    this.enableManualMode('页面加载失败，请手动操作');
    this.showRefreshBtn = true;
  }

  private reloadCurrentPage(): void {
    const url: string = this.controller.getUrl();
    if (url && url.length > 0) {
      this.controller.loadUrl(url);
      return;
    }
    this.controller.loadUrl(this.currentUrl);
  }

  private enableManualMode(reason: string): void {
    this.isProcessing = false;
    this.message = reason;
    this.needManualClick = true;
    this.manualMode = true;
    this.autoNavigateTriggered = false;
  }

  parseAndPrintCourses(data: CourseTableData): void {
    console.info('[ClassTableScrape] ========== 课表数据 ==========');
    console.info('[ClassTableScrape] 总单元数:', data.unitCounts);
    console.info('[ClassTableScrape] =============================');

    let courseCount: number = 0;
    this.currentActivities = data.activities;

    for (let i: number = 0; i < data.activities.length; i++) {
      const slotActivities: CourseActivity[] = data.activities[i];
      if (slotActivities && slotActivities.length > 0) {
        for (const activity of slotActivities) {
          if (activity && activity.courseName) {
            courseCount++;
            console.info('[ClassTableScrape] \n【课程 ' + courseCount + '】');
            console.info('[ClassTableScrape] 时间段索引:', i);
            console.info('[ClassTableScrape] 课程名称:', activity.courseName);
            console.info('[ClassTableScrape] 教师:', activity.teacherName || '未知');
            console.info('[ClassTableScrape] 教室:', activity.roomName || '未知');
            console.info('[ClassTableScrape] 教师ID:', activity.teacherId);
            console.info('[ClassTableScrape] 课程ID:', activity.courseId);
            console.info('[ClassTableScrape] 教室ID:', activity.roomId);
            console.info('[ClassTableScrape] 有效周次:', this.parseValidWeeks(activity.vaildWeeks));
            console.info('[ClassTableScrape] 原始周次字符串:', activity.vaildWeeks);
          }
        }
      }
    }

    console.info('[ClassTableScrape] \n=============================');
    console.info('[ClassTableScrape] 共找到 ' + courseCount + ' 门课程');
    console.info('[ClassTableScrape] =============================');
  }

  parseValidWeeks(weeksStr: string): string {
    if (!weeksStr || weeksStr.length === 0) {
      return '未知';
    }

    const weekRanges: string[] = [];
    let startWeek: number | null = null;
    let prevWeek: number | null = null;

    for (let i: number = 0; i < weeksStr.length; i++) {
      if (weeksStr[i] === '1') {
        const currentWeek: number = i + 1;
        if (startWeek === null) {
          startWeek = currentWeek;
        }
        prevWeek = currentWeek;
      } else {
        if (startWeek !== null && prevWeek !== null) {
          if (startWeek === prevWeek) {
            weekRanges.push('' + startWeek);
          } else {
            weekRanges.push(startWeek + '-' + prevWeek);
          }
          startWeek = null;
          prevWeek = null;
        }
      }
    }

    if (startWeek !== null && prevWeek !== null) {
      if (startWeek === prevWeek) {
        weekRanges.push('' + startWeek);
      } else {
        weekRanges.push(startWeek + '-' + prevWeek);
      }
    }

    return weekRanges.length > 0 ? weekRanges.join(', ') : '无';
  }

  private async persistAndNavigateToTableUI(courseData: string): Promise<void> {
    let persisted: boolean = false;
    try {
      const context = getContext(this);
      await CourseRepository.saveCourseDataBySemester(context, this.courseTableTargetSemesterId, courseData);
      // 仅抓当前学期时才联动「下一节课卡片缓存 + 云同步」；
      // 抓归档学期时严禁再走 saveRawCourseData（其内部无条件写 calculateSemesterId() 分片，
      // 历史双写会用归档课表整片覆盖当前学期数据）
      if (this.courseTableTargetSemesterId === calculateSemesterId()) {
        await CourseService.saveRawCourseData(context, JSON.parse(courseData));
      }
      console.info('[ClassTableScrape] courseCache: 抓取成功并已写入本地');
      persisted = true;
    } catch (error) {
      console.error('[ClassTableScrape] courseCache: 保存课表本地数据失败:', error);
    }

    if (persisted) {
      // 校验通过的抓取后触发「该学期替换式云同步」（上传本地分片 + 裁剪云端该学期多余记录），失败静默
      SyncService.replaceSemesterCoursesInCloud(getContext(this), this.courseTableTargetSemesterId)
        .catch((syncError: Object) => {
          console.error('[ClassTableScrape] 替换式云同步失败:', syncError);
        });
    }

    if (this.returnToHome) {
      router.back();
    } else {
      this.navigateToTableUI(courseData);
    }
  }

  navigateToTableUI(courseDataParam?: string): void {
    const courseData = courseDataParam || this.lastCourseData;

    if (!courseData) {
      this.message = '请先获取课表数据';
      return;
    }

    this.lastCourseData = courseData;

    AppStorage.set('pendingCourseData', courseData);
    AppStorage.set('pendingCourseSemesterId', this.courseTableTargetSemesterId);
    router.back();
  }

  getActivitiesFromMemory(): CourseActivity[][] {
    return this.currentActivities;
  }
}
