# 变更日志 (CHANGES.md)

记录 UESTC Helper（成电校园助手）的重大演进、功能重构、架构演进与特性落地记录。

---

## 2026-08: 华为应用市场上架合规与端云体验 8 大核心优化

- **1. 首次启动隐私授权弹窗与 SDK 延迟初始化 (`PrivacyDialogComponent.ets`, `AuthService.ets`, `EntryAbility.ets`)**：
  - 移除非法自启第三方 SDK 行为，增加启动阶段合规弹窗展示权限用途并提供《用户服务协议》与《隐私政策》长文本详情查阅；
  - 用户点击「同意」后持久化状态并执行 `AuthService.initSDK()` 延迟初始化，点击「不同意」安全退出应用。
- **2. 包名与元信息规范化 (`app.json5`, `string.json`)**：
  - 统一规范应用厂商 `vendor: "uestc_campus"`、应用显示名 `成电助手` 与 EntryAbility 描述信息。
- **3. 账号注销全量清空 (`AccountManage.ets`, `AppSettings.ets`, `AuthService.ets`)**：
  - 在账号管理与设置页中新增「注销账号」危险操作，配备二次确认风险弹窗；
  - 一键登出云端账号并彻底清空本地用户凭据（`classtable_login_pref`）、业务数据库（`course_table_local_db`）及 AI 会话历史（`chat_sessions_db` / `chat_messages_db`）。
- **4. 生成式 AI 内容免责声明 (`AssistantPage.ets`, `FloatingSubWindowContent.ets`)**：
  - 依据《生成式人工智能服务管理暂行办法》，在全屏 AI 助手页与全局悬浮 Mini 助手底部常驻展示「⚠️ AI 生成内容仅供参考，课程与考试安排请以教务处官方系统为准」。
- **5. 权限动态按需申请 (`PermissionHelper.ets`)**：
  - 封装 `PermissionHelper`，将日历读写等敏感权限统一收归为触发操作时按需申请，并提供用户拒绝后的友好引导。
- **6. 大模型 API 防盗刷与安全加固 (`ai-proxy/src/security.ts`, `BackendAgentClient.ets`)**：
  - 后端引入 HMAC-SHA256 请求签名校验、5 分钟 Anti-Replay Nonce 防重放、IP 滑动窗口限流（对话 30 次/分，视觉 10 次/分）及 4000 字符 Payload 边界防护；端侧自动注入安全请求头。
- **7. 教务认证异常与验证码全屏手动接管 (`WebScrapeTakeoverBar.ets`, `Index.ets`, `ExamImport.ets`, `GradeImport.ets`)**：
  - 封装通用手动接管条 `WebScrapeTakeoverBar`，在课表、考试、成绩抓取中遇到统一身份认证、滑块验证码或异常时自动解除遮罩，允许用户手动操作后一键「立即抓取当前页」。
- **8. 多学期课表归档与离线切换 (`CourseRepository.ets`, `CourseService.ets`, `tableUI.ets`, `CourseManage.ets`)**：
  - 课表页学期下拉菜单实时展示各学期归档课程门数，切换已归档学期支持秒级离线渲染；切换未导入学期展示友好空状态与一键导入入口；本地课表管理支持针对各学期独立维护。

---

## 2026-08: 日程日历唯一性保证与双向联动同步

- **系统日历（CalendarKit）去重与唯一性保证 (`CalendarKitReminderService.ets`)**：
  - 修复向系统日历写入日程时可能发生的重复事件问题；
  - 建立唯一事件键与本地映射校验，防止重复点击或多端同步导致的日历事件冗余。
- **双向联动与状态一致性删除 (`ScheduleService.ets`, `ToolExecutor.ets`)**：
  - 在删除本地日程（`deleteSchedule` / `app_data_mutate`）时，自动检索并同步清除系统日历中关联的 Calendar Event；
  - 保证本地数据库（Preferences）与 HarmonyOS 系统日历状态始终严格一致。

---

## 2026-08: 原生 Markdown 渲染组件与浮窗富文本适配

