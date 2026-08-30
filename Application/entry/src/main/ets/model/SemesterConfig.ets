/**
 * 学期参数纯数据模型（T5a 学期参数云端化）
 *
 * 职责边界：只做数据结构与换算逻辑，禁止任何 @kit 导入（model 层铁律）。
 * 网络拉取与持久化在 repository/AppConfigRepository 完成，本文件不感知存储与网络。
 *
 * 兜底约定（常量即最终兜底，勿随意改动数值）：
 * - 行课首日锚点 2026-08-31（周一）：2026-2027 学年第一学期行课首日为 2026-09-01（周二），
 *   周次按周一~周日对齐 validWeeks，故锚定到所在周的周一；
 * - 教务学期 ID 锚点 503 ↔ 2025-2026-2（ID 步进 20，见 ExamAccessRules）。
 *
 * 教务学期 id 锚点客观事实（教务系统实测，id 步进 20）：
 * 483 ↔ 2025-2026-1、503 ↔ 2025-2026-2、523 ↔ 2026-2027-1。
 * id 与标签必须成对正确，否则全部学期换算整体偏移（本文件解析闸门会拦截错配配置）。
 * 与 common/constants/AppConstants.SCHOOL_SEMESTER_START 保持同一兜底口径。
 */

/**
 * 教务学期 id 空间的历史锚点（客观事实，非业务可配置项）：
 * 2025-2026-1 ↔ 483，相邻学期步进 20（如 2025-2026-2 ↔ 503、2026-2027-1 ↔ 523）。
 * 用于对云端下发的 (baseSemesterId, semesterLabel) 做语义一致性校验。
 */
const HISTORICAL_SEMESTER_ANCHOR_ID = 483;
const HISTORICAL_SEMESTER_ANCHOR_START_YEAR = 2025;
const HISTORICAL_SEMESTER_ANCHOR_TERM_NUMBER = 1;
const SEMESTER_ID_STEP_FOR_ANCHOR = 20;

/**
 * 学期索引换算：与 ExamAccessRules 同公式（startYear*2 + (termNumber-1)）。
 * 在本文件内私有实现，避免 model 间循环依赖（ExamAccessRules 在 repository 层依赖本文件）。
 */
function toSemesterIndexLocal(startYear: number, termNumber: number): number {
  return startYear * 2 + (termNumber - 1);
}

/** 学期配置数据结构（云端 app-config 的本地 last-good 形态） */
export interface SemesterConfigData {
  /** 行课首日，格式 YYYY-MM-DD；可为该周任意一天，周次计算会归一到所在周的周一 */
  semesterStartDate: string;
  /** 当前学期对应的教务系统 semester.id */
  baseSemesterId: number;
  /** 学期标签，如 2026-2027-1；用于反推 baseSemesterId 所属学年/学期锚点 */
  semesterLabel: string;
  /** 数据生成/拉取时间（透传展示用，不参与计算） */
  fetchedAt: string;
}

/** 学年期锚点：某学期标签解析出的学年起始年与学期序号 */
export interface SemesterAnchor {
  startYear: number;
  termNumber: number;
}

/**
 * 最终兜底配置：数值与历史硬编码行为完全一致（云端不可用时整体启用）。
 * 兜底配对 (503, '2025-2026-2') 语义正确，勿改动数值。
 * 教务 id 锚点客观事实：483↔2025-2026-1、503↔2025-2026-2、523↔2026-2027-1（步进 20）。
 */
export const FALLBACK_SEMESTER_CONFIG: SemesterConfigData = {
  semesterStartDate: '2026-08-31',
  baseSemesterId: 503,
  semesterLabel: '2025-2026-2',
  fetchedAt: ''
};

/** 校验 YYYY-MM-DD 格式（含真实日历校验，拦截 02-30 之类非法日期） */
export function isValidIsoDate(text: string): boolean {
  return parseIsoDateToMidnight(text) !== null;
}

/** 解析 YYYY-MM-DD 为本地零点 Date；格式或日期非法时返回 null */
export function parseIsoDateToMidnight(text: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    return null;
  }
  const year: number = Number.parseInt(text.substring(0, 4), 10);
  const month: number = Number.parseInt(text.substring(5, 7), 10);
  const day: number = Number.parseInt(text.substring(8, 10), 10);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  const d = new Date(year, month - 1, day);
  if (d.getFullYear() !== year || d.getMonth() !== month - 1 || d.getDate() !== day) {
    return null;
  }
  d.setHours(0, 0, 0, 0);
  return d;
}

/**
 * 由行课首日文本解析出「所在教学周的周一」零点锚点。
 * 行课首日允许是一周内任意一天（如周二行课），统一回退到本周一，
 * 保证周次与 validWeeks 的周一~周日对齐口径不变。
 */
