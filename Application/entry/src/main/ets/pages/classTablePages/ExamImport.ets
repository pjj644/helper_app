import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { ExamItem } from '../../model/classTableModel/ExamModel';
import {
  EAMS_EXAM_MENU_URL,
  buildExamTableUrl,
  calculateSemesterId,
  getExamTypeLabelById,
  getSemesterLabelById,
  normalizeExamTypeId,
  normalizeSemesterId,
} from '../../model/classTableModel/ExamAccessRules';
import { WebScrapeService } from '../../service/WebScrapeService';
import { ExamService } from '../../service/ExamService';
import { ExamUtils, RawExamRow } from '../../common/utils/ExamUtils';
import { VpnEncoder } from '../../common/utils/VpnEncoder';
import { AppConstants } from '../../common/constants/AppConstants';
import { LoadingOverlay } from '../../components/LoadingOverlay';
import { WebScrapeTakeoverBar } from '../../components/WebScrapeTakeoverBar';

interface ParseError {
  error: string;
}

interface ParseDiagnostics {
  currentUrl: string;
  formTableRowCount: number;
  examsTableRowCount: number;
  totalCandidateRows: number;
  parsedExamCount: number;
  hasSemesterInput: boolean;
  hasExamTypeInput: boolean;
  sampleCellText: string;
}

interface ParsePayload {
  exams: RawExamRow[];
  diagnostics: ParseDiagnostics;
  error?: string;
}

