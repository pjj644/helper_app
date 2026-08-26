# 项目架构 (ARCHITECTURE.md)

> UESTC Helper（成电校园助手）的代码结构、分层设计与数据流。给接手代码的人 / 下一个 AI 快速定位用。
> AI 助手子系统详细规格见 [AI_AGENT.md](./AI_AGENT.md)；构建与测试见 [BUILD_AND_TEST.md](./BUILD_AND_TEST.md)；精简上手入口见根目录 [`../AGENTS.md`](../AGENTS.md)。

## 总览

HarmonyOS（ArkTS，stage model，API 6.0.2/22）端云一体应用。通过 WebView JS 注入抓取教务系统（EAMS）的课表 / 考试 / 成绩，本地存储（preferences），并同步到华为 Cloud DB。内含 AI 助手（后端 LangGraph 大脑 + 设备端统一控制引擎与数据查询引擎）。

两个顶层目录：

- **`Application/`** — HarmonyOS app（ArkTS）。源码在 `entry/src/main/ets/`。
- **`CloudProgram/`** — 云端 Node.js（Cloud DB schema、云函数）。

**git 仓库在项目根目录 `D:\harmony\helper_app`**（2026-08 由 `Application/` 内迁移而来，历史保留，所有项目文件统一入库；`information/` 抓取存档不入库）。根目录包含：`AGENTS.md` 统一上手指南、`doc/` 本文档集、`icon/` 素材。

## 分层（`Application/entry/src/main/ets/`）

```
pages/          -> UI 页面（@Entry / @Component）
                   ├─ Index.ets (主框架：五 Tab 结构)
                   ├─ classTablePages/ (课表网格 tableUI, 考试 ExamPage, 导入与管理 CourseManage 含 GLM-4V 截图导入, 设置 AppSettings, 内嵌网页 WebPage)
                   ├─ gradePages/ (成绩 GradePage 含 GLM-4V 截图导入, 导入 GradeImport)
                   ├─ schedulePages/ (日历 CalendarPage, 班车时刻表 BusSchedulePage, 新建/编辑日程)
                   ├─ quick/ (发现门户 quickIndex, AI 助手全屏页 AssistantPage)
                   └─ login/ (登录与统一身份认证 loginIndex)
components/     -> 可复用 UI 组件
                   ├─ home/ (主页解耦子组件：Header, NextCourseCard, ExamCountdownCard, QuickLinksGrid)
                   ├─ agent/ (原生 Markdown 渲染气泡 MarkdownBubble, 遥测指标卡片, 紧凑折叠工具面板)
                   ├─ PrivacyDialogComponent.ets (首次启动合规隐私授权弹窗)
                   ├─ WebScrapeTakeoverBar.ets (教务抓取全屏手动接管控制条)
                   └─ common/ (主题切换、高亮聚光灯遮罩等)
entryformability/ -> 鸿蒙桌面万能服务卡片生命周期服务 (EntryFormAbility.ets)
widget/pages/   -> 鸿蒙桌面卡片 UI 组件
                   ├─ CourseWidgetCard2x2.ets (2x2 下一节课倒计时与地点卡片)
                   └─ CourseWidgetCard2x4.ets (2x4 今日全天排期与状态时间线卡片)
service/        -> 业务逻辑（auth / scrape / sync / reminder / 各数据服务）
                   ├─ AuthService.ets (AGC 认证延迟初始化、账号注销与凭证彻底清空)
                   ├─ CourseService.ets / ExamService.ets / GradeService.ets
                   ├─ ScheduleService.ets (日程管理与系统日历双向联动删除)
                   ├─ CalendarKitReminderService.ets (HarmonyOS 系统日历写入、班车/考试去重与事件查询)
                   ├─ ReminderService.ets (应用内通知代理、提醒分类开关/提前量与日历兜底)
                   ├─ SyncService.ets (Cloud DB 双向同步，云端记录带 updatedAt 支持 LWW 冲突裁决)
                   └─ WebScrapeService.ets (EAMS 教务系统 WebView JS 注入抓取)
repository/     -> 数据持久化（Preferences 键值存储、Cloud DB、会话仓库）
                   ├─ CourseRepository (多学期归档查询、多学期独立存储与删除)
                   ├─ ExamRepository / GradeRepository / ScheduleRepository
                   ├─ ChatSessionRepository.ets (统一管理全屏助手与悬浮 Mini 助手的会话与消息历史)
                   ├─ SettingsRepository.ets (应用设置与助手后端地址)
                   └─ CloudDbRepository.ets (华为云数据库)
model/          -> 数据模型 + 纯数据变换（解析/过滤/排序，严禁 `@kit.*` 导入）
                   ├─ classTableModel/ (CourseModel, ExamModel, ExamAccessRules)
                   ├─ BusScheduleModel.ets (纯 TS 双校区班车时刻与倒计时算法)
                   ├─ GradeModel.ets / ScheduleModel.ets / ReminderModel.ets
                   └─ agent/ (ToolCall, ToolResult, ChatMessage, TelemetryMetrics)
common/         -> 共享基础设施
                   ├─ agent/ (统一控制引擎与智能体端侧执行层)
                   │  ├─ BackendAgentClient.ets (SSE 流式长连接、安全请求头注入与事件分发)
                   │  ├─ DataQueryEngine.ets (纯内存多维数据过滤与统一查询引擎)
                   │  ├─ ToolExecutor.ets (5 大元工具、流水线批处理、日历一致性执行与校园指南四级降级缓存)
                   │  ├─ ToolRegistry.ets (元数据定义与动态风险判定)
                   │  ├─ FloatingWindowManager.ets (HarmonyOS SubWindow 全局悬浮球与 Mini 浮窗生命周期)
                   │  ├─ PageContextTracker.ets (全局页面活跃状态与数据快照感知中心)
                   │  ├─ UIActionDispatcher.ets (页面 UI 动作与高亮聚光灯指令总线)
                   │  └─ VisionScheduleHelper.ets (智谱 GLM-4V 视觉识别：海报日程提取 + 课表/成绩单截图导入)
                   ├─ speech/ (CoreSpeechKit 原生语音转写 SpeechRecognizerHelper)
                   ├─ constants/AppConstants.ets (所有偏好键 / URL / 魔法数字的唯一来源)
                   └─ utils/ (PermissionHelper, Logger, ThemeManager, DateUtils, BreakpointUtils)
```

