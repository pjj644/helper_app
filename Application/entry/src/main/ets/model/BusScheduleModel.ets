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

/**
 * 纯 TS 成电两校区往返班车时刻表与运算模型
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
   * 计算下一班车及倒计时分钟数
   */
  static getNextBus(departure: 'qsh' | 'sh', isWeekend: boolean, now: Date = new Date()): NextBusInfo | null {
    const list = BusScheduleModel.getBusList(departure, isWeekend);
    if (list.length === 0) {
      return null;
    }

    const currentMinutes = now.getHours() * 60 + now.getMinutes();

    for (let i = 0; i < list.length; i++) {
      const item = list[i];
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
    const tomorrowIsWeekend = BusScheduleModel.isWeekendDay(new Date(now.getTime() + 24 * 60 * 60 * 1000));
    const tomorrowList = BusScheduleModel.getBusList(departure, tomorrowIsWeekend);
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
