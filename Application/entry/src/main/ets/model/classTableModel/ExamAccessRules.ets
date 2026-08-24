import { AppConstants } from '../../common/constants/AppConstants';
import { AppConfigRepository } from '../../repository/AppConfigRepository';
import { SemesterAnchor, parseSemesterAnchorFromLabel } from '../SemesterConfig';

export const EAMS_EXAM_MENU_URL: string = AppConstants.EAMS_EXAM_MENU_URL;
export const EAMS_EXAM_TABLE_BASE_URL: string = AppConstants.EAMS_EXAM_TABLE_BASE_URL;

// ===== 教务系统学期 ID 锚点（T5a 云端化） =====
// 优先消费云端 app-config 注入：baseSemesterId 与 semesterLabel 反推的学年/学期锚点必须
// 成对生效（同一包内校验通过才启用），避免 id 空间与锚点错位；
// 以下常量为云端不可用时的最终兜底（历史硬编码值），勿删除。
const FALLBACK_BASE_SEMESTER_ID: number = 503;
const FALLBACK_BASE_ACADEMIC_START_YEAR: number = 2025;
const FALLBACK_BASE_TERM_NUMBER: number = 2;
const SEMESTER_ID_STEP: number = 20;

/** 生效的学期 ID 映射基准：id 基准值 + 其对应的学年期锚点 */
interface BaseSemesterMapping {
  baseSemesterId: number;
  baseStartYear: number;
  baseTermNumber: number;
}

/** 解析生效映射基准：云端配置合法时用注入值，否则整体回退内置常量 */
function resolveBaseSemesterMapping(): BaseSemesterMapping {
  const config = AppConfigRepository.getConfig();
  const anchor: SemesterAnchor | null = parseSemesterAnchorFromLabel(config.semesterLabel);
  if (config.baseSemesterId > 0 && anchor !== null) {
    const injected: BaseSemesterMapping = {
      baseSemesterId: config.baseSemesterId,
      baseStartYear: anchor.startYear,
      baseTermNumber: anchor.termNumber
    };
    return injected;
  }
  return {
    baseSemesterId: FALLBACK_BASE_SEMESTER_ID,
    baseStartYear: FALLBACK_BASE_ACADEMIC_START_YEAR,
    baseTermNumber: FALLBACK_BASE_TERM_NUMBER
  };
}

const EXAM_TYPE_LABELS: string[] = ['期末考试', '期中考试', '缓补考试'];

export const EXAM_TYPE_OPTIONS: SelectOption[] = [
  { value: EXAM_TYPE_LABELS[0] },
  { value: EXAM_TYPE_LABELS[1] },
  { value: EXAM_TYPE_LABELS[2] },
];

export interface SemesterOptionSet {
  options: SelectOption[];
  semesterIds: number[];
}

interface AcademicSemester {
  startYear: number;
  termNumber: number;
}

function toSemesterIndex(semester: AcademicSemester): number {
  return semester.startYear * 2 + (semester.termNumber - 1);
}

function fromSemesterIndex(index: number): AcademicSemester {
  return {
    startYear: Math.floor(index / 2),
    termNumber: index % 2 === 0 ? 1 : 2,
  };
}

function toSemesterLabel(semester: AcademicSemester): string {
  const endYear: number = semester.startYear + 1;
  const termLabel: string = semester.termNumber === 1 ? '第一学期' : '第二学期';
  return `${semester.startYear}-${endYear}学年${termLabel}`;
}

function getCurrentAcademicSemester(date: Date): AcademicSemester {
  const month: number = date.getMonth() + 1;
  const year: number = date.getFullYear();

  if (month >= 2 && month <= 7) {
    return {
      startYear: year - 1,
      termNumber: 2,
    };
  }

  if (month >= 8) {
    return {
      startYear: year,
      termNumber: 1,
    };
  }

  return {
    startYear: year - 1,
    termNumber: 1,
  };
}

function getSemesterIdByYearTerm(startYear: number, termNumber: number): number {
  const targetIndex: number = toSemesterIndex({ startYear, termNumber });
  const base: BaseSemesterMapping = resolveBaseSemesterMapping();
  const baseIndex: number = toSemesterIndex({
    startYear: base.baseStartYear,
    termNumber: base.baseTermNumber,
  });
  return base.baseSemesterId + (targetIndex - baseIndex) * SEMESTER_ID_STEP;
}

export function normalizeExamTypeId(value: string | number | undefined): number {
  const parsed: number = typeof value === 'number' ? value : Number.parseInt(value || '', 10);
  if (parsed === 2 || parsed === 3) {
    return parsed;
  }
  return 1;
}

export function getExamTypeIdByIndex(index: number): number {
  if (index === 1) {
    return 2;
  }
  if (index === 2) {
    return 3;
  }
  return 1;
}

export function getExamTypeIndexById(examTypeId: number): number {
  if (examTypeId === 2) {
    return 1;
  }
  if (examTypeId === 3) {
    return 2;
  }
  return 0;
}

export function getExamTypeLabelById(examTypeId: number): string {
  return EXAM_TYPE_LABELS[getExamTypeIndexById(examTypeId)];
}

