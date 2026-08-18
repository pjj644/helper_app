# 项目架构 (ARCHITECTURE.md)

> UESTC Helper（成电校园助手）的代码结构与数据流。给接手代码的人 / 下一个 AI 快速定位用。
> AI 助手子系统单独见 [AI_AGENT.md](./AI_AGENT.md)；构建与测试见 [BUILD_AND_TEST.md](./BUILD_AND_TEST.md)。

## 总览

HarmonyOS（ArkTS，stage model，API 6.0.2/22）端云一体应用。通过 WebView JS 注入抓取教务系统（EAMS）的课表 / 考试 / 成绩，本地存储（preferences），并同步到华为 Cloud DB。内含 AI 助手（后端 LangGraph 大脑 + 设备端工具执行）。

两个顶层目录：

- **`Application/`** — HarmonyOS app（ArkTS）。源码在 `entry/src/main/ets/`。
- **`CloudProgram/`** — 云端 Node.js（Cloud DB schema、云函数）。

**git 仓库在项目根目录 `D:\harmony\helper_app`**（2026-08 由 `Application/` 内迁移而来，历史保留，所有项目文件统一入库；`information/` 抓取存档与 AI 工具配置（`.agents` / `.claude` / `.opencode`）不入库）。根目录还有：`CLAUDE.md` 精简入口、`doc/` 本文档集、`_build.bat` / `_clean_build.bat` / `_lint.bat` 构建脚本、`icon/` 素材、`playwright/` 测试脚本。

## 分层（`Application/entry/src/main/ets/`）

```
pages/          -> UI 页面（@Entry / @Component）
components/     -> 可复用 UI 组件（home/ 下包含解耦的主页四大子组件）
entryformability/ -> 鸿蒙桌面万能卡片生命周期服务 (EntryFormAbility.ets)
widget/pages/   -> 鸿蒙桌面卡片 UI 组件 (CourseWidgetCard2x2.ets)
service/        -> 业务逻辑（auth / scrape / sync / reminder / 各数据服务）
repository/     -> 数据持久化（preferences 键值存储、Cloud DB）
model/          -> 数据模型 + 纯数据变换（解析/过滤/排序，无 HarmonyOS 导入）
common/         -> 共享工具（Logger / ThemeManager / DateUtils / BreakpointUtils）+ AppConstants
                   common/agent/   -> AI 助手前端（BackendAgentClient / ToolExecutor / ToolRegistry / VisionScheduleHelper）
                   common/speech/  -> 鸿蒙原生 CoreSpeechKit 语音转写 (SpeechRecognizerHelper)
                   common/constants/AppConstants.ets -> 所有偏好键 / URL / 魔法数字的唯一来源
```

**数据流**：Pages → Service → Repository → Preferences / Cloud DB
**Models 是纯 TS**（无 `@kit.*` 导入），只做解析 / 过滤 / 排序。

## 入口与桌面卡片

- **主应用入口**：`EntryAbility.ets` 加载 `pages/Index` 为主页，从 `agconnect-services.json` 初始化 AGC Auth，设置颜色模式。
- **万能服务卡片入口**：`EntryFormAbility.ets` 管理 2x2/2x4 桌面课表卡片生命周期，通过 `CourseService.updateNextCourseCache` 维护 Preferences 缓存并即时刷新卡片，点击直达应用内。
- **一多响应式适配**：`BreakpointUtils.ets` 监听窗口断点（sm <600vp 手机竖屏 / md 600-840vp 折叠屏展开 / lg >=840vp 平板与2in1），主页与发现页支持自动从单栏切换为双栏/多列栅格联动布局。

## 各功能与关键文件

