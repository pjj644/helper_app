export class AppConstants {
  static readonly LOGIN_PREF_NAME: string = 'classtable_login_pref';
  static readonly LOGIN_SESSION_KEY: string = 'login_session_json';

  static readonly COURSE_TABLE_PREF_NAME: string = 'course_table_local_db';
  static readonly COURSE_TABLE_DATA_KEY: string = 'course_table_data_json';
  static readonly COURSE_TABLE_DATA_KEY_PREFIX: string = 'course_table_data_json_';
  static readonly EXAM_DATA_KEY: string = 'exam_data_json';
  static readonly RECENT_LINKS_KEY: string = 'recent_links_json';

  static readonly SETTING_THEME_DARK_KEY: string = 'setting_theme_dark';
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
  static readonly SCHOOL_SEMESTER_START: string = '2026-02-23';
  static readonly SCHOOL_SEMESTER_END: string = '2026-07-05';

  static readonly EAMS_HOME_URL: string = 'https://eams.uestc.edu.cn/eams/home!index.action';
  static readonly EAMS_GRADE_URL_BASE: string = 'https://eams.uestc.edu.cn/eams/teach/grade/course/person!search.action';
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
  static readonly EPORTAL_URL: string = 'https://eportal.uestc.edu.cn';
  static readonly YJSY_URL: string = 'https://yjsy.uestc.edu.cn';
  static readonly UESTC_URL: string = 'https://www.uestc.edu.cn';
  static readonly EAMS_PORTAL_URL: string = 'https://eams.uestc.edu.cn/eams/home!childmenus.action?menu.id=844';

  static readonly CLOUD_DB_ZONE_NAME: string = 'classData';
  static readonly MAX_FETCH_RETRY: number = 2;
  static readonly MAX_PAGE_RETRY: number = 2;
  static readonly MAX_PARSE_RETRY: number = 5;

  static readonly CONTENT_MAX_LINE: number = 2;
  static readonly MAX_ID: number = 100;
  static readonly MAX_SELECT_NUMBER: number = 1;
  static readonly UPDATE_PROGRESS_MIN_VALUE: number = 0;
  static readonly UPDATE_PROGRESS_MAX_VALUE: number = 100;
  static readonly UPDATE_PROGRESS_LENGTH: number = 5;
}