**核心铁律**：
- **数据流**：Pages → Service → Repository → Preferences / Cloud DB
- **Models 是纯 TS**（禁止任何 `@kit.*` 导入），只做数据建模、字符串/JSON 解析、内存级排序与纯计算。
- **所有常量唯一收纳于 `AppConstants.ets`**，严禁在业务逻辑中散落硬编码 URL 或魔法字符串。

## 导航与五 Tab 结构

应用底部采用现代化五 Tab 架构（`pages/Index.ets`）：
1. **发现 (Quick)**：校内常用系统门户（「云中成电」Hero Banner 推广位、校园地图、清水河畔、图书馆等）与「成电班车」时刻表入口。
2. **AI助手 (Assistant)**：全屏多模态智能体交互界面（集成打字机流式 Markdown 渲染、超链接拦截内嵌直达、语音输入、海报提取与快捷场景胶囊）。
3. **课程 (Class / Home)**：课表主仪表盘，包含周网格课表、今日课程卡片（支持点击右上角图标自由切换为考试倒计时卡片）。
4. **日历 (Calendar)**：统一事件日历，聚合课程、考试与自定义日程，支持月视图、列表视图与日程快速新建。
5. **我的 (Mine)**：账号登录态、华为云同步、悬浮球设置、助手后端配置、意见反馈（一键复制开发者邮箱 `pjj644@users.noreply.github.com`）与版本关于信息。

页面跳转统一走 `router.pushUrl`，路由常量集中定义在 `AppConstants.RouterConstants`。对于外部 HTTP 链接统一唤起 `pages/classTablePages/WebPage` 内嵌原生顶栏浏览器打开。

## 鸿蒙桌面万能服务卡片（Form Widget）

应用支持两种规格的桌面服务卡片（`form_config.json`）：
- **2x2 卡片 (`CourseWidgetCard2x2.ets`)**：展示最近一门待上课程、教室地点以及距上课实时倒计时，已无课状态自动展示友好提示。
- **2x4 卡片 (`CourseWidgetCard2x4.ets`)**：全天排期时间线卡片，展示今日 1-12 节多时段课程安排与「上课中 / 未开始 / 已结束」实时状态指示。
- **生命周期与静默刷新**：`EntryFormAbility.ets` 处理卡片添加与周期更新，`CourseService.updateNextCourseCache` 在课表发生任何增删改或导入时计算富状态并持久化至 `next_course_cache`，支持桌面卡片毫秒级无感静默更新。

## 双校区班车时刻与日历联动模块

