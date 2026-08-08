import { AnnounceItem, TodoItem, MessageInfo, MsgType, ServiceItem, StatData, TabItem } from '../common/types/ModelTypes';
import { StringUtils } from '../common/utils/StringUtils';

export class HomeModel {
  static getTabList(): TabItem[] {
    return [
      { name: '首页', index: 0, icon: $r('app.media.home') },
      { name: '服务', index: 1, icon: $r('app.media.service') },
      { name: '消息', index: 2, icon: $r('app.media.message') },
      { name: '我的', index: 3, icon: $r('app.media.mine') }
    ];
  }

  static getAnnounceList(): AnnounceItem[] {
    return [
      {
        id: StringUtils.generateId(),
        title: '【通知】2026春季学期作息时间调整',
        bgColor: $r('app.color.primary_color')
      },
      {
        id: StringUtils.generateId(),
        title: '【活动】校园社团文化节正式报名',
        bgColor: $r('app.color.info_color')
      },
      {
        id: StringUtils.generateId(),
        title: '【重要】图书馆暑期开放安排',
        bgColor: $r('app.color.purple_color')
      }
    ];
  }

  static getTodoList(): TodoItem[] {
    return [
      {
        id: StringUtils.generateId(),
        title: '高数作业提交',
        desc: '今日 23:59 截止',
        tag: '紧急',
        tagColor: $r('app.color.danger_color'),
        priority: 1
      },
      {
        id: StringUtils.generateId(),
        title: '英语单词打卡',
        desc: '连续打卡第5天',
        tag: '日常',
        tagColor: $r('app.color.primary_color'),
        priority: 2
      },
      {
        id: StringUtils.generateId(),
        title: '查看本周课表',
        desc: '已同步最新课程',
        tag: '已完成',
        tagColor: $r('app.color.success_color'),
        priority: 3
      },
      {
        id: StringUtils.generateId(),
        title: '计算机基础考试',
        desc: '05-20 下午14:00',
        tag: '考试',
        tagColor: $r('app.color.warning_color'),
        priority: 1
      }
    ];
  }

  static getMessageList(): MessageInfo[] {
    return [
      {
        id: 1,
        type: MsgType.Private,
        sender: '流萤',
        content: '今晚上你床',
        time: '5:20',
        isUnRead: true,
        avatarBg: $r('app.color.avatar_bg_1')
      },
      {
        id: 2,
        type: MsgType.System,
        sender: '系统推送',
        content: '流萤今晚上你床',
        time: '13:14',
        isUnRead: false,
        avatarBg: $r('app.color.avatar_bg_2')
      },
      {
        id: 3,
        type: MsgType.Notice,
        sender: '校园通知',
        content: '警惕二次元陷阱：有人冒充二次元角色施行诈骗',
        time: '11:45',
        isUnRead: false,
        avatarBg: $r('app.color.avatar_bg_3')
      }
    ];
  }

  static getServiceList(): ServiceItem[] {
    return [
      {
        id: StringUtils.generateId(),
        name: '课表查看',
        icon: '📅',
        color: $r('app.color.primary_color'),
        desc: '查看本周课程',
        route: 'pages/CoursePage'
      },
      {
        id: StringUtils.generateId(),
        name: '考试信息',
        icon: '📝',
        color: $r('app.color.warning_color'),
        desc: '考试安排查询',
        route: 'pages/ExamPage'
      },
      {
        id: StringUtils.generateId(),
        name: '成绩查询',
        icon: '📊',
        color: $r('app.color.success_color'),
        desc: '学期成绩查看',
        route: 'pages/GradePage'
      },
      {
        id: StringUtils.generateId(),
        name: '图书馆',
        icon: '📚',
        color: $r('app.color.info_color'),
        desc: '图书借阅服务',
        route: 'pages/LibraryPage'
      },
      {
        id: StringUtils.generateId(),
        name: '校园卡',
        icon: '💳',
        color: $r('app.color.purple_color'),
        desc: '一卡通服务',
        route: 'pages/CardPage'
      },
      {
        id: StringUtils.generateId(),
        name: '宿舍管理',
        icon: '🏠',
        color: $r('app.color.danger_color'),
        desc: '宿舍报修服务',
        route: 'pages/DormitoryPage'
      }
    ];
  }

  static getStatData(): StatData[] {
    return [
      { label: '今日待办', value: '4', color: $r('app.color.warning_color') },
      { label: '未读消息', value: '3', color: $r('app.color.danger_color') },
      { label: '本周课程', value: '12', color: $r('app.color.success_color') }
    ];
  }
}
