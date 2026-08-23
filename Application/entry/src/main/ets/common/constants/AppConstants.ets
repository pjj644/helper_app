export class AppConstants {
  static readonly LOGIN_PREF_NAME: string = 'classtable_login_pref';
  static readonly LOGIN_SESSION_KEY: string = 'login_session_json';
  static readonly PREF_PRIVACY_AGREED: string = 'app_privacy_policy_agreed';

  static readonly COURSE_TABLE_PREF_NAME: string = 'course_table_local_db';
  static readonly PREF_COURSE_DB_NAME: string = 'course_table_local_db';
  static readonly COURSE_TABLE_DATA_KEY: string = 'course_table_data_json';
  static readonly COURSE_TABLE_DATA_KEY_PREFIX: string = 'course_table_data_json_';
  static readonly EXAM_DATA_KEY: string = 'exam_data_json';
  static readonly RECENT_LINKS_KEY: string = 'recent_links_json';

  static readonly SETTING_SHOW_TODAY_KEY: string = 'setting_show_today';
  static readonly SETTING_SHOW_TOMORROW_KEY: string = 'setting_show_tomorrow';
  static readonly SETTING_SHOW_EXAM_KEY: string = 'setting_show_exam';
  static readonly SETTING_EXAM_REMIND_MINUTES_KEY: string = 'setting_exam_remind_minutes';
  static readonly SETTING_COURSE_REMIND_MINUTES_KEY: string = 'setting_course_remind_minutes';
  static readonly EXAM_SELECTED_TYPE_ID_KEY: string = 'exam_selected_type_id';
  static readonly EXAM_SELECTED_SEMESTER_ID_KEY: string = 'exam_selected_semester_id';

  static readonly GRADE_DATA_KEY: string = 'grade_data_json';
  static readonly SCHEDULE_DATA_KEY: string = 'schedule_data_json';
  static readonly SETTING_REMINDER_ENABLED_KEY: string = 'setting_reminder_enabled';
  static readonly SETTING_EXAM_REMINDER_ENABLED_KEY: string = 'setting_exam_reminder_enabled';
  static readonly SETTING_SCHEDULE_REMINDER_MASTER_KEY: string = 'setting_schedule_reminder_master';
  static readonly SETTING_SCHEDULE_REMINDER_EXAM_KEY: string = 'setting_schedule_reminder_exam';
  static readonly SETTING_SCHEDULE_REMINDER_COURSE_KEY: string = 'setting_schedule_reminder_course';
  static readonly SETTING_SCHEDULE_REMINDER_CUSTOM_KEY: string = 'setting_schedule_reminder_custom';
  static readonly SETTING_SCHEDULE_REMINDER_ASSIGNMENT_KEY: string = 'setting_schedule_reminder_assignment';
  static readonly SETTING_AUTO_SYNC_SCHEDULE_KEY: string = 'setting_auto_sync_schedule';
  static readonly SETTING_SCHEDULE_REMIND_MINUTES_EXAM_KEY: string = 'setting_schedule_remind_minutes_exam';
  static readonly SETTING_SCHEDULE_REMIND_MINUTES_COURSE_KEY: string = 'setting_schedule_remind_minutes_course';
  static readonly SETTING_SCHEDULE_REMIND_MINUTES_CUSTOM_KEY: string = 'setting_schedule_remind_minutes_custom';
  static readonly SETTING_SCHEDULE_REMIND_MINUTES_ASSIGNMENT_KEY: string = 'setting_schedule_remind_minutes_assignment';
  // 2026-2027学年第一学期（行课首日 2026-09-01 周二；END 为估测放假日，逻辑未使用，可按校历修正）
  static readonly SCHOOL_SEMESTER_START: string = '2026-09-01';
  static readonly SCHOOL_SEMESTER_END: string = '2027-01-18';

  static readonly EAMS_HOME_URL: string = 'https://eams.uestc.edu.cn/eams/home!index.action';
  static readonly EAMS_GRADE_URL_BASE: string = 'https://eams.uestc.edu.cn/eams/teach/grade/course/person!history.action';
  static readonly EAMS_GRADE_SEARCH_URL_BASE: string = 'https://eams.uestc.edu.cn/eams/teach/grade/course/person!search.action';
  static readonly EAMS_USUAL_GRADE_URL_BASE: string = 'https://eams.uestc.edu.cn/eams/teach/grade/usual/usual-grade-std!search.action';
  static readonly EAMS_LOGIN_URL_PATTERN: string = 'idas.uestc.edu.cn/authserver/login';
  static readonly EAMS_EXAM_MENU_URL: string = 'https://eams.uestc.edu.cn/eams/home!childmenus.action?menu.id=844';
  static readonly EAMS_EXAM_TABLE_BASE_URL: string = 'https://eams.uestc.edu.cn/eams/stdExamTable!examTable.action';
  static readonly EAMS_COURSE_TABLE_URL: string = 'https://eams.uestc.edu.cn/eams/courseTableForStd.action';

  static readonly ONLINE_URL: string = 'https://online.uestc.edu.cn/';
  static readonly GIS_MAP_URL: string = 'https://gis.uestc.edu.cn/#/';
  static readonly LIB_FULL_URL: string = 'https://www.lib.uestc.edu.cn/engine2/general/more?appId=4483334&websiteId=464744&wfwfid=22855&pageId=877838&typeId=10937088&currentBranch=1';
  static readonly LIB_URL: string = 'https://www.lib.uestc.edu.cn';
  static readonly QINGSHUI_RIVER_URL: string = 'https://bbs.uestc.edu.cn/new';
  static readonly CARD_BALANCE_URL: string = 'https://mapp.uestc.cn/site/ipasscd/index';
  static readonly EPORTAL_URL: string = 'https://online.uestc.edu.cn/';
  static readonly YJSY_URL: string = 'https://yjsjy.uestc.edu.cn/pyxx/jzsso/login';
  static readonly UESTC_URL: string = 'https://www.uestc.edu.cn';
  static readonly EAMS_PORTAL_URL: string = 'https://eams.uestc.edu.cn/eams/home!childmenus.action?menu.id=844';

  static readonly WEBVPN_BASE_URL: string = 'https://webvpn.uestc.edu.cn';
  static readonly WEBVPN_LOGIN_URL: string = 'https://webvpn.uestc.edu.cn';
  static readonly WEBVPN_EAMS_ENCODED_DOMAIN: string =
    '77726476706e69737468656265737421f5f64c8f69256d436a0bc7a99c406d36c2';
  static readonly WEBVPN_EAMS_DOMAIN: string = 'eams.uestc.edu.cn';

  static readonly CLOUD_DB_ZONE_NAME: string = 'classData';
  static readonly MAX_FETCH_RETRY: number = 2;
  static readonly MAX_PAGE_RETRY: number = 2;
  static readonly MAX_PARSE_RETRY: number = 5;

  static readonly AI_CHAT_SESSIONS_KEY: string = 'ai_chat_sessions';
  static readonly AI_CHAT_MAX_SESSIONS: number = 20;
  static readonly AI_AGENT_MAX_TOOL_ROUNDS: number = 5;
  static readonly AI_AGENT_TOOL_TIMEOUT_MS: number = 30000;

  // ECS proxy — change URL to your ECS server address
  static readonly AI_AGENT_URL: string = 'http://192.168.1.100:3000';
  static readonly AI_AGENT_KEY: string = 'uestc-helper-proxy-key-change-me';
  static readonly AI_CHAT_PATH: string = 'api/chat';
  static readonly AI_TOOL_RESULT_PATH: string = 'api/tool-result';
  static readonly SETTING_AGENT_BACKEND_URL_KEY: string = 'setting_agent_backend_url';
  static readonly SETTING_AI_SHOW_TOOL_CALLS_KEY: string = 'setting_ai_show_tool_calls';
  static readonly SETTING_FLOATING_BALL_ENABLED_KEY: string = 'setting_floating_ball_enabled';
  static readonly FLOATING_SUBWINDOW_NAME: string = 'ai_floating_subwindow';

  static readonly CONTENT_MAX_LINE: number = 2;
  static readonly MAX_ID: number = 100;
  static readonly MAX_SELECT_NUMBER: number = 1;
  static readonly UPDATE_PROGRESS_MIN_VALUE: number = 0;
  static readonly UPDATE_PROGRESS_MAX_VALUE: number = 100;
  static readonly UPDATE_PROGRESS_LENGTH: number = 5;

  // ==================== UI配置 ====================
  static readonly PAGE_PADDING: number = 16;
  static readonly CARD_RADIUS: number = 16;
  static readonly SMALL_RADIUS: number = 12;
  static readonly CARD_SPACE: number = 16;
  static readonly LIST_ITEM_SPACE: number = 12;

  // ==================== 尺寸配置 ====================
  static readonly ICON_SIZE: number = 24;
  static readonly SMALL_ICON_SIZE: number = 20;
  static readonly LARGE_ICON_SIZE: number = 32;
  static readonly AVATAR_SIZE: number = 52;
  static readonly SMALL_AVATAR_SIZE: number = 40;

  // ==================== 字体大小 ====================
  static readonly FONT_TITLE: number = 24;
  static readonly FONT_SUBTITLE: number = 18;
  static readonly FONT_BODY: number = 15;
  static readonly FONT_CAPTION: number = 13;
  static readonly FONT_SMALL: number = 12;
  static readonly FONT_TINY: number = 11;

  // ==================== 动画配置 ====================
  static readonly ANIMATION_FAST: number = 100;
  static readonly ANIMATION_NORMAL: number = 300;
  static readonly ANIMATION_SLOW: number = 500;
  static readonly SWIPER_INTERVAL: number = 3500;

  // ==================== 阴影配置 ====================
  static readonly SHADOW_SMALL: number = 4;
  static readonly SHADOW_MEDIUM: number = 8;
  static readonly SHADOW_LARGE: number = 16;

  // ==================== 沉浸光感配置 ====================
  static readonly LIGHT_INTENSITY_DEFAULT: number = 2.5;
  static readonly LIGHT_INTENSITY_WEAK: number = 1.5;
  static readonly LIGHT_INTENSITY_STRONG: number = 3.0;

  // ==================== 网格配置 ====================
  static readonly SERVICE_GRID_COLUMNS: number = 3;
  static readonly SERVICE_GRID_ROWS: number = 2;
  static readonly GRID_GAP: number = 12;

  // ==================== 其他UI配置 ====================
  static readonly MAX_LINES: number = 2;
  static readonly SINGLE_LINE: number = 1;
  static readonly UNREAD_DOT_SIZE: number = 8;
}

