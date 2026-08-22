# AI 助手子系统 (AI_AGENT.md)

> 架构模式：**后端 LangGraph 大脑（本地电脑）+ ArkTS 前端（统一控制引擎、数据查询引擎与页面感知伴随浮窗）**。
> 端侧机制：**统一控制引擎（Universal App Control Engine）**——收敛为 5 个核心原子元工具 + 4 个高阶感知控制工具 + 声明式流水线批处理器。

## 架构总览

```
手机(ArkTS / HarmonyOS)                     本地电脑(后端 ai-proxy)
┌──────────────────────────────────────┐     SSE ↓     ┌──────────────────────────────┐
│ AssistantPage.ets / FloatingWindow   │──────────────▶│ Express + LangGraph.js       │
│  ├─ 原生 Markdown 渲染 (MarkdownBubble)│               │  ├─ POST /api/chat -> SSE 流  │
│  ├─ 紧凑折叠工具面板 (Tool Collapse)   │               │  ├─ POST /api/vision/parse.. │
│  ├─ 遥测指标卡片 (Telemetry Metrics)  │               │  ├─ GET /api/knowledge/se.. │
│  ├─ 语音输入 (CoreSpeechKit)         │               │  ├─ StateGraph(Messages)      │
│  ├─ 智谱 GLM-4V 海报/通知日程识别    │               │  │   ├─ agentNode(DeepSeek)   │
│  ├─ 会话持久化 (ChatSessionRepository)│               │  │   └─ toolsNode(interrupt)  │
│  ├─ 页面感知 (PageContextTracker)    │               │  ├─ SqliteSaver 检查点持久化  │
│  ├─ UI动作总线 (UIActionDispatcher)  │               │  ├─ 智谱 GLM-4V (多模态视觉)  │
│  ├─ 统一确认弹窗 (动态风险鉴权)       │               │  ├─ CampusKnowledgeStore(RAG)│
│  └─ BackendAgentClient (SSE流式客户端)│    POST ↑     │  ├─ JWC 官网实时爬虫检索     │
│     ├─ ToolExecutor                  │──────────────▶│  └─ DeepSeek API (推理核心)  │
│     │   ├─ DataQueryEngine (多维过滤) │               └──────────────────────────────┘
│     │   ├─ CalendarKit (双向同步去重)│
│     │   └─ Pipeline 复合批处理器     │
│     └─ 本地 Preferences / 日历读写   │
└──────────────────────────────────────┘
```

- **大脑在后端**：LangGraph 编排、DeepSeek 推理、智谱 GLM-4V 视觉识别、CampusKnowledgeStore RAG 校园生活知识库、教务处官网实时检索、SQLite 持久化会话状态。手机端只发送最新增量消息（`{session_id, message}`），**历史完全由后端检查点管理**。
- **端侧统一控制引擎**：前端实现 `DataQueryEngine`（纯内存级全域多维过滤）与 `ToolExecutor` 批处理执行器。后端 `tools.ts` 仅需 Bind 核心元工具，执行时走 interrupt 挂起，端侧批量执行并回传结果。

---

## 统一控制元工具清单（5 大核心元工具）

### 1. `app_data_query`（统一数据智能查询器，Low 风险，无需确认）
- **功能**：统一查询 App 内所有核心数据（课表、考试、成绩/GPA、日程、系统日历、提醒配置、系统时间与教学周）。
- **参数**：
  - `domain`: `course` | `exam` | `grade` | `schedule` | `calendar` | `reminder_setting` | `system_info`
  - `filter`: 包含 `date` (YYYY-MM-DD), `week` (1-20), `dayOfWeek` (1-7), `keyword`, `teacher`, `room`, `upcomingOnly`, `semesterId`, `minGpa`, `maxGpa`, `type`, `startDate`, `endDate`
  - `limit`: 返回数量限制

