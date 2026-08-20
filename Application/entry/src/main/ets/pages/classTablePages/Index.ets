import { AppConstants } from '../../common/constants/AppConstants';
import { webview } from '@kit.ArkWeb';
import { buffer } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { WebScrapeService } from '../../service/WebScrapeService';
import { CourseService } from '../../service/CourseService';
import { CourseRepository } from '../../repository/CourseRepository';
import { VpnEncoder } from '../../common/utils/VpnEncoder';
import { LoadingOverlay } from '../../components/LoadingOverlay';
import { calculateSemesterId } from '../../model/classTableModel/ExamAccessRules';

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
  private pendingSemesterSwitchId: number = 0;
  private isPageActive: boolean = false;
  private vpnAutoDetected: boolean = false;
  private vpnNavigatedFromPortal: boolean = false;
  private semesterSwitchRetryCount: number = 0;
  private readonly MAX_SEMESTER_SWITCH_RETRY: number = 2;
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
        this.pendingSemesterSwitchId = parsed;
      }
    }
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
        Text(this.message)
          .fontSize(14)
          .fontColor('#666666')
          .margin({ top: 8, bottom: 4, left: 12, right: 12 });

        if (this.needManualClick) {
          Text('自动处理失败，请在当前页面手动操作')
            .fontSize(13)
            .fontColor('#D32F2F')
            .margin({ left: 12, right: 12, bottom: 8 });
        }

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
          console.info('testTag页面开始加载');
        })
        .onPageEnd(() => {
          console.info('testTag页面加载完成');
          this.pageRetryCount = 0;
          this.hasRefreshedAfterLoadFail = false;
          this.showRefreshBtn = false;
          this.table0NotFoundCount = 0;
          this.checkCurrentPage();

          if (this.manualMode) {
            return;
          }

          const url: string = this.controller.getUrl();
          console.info('testTag页面加载完成:', url);

          if (VpnEncoder.isLoginPage(url) || url.includes(this.loginUrlPattern)) {
            return;
          }

          if (!this.isLoggedIn && !url.includes('courseTableForStd')) {
            this.checkLoginStatusAndNavigate();
          }

          if (url.includes('courseTableForStd') && !this.autoNavigateTriggered) {
            if (this.pendingSemesterSwitchId > 0) {
              console.info('testTag检测到课表页面，需要切换学期到:', this.pendingSemesterSwitchId);
              const getParamsJs: string = WebScrapeService.buildGetFormParamsScript();
              this.controller.runJavaScript(getParamsJs, (paramsError: Error | null, paramsResult: string) => {
                if (paramsError) {
                  console.error('testTag获取当前学期参数失败:', paramsError);
                  this.pendingSemesterSwitchId = 0;
                  setTimeout(() => {
                    if (!this.isPageActive) {
                      return;
                    }
                    this.extractCourseData();
                  }, 2000);
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
                  const currentSemesterId: number = (paramsObj['semesterId'] as number) || 0;
                  console.info('testTag当前学期ID:', currentSemesterId, '目标学期ID:', this.pendingSemesterSwitchId);
                  if (currentSemesterId !== this.pendingSemesterSwitchId) {
                    const onCampusForSwitch: boolean = url.includes('eams.uestc.edu.cn');
                    const useVpnForSwitch: boolean = this.isVpnMode && !onCampusForSwitch;
                    try {
                      const cookieDomain = useVpnForSwitch ?
                        AppConstants.WEBVPN_BASE_URL : 'https://eams.uestc.edu.cn';
                      webview.WebCookieManager.configCookieSync(cookieDomain,
                        'semester.id=' + this.pendingSemesterSwitchId);
                      console.info('testTag已设置Cookie semester.id=', this.pendingSemesterSwitchId, 'useVpn=', useVpnForSwitch);
                    } catch (cookieErr) {
                      console.error('testTag设置Cookie失败:', cookieErr);
                    }
                    const switchJs: string = useVpnForSwitch ?
                      WebScrapeService.buildVpnSemesterSwitchScript(this.pendingSemesterSwitchId,
                        VpnEncoder.buildVpnEamsUrl('/eams/courseTableForStd!courseTable.action')) :
                      WebScrapeService.buildSemesterSwitchScript(this.pendingSemesterSwitchId);
                    const executeSemesterSwitch = (): void => {
                      this.controller.runJavaScript(switchJs, (sErr: Error | null, sRes: string) => {
                        if (sErr) {
                          console.error('testTag切换学期失败:', sErr);
                        } else {
                          console.info('testTag切换学期结果:', sRes);
                          if (sRes && sRes.includes('403') && !this.vpnAutoDetected) {
                            console.info('testTag学期切换403，切换到VPN模式');
                            this.switchToVpnMode();
                            return;
                          }
                          if (sRes && sRes.includes('500') && this.semesterSwitchRetryCount < this.MAX_SEMESTER_SWITCH_RETRY) {
                            this.semesterSwitchRetryCount++;
                            console.info('testTag学期切换HTTP 500，延迟3秒重试，第', this.semesterSwitchRetryCount, '次');
                            setTimeout(() => {
                              if (!this.isPageActive) {
                                return;
                              }
                              executeSemesterSwitch();
                            }, 3000);
                            return;
                          }
                        }
                        if (this.semesterSwitchRetryCount >= this.MAX_SEMESTER_SWITCH_RETRY) {
                          console.info('testTag学期切换重试次数已用尽，刷新课表页面');
                          this.semesterSwitchRetryCount = 0;
                          this.pendingSemesterSwitchId = 0;
                          const refreshUrl = this.controller.getUrl();
                          this.controller.loadUrl(refreshUrl);
                          return;
                        }
                        this.semesterSwitchRetryCount = 0;
                        this.pendingSemesterSwitchId = 0;
                        setTimeout(() => {
                          if (!this.isPageActive) {
                            return;
                          }
                          this.extractCourseData();
                        }, 2000);
                      });
                    };
                    executeSemesterSwitch();
                  } else {
                    console.info('testTag当前学期与目标学期一致，无需切换');
                    this.pendingSemesterSwitchId = 0;
                    setTimeout(() => {
                      if (!this.isPageActive) {
                        return;
                      }
                      this.extractCourseData();
                    }, 2000);
                  }
                } catch (e) {
                  console.error('testTag解析学期参数失败:', e);
                  this.pendingSemesterSwitchId = 0;
                  setTimeout(() => {
                    if (!this.isPageActive) {
                      return;
                    }
                    this.extractCourseData();
                  }, 2000);
                }
              });
            } else {
              console.info('testTag检测到课表页面，延迟2秒等二次跳转稳定后再提取');
              setTimeout(() => {
                if (!this.isPageActive) {
                  console.info('testTag页面已离开，跳过数据提取');
                  return;
                }
                try {
                  const currentUrl: string = this.controller.getUrl();
                  console.info('testTag延迟后当前URL:', currentUrl);
                  if (currentUrl.includes('courseTableForStd') && !this.autoNavigateTriggered) {
                    this.extractCourseData();
                  }
                } catch (e) {
                  console.error('testTag获取URL失败，页面可能已销毁:', e);
                }
              }, 2000);
            }
          }
        })
        .onHttpErrorReceive((event) => {
          const statusCode = event.response.getResponseCode();
          console.error('testTag HTTP错误状态码:', statusCode);
          if (!this.vpnAutoDetected && statusCode === 403) {
            console.info('testTag检测到HTTP 403，切换到VPN模式');
            this.switchToVpnMode();
            return;
          }
          if (statusCode === 500 && this.http500RetryCount < this.MAX_HTTP_500_RETRY) {
            this.http500RetryCount++;
            this.message = `教务系统会话就绪中，正在重试(${this.http500RetryCount}/${this.MAX_HTTP_500_RETRY})...`;
            console.info(`testTag Index HTTP 500, retrying in 1.5s (attempt ${this.http500RetryCount})`);
            setTimeout(() => {
              if (!this.isPageActive) {
                return;
              }
              this.navigateToCourseTable();
            }, 1500);
            return;
          }
          this.showRefreshBtn = true;
        })
        .onErrorReceive((error) => {
          console.error('testTag页面加载错误:', error.error.getErrorInfo());
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
          this.semesterSwitchRetryCount = 0;
          this.reloadCurrentPage();
        })
      }
    }
    .width('100%')
    .height('100%');
  }

  private switchToVpnMode(): void {
    if (this.vpnAutoDetected) {
      console.info('testTag VPN mode already switched, skip');
      return;
    }
    console.info('testTag检测到非校园网环境，自动切换VPN模式');
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
    console.info('testTag当前页面URL:', url);

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
          console.info('testTag VPN模式：已从门户导航过，跳过重复导航');
          return;
        }
        console.info('testTag VPN模式：检测到WebVPN门户页，等待加载教务系统...');
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
    console.info('testTag检查登录状态，当前URL:', currentUrl);

    if (VpnEncoder.isLoginPage(currentUrl) || currentUrl.includes(this.loginUrlPattern)) {
      console.info('testTag当前在登录页面，需要登录');
      this.message = this.isVpnMode ? 'VPN模式：请完成统一身份认证登录' : '请完成统一身份认证登录';
      this.isLoggedIn = false;
      this.isProcessing = false;
      return;
    }

    if (this.isVpnMode && VpnEncoder.isWebvpnPortal(currentUrl)) {
      console.info('testTag VPN模式：在WebVPN门户页，导航到EAMS...');
      this.message = 'VPN登录成功，正在跳转教务系统...';
      setTimeout(() => {
        this.controller.loadUrl(VpnEncoder.buildVpnEamsPortalUrl());
      }, 1000);
      return;
    }

    const checkLoginJs: string = WebScrapeService.buildLoginCheckScript();

    this.controller.runJavaScript(checkLoginJs, (error: Error | null, result: string) => {
      if (error) {
        console.error('testTag检查登录状态失败:', error);
        return;
      }

      try {
        let loginResult: string = result;
        if (result.trim().startsWith('"')) {
          const inner: string = JSON.parse(result);
          if (typeof inner === 'string') {
            loginResult = inner;
            console.info('testTag登录状态双重JSON编码，取内部字符串');
          }
        }
        const loginStatus: LoginStatus = JSON.parse(loginResult) as LoginStatus;
        console.info('testTag登录状态:', loginStatus);

        if (loginStatus.status === 'repeat_login_prompt') {
          console.info('testTag检测到重复登录踢出确认页，执行自动确认');
          this.message = '检测到多设备登录提示，正在自动确认...';
          const confirmUrl: string = (loginStatus.href && loginStatus.href.length > 0) ?
            loginStatus.href :
            (this.isVpnMode ? VpnEncoder.buildVpnHomeUrl() : 'https://eams.uestc.edu.cn/eams/home.action');
          setTimeout(() => {
            if (!this.isPageActive) {
              return;
            }
            console.info('testTag loadUrl confirm repeat login:', confirmUrl);
            this.controller.loadUrl(confirmUrl);
          }, 300);
          return;
        }

        if (loginStatus.status === 'logged_in') {
          console.info('testTag检测到已登录，原因:', loginStatus.reason || 'unknown');
          this.isLoggedIn = true;
          this.message = '已登录，正在跳转课表...';
          setTimeout(() => {
            this.navigateToCourseTable();
          }, 800);
        } else if (loginStatus.status === 'not_logged_in') {
          console.info('testTag未登录，等待用户输入凭据');
          this.isLoggedIn = false;
          this.isProcessing = false;
          this.message = '请完成统一身份认证登录';
        }
      } catch (e) {
        console.error('testTag解析登录状态失败:', e);
      }
    });
  }

  navigateToCourseTable(): void {
    if (this.manualMode) {
      return;
    }

    this.message = '正在查找课表链接...';
    console.info('testTag开始查找课表链接，延迟2秒确保页面加载完成');

    setTimeout(() => {
      this.doNavigateToCourseTable();
    }, 2000);
  }

  doNavigateToCourseTable(): void {
    const currentUrl: string = this.controller.getUrl();
    const onCampusNetwork: boolean = currentUrl.includes('eams.uestc.edu.cn');

    if (currentUrl.includes('courseTableForStd')) {
      console.info('testTag已在课表页面，无需再次导航');
      return;
    }

    if (this.isVpnMode && !onCampusNetwork) {
      console.info('testTag VPN模式：直接导航到VPN代理的课表URL');
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
        console.error('testTag查找课表链接失败:', error);
        this.message = '查找课表链接失败，请手动点击';
        this.needManualClick = true;
        return;
      }

      try {
        console.info('testTag准备解析result:', result);
        let parsedResult: object | string;
        if (result.trim().startsWith('"')) {
          const inner: string = JSON.parse(result);
          if (typeof inner === 'string' && (inner.trim().startsWith('{') || inner.trim().startsWith('['))) {
            parsedResult = JSON.parse(inner);
            console.info('testTag双重JSON编码，解析内部JSON');
          } else {
            parsedResult = inner;
          }
        } else {
          parsedResult = JSON.parse(result);
        }
        const linkInfo: LinkInfo = parsedResult as LinkInfo;
        console.info('testTag查找结果:', JSON.stringify(linkInfo));

        if (linkInfo && linkInfo.href && linkInfo.href.length > 0) {
          this.message = '正在跳转到课表页面...';
          console.info('testTag正在导航到:', linkInfo.href);
          const targetUrl: string = linkInfo.href;
          setTimeout(() => {
            console.info('testTag执行loadUrl:', targetUrl);
            this.controller.loadUrl(targetUrl);
            console.info('testTagloadUrl已执行');
          }, 500);
        } else {
          console.error('testTag未找到有效的课表链接，linkInfo:', linkInfo);
          const fallbackUrl: string = AppConstants.EAMS_COURSE_TABLE_URL;
          console.info('testTag使用回退URL导航:', fallbackUrl);
          this.message = '正在跳转到课表页面...';
          setTimeout(() => {
            this.controller.loadUrl(fallbackUrl);
          }, 500);
        }
      } catch (e) {
        console.error('testTag解析链接信息失败:', e);
        this.message = '解析失败，请手动点击"我的课表"';
        this.needManualClick = true;
      }
    });
  }

  extractCourseData(): void {
    if (this.manualMode || this.isExtracting || this.autoNavigateTriggered) {
      return;
    }

    this.isExtracting = true;
    this.message = '正在获取课表数据...';

    const jsCode: string = WebScrapeService.buildCourseTableScrapeScript();

    this.controller.runJavaScript(jsCode, (error: Error | null, result: string) => {
      this.isExtracting = false;
      if (error) {
        console.error('testTag执行JavaScript失败:', error);
        this.handleCourseFetchFailure('脚本执行失败');
        return;
      }

      console.info('testTag JavaScript执行结果:', result);

      if (result) {
        try {
          console.info('testTag原始result长度:', result.length);
          console.info('testTag原始result前200字符:', result.substring(0, 200));

          let inner: string = '';
          if (result.trim().startsWith('"')) {
            inner = JSON.parse(result);
            console.info('testTag JSON.parse后长度:', inner.length);
            console.info('testTag JSON.parse后前100字符:', inner.substring(0, 100));
          } else {
            inner = result;
          }

          let courseData: CourseTableData;

          if (inner.trim().startsWith('{')) {
            courseData = JSON.parse(inner) as CourseTableData;
            console.info('testTag direct JSON parse');
          } else {
            const decodedBuf: buffer.Buffer = buffer.from(inner, 'base64');
            const jsonStr: string = decodedBuf.toString('utf-8');
            console.info('testTag Base64解码后JSON长度:', jsonStr.length);
            console.info('testTag Base64解码后JSON前200字符:', jsonStr.substring(0, 200));
            courseData = JSON.parse(jsonStr) as CourseTableData;
            console.info('testTag Base64 decode and JSON parse OK');
          }

          if (courseData.error) {
            console.error('testTag获取数据错误:', courseData.error);
            if (courseData.error.includes('未找到table0')) {
              this.table0NotFoundCount++;
              if (this.table0NotFoundCount >= this.MAX_TABLE0_NOT_FOUND) {
                console.error('testTag未找到table0次数过多，停止自动重试');
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
            console.error('testTag activities为undefined, courseData:', JSON.stringify(courseData).substring(0, 500));
            this.handleCourseFetchFailure('数据格式错误');
            return;
          }

          console.info('testTag activities长度:', courseData.activities.length);

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
            console.info('testTag未获取到课程数据，页面可能尚未完全加载');
            this.handleCourseFetchFailure('课表数据为空');
          }
        } catch (e) {
          console.error('testTag 解析课程数据失败:', e);
          this.handleCourseFetchFailure('数据解析失败');
        }
      } else {
        console.info('testTagJavaScript执行结果为空');
        this.handleCourseFetchFailure('执行结果为空');
      }
    });
  }

  private handleCourseFetchFailure(reason: string): void {
    console.info('testTag自动获取失败原因:', reason);
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
      console.info('testTag Course fetch failed, switching to VPN mode');
      this.switchToVpnMode();
      return;
    }

    this.enableManualMode('自动获取失败，请手动操作');
  }

  private handlePageLoadFailure(reason: string): void {
    console.info('testTag页面加载失败:', reason);
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
    console.info('testTag========== 课表数据 ==========');
    console.info('testTag总单元数:', data.unitCounts);
    console.info('testTag=============================');

    let courseCount: number = 0;
    this.currentActivities = data.activities;

    for (let i: number = 0; i < data.activities.length; i++) {
      const slotActivities: CourseActivity[] = data.activities[i];
      if (slotActivities && slotActivities.length > 0) {
        for (const activity of slotActivities) {
          if (activity && activity.courseName) {
            courseCount++;
            console.info('\n【课程 ' + courseCount + '】');
            console.info('时间段索引:', i);
            console.info('课程名称:', activity.courseName);
            console.info('教师:', activity.teacherName || '未知');
            console.info('教室:', activity.roomName || '未知');
            console.info('教师ID:', activity.teacherId);
            console.info('课程ID:', activity.courseId);
            console.info('教室ID:', activity.roomId);
            console.info('有效周次:', this.parseValidWeeks(activity.vaildWeeks));
            console.info('原始周次字符串:', activity.vaildWeeks);
          }
        }
      }
    }

    console.info('testTag\n=============================');
    console.info('testTag共找到 ' + courseCount + ' 门课程');
    console.info('testTag=============================');
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
    try {
      const context = getContext(this);
      await CourseRepository.saveCourseDataBySemester(context, this.courseTableTargetSemesterId, courseData);
      await CourseService.saveRawCourseData(context, JSON.parse(courseData));
      console.info('courseCache: 抓取成功并已写入本地');
    } catch (error) {
      console.error('courseCache: 保存课表本地数据失败:', error);
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
