import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { GradeItem, GradeParsePayload } from '../../model/GradeModel';
import { WebScrapeService } from '../../service/WebScrapeService';
import { GradeService } from '../../service/GradeService';
import { AppConstants } from '../../common/constants/AppConstants';
import { VpnEncoder } from '../../common/utils/VpnEncoder';
import { Logger } from '../../common/utils/Logger';
import { LoadingOverlay } from '../../components/LoadingOverlay';
import { calculateSemesterId, getGradeSemesterOptions, getPreviousSemesterId, GradeSemesterOptionItem } from '../../model/classTableModel/ExamAccessRules';
import { WebScrapeTakeoverBar } from '../../components/WebScrapeTakeoverBar';

const TAG = 'GradeImport';

@Entry
@Component
struct GradeImport {
  @State message: string = '请登录后等待自动抓取成绩信息';
  @State autoDone: boolean = false;
  @State isProcessing: boolean = true;
  @State isVpnMode: boolean = false;
  @State showRefreshBtn: boolean = false;
  @State manualMode: boolean = false;
  @State selectedSemesterIndex: number = 0;
  controller: webview.WebviewController = new webview.WebviewController();
  @State currentUrl: string = AppConstants.EAMS_PORTAL_URL;
  private returnHome: boolean = false;
  private semesterId: number = 0;
  private gradeUrl: string = '';
  private parseRetryCount: number = 0;
  private readonly MAX_PARSE_RETRY: number = 2;
  private destroyed: boolean = false;
  private pendingTimer: number = -1;
  private hasNavigatedToGrade: boolean = false;
  private vpnAutoDetected: boolean = false;
  private vpnPortalNavigated: boolean = false;
  private pollCount: number = 0;
  private http500RetryCount: number = 0;
  private readonly MAX_HTTP_500_RETRY: number = 2;
  private semesterOptionList: GradeSemesterOptionItem[] = [];

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    this.returnHome = !!(params && params['returnHome']);
    const rawOptions: GradeSemesterOptionItem[] = getGradeSemesterOptions();
    this.semesterOptionList = rawOptions.filter((o: GradeSemesterOptionItem) => o.semesterId > 0);

    const defaultSemId: number = getPreviousSemesterId();
    this.semesterId = (params && params['semesterId']) ? Number(params['semesterId']) : defaultSemId;
    if (this.semesterId <= 0) {
      this.semesterId = defaultSemId;
    }

    let foundIdx: number = -1;
    for (let i = 0; i < this.semesterOptionList.length; i++) {
      if (this.semesterOptionList[i].semesterId === this.semesterId) {
        foundIdx = i;
        break;
      }
    }
    this.selectedSemesterIndex = foundIdx >= 0 ? foundIdx : 0;
    if (foundIdx >= 0) {
      this.semesterId = this.semesterOptionList[foundIdx].semesterId;
    }

