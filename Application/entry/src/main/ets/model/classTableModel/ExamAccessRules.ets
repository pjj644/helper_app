import { AppConstants } from '../../common/constants/AppConstants';

export const EAMS_EXAM_MENU_URL: string = AppConstants.EAMS_EXAM_MENU_URL;
export const EAMS_EXAM_TABLE_BASE_URL: string = AppConstants.EAMS_EXAM_TABLE_BASE_URL;

const BASE_SEMESTER_ID: number = 503;
const BASE_ACADEMIC_START_YEAR: number = 2025;
const BASE_TERM_NUMBER: number = 2;
const SEMESTER_ID_STEP: number = 20;

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
  const baseIndex: number = toSemesterIndex({
    startYear: BASE_ACADEMIC_START_YEAR,
    termNumber: BASE_TERM_NUMBER,
  });
  return BASE_SEMESTER_ID + (targetIndex - baseIndex) * SEMESTER_ID_STEP;
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
  const baseIndex: number = toSemesterIndex({
    startYear: BASE_ACADEMIC_START_YEAR,
    termNumber: BASE_TERM_NUMBER,
  });
  return BASE_SEMESTER_ID + (targetIndex - baseIndex) * SEMESTER_ID_STEP;
}

export function normalizeSemesterId(value: string | number | undefined, fallbackDate: Date = new Date()): number {
  const parsed: number = typeof value === 'number' ? value : Number.parseInt(value || '', 10);
  if (Number.isFinite(parsed) && parsed > 0) {
    return parsed;
  }
  return calculateSemesterId(fallbackDate);
}

export function getSemesterLabelById(semesterId: number): string {
  const baseIndex: number = toSemesterIndex({
    startYear: BASE_ACADEMIC_START_YEAR,
    termNumber: BASE_TERM_NUMBER,
  });
  const diffStep: number = Math.round((semesterId - BASE_SEMESTER_ID) / SEMESTER_ID_STEP);
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