- **ArkTS 原生 Markdown 渲染引擎 (`MarkdownBubble.ets`)**：
  - 纯原生 ArkTS 实现 Markdown 解析与排版渲染，支持标题（# ~ ### 多级标题与紧凑间距）、粗体、行内代码、引用块、有序/无序列表及代码块。
  - 优化段落智能换行：支持紧凑属性文本（如 `日期:`、`时间:`、`地点:`、`类型:`、`备注:`）自动换行排版，以及操作状态提示（如 `已同步至系统日历`）独立分段。
- **全局悬浮 Mini 助手 Markdown 适配 (`FloatingSubWindowContent.ets`)**：
  - 将悬浮 Mini 助手的原始 Text 替换为 `MarkdownBubble` 组件，实现全屏与浮窗统一的高质量排版体验。
- **紧凑折叠工具调用面板 (Tool Call Collapse UI)**：
  - 借鉴现代 Agent 交互设计（如 Claude Code / Antigravity），对工具调用和执行结果提供优雅的紧凑折叠指示条，支持实时状态旋转、执行耗时显示与一键展开明细。
- **Agent 遥测性能指标 (Telemetry Metrics)**：
  - 在 AI 回复气泡底部展示流式推理耗时（ms）、Token 消耗估算与工具调用计数指标卡片。

---

## 2026-08: 前端界面体验与多端 UI 细节深度优化

- **课表网格 (`tableUI.ets`)**：
  - 新增实时当前时间线指示器（Current Time Indicator），直观标明当前所处节次；
  - 修复 AI 助手课程卡片宽度溢出与过长课名折叠问题。
- **AI 助手欢迎页 (`AssistantPage.ets`)**：
  - 新增快捷场景胶囊按钮（Prompt Chips：`查今天课表` / `查最近考试` / `查GPA` / `查校车时刻` / `建自习日程`），一键快速交互。
- **考试卡片 (`ExamPage.ets`, `ExamCountdownCard.ets`)**：
  - 新增紧急考试倒计时（<24h）呼吸高亮视觉动效与考场地图快捷入口。
- **成绩页 (`GradePage.ets`)**：
  - 升级 GPA 概览 Hero 仪表盘卡片与分类成绩卡片流。
- **日历页 (`CalendarPage.ets`)**：
  - 优化月视图事件标记点排布，防止多事件圆点超出单元格边界。

---

## 2026-08: 全局悬浮 AI 伴随助手与会话统一持久化

- **会话统一持久化中心 (`ChatSessionRepository.ets`)**：
  - 统一全屏助手页（`AssistantPage`）与悬浮 Mini 助手（`FloatingSubWindowContent`）的会话存储与消息历史。
  - 悬浮窗顶部新增「➕ 新对话」按钮，点击立即重置上下文并给出即时 Toast 提示。
- **多端开关状态联动**：
  - 基于 `AppStorage` 实现悬浮球开关状态在全屏助手侧边栏、应用设置页（`AppSettings.ets`）与悬浮窗本体之间的毫秒级双向同步与持久化（`setting_floating_ball_enabled`）。
- **HarmonyOS 子窗口架构 (`FloatingWindowManager.ets`)**：
  - 基于 `windowStage.createSubWindow` 实现全局跨页面透明子窗口；
  - **球态 (Ball Mode)**：60×60 vp 发光呼吸球，支持自由全屏拖拽与贴边吸附物理反馈；
  - **浮窗态 (Panel Mode)**：覆盖在当前页面的 Mini 助手卡片，右上角配备 `[-]` 缩小至悬浮球与 `[X]` 关闭悬浮球；
  - 修复子窗口初始化生命周期（必须先 `setUIContent` 再配置尺寸与位置，规避 `1300002` 错误码）与 CalendarKit 权限前置检查（规避 `201` 拒绝异常）。
- **页面上下文感知与 UI 动作总线 (`PageContextTracker.ets`, `UIActionDispatcher.ets`)**：
  - 课表、成绩、考试及首页各 Tab 实时向感知中心上报数据快照；
  - Mini 助手与后端 Agent 对话时自动注入当前页面快照，赋予 AI 敏锐的实时感知能力；
  - 支持通过 `execute_page_action` 直接控制页面切周、切换 Tab、触发数据导入或展示高亮聚光灯引导（Spotlight Guidance）。

---

## 2026-08: 教务系统登录与导入状态机健壮性升级