export function detectExamTypeIdFromText(examTypeText: string): number | undefined {
  const text: string = examTypeText || '';
  if (text.includes('期末')) {
    return 1;
  }
  if (text.includes('期中')) {
    return 2;
  }
  if (text.includes('缓补')) {
    return 3;
  }
  return undefined;
}

export function calculateSemesterId(date: Date = new Date()): number {
  const targetSemester: AcademicSemester = getCurrentAcademicSemester(date);
  const targetIndex: number = toSemesterIndex(targetSemester);
  const base: BaseSemesterMapping = resolveBaseSemesterMapping();
  const baseIndex: number = toSemesterIndex({
    startYear: base.baseStartYear,
    termNumber: base.baseTermNumber,
  });
  return base.baseSemesterId + (targetIndex - baseIndex) * SEMESTER_ID_STEP;
}

export function normalizeSemesterId(value: string | number | undefined, fallbackDate: Date = new Date()): number {
  const parsed: number = typeof value === 'number' ? value : Number.parseInt(value || '', 10);
  if (Number.isFinite(parsed) && parsed > 0) {
    return parsed;
  }
  return calculateSemesterId(fallbackDate);
}

export function getSemesterLabelById(semesterId: number): string {
  const base: BaseSemesterMapping = resolveBaseSemesterMapping();
  const baseIndex: number = toSemesterIndex({
    startYear: base.baseStartYear,
    termNumber: base.baseTermNumber,
  });
  const diffStep: number = Math.round((semesterId - base.baseSemesterId) / SEMESTER_ID_STEP);
  const targetSemester: AcademicSemester = fromSemesterIndex(baseIndex + diffStep);
  return toSemesterLabel(targetSemester);
}

export function getPreviousSemesterId(date: Date = new Date()): number {
  return calculateSemesterId(date) - SEMESTER_ID_STEP;
}

export function buildExamTableUrl(semesterId: number, examTypeId: number): string {
  const normalizedExamType: number = normalizeExamTypeId(examTypeId);
  return `${EAMS_EXAM_TABLE_BASE_URL}?semester.id=${semesterId}&examType.id=${normalizedExamType}`;
}

export interface GradeSemesterOptionItem {
  semesterId: number;
  label: string;
}

export function getGradeSemesterOptions(baseDate: Date = new Date()): GradeSemesterOptionItem[] {
  const options: GradeSemesterOptionItem[] = [{ semesterId: 0, label: '所有学期' }];
  const currentSemester: AcademicSemester = getCurrentAcademicSemester(baseDate);
  const currentIndex: number = toSemesterIndex(currentSemester);
  const endIndex: number = currentIndex + 2;
  const startIndex: number = currentIndex - 10;

  for (let index = endIndex; index >= startIndex; index--) {
    const semester: AcademicSemester = fromSemesterIndex(index);
    const endYear: number = semester.startYear + 1;
    const label: string = `${semester.startYear}-${endYear}-${semester.termNumber}`;
    const id: number = getSemesterIdByYearTerm(semester.startYear, semester.termNumber);
    options.push({ semesterId: id, label });
  }

  return options;
}

export function getSemesterOptions(): SemesterOptionSet {
  const options: SelectOption[] = [{ value: '全部学期' }];
  const semesterIds: number[] = [0];

  const currentSemester: AcademicSemester = getCurrentAcademicSemester(new Date());
  const currentIndex: number = toSemesterIndex(currentSemester);
  const endIndex: number = currentIndex + 2;
  const startIndex: number = currentIndex - 10;

  for (let index = endIndex; index >= startIndex; index--) {
    const semester: AcademicSemester = fromSemesterIndex(index);
    const endYear: number = semester.startYear + 1;
    const label: string = `${semester.startYear}-${endYear}-${semester.termNumber}`;
    const id: number = getSemesterIdByYearTerm(semester.startYear, semester.termNumber);
    options.push({ value: label });
    semesterIds.push(id);
  }

  return { options, semesterIds };
}

export function parseSemesterIdFromAcademicYear(academicYearText: string): number | undefined {
  if (!academicYearText) {
    return undefined;
  }
  const clean: string = academicYearText.replace(/\s+/g, '');
  // Match "2024-2025-1", "2024-2025-2", "2024-2025_1", "2024-2025-1学期"
  const matchNum: RegExpMatchArray | null = clean.match(/(\d{4})[-_~](\d{4})[-_~]?([12])/);
  if (matchNum) {
    const startYear: number = Number.parseInt(matchNum[1], 10);
    const termNumber: number = Number.parseInt(matchNum[3], 10);
    if (Number.isFinite(startYear) && (termNumber === 1 || termNumber === 2)) {
      return getSemesterIdByYearTerm(startYear, termNumber);
    }
  }
  // Match "2024-2025学年第一学期", "2024-2025学年第二学期"
  const matchCn: RegExpMatchArray | null = clean.match(/(\d{4})[-_~](\d{4})[^\d]*([一二12])/);
  if (matchCn) {
    const startYear: number = Number.parseInt(matchCn[1], 10);
    const termStr: string = matchCn[3];
    const termNumber: number = (termStr === '一' || termStr === '1') ? 1 : 2;
    if (Number.isFinite(startYear)) {
      return getSemesterIdByYearTerm(startYear, termNumber);
    }
  }
  return undefined;
}

