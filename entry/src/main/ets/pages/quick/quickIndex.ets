import { router } from '@kit.ArkUI';
import { ThemeManager } from '../../common/utils/ThemeManager';
import { GradeService } from '../../service/GradeService';
import { ScheduleService } from '../../service/ScheduleService';
import { AppConstants } from '../../common/constants/AppConstants';
import { BottomTabBar, TabItem } from '../../components/BottomTabBar';

interface ToolItem {
  title: string;
  icon: string;
  color: string;
  route?: string;
  url?: string;
  iconImage?: Resource;
}

@Entry
@Component
struct QuickIndexPage {
  @State currentTabIndex: number = 0;
  @State latestGpa: string = '--';
  @State todayEventCount: number = 0;
  @StorageLink(ThemeManager.THEME_STORAGE_KEY) isDarkMode: boolean = false;
  private tabs: TabItem[] = [
    { label: '发现' },
    { label: '课表' },
  ];

  private tools: ToolItem[] = [
    { title: 'AI 助手', icon: '🤖', color: '#6366F1', route: 'pages/quick/AssistantPage', iconImage: $r('app.media.ic_ai_assistant') },
    { title: '校园地图', icon: '🗺️', color: '#3B82FF', url: AppConstants.GIS_MAP_URL, iconImage: $r('app.media.ic_campus_map') },
    { title: '图书馆', icon: '📚', color: '#10B981', url: AppConstants.LIB_FULL_URL },
    { title: '校园卡', icon: '💳', color: '#F59E0B' },
    { title: '计算器', icon: '🧮', color: '#EF4444' },
    { title: '天气', icon: '🌤️', color: '#8B5CF6' },
    { title: '成绩查询', icon: '📊', color: '#EC4899', route: 'pages/gradePages/GradePage' },
    { title: '空教室', icon: '🏫', color: '#06B6D4' },
    { title: '校园日历', icon: '📅', color: '#84CC16', route: 'pages/schedulePages/CalendarPage' },
    { title: '清水河畔', icon: '🌊', color: '#0EA5E9', url: AppConstants.QINGSHUI_RIVER_URL, iconImage: $r('app.media.ic_qingshui_river') },
    { title: '一卡通余额', icon: '💰', color: '#F97316', url: AppConstants.CARD_BALANCE_URL, iconImage: $r('app.media.ic_card_balance') },
  ];

  aboutToAppear(): void {
    this.loadQuickInfo();
  }

  onPageShow(): void {
    this.currentTabIndex = 0;
    this.loadQuickInfo();
  }

  private async loadQuickInfo(): Promise<void> {
    try {
      const context = getContext(this);
      const grades = await GradeService.loadGrades(context);
      if (grades.length > 0) {
        const gpa: number = GradeService.getLatestSemesterGPA(grades);
        this.latestGpa = gpa > 0 ? gpa.toFixed(2) : '--';
      } else {
        this.latestGpa = '--';
      }

      const events = await ScheduleService.getAllEvents(context);
      const today = new Date();
      const todayStr: string = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
      let count: number = 0;
      for (let i = 0; i < events.length; i++) {
        if (events[i].date === todayStr) {
          count++;
        }
      }
      this.todayEventCount = count;
    } catch (error) {
      console.error('loadQuickInfo error:', JSON.stringify(error));
    }
  }

  private navToClass(): void {
    router.pushUrl({ url: 'pages/classTablePages/Home' })
      .catch((error: Error) => console.error('跳转 class 页面失败:', error));
  }

  private onTabChange(index: number): void {
    this.currentTabIndex = index;
    if (index === 1) { this.navToClass(); }
  }

  private onToolClick(tool: ToolItem): void {
    if (tool.route) {
      router.pushUrl({ url: tool.route }, router.RouterMode.Standard)
        .catch((error: Error) => console.error(`跳转 ${tool.title} 页面失败:`, error));
    } else if (tool.url) {
      router.pushUrl({
        url: 'pages/classTablePages/WebPage',
        params: { title: tool.title, url: tool.url }
      }, router.RouterMode.Standard)
        .catch((error: Error) => console.error(`打开 ${tool.title} 网页失败:`, error));
    } else {
      this.getUIContext().getPromptAction().showToast({ message: `${tool.title} 功能开发中` });
    }
  }

  build() {
    Column() {
      Column({ space: 4 }) {
        Text('发现')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeManager.getTextPrimaryColor());

        Text('校园实用工具')
          .fontSize(14)
          .fontColor(ThemeManager.getTextSecondaryColor());
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 16, bottom: 8 });

      Text('快捷功能')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextTertiaryColor())
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 });

      Row({ space: 12 }) {
        Column() {
          Text('📊')
            .fontSize(24);
          Text('成绩查询')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .margin({ top: 4 });
          Text(this.latestGpa === '--' ? '点击导入' : `GPA ${this.latestGpa}`)
            .fontSize(10)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .height(90)
        .borderRadius(14)
        .backgroundColor(ThemeManager.isDarkMode() ? '#1A3A5C' : '#EBF5FF')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const gradeTool = this.tools.find(t => t.title === '成绩查询');
          if (gradeTool) this.onToolClick(gradeTool);
        });

        Column() {
          Text('📅')
            .fontSize(24);
          Text('校园日历')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .margin({ top: 4 });
          Text(this.todayEventCount > 0 ? `今日 ${this.todayEventCount} 件事` : '查看日程')
            .fontSize(10)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .height(90)
        .borderRadius(14)
        .backgroundColor(ThemeManager.getAccentBgColor())
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const calTool = this.tools.find(t => t.title === '校园日历');
          if (calTool) this.onToolClick(calTool);
        });

        Column() {
          Text('📚')
            .fontSize(24);
          Text('图书馆')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeManager.getTextPrimaryColor())
            .margin({ top: 4 });
          Text('点击打开')
            .fontSize(10)
            .fontColor(ThemeManager.getTextTertiaryColor())
            .margin({ top: 2 });
        }
        .layoutWeight(1)
        .height(90)
        .borderRadius(14)
        .backgroundColor(ThemeManager.getAccentBgColor())
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          const libTool = this.tools.find(t => t.title === '图书馆');
          if (libTool) this.onToolClick(libTool);
        });
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 });

      Text('全部工具')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeManager.getTextTertiaryColor())
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 });

      Grid() {
        ForEach(this.tools, (tool: ToolItem) => {
          GridItem() {
            Column({ space: 8 }) {
              if (tool.iconImage) {
                Image(tool.iconImage)
                  .width(28)
                  .height(28);
              } else {
                Text(tool.icon)
                  .fontSize(28);
              }
              Text(tool.title)
                .fontSize(13)
                .fontColor(ThemeManager.getTextPrimaryColor());
            }
            .width('100%')
            .height(90)
            .borderRadius(16)
            .backgroundColor(ThemeManager.getCardColor())
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.onToolClick(tool));
          }
        });
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
      .columnsGap(14)
      .rowsGap(14)
      .padding({ left: 16, right: 16 })
      .layoutWeight(1);

      BottomTabBar({ currentIndex: $currentTabIndex, tabs: this.tabs, onChange: (index: number) => this.onTabChange(index) });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeManager.getBackgroundColor());
  }
}