export class RouterConstants {
  static readonly PAGE_INDEX: string = 'pages/Index';
  static readonly PAGE_TABLE_UI: string = 'pages/classTablePages/tableUI';
  static readonly PAGE_COURSE_IMPORT: string = 'pages/classTablePages/Index';
  static readonly PAGE_EXAM: string = 'pages/classTablePages/ExamPage';
  static readonly PAGE_EXAM_IMPORT: string = 'pages/classTablePages/ExamImport';
  static readonly PAGE_GRADE: string = 'pages/gradePages/GradePage';
  static readonly PAGE_GRADE_IMPORT: string = 'pages/gradePages/GradeImport';
  static readonly PAGE_CALENDAR: string = 'pages/schedulePages/CalendarPage';
  static readonly PAGE_BUS_SCHEDULE: string = 'pages/schedulePages/BusSchedulePage';
  static readonly PAGE_SETTINGS: string = 'pages/classTablePages/AppSettings';
  static readonly PAGE_LOGIN: string = 'pages/login/loginIndex';
  static readonly PAGE_ACCOUNT_MANAGE: string = 'pages/login/AccountManage';
  static readonly PAGE_ASSISTANT: string = 'pages/quick/AssistantPage';
  static readonly PAGE_FLOATING_SUBWINDOW: string = 'pages/quick/FloatingSubWindowContent';
  static readonly PAGE_WEB: string = 'pages/classTablePages/WebPage';
}