### 2. `app_data_mutate`（统一数据变更器，Medium 风险，需端侧确认）
- **功能**：统一处理日程 CRUD（支持系统日历自动联动与双向删除）、系统日历事件删除、提醒配置变更。
- **参数**：
  - `domain`: `schedule` | `calendar` | `reminder_setting`
  - `action`: `create` | `update` | `delete`
  - `payload`: 载荷数据对象
  - `syncCalendar`: 是否同步写入系统日历（默认 `true`，具备唯一性查重）
  - `remindMinutesBefore`: 提前提醒分钟数（默认 `30`）

### 3. `app_control`（统一应用与系统控制，High 风险 / 页面跳转 Low 风险）
- **功能**：控制页面路由平滑导航（10 个主要页面）、云端同步/下载恢复、提醒数据全量重建刷新。
- **参数**：
  - `action`: `navigate` | `sync_cloud` | `download_cloud` | `refresh_reminders`
  - `params`: `{ page?: string, syncScope?: 'all'|'courses'|'exams' }`

### 4. `campus_search`（统一校园智搜，Low 风险，无需确认）
- **功能**：统一检索成电校园生活指南（校车时刻/缓考补考/保研/校医院/场馆）及教务处官网实时公告新闻。
- **参数**：
  - `query`: 检索问题或关键词
  - `source`: `guide` | `jwc_news` | `auto`
  - `category`: `bus` | `academic_policy` | `hospital` | `facilities` | `all`

### 5. `app_pipeline`（声明式复合流水线批处理，Medium 风险，需端侧确认）
- **功能**：当遇到多步复合任务时（如“查下周二空闲时间 ➔ 创建自习日程 ➔ 写入日历”），一次性下发有序原子步骤并在端侧顺序批量执行，极大降低网络往返延迟。
- **参数**：
  - `steps`: `[{ stepId: string, tool: string, args: object }, ...]`

---

## 智能辅助与页面感知控制工具

- `get_current_page_context`：获取手机当前活跃页面名称、数据快照与可用操作列表（Low 风险，无需确认）。
- `execute_page_action`：在当前页面执行 UI 动作（如自动切周、切换 Tab、触发教务导入、展示聚光灯高亮引导）（Low 风险，无需确认）。
- `generate_study_plan`：考前智能突击复习规划师（按考试科目倒计时加权分配每日复习任务）。
- `parse_text_to_schedule`：讲座/海报通知文本智能提取结构化日程。
- `search_jwc_news`：成电教务处官网实时公告爬取与摘要检索。

---

## 全局悬浮 AI 伴随助手（Floating Assistant）

- **SubWindow 独立子窗口架构 (`FloatingWindowManager.ets`)**：
  - 基于 HarmonyOS `windowStage.createSubWindow` 实现跨页面透明子窗口；
  - 严格生命周期管理：先调用 `setUIContent` 再配置尺寸与位置（规避 `1300002` 异常）。
- **双形态自由切换**：
  - **球态 (Ball Mode)**：60×60 vp 呼吸发光微型球，支持全屏自由拖拽与贴边吸附物理反馈；
  - **浮窗态 (Panel Mode)**：覆盖在当前页面的 Mini 助手卡片，右上角配备缩小 `[-]`、新对话 `[+]` 与关闭 `[X]`。
- **统一会话与历史管理 (`ChatSessionRepository.ets`)**：
  - 全屏助手与悬浮 Mini 助手共享同一套本地会话仓库，支持会话实时双向同步与独立新建。
- **状态同步与避让**：
  - 通过 `AppStorage` 实现悬浮球开关状态在全屏助手、应用设置页（`AppSettings.ets`）与浮窗本体之间的毫秒级双向同步；
  - 在全屏助手页自动避让隐藏，离开后自动恢复。

---

## 界面与渲染特性

