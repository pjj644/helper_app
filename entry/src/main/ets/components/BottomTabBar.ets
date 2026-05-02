import { ThemeManager } from '../common/utils/ThemeManager';

export interface TabItem {
  label: string;
}

@Component
export struct BottomTabBar {
  @Link currentIndex: number;
  @Prop tabs: TabItem[] = [];
  onChange?: (index: number) => void;

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
      ForEach(this.tabs, (tab: TabItem) => {
        TabContent() {
          Column().width('100%').height(0);
        }.tabBar(tab.label);
      });
    }
    .barMode(BarMode.Fixed)
    .scrollable(false)
    .animationDuration(0)
    .onChange((index: number) => {
      this.currentIndex = index;
      if (this.onChange) {
        this.onChange(index);
      }
    })
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4, top: 2, bottom: 4 })
    .backgroundColor(ThemeManager.getBackgroundSecondaryColor())
    .border({ width: { top: 1 }, color: ThemeManager.getBorderColor() });
  }
}
