import { router } from '@kit.ArkUI';
import { Course } from '../../model/classTableModel/CourseModel';
import { CourseService } from '../../service/CourseService';
import { ThemeManager } from '../../common/utils/ThemeManager';

@Entry
@Component
struct CourseManage {
  @State courses: Course[] = [];
  @State showEditor: boolean = false;
  @State editIndex: number = -1;

  @State formId: string = '';
  @State formName: string = '';
  @State formTeacher: string = '';
  @State formRoom: string = '';
  @State formDay: number = 1;
  @State formStartSection: number = 1;
  @State formDuration: number = 2;
  @State formWeeks: string = '1-20';

  aboutToAppear(): void {
    this.loadCourseList();
  }

  private async loadCourseList(): Promise<void> {
    try {
      const allCourses: Course[] = await CourseService.loadCourses(getContext(this));
      allCourses.sort((a, b) => {
        if (a.time.dayOfWeek !== b.time.dayOfWeek) {
          return a.time.dayOfWeek - b.time.dayOfWeek;
        }
        return a.time.startSection - b.time.startSection;
      });
      this.courses = allCourses;
    } catch (error) {
      console.error('加载本地课程失败:', error);
      this.courses = [];
    }
  }

  private buildValidWeeksFromText(weeksText: string): string {
    const weeks: boolean[] = [];
    for (let i = 0; i < 31; i++) {
      weeks.push(false);
    }
    const cleaned: string = weeksText.replace(/\s+/g, '');
    const segments: string[] = cleaned.split(',').filter(item => item.length > 0);

    if (segments.length === 0) {
      for (let w = 1; w <= 20; w++) {
        weeks[w] = true;
      }
    } else {
      for (const segment of segments) {
        if (segment.includes('-')) {
          const parts: string[] = segment.split('-');
          if (parts.length !== 2) {
            continue;
          }
          const start: number = Number(parts[0]);
          const end: number = Number(parts[1]);
          if (Number.isNaN(start) || Number.isNaN(end)) {
            continue;
          }
          const left: number = Math.max(1, Math.min(start, end));
          const right: number = Math.min(30, Math.max(start, end));
          for (let w = left; w <= right; w++) {
            weeks[w] = true;
          }
        } else {
          const week: number = Number(segment);
          if (!Number.isNaN(week) && week >= 1 && week <= 30) {
            weeks[week] = true;
          }
        }
      }
    }

    let result: string = '0';
    for (let w = 1; w <= 30; w++) {
      result += weeks[w] ? '1' : '0';
    }
    return result;
  }

  private validWeeksToText(validWeeks: string): string {
    if (!validWeeks || validWeeks.length < 2) {
      return '1-20';
    }

    const ranges: string[] = [];
    let start: number = -1;
    let prev: number = -1;

    for (let i = 1; i < validWeeks.length; i++) {
      if (validWeeks[i] === '1') {
        if (start === -1) {
          start = i;
        }
        prev = i;
      } else if (start !== -1) {
        ranges.push(start === prev ? `${start}` : `${start}-${prev}`);
        start = -1;
        prev = -1;
      }
    }

    if (start !== -1) {
      ranges.push(start === prev ? `${start}` : `${start}-${prev}`);
    }

    return ranges.length > 0 ? ranges.join(',') : '1-20';
  }

  private generateCourseId(name: string): string {
    return `${name}_${Date.now()}`;
  }

  private openAddEditor(): void {
    this.editIndex = -1;
    this.formId = '';
    this.formName = '';
    this.formTeacher = '';
    this.formRoom = '';
    this.formDay = 1;
    this.formStartSection = 1;
    this.formDuration = 2;
    this.formWeeks = '1-20';
    this.showEditor = true;
  }

  private openEditEditor(index: number): void {
    const course: Course = this.courses[index];
    this.editIndex = index;
    this.formId = course.id;
    this.formName = course.name;
    this.formTeacher = course.teacherName;
    this.formRoom = course.roomName;
    this.formDay = course.time.dayOfWeek;
    this.formStartSection = course.time.startSection;
    this.formDuration = course.time.duration;
    this.formWeeks = this.validWeeksToText(course.validWeeks);
    this.showEditor = true;
  }

