# AI 助手子系统 (AI_AGENT.md)

> 当前架构：**后端 LangGraph 大脑（本地电脑）+ ArkTS 前端（统一控制引擎与数据查询引擎）**。
> 演进方案：**统一控制引擎（Universal App Control Engine）**——将原 33+ 分散硬编码工具收敛为 4 个全能原子元工具 + 1 个声明式流水线执行器。

## 架构

```
手机(ArkTS)                           本地电脑(后端 ai-proxy)
┌──────────────────────────┐         ┌──────────────────────────────┐
│ AssistantPage.ets        │  SSE ↓  │ Express + LangGraph.js       │
│  ├─ 语音输入(CoreSpeech) │────────▶│  ├─ POST /api/chat -> SSE 流  │
│  ├─ 拍照/相册海报识别    │         │  ├─ POST /api/vision/parse.. │
│  ├─ 会话/历史/气泡 UI    │         │  ├─ GET /api/knowledge/se.. │
│  ├─ 统一确认弹窗         │         │  ├─ StateGraph(Messages)      │
│  └─ BackendAgentClient   │  POST ↑ │  │   ├─ agentNode(DeepSeek)   │
│     ├─ SSE 解析          │────────▶│  │   └─ toolsNode(interrupt)  │
│     ├─ ToolExecutor      │         │  ├─ SqliteSaver 检查点        │
│     │   ├─ DataQueryEngine│        │  ├─ 智谱 GLM-4V (多模态视觉)  │
│     │   └─ Pipeline 批处理│        │  ├─ CampusKnowledgeStore(RAG)│
│     └─ 读写手机本地数据  │         │  └─ DeepSeek API (推理核心)  │
└──────────────────────────┘         └──────────────────────────────┘
```

- **大脑在后端**：LangGraph 编排、DeepSeek 推理、智谱 GLM-4V 视觉识别、CampusKnowledgeStore RAG 知识检索、SQLite 持久化会话状态。手机只发用户新消息（`{session_id, message}`），**历史由后端检查点管理**。
- **端侧统一控制引擎**：前端实现 `DataQueryEngine`（内存级通用数据多维过滤）与 `ToolExecutor` 批处理执行器。后端 `tools.ts` 仅需 Bind 5 个核心元工具，执行时走 interrupt，端侧批量执行并回传结果。

## 统一控制元工具清单（5 大核心工具）

### 1. `app_data_query`（统一数据智能查询器，Low 风险，无需确认）
- **功能**：统一查询 App 内所有核心数据（课表、考试、成绩/GPA、日程、系统日历、提醒配置、系统时间与教学周）。
- **参数**：
  - `domain`: `course` | `exam` | `grade` | `schedule` | `calendar` | `reminder_setting` | `system_info`
  - `filter`: 包含 `date` (YYYY-MM-DD), `week` (1-20), `dayOfWeek` (1-7), `keyword`, `teacher`, `room`, `upcomingOnly`, `semesterId`, `minGpa`, `maxGpa`, `type`, `startDate`, `endDate`
  - `limit`: 返回数量限制

### 2. `app_data_mutate`（统一数据变更器，Medium 风险，需端侧确认）
- **功能**：统一处理日程 CRUD（支持系统日历自动联动）、系统日历事件删除、提醒配置变更。
- **参数**：
  - `domain`: `schedule` | `calendar` | `reminder_setting`
  - `action`: `create` | `update` | `delete`
  - `payload`: 载荷数据对象
  - `syncCalendar`: 是否同步写入系统日历（默认 `true`）
  - `remindMinutesBefore`: 提前提醒分钟数（默认 `30`）

### 3. `app_control`（统一应用与系统控制，High 风险 / 页面跳转 Low 风险）
- **功能**：控制页面路由导航、云端同步/下载恢复、提醒数据全量重建刷新。
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
- **功能**：当遇到多步复合任务时（如“查下周二空闲时间 ➔ 创建自习日程 ➔ 写入日历”），一次性生成有序原子步骤并在端侧顺序批量执行，极大降低网络往返延迟。
- **参数**：
  - `steps`: `[{ stepId: string, tool: string, args: object }, ...]`

---

## 智能辅助与页面控制工具
- `generate_study_plan` - 考前智能突击复习规划师（按考试科目倒计时加权分配每日复习任务）
- `parse_text_to_schedule` - 讲座/海报通知文本提取日程
- `get_current_page_context` - 获取手机当前活跃页面名称、数据快照与可用操作列表（Low 风险，无需确认）
- `execute_page_action` - 在当前页面执行 UI 动作（如自动切周、切换Tab、触发导入、高亮聚光灯引导）（Low 风险，无需确认）

---

## 全局悬浮 AI 伴随助手（Floating Assistant）
- **SubWindow 独立子窗口**：通过 `FloatingWindowManager` 在主窗口之上创建透明子窗口，支持全局悬浮。
- **双形态切换**：
  - **球态 (Ball Mode)**：60×60 vp 悬浮球，支持手指拖拽与左右边缘智能吸附，呼吸发光动效。
  - **浮窗态 (Panel Mode)**：点击展开为覆盖卡片，顶部含 `[-]` 缩小为悬浮球、`[X]` 关闭悬浮球，提供精简流式对话与语音输入。
- **页面感知中心 (PageContextTracker)**：各页面（首页、周课表、成绩页、考试页）实时上报快照数据与可用动作，Mini 助手与后端 Agent 对话时自动注入当前页面上下文。
- **UI 操作与引导分发器 (UIActionDispatcher)**：事件总线机制，支持 AI 直接控制页面状态（如切周、触发教务导入）或展示高亮聚光灯引导。
- **开关与自动避让**：在全屏 `AssistantPage` 中悬浮球自动隐藏，离开后恢复；在设置与侧边栏提供持久化开关。

---

## 协议（SSE 下行 + HTTP POST 上行）

1. `POST /api/chat` `{session_id, message}` -> 后端开 SSE 流，事件类型：
   - `text_chunk` - LLM 增量文本
   - `tool_call` - `{batch_id, tool_calls:[{tool_call_id,name,args,requiresConfirmation}], ...}` 后端挂起等待工具结果
   - `final` - 正常结束
   - `error` - 错误
2. 手机收到 `tool_call`：按 `requiresConfirmation` 决定是否弹确认框；执行 `ToolExecutor.execute(name, args)`；把结果 `POST /api/tool-result` `{session_id, batch_id, results:[{tool_call_id,success,data}]}`。
3. 后端收到结果 -> `graph.stream(new Command({resume: results}), config)` 唤醒 `toolsNode`，继续推理。

---

## 代码位置

- **后端**（独立 git 仓库）：`C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`
  - `src/tools.ts` - 5 个核心元工具定义与 Schema
  - `src/prompt.ts` - 统一控制引擎提示词与场景示例
  - `src/graph.ts` - StateGraph（interrupt / resume 调度）
  - `test/phone-sim.mjs` - 端侧元工具与 Pipeline 模拟联调脚本
- **前端**（根仓库 `D:\harmony\helper_app`）：`entry/src/main/ets/common/agent/`
  - `DataQueryEngine.ets` - 统一内存数据多维查询引擎
  - `ToolExecutor.ets` - 元工具分发、数据变更与 Pipeline 执行器
  - `ToolRegistry.ets` - 工具元数据与动态风险判定
  - `BackendAgentClient.ets` - SSE 流式客户端
  - `pages/quick/AssistantPage.ets` - 智能对话与气泡格式化渲染