@Entry
@Component
struct ExamImport {
  @State message: string = '请登录后等待自动抓取考试信息';
  @State autoDone: boolean = false;
  @State isProcessing: boolean = true;
  @State isVpnMode: boolean = false;
  @State showRefreshBtn: boolean = false;
  @State manualMode: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();
  @State currentUrl: string = EAMS_EXAM_MENU_URL;
  private returnHome: boolean = false;
  private readonly menuUrl: string = EAMS_EXAM_MENU_URL;
  private examUrl: string = '';
  private selectedExamTypeId: number = 1;
  private selectedSemesterId: number = calculateSemesterId();
  private hasJumpedToExam: boolean = false;
  private parseRetryCount: number = 0;
  private readonly MAX_PARSE_RETRY: number = 5;
  private vpnAutoDetected: boolean = false;
  private vpnPortalNavigated: boolean = false;
  private http500RetryCount: number = 0;
  private readonly MAX_HTTP_500_RETRY: number = 2;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.returnHome = !!(params && params['returnHome'] === '1');
    this.selectedExamTypeId = normalizeExamTypeId(params ? params['examTypeId'] : undefined);
    this.selectedSemesterId = normalizeSemesterId(params ? params['semesterId'] : undefined);
    this.examUrl = buildExamTableUrl(this.selectedSemesterId, this.selectedExamTypeId);
    this.message = `请登录后等待自动抓取${getSemesterLabelById(this.selectedSemesterId)} ${getExamTypeLabelById(this.selectedExamTypeId)}信息`;
    console.info(`[ExamImport] aboutToAppear returnHome=${this.returnHome}`);
    console.info(`[ExamImport] params examTypeId=${this.selectedExamTypeId} semesterId=${this.selectedSemesterId}`);
    this.initVpnMode();
  }

  private async initVpnMode(): Promise<void> {
    this.isVpnMode = false;
  }

  private navigateToExamPage(): void {
    this.message = `已进入教务系统，正在跳转${getSemesterLabelById(this.selectedSemesterId)} ${getExamTypeLabelById(this.selectedExamTypeId)}页面`;
    const currentUrl = this.controller.getUrl();
    const onCampusNetwork = currentUrl.includes('eams.uestc.edu.cn');
    const useVpn = this.isVpnMode && !onCampusNetwork;
    const targetUrl = useVpn ?
      VpnEncoder.buildVpnExamTableUrl(this.selectedSemesterId, this.selectedExamTypeId) :
      this.examUrl;
    console.info(`[ExamImport] navigateToExamPage useVpn=${useVpn} target=${targetUrl}`);
    this.controller.loadUrl(targetUrl);
  }

  private async mergeWithLocalExams(importedExams: ExamItem[]): Promise<ExamItem[]> {
    const existingItems: ExamItem[] = await ExamService.loadExams(getContext(this));
    const keptItems: ExamItem[] = existingItems.filter((item: ExamItem) => {
      const itemSemesterId: number = ExamUtils.resolveSemesterId(item, this.selectedSemesterId);
      const itemExamTypeId: number = ExamUtils.resolveExamTypeId(item, this.selectedExamTypeId);
      return !(itemSemesterId === this.selectedSemesterId && itemExamTypeId === this.selectedExamTypeId);
    });
    return ExamUtils.sortExams([...keptItems, ...importedExams]);
  }

  private async saveAndReturn(exams: ExamItem[]): Promise<void> {
    const mergedExams: ExamItem[] = await this.mergeWithLocalExams(exams);
    console.info(`[ExamImport] saveAndReturn imported=${exams.length} merged=${mergedExams.length}`);
    await ExamService.saveExams(getContext(this), mergedExams);
    this.getUIContext().getPromptAction().showToast({ message: `考试导入成功，本次${exams.length}条` });
    router.back();
  }

  private retryParseWithDelay(reason: string): void {
    if (this.parseRetryCount >= this.MAX_PARSE_RETRY) {
      if (!this.isVpnMode && !this.vpnAutoDetected) {
        console.info(`[ExamImport] retry exhausted, switching to VPN mode`);
        this.switchToVpnMode();
        return;
      }
      this.message = '解析失败：页面数据未就绪，请停留考试页后手动重试';
      this.isProcessing = false;
      console.error(`[ExamImport] retry exhausted reason=${reason}`);
      return;
    }
    this.parseRetryCount++;
    this.message = `数据尚未就绪，正在重试(${this.parseRetryCount}/${this.MAX_PARSE_RETRY})`;
    console.info(`[ExamImport] retryParse reason=${reason} retry=${this.parseRetryCount}`);
    setTimeout(() => this.parseExamRows(), 1200);
  }

  private parseExamRows(): void {
    if (this.autoDone) {
      console.info('[ExamImport] parseExamRows skipped autoDone=true');
      return;
    }

    const currentUrl = this.controller.getUrl();
    console.info(`[ExamImport] parseExamRows start url=${currentUrl}`);

    const jsCode: string = WebScrapeService.buildExamScrapeScript();

    this.controller.runJavaScript(jsCode, async (error: Error | null, result: string) => {
      if (error) {
        console.error(`[ExamImport] runJavaScript error=${JSON.stringify(error)}`);
        this.message = '抓取失败，请手动停留在考试列表后重试';
        this.retryParseWithDelay('runJavaScript error');
        return;
      }

      console.info(`[ExamImport] runJavaScript rawResultLength=${result ? result.length : 0}`);

      try {
        let parsed: Object | string = JSON.parse(result) as Object | string;
        if (typeof parsed === 'string') {
          console.info('[ExamImport] detected double-json result, parsing second time');
          parsed = JSON.parse(parsed) as Object;
        }

        const payload = parsed as ParsePayload | ParseError;
        if ((payload as ParseError).error && !(payload as ParsePayload).exams) {
          const err = payload as ParseError;
          console.error(`[ExamImport] parse payload error=${err.error}`);
          this.retryParseWithDelay(`payload error ${err.error}`);
          return;
        }

        const structured = payload as ParsePayload;
        if (!structured || !Array.isArray(structured.exams)) {
          console.error(`[ExamImport] payload invalid type=${typeof parsed}`);
          this.message = '解析失败，请手动检查页面';
          return;
        }

        if (structured.error) {
          console.error(`[ExamImport] js catch error=${structured.error}`);
          this.retryParseWithDelay(`js catch ${structured.error}`);
          return;
        }

        const diagnostics = structured.diagnostics;
        if (diagnostics) {
          console.info(`[ExamImport] diagnostics url=${diagnostics.currentUrl}`);
          console.info(`[ExamImport] diagnostics rows form=${diagnostics.formTableRowCount} exams=${diagnostics.examsTableRowCount} candidates=${diagnostics.totalCandidateRows} parsed=${diagnostics.parsedExamCount}`);
          console.info(`[ExamImport] diagnostics inputs semester=${diagnostics.hasSemesterInput} examType=${diagnostics.hasExamTypeInput} sampleCell=${diagnostics.sampleCellText}`);
        }

        const rows = structured.exams;
        if (rows.length === 0) {
          this.retryParseWithDelay('no exam rows parsed');
          return;
        }

        const normalized: ExamItem[] = [];
        for (let i = 0; i < rows.length; i++) {
          normalized.push(ExamUtils.rowToExam(rows[i], this.selectedSemesterId, this.selectedExamTypeId));
        }
        const sorted: ExamItem[] = ExamUtils.sortExams(normalized);
        if (sorted.length === 0) {
          this.message = '未抓取到考试信息，请先切换到有数据的考试类型后重试';
          this.isProcessing = false;
          console.info('[ExamImport] sorted empty after normalization');
          return;
        }

        this.parseRetryCount = 0;
        this.autoDone = true;
        this.isProcessing = false;
        this.message = `抓取完成，正在保存${getSemesterLabelById(this.selectedSemesterId)} ${getExamTypeLabelById(this.selectedExamTypeId)} ${sorted.length} 条数据`;
        console.info(`[ExamImport] parse success count=${sorted.length}`);
        await this.saveAndReturn(sorted);
      } catch (e) {
        console.error(`[ExamImport] parse exception=${JSON.stringify(e)}`);
        this.message = '数据解析异常，请重试';
        this.retryParseWithDelay('parse exception');
      }
    });
  }

  private switchToVpnMode(): void {
    if (this.vpnAutoDetected) {
      console.info('[ExamImport] VPN mode already switched, skip');
      return;
    }
    console.info('[ExamImport] 检测到非校园网环境，自动切换VPN模式');
    this.vpnAutoDetected = true;
    this.isVpnMode = true;
    this.hasJumpedToExam = false;
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
            this.parseRetryCount = 0;
            const url = this.controller.getUrl();
            console.info(`[ExamImport] manual scrape url=${url}`);
            this.parseExamRows();
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
              this.message = '已开启手动接管：请在网页中完成登录并导航至考试页，随后点击“立即抓取当前页”';
            } else {
              this.isProcessing = true;
              this.message = '正在自动处理中...';
            }
          }
        })

        Web({ src: this.currentUrl, controller: this.controller })
        .width('100%')
        .height('100%')
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .onPageEnd(() => {
          const url = this.controller.getUrl();
          this.showRefreshBtn = false;
          console.info(`[ExamImport] onPageEnd url=${url}`);

          if (VpnEncoder.isLoginPage(url) || url.includes('authserver/login')) {
            this.message = this.isVpnMode ? 'VPN模式：请先完成统一身份认证登录' : '请先登录统一身份认证，登录后会自动跳转考试页';
            this.isProcessing = false;
            this.hasJumpedToExam = false;
            this.vpnPortalNavigated = false;
            console.info('[ExamImport] on login page, waiting for auth');
            return;
          }

          if (this.isVpnMode && VpnEncoder.isWebvpnPortal(url)) {
            if (!this.vpnPortalNavigated) {
              this.vpnPortalNavigated = true;
              this.message = 'VPN登录成功，正在跳转教务系统...';
              console.info('[ExamImport] VPN portal detected, navigating to EAMS');
              setTimeout(() => {
                this.controller.loadUrl(VpnEncoder.buildVpnExamMenuUrl());
              }, 1000);
            }
            return;
          }

          if (url.includes('stdExamTable!examTable.action')) {
            this.message = '已进入考试页面，正在抓取';
            console.info('[ExamImport] entered exam page, schedule parse');
            setTimeout(() => this.parseExamRows(), 1200);
            return;
          }

          // 运行通用登录状态与重复登录检测脚本
          const checkLoginJs = WebScrapeService.buildLoginCheckScript();
          this.controller.runJavaScript(checkLoginJs, (error: Error | null, result: string) => {
            if (error) {
              console.error(`[ExamImport] checkLogin error:`, error);
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
              console.info(`[ExamImport] loginStatus:`, loginStatus);

              if (loginStatus.status === 'repeat_login_prompt') {
                console.info('[ExamImport] 检测到重复登录提示，执行自动确认');
                this.message = '检测到多设备登录提示，正在自动确认...';
                const confirmUrl: string = (loginStatus.href && loginStatus.href.length > 0) ?
                  loginStatus.href :
                  (this.isVpnMode ? VpnEncoder.buildVpnHomeUrl() : 'https://eams.uestc.edu.cn/eams/home.action');
                setTimeout(() => {
                  console.info('[ExamImport] loadUrl confirm repeat login:', confirmUrl);
                  this.controller.loadUrl(confirmUrl);
                }, 300);
                return;
              }

              if (loginStatus.status === 'logged_in') {
                if (!this.hasJumpedToExam) {
                  this.hasJumpedToExam = true;
                  this.message = '已登录，正在跳转考试页面...';
                  console.info('[ExamImport] logged_in confirmed, jumping to exam page');
                  setTimeout(() => this.navigateToExamPage(), 800);
                }
              } else if (loginStatus.status === 'not_logged_in') {
                console.info('[ExamImport] not_logged_in, waiting for credentials');
                this.isProcessing = false;
                this.message = '请完成统一身份认证登录';
              }
            } catch (e) {
              console.error('[ExamImport] parse loginStatus error:', e);
            }
          });
        })
        .onHttpErrorReceive((event) => {
          const statusCode = event.response.getResponseCode();
          console.error(`[ExamImport] HTTP error status=${statusCode}`);
          if (!this.vpnAutoDetected && statusCode === 403) {
            console.info('[ExamImport] detected 403, switching to VPN mode');
            this.switchToVpnMode();
            return;
          }
          if (statusCode === 500 && this.http500RetryCount < this.MAX_HTTP_500_RETRY) {
            this.http500RetryCount++;
            this.hasJumpedToExam = false;
            this.message = `教务会话初始化中，正在通过主页激活(${this.http500RetryCount}/${this.MAX_HTTP_500_RETRY})...`;
            console.info(`[ExamImport] HTTP 500, navigating to home.action to restore session (attempt ${this.http500RetryCount})`);
            const homeUrl: string = this.isVpnMode ?
              VpnEncoder.buildVpnHomeUrl() :
              'https://eams.uestc.edu.cn/eams/home.action';
            setTimeout(() => {
              this.controller.loadUrl(homeUrl);
            }, 1000);
            return;
          }
        })
        .onErrorReceive((event) => {
          const err = event.error.getErrorInfo();
          console.error(`[ExamImport] web error=${err}`);
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