- **统一身份认证状态机优化**：
  - 修复用户输入凭证阶段提前自动跳转问题，在输入账号密码时暂停自动跳转逻辑；
  - 修复多设备重复登录拦截提示（`home.action`）时明文 HTTP 导致的会话丢失，使用原生 `loadUrl` 自动确认放行。
- **全链路 HTTP 500 容错与重试**：
  - 课表与成绩导入全链路增加 HTTP 500 自动重试与指数退避机制，大幅提升弱网/高峰期教务导入成功率。
- **动态学期计算与 GPA 过滤**：
  - 成绩筛选支持相邻上下 10 学期动态换算，默认回退至已出分学期（base 503），修复历史成绩动态学期解析与 GPA 绩点分母计算逻辑。

---

## 2026-08: 统一控制引擎与内存数据查询引擎

- **统一端侧元工具架构 (Universal App Control Engine)**：
  - 将过去 33+ 个分散原子工具收敛为 **5 大核心元工具**（`app_data_query`, `app_data_mutate`, `app_control`, `campus_search`, `app_pipeline`）与 4 大高阶辅助工具（`get_current_page_context`, `execute_page_action`, `generate_study_plan`, `parse_text_to_schedule`）。
  - 新增教务处官网实时公告抓取工具（`search_jwc_news`）。
- **纯内存级多维查询引擎 (`DataQueryEngine.ets`)**：
  - 接管课表、考试、成绩、日程、系统日历、提醒配置与教学周系统信息，支持日期/周次换算、GPA 实时计算与多维组合过滤。
- **声明式复合流水线批处理 (`executePipeline`)**：
  - 支持端侧顺序批处理多步复合指令（如查空闲 ➔ 创日程 ➔ 写日历），彻底消除多轮网络往返。

---

## 2026-08: 评奖升级与多模态智能体演进

- **交互多模态化（语音 ASR + 智谱视觉日程识别）**：
  - **鸿蒙原生语音识别 (CoreSpeechKit)**：引入 `SpeechRecognizerHelper.ets` 对接 `@kit.CoreSpeechKit`，输入栏集成「🎙️ 语音输入」。
  - **智谱 GLM-4V 多模态海报/截图日程提取**：后端接入 `glm-4v-plus` 视觉大模型（`src/vision.ts`），前端通过 `VisionScheduleHelper.ets` 免权限选择图片并自动提取日程。
- **成电深度场景 RAG 知识库解耦 (`CampusKnowledgeStore`)**：
  - 后端模块化知识库：`bus_schedule.json`（班车）、`academic_policy.json`（缓考/补考/保研GPA）、`hospital_guide.json`（校医院/医保）、`facilities_guide.json`（图书馆/场馆）、`campus_life.json`（一卡通/水电/校园网）。
- **鸿蒙桌面万能服务卡片 (Widget)**：
  - 声明 `EntryFormAbility`，支持 2x2 与 2x4 万能课表服务卡片，倒计时下节课并支持点击直达。
- **折叠屏与平板一多自适应**：
  - `BreakpointUtils.ets` 监听窗口断点（sm/md/lg），首页解耦为四大子组件（`HomeHeaderComponent`、`NextCourseCardComponent`、`ExamCountdownCard`、`QuickLinksGrid`），自适应呈现双栏/多列栅格。

---

## 2026-08: 首页五 Tab 架构重构

- 主界面重构为五大 Tab：**发现（Quick）/ AI助手（Assistant）/ 课程（Class）/ 日历（Calendar）/ 我的（Mine）**。
- 今日课程卡片增加门数文案与切换图标（`switch.svg`），点击可自由在课程与考试倒计时卡片之间切换。
- 我的页新增意见反馈弹窗（支持一键复制开发者邮箱 `pjj644@users.noreply.github.com`）与版本信息展示。

---

## 2026-08: 仓库根目录迁移与工程级工具链升级

- **Git 仓库根目录迁移**：仓库根迁移至 `D:\harmony\helper_app`，统一纳管 `Application/`、`CloudProgram/`、`doc/`、脚本及素材。
- **官方 DevEco CLI 与 MCP 接入**：集成 `@deveco/deveco-cli`（`devecocli`）与 `deveco-mcp`（ArkTS/C++ LSP 静态诊断），提供根目录标准构建批处理脚本（`_build.bat`、`_clean_build.bat`、`_lint.bat`）。
