export interface TabItem {
  name: string;
  index: number;
  icon: Resource;
}

export interface AnnounceItem {
  title: string;
  bgColor: ResourceColor;
  id?: string;
}

export interface TodoItem {
  title: string;
  desc: string;
  tag: string;
  tagColor: ResourceColor;
  id?: string;
  deadline?: string;
  priority?: number;
}

export enum MsgType {
  All = 0,
  System = 1,
  Notice = 2,
  Private = 3
}

export interface MessageInfo {
  id: number;
  type: MsgType;
  sender: string;
  content: string;
  time: string;
  isUnRead: boolean;
  avatarBg: ResourceColor;
}

export interface ServiceItem {
  name: string;
  icon: string;
  color: ResourceColor;
  desc: string;
  id?: string;
  route?: string;
}

export interface UserInfo {
  userId: string;
  userName: string;
  avatar?: string;
  school?: string;
  studentId?: string;
}

export interface StatData {
  label: string;
  value: string | number;
  color: ResourceColor;
}

export enum LoadingState {
  Initial = 0,
  Loading = 1,
  Success = 2,
  Error = 3,
  Empty = 4
}

export interface Result<T> {
  success: boolean;
  data?: T;
  message?: string;
  code?: number;
}
