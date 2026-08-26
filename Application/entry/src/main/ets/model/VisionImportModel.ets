// 截图导入预览数据模型（P2-9）：
// GLM-4V 解析结果与入库之间的可编辑中间层。纯数据定义，不含任何 UI 代码；
// 字段值已按原导入逻辑做过兜底处理，预览中展示的即"确认后将入库"的内容。
// 置信度为整条级别（VisionCourseItem.confidence / VisionGradeItem.confidence），非字段级。

import {
  VisionCourseTableResult,
  VisionCourseItem,
  VisionGradeReportResult,
  VisionGradeItem
} from '../common/agent/VisionScheduleHelper';

/** 低置信度阈值：条目置信度低于该值时在预览中琥珀色高亮提醒 */
export const VISION_LOW_CONFIDENCE_THRESHOLD: number = 0.85;

/** confidence 缺失时的哨兵值，表示无法评估置信度（不高亮） */
export const CONFIDENCE_UNKNOWN: number = -1;

/** 判断一条解析结果的置信度是否需要低置信度高亮 */
export function isLowConfidenceScore(confidence: number): boolean {
  return confidence >= 0 && confidence < VISION_LOW_CONFIDENCE_THRESHOLD;
}

/** 课表预览条目：文本字段均可直接绑定 TextInput 编辑 */
export class VisionCoursePreviewItem {
  name: string = '';
  teacher: string = '';
  room: string = '';
  dayOfWeekText: string = '1';
  startSectionText: string = '1';
  durationText: string = '2';
  weeksText: string = '1-16';
  confidence: number = CONFIDENCE_UNKNOWN;
  selected: boolean = true;
}

/** 成绩单预览条目：courseCode/courseCategory 仅透传，不参与编辑 */
export class VisionGradePreviewItem {
  courseName: string = '';
  score: string = '';
  creditText: string = '0';
  gradePointText: string = '0';
  semester: string = '';
  courseCode: string = '';
  courseCategory: string = '';
  confidence: number = CONFIDENCE_UNKNOWN;
  selected: boolean = true;
}

/**
 * 把用户编辑后的数字文本收敛到合法区间：
 * 空串或非法数字回退到 fallback（与原导入逻辑的兜底语义一致）。
 */
export function parseClampedNumber(text: string, min: number, max: number, fallback: number): number {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return fallback;
  }
  const value: number = Number(trimmed);
  if (Number.isNaN(value)) {
    return fallback;
  }
  if (value < min || value > max) {
    return fallback;
  }
  return value;
}

function clampOrFallback(value: number, min: number, max: number, fallback: number): number {
  if (!Number.isFinite(value)) {
    return fallback;
  }
  if (value < min || value > max) {
    return fallback;
  }
  return value;
}

/** 把课表解析结果转换为可编辑预览条目（数值字段先按原导入规则收敛到合法区间） */
export function createCoursePreviewItems(result: VisionCourseTableResult): VisionCoursePreviewItem[] {
  const items: VisionCoursePreviewItem[] = [];
  const courses: VisionCourseItem[] = result.courses;
  for (let i = 0; i < courses.length; i++) {
    const vc: VisionCourseItem = courses[i];
    const item: VisionCoursePreviewItem = new VisionCoursePreviewItem();
    item.name = vc.name || '未命名课程';
    item.teacher = vc.teacher || '';
    item.room = vc.room || '';
    item.dayOfWeekText = `${clampOrFallback(vc.dayOfWeek, 1, 7, 1)}`;
    item.startSectionText = `${clampOrFallback(vc.startSection, 1, 12, 1)}`;
    item.durationText = `${clampOrFallback(vc.duration, 1, 5, 2)}`;
    item.weeksText = vc.validWeeks || '1-16';
    item.confidence = typeof vc.confidence === 'number' ? vc.confidence : CONFIDENCE_UNKNOWN;
    items.push(item);
  }
  return items;
}

/** 把成绩单解析结果转换为可编辑预览条目（学分/绩点按原导入规则做 Number 兜底） */
export function createGradePreviewItems(result: VisionGradeReportResult): VisionGradePreviewItem[] {
  const items: VisionGradePreviewItem[] = [];
  const grades: VisionGradeItem[] = result.grades;
  for (let i = 0; i < grades.length; i++) {
    const vg: VisionGradeItem = grades[i];
    const item: VisionGradePreviewItem = new VisionGradePreviewItem();
    item.courseName = vg.courseName || '未知课程';
    item.score = vg.score ? String(vg.score) : '';
    item.creditText = `${Number(vg.credit) || 0}`;
    item.gradePointText = `${Number(vg.gradePoint) || 0}`;
    item.semester = vg.semester || '';
    item.courseCode = vg.courseCode || '';
    item.courseCategory = vg.courseCategory || '';
    item.confidence = typeof vg.confidence === 'number' ? vg.confidence : CONFIDENCE_UNKNOWN;
    items.push(item);
  }
  return items;
}