- **纯 TS 班车算法 (`BusScheduleModel.ets`)**：内嵌清水河与沙河工作日（各 18 班）及周末（各 10 班）全量时刻表，支持动态计算下一班车倒计时与明日首班车预测。
- **班车页面 (`BusSchedulePage.ets`)**：双向校区一键切换（清水河 ➔ 沙河 / 沙河 ➔ 清水河）、Hero 下一班发车倒计时卡片、时刻表全览与乘车指南。
- **日历提醒联动 (`CalendarKitReminderService.createBusReminder`)**：支持为任意班次一键设置发车前 15 分钟 HarmonyOS 系统日历提醒，具备同日期同方向同发车点强力去重机制。

## 全局悬浮伴随助手与页面感知子系统

- **SubWindow 架构**：`FloatingWindowManager` 利用 `windowStage.createSubWindow` 在主窗口之上拉起独立透明子窗口。
  - **球态 (Ball Mode)**：60×60 vp 呼吸发光微型球，支持全屏自由拖拽与左右边缘智能吸附；
  - **浮窗态 (Panel Mode)**：覆盖在当前页面之上的 Mini 助手卡片，支持流式 Markdown 对话、语音识别与感知胶囊，顶部配备缩小 `[-]`、新对话 `[+]` 与关闭 `[X]`。
- **页面感知中心 (`PageContextTracker`)**：各页面（课表、考试、成绩、首页各 Tab）在 `onPageShow` 或数据变更时上报当前活跃数据快照与可用操作集合。
- **UI 动作总线 (`UIActionDispatcher`)**：支持 AI 直接下发指令控制页面（如自动切周、触发教务导入、切换 Tab、聚光灯遮罩引导）。
- **统一会话中心 (`ChatSessionRepository`)**：全屏助手与悬浮窗共享同一套会话列表与持久化历史，支持无缝切换与一键新建。

## 数据存储与日历双向同步

- **本地存储**：全部基于 `@kit.ArkData` 的 `preferences`。
  - `classtable_login_pref`：用户认证与凭据；
  - `course_table_local_db`：应用全量业务数据（课表、考试、成绩、日程、设置、桌面卡片缓存等）；
  - `chat_sessions_db` / `chat_messages_db`：AI 对话历史与会话元数据。
- **系统日历双向同步 (`CalendarKitReminderService`)**：
  - 接入 HarmonyOS `@kit.CalendarKit`；
  - 写入日程/班车/考试时支持自动查重与唯一性校验，防止重复事件冗余；
  - 删除日程时自动联动清除系统日历关联事件，维持双向严格一致。
- **云端存储**：华为 Cloud DB（Zone: `classData`），对象类型 `ClassCourse`、`ClassExam`（继承 `DatabaseObject`），鉴权走 `@hw-agconnect/auth`。

## 抓取模式与教务状态机 (Web Scraping)

通过 `webview.WebviewController` 加载 EAMS 教务系统，注入 `WebScrapeService.ets` 构建的 IIFE JavaScript 抓取脚本。
- **登录状态机**：优先识别统一身份认证（CAS / IDAS）输入凭据阶段，未完成登录前暂停自动跳转，等待用户认证通过。
- **500 与会话恢复机制**：全面识别多设备登录踢出、会话失效以及包含 `[点击此处](http://eams.uestc.edu.cn/eams/home.action)` 或返回 HTTP 500 状态码的异常。收到 500 时先自动导航至 `home.action` 激活教务系统主 Session，待主站确立登录态后再平滑跳转至课表（`courseTableForStd.action`）、考试或成绩页面进行数据提取，避免二级子页面连续 500 死循环。
- **非 Headless 约束**：抓取依赖真实 WebView 渲染，AI 助手导入操作通过 `app_control` (`navigate`) 跳转到对应导入页完成。

## 学期 / 周次 计算

- `CourseModel.ets` 的 `getCurrentWeek()` / `getWeekForDate(date)`：锚定到「含行课首日的那个自然周的周一」，周一至周日严格对齐 84 槽位 `validWeeks`。
  - 当前学期锚点：`2026-08-31`（2026-2027 第一学期，行课首日 2026-09-01 周二所在周的周一）。开学前返回第 1 周。
- `ExamAccessRules.ets`：学期 ID 相对 base 503（2025-2026 第二学期）按 `startYear*2 + (termNumber-1)` 步长 20 动态计算。
- 成绩学期筛选支持相邻上下 10 学期动态换算，默认自动回退至已出分学期（503）。