| 功能 | 关键文件 |
|---|---|
| **课表** — 抓取/解析/周网格展示 | `service/WebScrapeService.ets`（JS 注入脚本）、`model/classTableModel/CourseModel.ets`、`pages/classTablePages/tableUI.ets`、`pages/Index.ets` |
| **桌面卡片 (Widget)** — 实时下节课倒计时与教室 | `entryformability/EntryFormAbility.ets`、`widget/pages/CourseWidgetCard2x2.ets`、`form_config.json` |
| **主页模块化组件** | `components/home/HomeHeaderComponent.ets`、`NextCourseCardComponent.ets`、`ExamCountdownCard.ets`、`QuickLinksGrid.ets` |
| **考试** — 抓取/解析/倒计时 | `model/classTableModel/ExamModel.ets`、`pages/classTablePages/ExamPage.ets`、`pages/classTablePages/ExamImport.ets` |
| **成绩** — 抓取/GPA/学期筛选 | `model/GradeModel.ets`、`pages/gradePages/GradePage.ets`、`pages/gradePages/GradeImport.ets` |
| **日程/日历** — 统一事件日历 + 自定义事件 | `model/ScheduleModel.ets`、`pages/schedulePages/CalendarPage.ets`、`service/ScheduleService.ets` |
| **提醒** — 通知 + 系统日历提醒（课程/考试） | `service/ReminderService.ets`（通知代理 + 日历兜底）、`service/CalendarKitReminderService.ets`（Calendar Kit） |
| **云同步** — 课表/考试上下云 | `service/SyncService.ets`、`repository/CloudDbRepository.ets` |
| **鉴权** — 登录态存 preferences | `service/AuthService.ets`、`pages/login/loginIndex.ets` |
| **快捷链接** — WebView 校园服务门户 | `pages/quick/quickIndex.ets` |
| **设置** — 主题/提醒偏好/助手后端地址 | `pages/classTablePages/AppSettings.ets`、`repository/SettingsRepository.ets` |
| **AI 助手（语音+视觉+RAG）** | `pages/quick/AssistantPage.ets`、`common/agent/*`、`common/speech/*`，详见 [AI_AGENT.md](./AI_AGENT.md) |

## 导航

底部 Tab 3 个：**Quick**（WebView 门户）、**Home**（课表/考试仪表盘，`pages/Index.ets`）、**Class**（课表）。Home 用 WebView 嵌 `online.uestc.edu.cn`。页面切换走 `router.pushUrl`。路由常量在 `AppConstants.RouterConstants`。

## 数据存储

- **本地**：全部用 `@kit.ArkData` 的 `preferences`。偏好名：`classtable_login_pref`（鉴权）、`course_table_local_db`（所有应用数据：课表/考试/成绩/日程/设置）。键名统一定义在 `AppConstants`。
- **云端**：华为 Cloud DB，两个对象类型 `ClassCourse`、`ClassExam`（在 `pages/CloudDb/` 以 `DatabaseObject` 子类定义）。Zone：`classData`。鉴权 provider：`@hw-agconnect/auth`。
- **AI 助手会话历史**：本地 preferences 双存储（见 AI_AGENT.md）。

## 抓取模式（Web Scraping）

用 `webview.WebviewController` 加载 EAMS 页面，通过 `controller.executeJavaScript()` 注入 JS。抓取脚本以 IIFE 字符串形式构建在 `WebScrapeService.ets`。注入后结果经 JSON 解析、由 model 类归一化、经 repository 持久化。重试与学期切换由 `CourseService` / `ExamService` / `GradeService` 处理。

> 抓取依赖 WebView，**无法 headless 执行**——所以 AI 助手的"导入课表/考试/成绩"只能跳转到对应导入页（`navigate_to_page`），不能直接触发抓取。

## 学期 / 周次 计算

- `model/classTableModel/CourseModel.ets` 的 `getCurrentWeek()` / `getWeekForDate(date)`：锚定到「含行课首日的那个自然周的周一」，按周一~周日对齐 `validWeeks`。
  - 当前锚点：`2026-08-31`（2026-2027 第一学期，行课首日 2026-09-01 周二所在周的周一）。开学前返回第 1 周。
- `model/classTableModel/ExamAccessRules.ets`：学期 ID 相对 base 503（2025-2026 第二学期）按 `startYear*2 + (termNumber-1)` 步长 20 计算。`calculateSemesterId(new Date())` 给出当前学期 ID。
- `AppConstants.SCHOOL_SEMESTER_START/END`：仅作文档用，**逻辑未引用**；真实周次计算在 `getCurrentWeek`。
- 课表数据结构：`activities` 是 84 元素数组（7 天 × 12 节），每个元素是 `RawActivity[]`。`validWeeks` 是二进制串，index 1+ 表示第 N 周（index 0 忽略）。

## 云集成

AGC 项目 `uestc_helper`（ID `YOUR_PROJECT_ID`）。Cloud DB schema 在 `CloudProgram/clouddb/`。云函数目录有 `id-generator`。app 内 `cloud_objects` 模块镜像 Cloud DB 对象类型。

## 重要约定

- `AppConstants.ets` 是所有偏好键 / URL / 魔法数字的**唯一来源**。
- Models 纯 TS、无 HarmonyOS 导入。
- 修改后**在 `Application/` 内** stage + commit，类型 `feat/fix/refactor/docs/chore`，消息以 `Co-Authored-By: Claude <noreply@anthropic.com>` 结尾。
- `.gitignore` 排除 `node_modules / oh_modules / build / .hvigor / .idea / .cxx`。
