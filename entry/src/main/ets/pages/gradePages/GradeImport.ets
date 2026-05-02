import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { GradeItem, GradeParsePayload } from '../../model/GradeModel';
import { WebScrapeService } from '../../service/WebScrapeService';
import { GradeService } from '../../service/GradeService';
import { AppConstants } from '../../common/constants/AppConstants';
import { Logger } from '../../common/utils/Logger';

const TAG = 'GradeImport';

@Entry
@Component
struct GradeImport {
  @State message: string = '请登录后等待自动抓取成绩信息';
  @State autoDone: boolean = false;
  controller: webview.WebviewController = new webview.WebviewController();
  @State currentUrl: string = AppConstants.EAMS_HOME_URL;
  private returnHome: boolean = false;
  private semesterId: number = 0;
  private gradeUrl: string = '';
  private parseRetryCount: number = 0;
  private readonly MAX_PARSE_RETRY: number = 5;
  private destroyed: boolean = false;
  private pendingTimer: number = -1;
  private hasNavigatedToGrade: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    this.returnHome = !!(params && params['returnHome']);
    this.semesterId = (params && params['semesterId']) ? Number(params['semesterId']) : 483;
    this.gradeUrl = `${AppConstants.EAMS_GRADE_URL_BASE}?semesterId=${this.semesterId}&projectType=`;
    this.message = '请登录后等待自动抓取成绩信息';
    this.destroyed = false;
    this.hasNavigatedToGrade = false;
    Logger.debug(TAG, `aboutToAppear semesterId=${this.semesterId} gradeUrl=${this.gradeUrl}`);
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
    Logger.debug(TAG, `navigateToGradePage target=${this.gradeUrl}`);
    this.controller.loadUrl(this.gradeUrl);
  }

  private findAndNavigateToGradeLink(): void {
    this.message = '正在查找成绩查询链接...';
    Logger.debug(TAG, '查找成绩链接，等待页面完全加载');

    const findGradeLinkJs: string = `
      (function() {
        try {
          var links = document.querySelectorAll('a');
          for (var i = 0; i < links.length; i++) {
            var href = links[i].getAttribute('href') || '';
            var text = (links[i].innerText || '').trim();
            if (href.includes('person!search.action') || href.includes('grade') || text.includes('成绩') || text.includes('Grade')) {
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

  private mergeWithLocalExams(imported: GradeItem[]): Promise<GradeItem[]> {
    return GradeService.loadGrades(getContext(this)).then((existing: GradeItem[]) => {
      return GradeService.mergeGrades(existing, imported);
    });
  }

  private async saveAndReturn(grades: GradeItem[]): Promise<void> {
    const mergedExams: GradeItem[] = await this.mergeWithLocalExams(grades);
    Logger.debug(TAG, `saveAndReturn imported=${grades.length} merged=${mergedExams.length}`);
    await GradeService.saveGrades(getContext(this), mergedExams);
    this.getUIContext().getPromptAction().showToast({ message: `成绩导入成功，本次${grades.length}条` });
    router.back();
  }

  private waitForDataLoad(): void {
    if (this.destroyed || this.autoDone) {
      return;
    }
    this.pollForGradeData();
  }

  private pollForGradeData(): void {
    const checkScript = `(function(){
      var bodyLen = (document.body && document.body.innerHTML) ? document.body.innerHTML.length : 0;
      var tables = document.querySelectorAll('table');
      var gridRows = 0;
      var gridtable = document.querySelector('.gridtable');
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
        Logger.debug(TAG, `pollForGradeData bodyLen=${status.bodyLen} tables=${status.tableCount} gridRows=${status.gridRows}`);

        if (status.gridRows > 1 || status.bodyLen > 5000) {
          Logger.debug(TAG, 'data seems loaded, start parse');
          this.message = '数据已加载，正在抓取';
          this.pendingTimer = setTimeout(() => {
            this.pendingTimer = -1;
            this.parseGradeRows();
          }, 800);
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
    }, 1500);
  }

  private retryParseWithDelay(reason: string): void {
    if (this.destroyed) {
      Logger.debug(TAG, 'retryParse skipped destroyed');
      return;
    }
    if (this.parseRetryCount >= this.MAX_PARSE_RETRY) {
      this.message = '解析失败：页面数据未就绪，请停留成绩页后手动重试';
      Logger.error(TAG, `retry exhausted reason=${reason}`);
      return;
    }
    this.parseRetryCount++;
    this.message = `数据尚未就绪，正在重试(${this.parseRetryCount}/${this.MAX_PARSE_RETRY})`;
    Logger.debug(TAG, `retryParse reason=${reason} retry=${this.parseRetryCount}`);
    this.pendingTimer = setTimeout(() => {
      this.pendingTimer = -1;
      this.parseGradeRows();
    }, 1200);
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
          Logger.debug(TAG, `diagnostics url=${d.currentUrl} selector=${d.tableSelector} rows=${d.rowCount} parsed=${d.parsedCount}`);
          Logger.debug(TAG, `diagnostics sampleRow=${d.sampleRow}`);
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
          this.message = '未抓取到成绩信息，请先确认该学期有成绩后重试';
          Logger.debug(TAG, 'grades empty after normalization');
          return;
        }

        this.parseRetryCount = 0;
        this.autoDone = true;
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

  build() {
    Column() {
      Text(this.message)
        .fontSize(14)
        .fontColor('#666666')
        .margin({ top: 8, bottom: 8, left: 12, right: 12 });

      Row({ space: 8 }) {
        Button('返回')
          .onClick(() => router.back());
        Button('手动重试抓取')
          .onClick(() => {
            if (this.destroyed) {
              return;
            }
            this.parseRetryCount = 0;
            this.message = '重新抓取...';
            const url = this.controller.getUrl();
            Logger.debug(TAG, `manual retry click url=${url}`);
            if (url.includes('person!search.action')) {
              this.waitForDataLoad();
              return;
            }
            this.hasNavigatedToGrade = false;
            this.findAndNavigateToGradeLink();
          });
      }
      .margin({ left: 12, right: 12, bottom: 8 })
      .width('100%');

      Web({ src: this.currentUrl, controller: this.controller })
        .width('100%')
        .height('100%')
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .onPageEnd(() => {
          const url = this.controller.getUrl();
          Logger.debug(TAG, `onPageEnd url=${url}`);

          if (url.includes('authserver/login')) {
            this.message = '请先登录教务系统，登录后会自动跳转成绩页';
            this.hasNavigatedToGrade = false;
            Logger.debug(TAG, 'on login page, waiting for auth');
            return;
          }

          if (url.includes('person!search.action')) {
            this.message = '已进入成绩页面，正在抓取';
            Logger.debug(TAG, 'entered grade page, schedule parse');
            setTimeout(() => this.waitForDataLoad(), 1500);
            return;
          }

          if (url.includes('/eams/') && !url.includes('person!search.action') && !url.includes('login')) {
            if (!this.hasNavigatedToGrade) {
              this.hasNavigatedToGrade = true;
              this.message = '已登录，正在准备进入成绩页面...';
              Logger.debug(TAG, 'in eams page, will find and navigate to grade (once)');
              setTimeout(() => this.findAndNavigateToGradeLink(), 2500);
            }
            return;
          }
        })
        .onErrorReceive((event) => {
          const err = event.error.getErrorInfo();
          Logger.error(TAG, `web error=${err}`);
        });
    }
    .width('100%')
    .height('100%');
  }
}
