export interface BusItem {
  id: string;
  time: string;
  departure: 'qsh' | 'sh';
  destination: 'sh' | 'qsh';
  departureName: string;
  destinationName: string;
  routeDescription: string;
  busType: string;
  isWeekend: boolean;
}

export interface NextBusInfo {
  time: string;
  minutesLeft: number;
  isTomorrow: boolean;
  busItem: BusItem;
}

/** 后端 knowledge/bus-schedule 端点的解析结果 */
export interface BusSchedulePayload {
  items: BusItem[];
  /** 数据生成时间（透传展示用） */
  generatedAt: string;
}

interface RawBusSchedulePayload {
  ok?: boolean;
  count?: number;
  generatedAt?: string;
  data?: RawBusItemPayload[];
}

interface RawBusItemPayload {
  id?: string;
  time?: string;
  departure?: string;
  destination?: string;
  departureName?: string;
  destinationName?: string;
  routeDescription?: string;
  busType?: string;
  isWeekend?: boolean;
}

/** 校区代码 → 展示名（与既有文案保持一致） */
function campusName(code: string): string {
  if (code === 'qsh') {
    return '清水河校区';
  }
  return '沙河校区';
}

/** 校验 HH:MM 格式且时分合法 */
function isValidBusTime(text: string): boolean {
  if (!/^\d{2}:\d{2}$/.test(text)) {
    return false;
  }
  const hour: number = Number.parseInt(text.substring(0, 2), 10);
  const minute: number = Number.parseInt(text.substring(3, 5), 10);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

/**
 * 解析后端 bus-schedule JSON 文本为 BusItem 列表。
 * 单条数据非法时跳过该条（不整包拒绝）；文本为空、结构缺失或解析异常时
 * 返回 null（items 为空数组的合法载荷原样返回），由调用方回退内置兜底表。
 * departure/destination 必须为 'qsh'|'sh' 且互异。
 */
export function parseBusSchedulePayload(text: string): BusSchedulePayload | null {
  const items: BusItem[] = [];
  if (!text) {
    return null;
  }
  try {
    const payload = JSON.parse(text) as RawBusSchedulePayload;
    const rawList = payload.data;
    if (!rawList || !Array.isArray(rawList)) {
      return null;
    }
    for (let i = 0; i < rawList.length; i++) {
      const raw = rawList[i] as RawBusItemPayload;
      const time: string = typeof raw.time === 'string' ? raw.time : '';
      const departure: string = typeof raw.departure === 'string' ? raw.departure : '';
      const destination: string = typeof raw.destination === 'string' ? raw.destination : '';
      if (!isValidBusTime(time)) {
        continue;
      }
      if ((departure !== 'qsh' && departure !== 'sh') || (destination !== 'qsh' && destination !== 'sh')) {
        continue;
      }
      if (departure === destination) {
        continue;
      }
      const departureName: string =
        (typeof raw.departureName === 'string' && raw.departureName.length > 0)
          ? raw.departureName : campusName(departure);
      const destinationName: string =
        (typeof raw.destinationName === 'string' && raw.destinationName.length > 0)
          ? raw.destinationName : campusName(destination);
      const routeDescription: string =
        (typeof raw.routeDescription === 'string' && raw.routeDescription.length > 0)
          ? raw.routeDescription : `${departureName} ➔ ${destinationName}`;
      const busType: string =
        (typeof raw.busType === 'string' && raw.busType.length > 0) ? raw.busType : '普通班车';
      const isWeekend: boolean = raw.isWeekend === true;
      const id: string =
        (typeof raw.id === 'string' && raw.id.length > 0)
          ? raw.id
          : `bus_${departure}_${destination}_${isWeekend ? 'weekend' : 'workday'}_${i}_${time.replace(':', '')}`;
      const item: BusItem = {
        id: id,
        time: time,
        // 此处已校验取值，收窄为接口的字面量联合类型
        departure: departure as 'qsh' | 'sh',
        destination: destination as 'qsh' | 'sh',
        departureName: departureName,
        destinationName: destinationName,
        routeDescription: routeDescription,
        busType: busType,
        isWeekend: isWeekend
      };
      items.push(item);
    }
    const result: BusSchedulePayload = {
      items: items,
      generatedAt: typeof payload.generatedAt === 'string' ? payload.generatedAt : ''
    };
    return result;
  } catch (e) {
    return null;
  }
}

/**
 * 纯 TS 成电两校区往返班车时刻表与运算模型
 *
 * 内置时刻表自 T6a 起降级为「离线兜底快照」：正常数据由后端
 * knowledge/bus-schedule 下发（service/BusDataService 消费），仅在
 * 首次安装离线 / 远端不可用时启用。快照日期：2026-08 前的公开时刻表，
 * 随应用版本固化，不再随学期更新。
 */
export class BusScheduleModel {
  // 清水河 ➔ 沙河（工作日）
  static readonly QSH_TO_SH_WORKDAY: string[] = [
    '06:40', '07:10', '07:30', '08:30', '09:30', '10:30', '11:30',
    '12:30', '13:00', '14:00', '15:00', '16:00', '17:00', '17:40',
    '18:40', '20:00', '21:30', '22:30'
  ];

  // 沙河 ➔ 清水河（工作日）
  static readonly SH_TO_QSH_WORKDAY: string[] = [
    '07:00', '07:30', '08:30', '09:30', '10:30', '11:30', '12:30',
    '13:30', '14:30', '15:30', '16:30', '17:00', '17:40', '18:30',
    '20:00', '21:30', '22:30'
  ];

  // 清水河 ➔ 沙河（周末及法定节假日）
  static readonly QSH_TO_SH_WEEKEND: string[] = [
    '07:30', '09:00', '10:30', '12:30', '14:00', '16:00', '18:00',
    '20:00', '21:30', '22:30'
  ];

  // 沙河 ➔ 清水河（周末及法定节假日）
  static readonly SH_TO_QSH_WEEKEND: string[] = [
    '07:30', '09:00', '10:30', '12:30', '14:00', '16:00', '18:00',
    '20:00', '21:30', '22:30'
  ];

  /**
   * 判断指定日期是否为周末
   */
  static isWeekendDay(date: Date = new Date()): boolean {
    const day = date.getDay();
    return day === 0 || day === 6;
  }

  /**
   * 获取时刻表列表
   */
  static getBusList(departure: 'qsh' | 'sh', isWeekend: boolean): BusItem[] {
    let times: string[] = [];
    const destination: 'sh' | 'qsh' = departure === 'qsh' ? 'sh' : 'qsh';
    const departureName = departure === 'qsh' ? '清水河校区' : '沙河校区';
    const destinationName = destination === 'qsh' ? '清水河校区' : '沙河校区';

    if (departure === 'qsh') {
      times = isWeekend ? BusScheduleModel.QSH_TO_SH_WEEKEND : BusScheduleModel.QSH_TO_SH_WORKDAY;
    } else {
      times = isWeekend ? BusScheduleModel.SH_TO_QSH_WEEKEND : BusScheduleModel.SH_TO_QSH_WORKDAY;
    }

    return times.map((time: string, idx: number): BusItem => {
      return {
        id: `bus_${departure}_${isWeekend ? 'weekend' : 'workday'}_${idx}_${time.replace(':', '')}`,
        time: time,
        departure: departure,
        destination: destination,
        departureName: departureName,
        destinationName: destinationName,
        routeDescription: `${departureName}主楼 ➔ ${destinationName}主楼`,
        busType: (time === '07:10' || time === '07:30' || time === '17:00' || time === '17:40') ? '高峰直达' : '普通班车',
        isWeekend: isWeekend
      };
    });
  }

  /**
   * 计算下一班车及倒计时分钟数（内置兜底表版本，保持原签名兼容）
   */
  static getNextBus(departure: 'qsh' | 'sh', isWeekend: boolean, now: Date = new Date()): NextBusInfo | null {
    const tomorrowIsWeekend = BusScheduleModel.isWeekendDay(new Date(now.getTime() + 24 * 60 * 60 * 1000));
    return BusScheduleModel.getNextBusInfo(
      BusScheduleModel.getBusList(departure, isWeekend),
      BusScheduleModel.getBusList(departure, tomorrowIsWeekend),
      now
    );
  }

  /**
   * 基于给定班次列表计算下一班车及倒计时分钟数。
   * todayList/tomorrowList 由调用方注入（远端缓存或内置兜底），本方法只做纯运算。
   */
  static getNextBusInfo(
    todayList: BusItem[],
    tomorrowList: BusItem[],
    now: Date = new Date()
  ): NextBusInfo | null {
    if (todayList.length === 0) {
      return null;
    }

    const currentMinutes = now.getHours() * 60 + now.getMinutes();

    for (let i = 0; i < todayList.length; i++) {
      const item = todayList[i];
      const parts = item.time.split(':').map(Number);
      const busMinutes = (parts[0] || 0) * 60 + (parts[1] || 0);

      if (busMinutes >= currentMinutes) {
        return {
          time: item.time,
          minutesLeft: busMinutes - currentMinutes,
          isTomorrow: false,
          busItem: item
        };
      }
    }

    // 今日已无班车，返回明日第一班
    if (tomorrowList.length > 0) {
      const firstBus = tomorrowList[0];
      const parts = firstBus.time.split(':').map(Number);
      const busMinutes = (parts[0] || 0) * 60 + (parts[1] || 0);
      const minutesLeft = (24 * 60 - currentMinutes) + busMinutes;
      return {
        time: firstBus.time,
        minutesLeft: minutesLeft,
        isTomorrow: true,
        busItem: firstBus
      };
    }

    return null;
  }
}
