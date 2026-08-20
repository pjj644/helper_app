# 变更日志 (CHANGES.md)

记录 UESTC Helper 的重大演进、功能重构与特性落地记录。

---

## 2026-08: 全局悬浮 AI 伴随助手与页面级感知控制

### 1. 全局悬浮球与 Mini 覆盖浮窗 (Floating Window SubSystem)
- **HarmonyOS 子窗口架构 (`FloatingWindowManager.ets`)**：
  - 基于 `windowStage.createSubWindow` 实现全局跨页面透明子窗口，支持应用内多级路由无缝悬浮。
  - **球态 (Ball Mode)**：60×60 vp 发光呼吸球，支持自由全屏拖拽与贴边吸附物理反馈。
  - **浮窗态 (Panel Mode)**：点击展开为覆盖在当前页面的 Mini 助手卡片，右上角配备 `[-]` 缩小至悬浮球与 `[X]` 关闭悬浮球，支持精简对话、语音输入与快捷感知胶囊。
  - **智能避让与开关持久化**：在全屏 AI 助手页（`AssistantPage`）自动避让隐藏，离开后自动恢复；在助手侧边栏与应用设置中提供独立开关（`setting_floating_ball_enabled`）。

### 2. 页面上下文感知引擎 (`PageContextTracker.ets`)
- 建立全局页面感知快照中心，课表网格（`tableUI`）、成绩查询（`GradePage`）、考试安排（`ExamPage`）以及首页各 Tab 实时上报当前展示数据（选中的周次/课程数/GPA/倒计时）与可用操作集合。
- Mini 助手与后端 Agent 对话时自动注入当前页面实时数据快照，赋予 AI 敏锐的当前页面感知能力。
- 新增 `get_current_page_context` 元工具，前后端三处同步。

### 3. UI 动作与视觉引导执行器 (`UIActionDispatcher.ets`)
- 建立 UI 指令分发总线，支持 AI 通过 `execute_page_action` 直接触发页面动作（如自动切周、触发教务数据导入、切换Tab等）。
- 支持聚光灯高亮视觉引导（Spotlight Guidance），为用户提供直观的操作指引。

---

## 2026-08: 评奖升级与多模态智能体演进

### 1. 交互多模态化（语音 ASR + 智谱视觉日程识别）
- **鸿蒙原生语音识别 (CoreSpeechKit)**：
  - 引入 `SpeechRecognizerHelper.ets`，对接 `@kit.CoreSpeechKit` (`speechRecognizer`) 短语音转写引擎，支持流式识别与优雅降级。
  - 在 `AssistantPage.ets` 输入栏集成「🎙️ 语音输入」按钮，按住/点击说话实时将语音转写成文本上屏。
- **智谱 GLM-4V 多模态海报/截图日程提取**：
  - 后端接入智谱开放平台 `glm-4v-plus` 视觉大模型（`src/vision.ts`），提供 `/api/vision/parse-schedule` 接口。
  - 前端开发 `VisionScheduleHelper.ets`，通过 `PhotoViewPicker` 免权限选择讲座海报、群通知截图并提取结构化日程，自动在对话中生成日程确认卡片。

### 2. 成电深度场景 RAG 知识库解耦与可扩充架构
- **解耦知识库检索引擎**：
  - 后端实现 `CampusKnowledgeStore`（`src/knowledge/store.ts`），支持分类筛选与多关键词匹配评分检索，暴露 `/api/knowledge/search` 接口。
- **模块化 JSON 知识库**：
  - `bus_schedule.json`：清水河 ⇋ 沙河 工作日/周末班车时刻与上车点。
  - `academic_policy.json`：本科生缓考/补考/重修、免修申请与保研推免学分绩点（GPA）计算细则。
  - `hospital_guide.json`：校医院 24h 急诊、门诊就医与大学生医保报销流程。
  - `facilities_guide.json`：清水河/沙河图书馆借阅、自习室预约与体育馆/游泳馆开放指南。
  - `campus_life.json`：一卡通充值、宿舍水电费缴纳与校园网 WebVPN 指南。

### 3. 鸿蒙桌面万能服务卡片（Widget）
- 在 `module.json5` 中声明 `EntryFormAbility`，定义 `form_config.json` 支持 2x2 与 2x4 卡片。
- 实现 `EntryFormAbility.ets` 与 `CourseWidgetCard2x2.ets`，展示下节课倒计时、教室与时间，点击通过 `postCardAction` 直达应用内。
- 在 `CourseService.ets` 中加入 `updateNextCourseCache` 自动维护本地 Preferences 缓存。

### 4. 折叠屏与平板一多自适应与主页解耦
- 创建 `BreakpointUtils.ets` 监听窗口尺寸变化（sm/md/lg 断点）。
- 拆解主页为 `HomeHeaderComponent.ets`、`NextCourseCardComponent.ets`、`ExamCountdownCard.ets`、`QuickLinksGrid.ets` 四大独立子组件。
- 主页在手机端展示紧凑单栏滑动流，在折叠屏/平板端自适应呈现多栏双轴联动栅格布局。

---

## 2026-08: AI 助手后端 LangGraph 架构重构

- 将 AI 助手大脑迁移至后端 `ai-proxy`（LangGraph + DeepSeek + SQLite Checkpointer）。
- 规范化「三处同步加工具」标准流程（后端 `src/tools.ts`、前端 `ToolRegistry.ets`、前端 `ToolExecutor.ets`）。
- 手机端重构为 `BackendAgentClient` 薄客户端，支持 typed SSE 事件流解析与工具中断确认恢复机制。