- **原生 ArkTS Markdown 渲染引擎 (`MarkdownBubble.ets`)**：
  - 支持多级标题（# ~ ###）、粗体、行内代码、引用块、列表、代码块；
  - 智能排版：属性字段（`日期:`、`时间:`、`地点:`、`类型:`、`备注:`）自动换行，状态提示单独分段；
  - 全屏助手与悬浮 Mini 浮窗统一采用 `MarkdownBubble` 渲染。
- **紧凑折叠工具面板**：
  - 优雅的折叠行设计，支持状态指示、耗时与工具参数/结果一键展开查看。
- **Agent Telemetry 遥测指标**：
  - 在气泡底部展示流式耗时（ms）、Token 消耗估算与工具调用计数。

---

## 协议（SSE 下行 + HTTP POST 上行）

1. `POST /api/chat` `{session_id, message}` -> 后端开 SSE 流，事件类型：
   - `text_chunk` - LLM 增量文本
   - `tool_call` - `{batch_id, tool_calls:[{tool_call_id,name,args,requiresConfirmation}], ...}` 后端挂起等待工具结果
   - `final` - 正常结束（包含 tokens/latency 等遥测数据）
   - `error` - 错误
2. 手机收到 `tool_call`：按 `requiresConfirmation` 决定是否弹确认框；执行 `ToolExecutor.execute(name, args)`；把结果 `POST /api/tool-result` `{session_id, batch_id, results:[{tool_call_id,success,data}]}`。
3. 后端收到结果 -> `graph.stream(new Command({resume: results}), config)` 唤醒 `toolsNode`，继续推理。

---

## 加工具的标准三处同步流程

新增或修改工具必须**同时修改以下 3 处**，工具名称与入参必须保持严格一致：

1. **后端 Schema 与元数据**：`ai-proxy/src/tools.ts`（定义 tool schema 与 `toolMeta`：`requiresConfirmation` / `riskLevel`）。
2. **前端执行器**：`ToolExecutor.ets`（`switch(toolName)` 分发执行具体逻辑）。
3. **前端注册表**：`ToolRegistry.ets`（定义镜像用于端侧动态风险评级与确认弹窗判定）。

---

## 代码位置与调试

- **后端**（独立 git 仓库）：`C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`
  - `src/tools.ts` - 核心元工具与高阶工具定义
  - `src/prompt.ts` - 统一控制引擎提示词与场景示例
  - `src/graph.ts` - StateGraph（interrupt / resume 调度）
  - `src/knowledge/store.ts` - 成电校园生活指南 RAG 知识库
  - `src/jwc.ts` - 教务处官网实时检索
  - `src/vision.ts` - 智谱 GLM-4V 多模态日程识别接口
  - `test/phone-sim.mjs` - 端侧元工具与 Pipeline 模拟联调脚本
- **前端**（根仓库 `D:\harmony\helper_app`）：`entry/src/main/ets/common/agent/`
  - `BackendAgentClient.ets` - SSE 流式客户端
  - `DataQueryEngine.ets` - 统一内存数据多维查询引擎
  - `ToolExecutor.ets` - 元工具分发、数据变更与 Pipeline 执行器
  - `ToolRegistry.ets` - 工具元数据与动态风险判定
  - `FloatingWindowManager.ets` - SubWindow 全局悬浮窗管理
  - `PageContextTracker.ets` - 页面活跃状态与数据感知中心
  - `UIActionDispatcher.ets` - 页面 UI 动作分发总线
  - `ChatSessionRepository.ets` - 统一会话存储中心
  - `VisionScheduleHelper.ets` - 智谱视觉海报提取调用
  - `components/agent/MarkdownBubble.ets` - 原生 ArkTS Markdown 渲染气泡
  - `pages/quick/AssistantPage.ets` - 全屏 AI 助手主页面
- **调试日志前缀**：`[BackendAgentClient]` / `[CalendarKit]` / `[ReminderDebug]` / `[ExamDebug]` / `[HomeDebug]` / `[FloatingWindow]`。