export function resolveTermMondayAnchor(startDateText: string): Date | null {
  const parsed: Date | null = parseIsoDateToMidnight(startDateText);
  if (parsed === null) {
    return null;
  }
  const dayOfWeek: number = parsed.getDay(); // 0=周日
  const offsetDays: number = (dayOfWeek + 6) % 7; // 回退到本周周一
  parsed.setDate(parsed.getDate() - offsetDays);
  return parsed;
}

/** 周次换算：与历史实现公式一致（锚点前返回第 1 周，此后每 7 天一周） */
export function weekNumberFor(date: Date, termMonday: Date): number {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);

  const diffMs: number = d.getTime() - termMonday.getTime();
  if (diffMs < 0) {
    return 1;
  }
  const week: number = Math.floor(diffMs / (7 * 24 * 60 * 60 * 1000)) + 1;
  return Math.max(1, week);
}

/** 指定教学周的周一零点毫秒数（targetWeek 最小按 1 处理） */
export function getMondayMsForWeek(termMonday: Date, targetWeek: number): number {
  return termMonday.getTime() + (Math.max(1, targetWeek) - 1) * 7 * 24 * 60 * 60 * 1000;
}

/**
 * 从学期标签（如 2026-2027-1）解析学年期锚点；
 * 标签为空或格式不符时返回 null，调用方应整体回退内置锚点（id 与锚点必须成对生效）。
 */
export function parseSemesterAnchorFromLabel(label: string): SemesterAnchor | null {
  if (!label) {
    return null;
  }
  const match: RegExpMatchArray | null = label.match(/(\d{4})-(\d{4})-(\d)/);
  if (!match) {
    return null;
  }
  const startYear: number = Number.parseInt(match[1], 10);
  const termNumber: number = Number.parseInt(match[3], 10);
  if (!Number.isFinite(startYear) || startYear < 2000 || startYear > 2999) {
    return null;
  }
  if (termNumber !== 1 && termNumber !== 2) {
    return null;
  }
  const anchor: SemesterAnchor = { startYear: startYear, termNumber: termNumber };
  return anchor;
}

interface SemesterConfigPayload {
  semesterStartDate?: string;
  baseSemesterId?: number;
  semesterLabel?: string;
  generatedAt?: string;
}

/**
 * 解析并校验云端 app-config JSON 文本为 SemesterConfigData。
 * 采用「全有或全无」策略：行课首日或学期 ID 任一字段非法即整包拒绝（返回 null），
 * 避免 id 与标签锚点混用两代数据导致换算错位。解析失败同样返回 null。
 * 格式校验通过后追加语义一致性校验：当学期标签非空且可解析时，按固定历史锚点
 * （483 ↔ 2025-2026-1，步进 20）重算标签期望 id，与 baseSemesterId 不一致即整包拒绝。
 * 标签为空时跳过该校验（保持向后兼容）。
 */
export function parseSemesterConfigJson(text: string): SemesterConfigData | null {
  if (!text) {
    return null;
  }
  try {
    const payload = JSON.parse(text) as SemesterConfigPayload;
    const startDate: string = typeof payload.semesterStartDate === 'string' ? payload.semesterStartDate : '';
    const baseId: number = typeof payload.baseSemesterId === 'number' ? payload.baseSemesterId : 0;
    if (!isValidIsoDate(startDate)) {
      return null;
    }
    if (!Number.isInteger(baseId) || baseId <= 0) {
      return null;
    }
    const label: string = typeof payload.semesterLabel === 'string' ? payload.semesterLabel : '';
    // 语义一致性闸门：拦截 (id, 标签) 错配配置（如坏配对 503 ↔ '2026-2027-1'）
    if (label) {
      const anchor: SemesterAnchor | null = parseSemesterAnchorFromLabel(label);
      if (anchor !== null) {
        const expectedId: number = HISTORICAL_SEMESTER_ANCHOR_ID +
          (toSemesterIndexLocal(anchor.startYear, anchor.termNumber) -
            toSemesterIndexLocal(HISTORICAL_SEMESTER_ANCHOR_START_YEAR, HISTORICAL_SEMESTER_ANCHOR_TERM_NUMBER)) *
          SEMESTER_ID_STEP_FOR_ANCHOR;
        if (baseId !== expectedId) {
          return null;
        }
      }
    }
    const fetchedAt: string = typeof payload.generatedAt === 'string' ? payload.generatedAt : '';
    const config: SemesterConfigData = {
      semesterStartDate: startDate,
      baseSemesterId: baseId,
      semesterLabel: label,
      fetchedAt: fetchedAt
    };
    return config;
  } catch (e) {
    return null;
  }
}