    this.gradeUrl = `${AppConstants.EAMS_GRADE_SEARCH_URL_BASE}?semesterId=${this.semesterId}&projectType=`;
    this.message = '请登录后等待自动抓取成绩信息';
    this.destroyed = false;
    this.hasNavigatedToGrade = false;
    this.pollCount = 0;
    this.http500RetryCount = 0;
    Logger.info(TAG, `aboutToAppear semesterId=${this.semesterId} gradeUrl=${this.gradeUrl}`);
    this.initVpnMode();
  }

  private getSemesterSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < this.semesterOptionList.length; i++) {
      opts.push({ value: this.semesterOptionList[i].label });
    }
    return opts;
  }

  private onSemesterSelected(index: number): void {
    if (index < 0 || index >= this.semesterOptionList.length) {
      return;
    }
    this.selectedSemesterIndex = index;
    this.semesterId = this.semesterOptionList[index].semesterId;
    this.gradeUrl = `${AppConstants.EAMS_GRADE_SEARCH_URL_BASE}?semesterId=${this.semesterId}&projectType=`;
    this.parseRetryCount = 0;
    this.autoDone = false;
    this.hasNavigatedToGrade = true;
    this.message = `正在切换到学期 ${this.semesterOptionList[index].label}...`;
    Logger.info(TAG, `switch semester to ${this.semesterId} (${this.semesterOptionList[index].label})`);
    this.navigateToGradePage();
  }

  private async initVpnMode(): Promise<void> {
    this.isVpnMode = false;
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    if (this.pendingTimer >= 0) {
      clearTimeout(this.pendingTimer);
      this.pendingTimer = -1;
      Logger.debug(TAG, 'aboutToDisappear cleared pending timer');
    }
  }

  private navigateToGradePage(): void {
    this.message = '已进入教务系统，正在跳转成绩查询页面...';
    const currentUrl = this.controller.getUrl();
    const onCampusNetwork = currentUrl.includes('eams.uestc.edu.cn');
    const useVpn = this.isVpnMode && !onCampusNetwork;
    const targetUrl = useVpn ?
      VpnEncoder.buildVpnGradeUrl(this.semesterId) :
      this.gradeUrl;
    Logger.debug(TAG, `navigateToGradePage useVpn=${useVpn} target=${targetUrl}`);
    this.controller.loadUrl(targetUrl);
  }

  private findAndNavigateToGradeLink(): void {
    this.message = '正在查找成绩查询链接...';
    Logger.debug(TAG, '查找成绩链接，等待页面完全加载');

    const currentUrl = this.controller.getUrl();
    const onCampusNetwork = currentUrl.includes('eams.uestc.edu.cn');
    const useVpn = this.isVpnMode && !onCampusNetwork;

    if (useVpn) {
      Logger.debug(TAG, 'VPN模式：直接导航到VPN代理的成绩URL');
      this.navigateToGradePage();
      return;
    }

    const findGradeLinkJs: string = `
      (function() {
        try {
          var links = document.querySelectorAll('a');
          for (var i = 0; i < links.length; i++) {
            var href = links[i].getAttribute('href') || '';
            var text = (links[i].innerText || '').trim();
            if (href.includes('person!search.action') || href.includes('person!history.action') || href.includes('grade') || text.includes('成绩') || text.includes('Grade')) {
              return JSON.stringify({ found: true, href: links[i].href, text: text });
            }
          }

          var currentHost = window.location.host;
          if (currentHost.includes('eams.uestc.edu.cn')) {
            return JSON.stringify({ found: true, href: '${this.gradeUrl}', text: 'constructed_url' });
          }

          return JSON.stringify({ found: false, href: '', text: '' });
        } catch(e) {
          return JSON.stringify({ found: false, error: e.message });
        }
      })();
    `;

    this.controller.runJavaScript(findGradeLinkJs, (error: Error | null, result: string) => {
      if (error) {
        Logger.error(TAG, `查找成绩链接失败=${JSON.stringify(error)}`);
        this.message = '查找链接失败，使用默认地址...';
        setTimeout(() => this.navigateToGradePage(), 500);
        return;
      }

      try {
        let parsed: Object | string = JSON.parse(result) as Object | string;
        if (typeof parsed === 'string') {
          parsed = JSON.parse(parsed) as Object;
        }
        const linkInfo = parsed as Record<string, string | boolean>;
        Logger.debug(TAG, `查找结果 found=${linkInfo.found} href=${linkInfo.href} text=${linkInfo.text}`);

        if (linkInfo.found && linkInfo.href) {
          this.message = '正在跳转到成绩页面...';
          const targetUrl: string = linkInfo.href as string;
          Logger.debug(TAG, `使用找到的链接: ${targetUrl}`);
          setTimeout(() => {
            this.controller.loadUrl(targetUrl);
          }, 500);
        } else {
          Logger.warn(TAG, '未找到成绩链接，使用默认URL');
          this.message = '未找到链接，正在直接访问...';
          setTimeout(() => this.navigateToGradePage(), 500);
        }
      } catch (e) {
        Logger.error(TAG, `解析链接失败=${JSON.stringify(e)}`);
        setTimeout(() => this.navigateToGradePage(), 500);
      }
    });
  }

  private mergeWithLocalGrades(imported: GradeItem[]): Promise<GradeItem[]> {
    return GradeService.loadGrades(getContext(this)).then((existing: GradeItem[]) => {
      return GradeService.mergeGrades(existing, imported);
    });
  }

  private async saveAndReturn(grades: GradeItem[]): Promise<void> {
    const mergedGrades: GradeItem[] = await this.mergeWithLocalGrades(grades);
    Logger.debug(TAG, `saveAndReturn imported=${grades.length} merged=${mergedGrades.length}`);
    await GradeService.saveGrades(getContext(this), mergedGrades);
    this.getUIContext().getPromptAction().showToast({ message: `成绩导入成功，本次${grades.length}条` });
    router.back();
  }

  private waitForDataLoad(): void {
    if (this.destroyed || this.autoDone) {
      return;
    }
    this.pollCount = 0;
    this.pollForGradeData();
  }

  private pollForGradeData(): void {
    this.pollCount++;
    const checkScript = `(function(){
      var bodyLen = (document.body && document.body.innerHTML) ? document.body.innerHTML.length : 0;
      var tables = document.querySelectorAll('table');
      var gridRows = 0;
      var gridtable = document.querySelector('.gridtable') || document.querySelector('table');
      if (gridtable) {
        var tbody = gridtable.querySelector('tbody');
        var rows = tbody ? tbody.querySelectorAll('tr') : gridtable.querySelectorAll('tr');
        gridRows = rows.length;
      }
      return JSON.stringify({ bodyLen: bodyLen, tableCount: tables.length, gridRows: gridRows });
    })();`;

    this.controller.runJavaScript(checkScript, (error: Error | null, result: string) => {
      if (this.destroyed || this.autoDone) {
        return;
      }
      if (error) {
        Logger.error(TAG, `pollForGradeData error=${JSON.stringify(error)}`);
        this.scheduleDataPoll();
        return;
      }

      try {
        let parsed: Object | string = JSON.parse(result) as Object | string;
        if (typeof parsed === 'string') {
          parsed = JSON.parse(parsed) as Object;
        }
        const status = parsed as Record<string, number>;
        Logger.debug(TAG, `pollForGradeData bodyLen=${status.bodyLen} tables=${status.tableCount} gridRows=${status.gridRows} pollCount=${this.pollCount}`);

        if (status.gridRows > 1 || status.bodyLen > 2000 || this.pollCount >= 3) {
          Logger.debug(TAG, 'data seems loaded or poll limit reached, start parse');
          this.message = '正在解析成绩数据...';
          this.pendingTimer = setTimeout(() => {
            this.pendingTimer = -1;
            this.parseGradeRows();
          }, 500);
          return;
        }

        this.message = `等待成绩数据加载...(${status.bodyLen}字节, ${status.gridRows}行)`;
        this.scheduleDataPoll();
      } catch (e) {
        Logger.error(TAG, `pollForGradeData parse error=${JSON.stringify(e)}`);
        this.scheduleDataPoll();
      }
    });
  }

  private scheduleDataPoll(): void {
    this.pendingTimer = setTimeout(() => {
      this.pendingTimer = -1;
      if (this.destroyed || this.autoDone) {
        return;
      }
      this.pollForGradeData();
    }, 1200);
  }

  private retryParseWithDelay(reason: string): void {
    if (this.destroyed) {
      Logger.debug(TAG, 'retryParse skipped destroyed');
      return;
    }
    if (this.parseRetryCount >= this.MAX_PARSE_RETRY) {
      this.message = '当前未查询到有效成绩记录，可返回或稍后重试';
      this.isProcessing = false;
      Logger.info(TAG, `retry completed reason=${reason}`);
      return;
    }
    this.parseRetryCount++;
    this.message = `数据解析中，正在尝试二次提取(${this.parseRetryCount}/${this.MAX_PARSE_RETRY})`;
    Logger.debug(TAG, `retryParse reason=${reason} retry=${this.parseRetryCount}`);
    this.pendingTimer = setTimeout(() => {
      this.pendingTimer = -1;
      this.parseGradeRows();
    }, 1000);
  }

  private parseGradeRows(): void {
    if (this.destroyed) {
      Logger.debug(TAG, 'parseGradeRows skipped destroyed');
      return;
    }
    if (this.autoDone) {
      Logger.debug(TAG, 'parseGradeRows skipped autoDone=true');
      return;
    }

    const currentUrl = this.controller.getUrl();
    Logger.debug(TAG, `parseGradeRows start url=${currentUrl}`);

    const jsCode: string = WebScrapeService.buildGradeScrapeScript();

    this.controller.runJavaScript(jsCode, (error: Error | null, result: string) => {
      if (this.destroyed) {
        Logger.debug(TAG, 'runJavaScript callback skipped destroyed');
        return;
      }
      if (error) {
        Logger.error(TAG, `runJavaScript error=${JSON.stringify(error)}`);
        this.message = '抓取失败，请手动停留在成绩列表后重试';
        this.retryParseWithDelay('runJavaScript error');
        return;
      }

      Logger.debug(TAG, `runJavaScript rawResultLength=${result ? result.length : 0}`);

      try {
        let parsed: Object | string = JSON.parse(result) as Object | string;
        if (typeof parsed === 'string') {
          Logger.debug(TAG, 'detected double-json result, parsing second time');
          parsed = JSON.parse(parsed) as Object;
        }

        const payload = parsed as GradeParsePayload;
        if (payload.diagnostics) {
          const d = payload.diagnostics;
          Logger.info(TAG, `diagnostics url=${d.currentUrl} title=${d.pageTitle || ''} selector=${d.tableSelector || ''} tables=${d.allTablesOnPage || 0} rows=${d.rowCount} parsed=${d.parsedCount}`);
          if (d.bodySnippet) {
            Logger.info(TAG, `diagnostics snippet=${d.bodySnippet}`);
          }
        }

        if (payload.error) {
          Logger.error(TAG, `payload error=${payload.error}`);
          this.retryParseWithDelay(`payload error ${payload.error}`);
          return;
        }

        if (!payload.grades || payload.grades.length === 0) {
          this.retryParseWithDelay('no grade rows parsed');
          return;
        }

        const grades: GradeItem[] = GradeService.parseRawGrades(payload.grades, this.semesterId);
        if (grades.length === 0) {
          this.message = '未抓取到有效成绩信息';
          this.isProcessing = false;
          Logger.debug(TAG, 'grades empty after normalization');
          return;
        }

        this.parseRetryCount = 0;
        this.autoDone = true;
        this.isProcessing = false;
        this.message = `抓取完成，正在保存${grades.length} 条数据`;
        Logger.info(TAG, `parse success count=${grades.length}`);
        this.saveAndReturn(grades);
      } catch (e) {
        Logger.error(TAG, `parse exception=${JSON.stringify(e)}`);
        this.message = '数据解析异常，请重试';
        this.retryParseWithDelay('parse exception');
      }
    });
  }

  private switchToVpnMode(): void {
    if (this.vpnAutoDetected) {
      Logger.debug(TAG, 'VPN mode already switched, skip');
      return;
    }
    Logger.info(TAG, '检测到非校园网环境，自动切换VPN模式');
    this.vpnAutoDetected = true;
    this.isVpnMode = true;
    this.hasNavigatedToGrade = false;
    this.vpnPortalNavigated = false;
    this.message = '检测到非校园网环境，已切换到VPN模式，正在加载WebVPN...';
    this.currentUrl = AppConstants.WEBVPN_LOGIN_URL;
    this.controller.loadUrl(AppConstants.WEBVPN_LOGIN_URL);
  }

  build() {
    Stack() {
      Column() {
        WebScrapeTakeoverBar({
          isManualMode: this.manualMode,
          promptMessage: this.message,
          isExtracting: !this.autoDone && this.isProcessing,
          onScrape: () => {
            if (this.destroyed) return;
            this.parseRetryCount = 0;
            this.autoDone = false;
            this.message = '正在抓取成绩数据...';
            this.waitForDataLoad();
          },
          onRefresh: () => {
            const url = this.controller.getUrl();
            this.controller.loadUrl(url || this.currentUrl);
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
              this.message = '已开启手动接管：请在网页中完成登录并导航至成绩页，随后点击“立即抓取当前页”';
            } else {
              this.isProcessing = true;
              this.message = '正在自动处理中...';
            }
          }
        })

        Row({ space: 8 }) {
          Select(this.getSemesterSelectOptions())
            .selected(this.selectedSemesterIndex)
            .value(this.semesterOptionList[this.selectedSemesterIndex]?.label || '选择学期')
            .onSelect((index: number) => {
              this.onSemesterSelected(index);
            })
            .layoutWeight(1);
        }
        .padding({ left: 12, right: 12, top: 4, bottom: 6 })
        .width('100%');

        Web({ src: this.currentUrl, controller: this.controller })
        .width('100%')
        .height('100%')
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .fileAccess(true)
        .imageAccess(true)
        .onlineImageAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .onPageEnd(() => {
          const url = this.controller.getUrl();
          this.showRefreshBtn = false;
          Logger.debug(TAG, `onPageEnd url=${url}`);

          if (VpnEncoder.isLoginPage(url) || url.includes('authserver/login')) {
            this.message = this.isVpnMode ? 'VPN模式：请先完成统一身份认证登录' : '请先登录统一身份认证，登录后会自动跳转成绩页';
            this.isProcessing = false;
            this.hasNavigatedToGrade = false;
            this.vpnPortalNavigated = false;
            Logger.debug(TAG, 'on login page, waiting for auth');
            return;
          }

          if (this.isVpnMode && VpnEncoder.isWebvpnPortal(url)) {
            if (!this.vpnPortalNavigated) {
              this.vpnPortalNavigated = true;
              this.message = 'VPN登录成功，正在跳转教务系统...';
              Logger.debug(TAG, 'VPN portal detected, navigating to EAMS');
              setTimeout(() => {
                this.controller.loadUrl(VpnEncoder.buildVpnEamsPortalUrl());
              }, 1000);
            }
            return;
          }

          if (url.includes('person!search.action') || url.includes('person!history.action') || url.includes('teach/grade/course/person')) {
            this.message = '已进入成绩页面，正在抓取';
            Logger.info(TAG, `entered grade page: ${url}, schedule parse`);
            this.http500RetryCount = 0;
            setTimeout(() => this.waitForDataLoad(), 1500);
            return;
          }

          // 运行通用登录状态与重复登录检测脚本
          const checkLoginJs = WebScrapeService.buildLoginCheckScript();
          this.controller.runJavaScript(checkLoginJs, (error: Error | null, result: string) => {
            if (error) {
              Logger.error(TAG, `checkLogin error: ${JSON.stringify(error)}`);
              return;
            }
            try {
              let loginResult: string = result;
              if (result.trim().startsWith('"')) {
                const inner: string = JSON.parse(result);
                if (typeof inner === 'string') {
                  loginResult = inner;
                }
              }
              const loginStatus = JSON.parse(loginResult) as Record<string, string>;
              Logger.debug(TAG, `loginStatus: ${JSON.stringify(loginStatus)}`);

              if (loginStatus.status === 'repeat_login_prompt') {
                Logger.info(TAG, '检测到重复登录提示，执行自动确认');
                this.message = '检测到多设备登录提示，正在自动确认...';
                const confirmUrl: string = (loginStatus.href && loginStatus.href.length > 0) ?
                  loginStatus.href :
                  (this.isVpnMode ? VpnEncoder.buildVpnHomeUrl() : 'https://eams.uestc.edu.cn/eams/home.action');
                setTimeout(() => {
                  if (this.destroyed) {
                    return;
                  }
                  Logger.info(TAG, `loadUrl confirm repeat login: ${confirmUrl}`);
                  this.controller.loadUrl(confirmUrl);
                }, 300);
                return;
              }

              if (loginStatus.status === 'logged_in') {
                if (!this.hasNavigatedToGrade) {
                  this.hasNavigatedToGrade = true;
                  const semLabel: string = this.semesterOptionList[this.selectedSemesterIndex]?.label || '';
                  this.message = `已登录，正在跳转至 ${semLabel} 成绩页面...`;
                  Logger.info(TAG, `logged_in confirmed, navigating to grade: ${this.gradeUrl}`);
                  setTimeout(() => this.navigateToGradePage(), 800);
                }
              } else if (loginStatus.status === 'not_logged_in') {
                Logger.debug(TAG, 'not_logged_in, waiting for credentials');
                this.isProcessing = false;
                this.message = '请完成统一身份认证登录';
              }
            } catch (e) {
              Logger.error(TAG, `parse loginStatus error: ${JSON.stringify(e)}`);
            }
          });
        })
        .onHttpErrorReceive((event) => {
          const statusCode = event.response.getResponseCode();
          Logger.error(TAG, `Grade HTTP error status=${statusCode}`);
          if (!this.vpnAutoDetected && statusCode === 403) {
            Logger.info(TAG, 'GradeImport detected 403, switching to VPN mode');
            this.switchToVpnMode();
            return;
          }
          if (statusCode === 500 && this.http500RetryCount < this.MAX_HTTP_500_RETRY) {
            this.http500RetryCount++;
            this.message = `教务系统会话就绪中，正在重试(${this.http500RetryCount}/${this.MAX_HTTP_500_RETRY})...`;
            Logger.info(TAG, `Grade HTTP 500, retrying in 1.5s (attempt ${this.http500RetryCount})`);
            setTimeout(() => {
              if (this.destroyed) {
                return;
              }
              this.navigateToGradePage();
            }, 1500);
            return;
          }
        })
        .onErrorReceive((event) => {
          const err = event.error.getErrorInfo();
          Logger.error(TAG, `web error=${err}`);
          if (!this.isVpnMode && !this.vpnAutoDetected &&
              (err.includes('net::ERR_CONNECTION') ||
               err.includes('net::ERR_NAME_NOT_RESOLVED'))) {
            this.switchToVpnMode();
            return;
          }
          this.showRefreshBtn = true;
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
          this.controller.loadUrl(this.currentUrl);
        })
      }
    }
    .width('100%')
    .height('100%');
  }
}
