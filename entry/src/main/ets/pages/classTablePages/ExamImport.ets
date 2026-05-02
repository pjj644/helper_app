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

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    this.returnHome = !!(params && params['returnHome'] === '1');
    this.selectedExamTypeId = normalizeExamTypeId(params ? params['examTypeId'] : undefined);
    this.selectedSemesterId = normalizeSemesterId(params ? params['semesterId'] : undefined);
    this.examUrl = buildExamTableUrl(this.selectedSemesterId, this.selectedExamTypeId);
    this.message = `请登录后等待自动抓取${getSemesterLabelById(this.selectedSemesterId)} ${getExamTypeLabelById(this.selectedExamTypeId)}信息`;
    console.info(`testTag ExamImport aboutToAppear returnHome=${this.returnHome}`);
    console.info(`testTag ExamImport params examTypeId=${this.selectedExamTypeId} semesterId=${this.selectedSemesterId}`);
  }

  private navigateToExamPage(): void {
    this.message = `已进入教务系统，正在跳转${getSemesterLabelById(this.selectedSemesterId)} ${getExamTypeLabelById(this.selectedExamTypeId)}页面`;
    console.info(`testTag ExamImport navigateToExamPage menuUrl=${this.menuUrl} target=${this.examUrl}`);
    this.controller.loadUrl(this.examUrl);
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
    console.info(`testTag ExamImport saveAndReturn imported=${exams.length} merged=${mergedExams.length}`);
    await ExamService.saveExams(getContext(this), mergedExams);
    this.getUIContext().getPromptAction().showToast({ message: `考试导入成功，本次${exams.length}条` });
    router.back();
  }

  private retryParseWithDelay(reason: string): void {
    if (this.parseRetryCount >= this.MAX_PARSE_RETRY) {
      this.message = '解析失败：页面数据未就绪，请停留考试页后手动重试';
      console.error(`testTag ExamImport retry exhausted reason=${reason}`);
      return;
    }
    this.parseRetryCount++;
    this.message = `数据尚未就绪，正在重试(${this.parseRetryCount}/${this.MAX_PARSE_RETRY})`;
    console.info(`testTag ExamImport retryParse reason=${reason} retry=${this.parseRetryCount}`);
    setTimeout(() => this.parseExamRows(), 1200);
  }

  private parseExamRows(): void {
    if (this.autoDone) {
      console.info('testTag ExamImport parseExamRows skipped autoDone=true');
      return;
    }

    const currentUrl = this.controller.getUrl();
    console.info(`testTag ExamImport parseExamRows start url=${currentUrl}`);

    const jsCode: string = WebScrapeService.buildExamScrapeScript();

    this.controller.runJavaScript(jsCode, async (error: Error | null, result: string) => {
      if (error) {
        console.error(`testTag ExamImport runJavaScript error=${JSON.stringify(error)}`);
        this.message = '抓取失败，请手动停留在考试列表后重试';
        this.retryParseWithDelay('runJavaScript error');
        return;
      }

      console.info(`testTag ExamImport runJavaScript rawResultLength=${result ? result.length : 0}`);

      try {
        let parsed: Object | string = JSON.parse(result) as Object | string;
        if (typeof parsed === 'string') {
          console.info('testTag ExamImport detected double-json result, parsing second time');
          parsed = JSON.parse(parsed) as Object;
        }

        const payload = parsed as ParsePayload | ParseError;
        if ((payload as ParseError).error && !(payload as ParsePayload).exams) {
          const err = payload as ParseError;
          console.error(`testTag ExamImport parse payload error=${err.error}`);
          this.retryParseWithDelay(`payload error ${err.error}`);
          return;
        }

        const structured = payload as ParsePayload;
        if (!structured || !Array.isArray(structured.exams)) {
          console.error(`testTag ExamImport payload invalid type=${typeof parsed}`);
          this.message = '解析失败，请手动检查页面';
          return;
        }

        if (structured.error) {
          console.error(`testTag ExamImport js catch error=${structured.error}`);
          this.retryParseWithDelay(`js catch ${structured.error}`);
          return;
        }

        const diagnostics = structured.diagnostics;
        if (diagnostics) {
          console.info(`testTag ExamImport diagnostics url=${diagnostics.currentUrl}`);
          console.info(`testTag ExamImport diagnostics rows form=${diagnostics.formTableRowCount} exams=${diagnostics.examsTableRowCount} candidates=${diagnostics.totalCandidateRows} parsed=${diagnostics.parsedExamCount}`);
          console.info(`testTag ExamImport diagnostics inputs semester=${diagnostics.hasSemesterInput} examType=${diagnostics.hasExamTypeInput} sampleCell=${diagnostics.sampleCellText}`);
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
          console.info('testTag ExamImport sorted empty after normalization');
          return;
        }

        this.parseRetryCount = 0;
        this.autoDone = true;
        this.message = `抓取完成，正在保存${getSemesterLabelById(this.selectedSemesterId)} ${getExamTypeLabelById(this.selectedExamTypeId)} ${sorted.length} 条数据`;
        console.info(`testTag ExamImport parse success count=${sorted.length}`);
        await this.saveAndReturn(sorted);
      } catch (e) {
        console.error(`testTag ExamImport parse exception=${JSON.stringify(e)}`);
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
            this.parseRetryCount = 0;
            const url = this.controller.getUrl();
            console.info(`testTag ExamImport manual retry click url=${url}`);
            if (url.includes('stdExamTable!examTable.action')) {
              this.parseExamRows();
              return;
            }
            this.navigateToExamPage();
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
          console.info(`testTag ExamImport onPageEnd url=${url}`);
          if (url.includes('home!childmenus.action') && url.includes('menu.id=844')) {
            if (!this.hasJumpedToExam) {
              this.hasJumpedToExam = true;
              console.info('testTag ExamImport reached menu page and will jump to exam page');
              setTimeout(() => this.navigateToExamPage(), 600);
            }
            return;
          }

          if (url.includes('stdExamTable!examTable.action')) {
            this.message = '已进入考试页面，正在抓取';
            console.info('testTag ExamImport entered exam page, schedule parse');
            setTimeout(() => this.parseExamRows(), 1200);
            return;
          }

          if (url.includes('authserver/login')) {
            this.message = '请先登录教务系统，登录后会自动跳转考试页';
            this.hasJumpedToExam = false;
            console.info('testTag ExamImport on login page, waiting for auth');
            return;
          }

          if (url.includes('/eams/') && !url.includes('stdExamTable!examTable.action') && !url.includes('home!childmenus.action')) {
            this.message = '已登录，正在定位考试页面';
            this.hasJumpedToExam = false;
            console.info('testTag ExamImport in eams non-target page, will jump to exam page');
            setTimeout(() => this.navigateToExamPage(), 600);
          }
        })
        .onErrorReceive((event) => {
          const err = event.error.getErrorInfo();
          console.error(`testTag ExamImport web error=${err}`);
        });
    }
    .width('100%')
    .height('100%');
  }
}