  private async confirmEditor(): Promise<void> {
    if (!this.formName.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '课程名称不能为空' });
      return;
    }

    const newCourse: Course = {
      id: this.formId.trim() || this.generateCourseId(this.formName.trim()),
      name: this.formName.trim(),
      teacherName: this.formTeacher.trim(),
      roomName: this.formRoom.trim(),
      validWeeks: this.buildValidWeeksFromText(this.formWeeks),
      colorIndex: Math.floor(Math.random() * 10),
      time: {
        dayOfWeek: this.formDay,
        startSection: this.formStartSection,
        duration: this.formDuration,
      }
    };

    if (this.editIndex >= 0) {
      CourseService.updateCourse(this.editIndex, newCourse);
    } else {
      CourseService.addCourse(newCourse);
    }

    this.showEditor = false;
    await CourseService.saveCourses(getContext(this), CourseService.getAllCourses());
    await this.loadCourseList();
  }

  private async deleteCourse(index: number): Promise<void> {
    CourseService.deleteCourse(index);
    await CourseService.saveCourses(getContext(this), CourseService.getAllCourses());
    this.courses = CourseService.getAllCourses().sort((a, b) => {
      if (a.time.dayOfWeek !== b.time.dayOfWeek) {
        return a.time.dayOfWeek - b.time.dayOfWeek;
      }
      return a.time.startSection - b.time.startSection;
    });
  }

  private weekNames: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  private getDayOptions(): SelectOption[] {
    return [
      { value: '周一' }, { value: '周二' }, { value: '周三' }, { value: '周四' },
      { value: '周五' }, { value: '周六' }, { value: '周日' }
    ];
  }

  private getSectionOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 1; i <= 12; i++) {
      options.push({ value: `${i}节` });
    }
    return options;
  }

  private getDurationOptions(): SelectOption[] {
    return [{ value: '1节' }, { value: '2节' }, { value: '3节' }, { value: '4节' }];
  }

  @Builder
  private EditorBuilder(): void {
    Column() {
      Text(this.editIndex >= 0 ? '编辑课程' : '新增课程')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 12 });

      TextInput({ text: this.formName, placeholder: '课程名称' })
        .onChange((v: string) => this.formName = v)
        .width('100%')
        .margin({ bottom: 8 });

      TextInput({ text: this.formTeacher, placeholder: '教师' })
        .onChange((v: string) => this.formTeacher = v)
        .width('100%')
        .margin({ bottom: 8 });

      TextInput({ text: this.formRoom, placeholder: '地点' })
        .onChange((v: string) => this.formRoom = v)
        .width('100%')
        .margin({ bottom: 8 });

      TextInput({ text: this.formWeeks, placeholder: '上课周次,如 1-16,18' })
        .onChange((v: string) => this.formWeeks = v)
        .width('100%')
        .margin({ bottom: 8 });

      Row({ space: 8 }) {
        Text('星期')
          .width(60);
        Select(this.getDayOptions())
          .selected(this.formDay - 1)
          .value(String(this.getDayOptions()[this.formDay - 1].value))
          .onSelect((index: number) => this.formDay = index + 1)
          .layoutWeight(1);
      }
      .width('100%')
      .margin({ bottom: 8 });

      Row({ space: 8 }) {
        Text('开始节次')
          .width(60);
        Select(this.getSectionOptions())
          .selected(this.formStartSection - 1)
          .value(String(this.getSectionOptions()[this.formStartSection - 1].value))
          .onSelect((index: number) => this.formStartSection = index + 1)
          .layoutWeight(1);
      }
      .width('100%')
      .margin({ bottom: 8 });

      Row({ space: 8 }) {
        Text('持续节数')
          .width(60);
        Select(this.getDurationOptions())
          .selected(this.formDuration - 1)
          .value(String(this.getDurationOptions()[this.formDuration - 1].value))
          .onSelect((index: number) => this.formDuration = index + 1)
          .layoutWeight(1);
      }
      .width('100%')
      .margin({ bottom: 12 });

      Row({ space: 8 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => this.showEditor = false);
        Button('保存')
          .layoutWeight(1)
          .onClick(() => this.confirmEditor());
      }
      .width('100%');
    }
    .padding(16)
    .width('100%');
  }

  build() {
    Column() {
      Row() {
        Text('本地课表管理')
          .fontSize(24)
          .fontWeight(FontWeight.Bold);
        Blank();
        Button('返回')
          .onClick(() => router.back());
      }
      .width('100%')
      .padding(12);

      Row({ space: 8 }) {
        Button('新增课程')
          .onClick(() => this.openAddEditor());
        Button('刷新')
          .onClick(() => this.loadCourseList());
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 8 });

      if (this.courses.length === 0) {
        Text('暂无本地课程，可点击"新增课程"')
          .fontSize(14)
          .fontColor(ThemeManager.getTextSecondaryColor())
          .margin({ top: 24 });
      } else {
        List() {
          ForEach(this.courses, (course: Course, index: number) => {
            ListItem() {
              Column() {
                Text(course.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .width('100%');
                Text(`周${this.weekNames[course.time.dayOfWeek - 1]} ${course.time.startSection}-${course.time.startSection + course.time.duration - 1}节`)
                  .fontSize(13)
                  .fontColor(ThemeManager.getTextPrimaryColor())
                  .width('100%')
                  .margin({ top: 4 });
                Text(`${course.roomName || '地点未知'} ${course.teacherName || '教师未知'}`)
                  .fontSize(13)
                  .fontColor(ThemeManager.getTextSecondaryColor())
                  .width('100%')
                  .margin({ top: 2 });
                Text(`周次: ${this.validWeeksToText(course.validWeeks)}`)
                  .fontSize(12)
                  .fontColor(ThemeManager.getTextTertiaryColor())
                  .width('100%')
                  .margin({ top: 2 });

                Row({ space: 8 }) {
                  Button('编辑')
                    .onClick(() => this.openEditEditor(index));
                  Button('删除')
                    .fontColor('#D32F2F')
                    .onClick(() => this.deleteCourse(index));
                }
                .margin({ top: 8 });
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(ThemeManager.getBackgroundColor())
              .margin({ left: 12, right: 12, top: 6, bottom: 6 });
            }
          });
        }
        .layoutWeight(1)
        .width('100%');
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showEditor, this.EditorBuilder(), {
      detents: [SheetSize.MEDIUM],
      showClose: true,
      title: {
        title: '课程编辑'
      }
    });
  }
}
