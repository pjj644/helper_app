/**
 * 首页统计卡片数据模型。
 *
 * 历史上本文件还承载旧版首页的公告/待办/消息/服务网格等类型定义，
 * 随旧版首页死代码（HomeModel/HomeViewModel 及相关组件）清理后，
 * 仅保留仍在使用的 StatData（components/QuickStatComponent 消费）。
 */
export interface StatData {
  label: string;
  value: string | number;
  color: ResourceColor;
}
