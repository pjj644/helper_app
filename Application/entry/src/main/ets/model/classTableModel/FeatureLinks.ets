import { AppConstants } from '../../common/constants/AppConstants';

export interface FeatureLink {
  title: string;
  url: string;
  category: string;
}

export const FEATURE_LINKS: FeatureLink[] = [
  { title: '教务系统首页', url: AppConstants.EAMS_PORTAL_URL, category: '课程学习' },
  { title: '考试信息', url: AppConstants.EAMS_EXAM_TABLE_BASE_URL, category: '课程学习' },
  { title: '图书馆', url: AppConstants.LIB_FULL_URL, category: '服务工具' },
  { title: '信息门户', url: AppConstants.EPORTAL_URL, category: '服务工具' },
  { title: '研究生系统', url: AppConstants.YJSY_URL, category: '学校管理' },
  { title: '学校官网', url: AppConstants.UESTC_URL, category: '学校管理' }
];
