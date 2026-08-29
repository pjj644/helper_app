# AI 助手子系统技术规格与架构 (AI_AGENT.md)

> **架构模式**：后端 LangGraph.js 编排大脑 + 端侧 HarmonyOS NEXT 统一端侧控制引擎（Universal App Control Engine）。
> **端云交互**：基于 SSE 流式下行推送与中断挂起（Interrupt & Resume），结合端侧内存级多维查询、系统日历联动与 SubWindow 全局悬浮伴随。
> **快速上手指令**：见根目录 [`../AGENTS.md`](../AGENTS.md)。

---

## 1. 系统全景架构与端云协同

成电校园助手 AI 子系统采用 **「后端大脑 + 端侧统一控制引擎」** 架构：
- **后端（`ai-proxy`，独立仓库）**：负责 LangGraph 状态机编排、多模型推理（DeepSeek V3/R1、小米 MiMo、智谱 GLM-4V）、系统提示词与成电 80+ 服务直达库 / 校园指南动态 RAG 检索注入、深度思考（Reasoning / Thought）流式下行、智谱 GLM-4V 视觉识别、教务处官网实时检索、SQLite 会话状态持久化。手机端仅发送最新增量消息（`{session_id, message}`），历史完全由后端检查点管理。
- **前端（HarmonyOS NEXT / ArkTS）**：作为薄客户端与端侧执行器，负责语音/文字/图片输入交互、SSE 深度思考与回复双流解析、折叠式思考过程展示（带毫秒计时）、打字机 Markdown 渲染（带流式光标）、敏感操作安全确认弹窗、端侧数据纯内存多维查询（`DataQueryEngine`）、系统日历联动（`CalendarKit`）、页面路由与 UI 引导。

```
手机 (ArkTS / HarmonyOS NEXT)                 本地/云端 后端服务 (ai-proxy)
┌──────────────────────────────────────┐     SSE ↓     ┌──────────────────────────────┐
│ AssistantPage.ets / FloatingWindow   │──────────────▶│ Express + LangGraph.js       │
│  ├─ 深度思考折叠面板 (Thought Card)   │               │  ├─ POST /api/chat -> SSE 流  │
│  │   └─ 实时耗时计时 & 动态思考状态   │               │  │   ├─ event: thought (推理) │
│  ├─ 原生 Markdown 渲染 (MarkdownBubble)│               │  │   ├─ event: text_chunk   │
│  │   └─ 流式呼吸光标 & 属性自动分段   │               │  │   └─ event: tool_call    │
│  ├─ 链接拦截与内嵌浏览器 (WebPage)    │               │  ├─ POST /api/vision/parse.. │
│  ├─ 紧凑折叠工具面板 (Tool Collapse)   │               │  ├─ GET /api/knowledge/se.. │
│  ├─ 遥测指标卡片 (Telemetry Metrics)  │               │  ├─ StateGraph(Messages)      │
│  ├─ 语音输入 (CoreSpeechKit)         │               │  │   ├─ agentNode (DeepSeek/ │
│  ├─ 智谱 GLM-4V 海报/通知日程识别    │               │  │   │             MiMo)    │
│  ├─ 会话持久化 (ChatSessionRepository)│               │  │   └─ toolsNode (interrupt) │
│  ├─ 页面感知 (PageContextTracker)    │               │  ├─ SqliteSaver 检查点持久化  │
│  ├─ UI动作总线 (UIActionDispatcher)  │               │  ├─ 智谱 GLM-4V (多模态视觉)  │
│  ├─ 统一确认弹窗 (动态风险鉴权)       │               │  ├─ Dynamic Context (80+服务)│
│  └─ BackendAgentClient (SSE流式客户端)│    POST ↑     │  ├─ JWC 官网实时爬虫检索     │
│     ├─ ToolExecutor                  │──────────────▶│  └─ Automated Eval Harness   │
│     │   ├─ DataQueryEngine (多维过滤) │               └──────────────────────────────┘
│     │   ├─ CalendarKit (双向同步去重)│
│     │   └─ Pipeline 复合批处理器     │
│     └─ 本地 Preferences / 日历读写   │
└──────────────────────────────────────┘
```

---

## 2. 后端 LangGraph 状态图与生命周期

### 2.1 状态机流转图 (Mermaid)

```mermaid
flowchart TD
    classDef startEnd fill:#4F46E5,stroke:#3730A3,stroke-width:2px,color:#FFFFFF,font-weight:bold;
    classDef nodeStyle fill:#F3F4F6,stroke:#4B5563,stroke-width:2px,color:#111827;
    classDef llmNode fill:#0284C7,stroke:#0369A1,stroke-width:2px,color:#FFFFFF,font-weight:bold;
    classDef interruptNode fill:#D97706,stroke:#B45309,stroke-width:2px,color:#FFFFFF,font-weight:bold;
    classDef condition fill:#F59E0B,stroke:#D97706,stroke-width:2px,color:#FFFFFF;

    START_NODE(["状态图起点 START"]):::startEnd --> AGENT_NODE

    subgraph Core_Graph ["LangGraph 核心状态机 (Thread: session_id)"]
        AGENT_NODE["agent 节点 (agentNode)<br/>1. 提取最新 HumanMessage<br/>2. 注入 SystemMessage (动态上下文与知识库)<br/>3. 调用 DeepSeek / MiMo (llmWithTools)"]:::llmNode

        ROUTE_DECISION{"routeAfterAgent<br/>检查 AIMessage 是否含 tool_calls?"}:::condition

        AGENT_NODE --> ROUTE_DECISION

        TOOLS_NODE["tools 节点 (toolsNode)<br/>1. 提取 tool_calls 列表<br/>2. 执行 interrupt 挂起状态图<br/>3. 等待端侧 POST /api/tool-result<br/>4. resume 接收工具执行结果<br/>5. 构造 ToolMessage 列表"]:::interruptNode

        ROUTE_DECISION -->|"存在工具调用 (tool_calls > 0)"| TOOLS_NODE
        TOOLS_NODE -->|"回传 ToolMessage 列表"| AGENT_NODE
    end

    ROUTE_DECISION -->|"无工具调用 (输出最终回答)"| END_NODE(["状态图终点 END"]):::startEnd

    subgraph Network_Device ["端云交互与执行通道"]
        SSE_PUSH["SSE 事件流推送<br/>- thought: 深度思考推理流<br/>- text_chunk: 正文文本增量<br/>- tool_call: 工具调用批次"]:::nodeStyle
        DEVICE_EXEC["鸿蒙前端端侧执行<br/>ToolExecutor 分发执行<br/>DataQueryEngine 查询 / CalendarKit 写入"]:::nodeStyle
        HTTP_RESUME["POST /api/tool-result<br/>回传执行结果唤醒图执行"]:::nodeStyle
    end

    TOOLS_NODE -.->|"触发 interrupt 挂起"| SSE_PUSH
    SSE_PUSH --> DEVICE_EXEC
    DEVICE_EXEC --> HTTP_RESUME
    HTTP_RESUME -.->|"Command resume 唤醒"| TOOLS_NODE
```

### 2.2 核心节点职责

| 节点名称 | 核心职责 | 输入与输出 |
| :--- | :--- | :--- |
| **`START`** | 接收外部触发输入，初始化当前 `thread_id` 状态。 | 输入：`{ messages: [HumanMessage] }` |
| **`agent`** | **推理大脑核心**：<br>1. 动态检索并生成 `SystemMessage`（注入统一控制元工具规范、校内 80+ 官方直达服务、动态生活指南与当前页面快照）；<br>2. 调用绑定了工具 Schema 的 LLM（`llmWithTools.invoke([sysMsg, ...msgs])`）；<br>3. 提取 `reasoning_content` / `<thought>` 并在 SSE 中下发 `thought` 事件；<br>4. 生成包含流式文本或 `tool_calls` 的 `AIMessage`。 | 输入：`MessagesAnnotation.State`<br>输出：`{ messages: [AIMessage] }`（注：`SystemMessage` 不存入持久化 State，避免膨胀） |
| **`tools`** | **端侧工具中断与恢复桥梁**：<br>1. 从上一条 `AIMessage` 中解析出 `tool_calls`；<br>2. 调用 LangGraph 原生 `interrupt({ toolCalls })` 挂起执行；<br>3. 恢复时接收前端回传的 `ToolResultInput[]`；<br>4. 将每个执行结果映射为 `ToolMessage`。 | 输入：`AIMessage.tool_calls`<br>中断输出：`{ toolCalls }`<br>恢复输入：`ToolResultInput[]`<br>节点输出：`{ messages: ToolMessage[] }` |
| **`END`** | 会话单轮推理完毕，SSE 向客户端发送 `type: 'final'` 并关闭流。 | 结束当前执行链 |

### 2.3 持久化与挂起恢复机制 (Interrupt & Resume)

1. **检查点存储**：`SqliteSaver.fromConnString('./checkpoints.sqlite')` 以 `thread_id: sessionId` 为主键持久化会话。
2. **挂起中断**：当 `toolsNode` 触发 `interrupt` 时，LangGraph 立即将图状态写入 SQLite 检查点并暂停当前任务。
3. **异步注册表**：后端在 `PendingToolRegistry` 中注册该会话的 Promise（带 30 秒超时控制）。
4. **恢复唤醒**：手机完成端侧执行后，`POST /api/tool-result` 携带 `batch_id` 和结果列表。后端调用 `registry.resolve()` 触发 `graph.stream(new Command({ resume: results }), config)`，直接从挂起点恢复图执行并无缝过渡回 `agent` 节点。

---

## 3. 前端端侧执行时序与生命周期

### 3.1 端侧执行时序图 (Mermaid)

```mermaid
sequenceDiagram
    autonumber
    actor User as 用户
    participant UI as AssistantPage / 悬浮球
    participant Client as BackendAgentClient
    participant Registry as ToolRegistry
    participant Exec as ToolExecutor
    participant Engine as DataQueryEngine
    participant CalKit as CalendarKitReminderService
    participant Server as 后端 ai-proxy (LangGraph)

    User->>UI: 语音或文本提问 ("明天有什么课")
    UI->>Client: run(sessionId, history)
    Client->>Server: POST /api/chat (开启 SSE 流)
    
    opt 深度思考推理阶段 (Reasoning Stream)
        loop 推理下发
            Server-->>Client: SSE thought (深度思考过程增量)
            Client->>UI: callbacks.onThoughtChunk() 渲染折叠卡片与计时
        end
    end

    loop 流式文本输出阶段
        Server-->>Client: SSE text_chunk (增量文本片段)
        Client->>UI: callbacks.onTextChunk() 打字机渲染 (带光标)
    end

    Note over Server,Client: 后端 toolsNode 触发 interrupt 挂起
    Server-->>Client: SSE tool_call (batch_id, tool_calls 列表)
    
    rect rgb(245, 247, 250)
        Note over Client,Exec: 端侧分发执行与安全确认
        Client->>Registry: getRiskLevel() & requiresConfirmation()
        
        alt 判定为中高风险 (如创建日程、云端同步)
            Client->>UI: callbacks.onConfirmationNeeded(toolName, args)
            UI->>User: 弹出标准化操作确认框
            User-->>UI: 点击确认 / 拒绝
            UI-->>Client: 返回确认结果
        end
        
        Client->>Exec: execute(toolName, args)
        
        alt domain 为 course / exam / grade 等查询
            Exec->>Engine: executeQuery(domain, filter, limit)
            Engine-->>Exec: 内存级多维过滤，返回 JSON 字符串
        else domain 为 schedule (创建日程)
            Exec->>CalKit: addEventReminder (申请日历权限并写入)
            CalKit-->>Exec: 返回 calendarEventId
            Exec-->>Exec: ScheduleService.saveSchedule(本地持久化)
        else tool 为 app_pipeline (复合流水线)
            loop 顺序批处理每个 step
                Exec->>Exec: execute(step.tool, step.args)
            end
        end
        
        Exec-->>Client: 返回 ToolResult (success, data)
    end

    Client->>Server: POST /api/tool-result (携带 session_id, batch_id, results)
    
    Note over Server: 后端 Command resume 唤醒 toolsNode 并回流 agentNode 继续推理
    Server-->>Client: SSE text_chunk ("已为您查询到明天的课表安排...")
    Server-->>Client: SSE final
    Client->>UI: callbacks.onComplete()
```

---

## 4. 统一控制元工具体系（Universal App Control Engine）

前端将工具全面收敛为 **5 大核心元工具** 与 **4 大高阶辅助/页面感知工具**。元数据定义于 `ToolRegistry.ets`，执行逻辑实现在 `ToolExecutor.ets`。

### 4.1 5 大核心元工具

| 工具名称 | 风险等级 | 端侧确认 | 核心入参 (Schema) | 功能与执行逻辑 |
| :--- | :---: | :---: | :--- | :--- |
| **`app_data_query`** | `low` | ❌ 免确认 | • `domain`: `course` \| `exam` \| `grade` \| `schedule` \| `calendar` \| `reminder_setting` \| `system_info`<br>• `filter`: `date` (YYYY-MM-DD), `week` (1-20), `dayOfWeek` (1-7), `keyword`, `teacher`, `room`, `upcomingOnly`, `semesterId`, `minGpa`, `maxGpa`<br>• `limit`: 数量限制 | **统一数据智能查询器**：<br>由 `DataQueryEngine` 接管。纯内存级多维检索过滤，支持教学周/日期自动换算、GPA 实时计算、考试倒计时与系统日历读取。 |
| **`app_data_mutate`** | `medium` | ⚠️ 需确认 | • `domain`: `schedule` \| `calendar` \| `reminder_setting`<br>• `action`: `create` \| `update` \| `delete`<br>• `payload`: 变更对象数据<br>• `syncCalendar`: 是否同步写入系统日历（默认 `true`，具备唯一性查重）<br>• `remindMinutesBefore`: 提前提醒分钟数（默认 `30`） | **统一数据变更器**：<br>统一处理日程 CRUD、日历事件删除、提醒时间设置。联动 HarmonyOS `CalendarKit`，自动完成系统日历读写与权限申请。 |
| **`app_control`** | `high`<br>*(跳转为low)* | ⚠️ 需确认<br>*(跳转免确认)* | • `action`: `navigate` \| `sync_cloud` \| `download_cloud` \| `refresh_reminders`<br>• `params`: `{ page: string, syncScope?: 'all'\|'courses'\|'exams' }` | **统一应用系统控制**：<br>1. `navigate`: 页面平滑路由（课表/考试/成绩/设置/导入等 10 个主要页面）；<br>2. `sync_cloud`/`download_cloud`: 华为云数据库全量/增量同步与恢复；<br>3. `refresh_reminders`: 全量提醒与日历事件重建。 |
| **`campus_search`** | `low` | ❌ 免确认 | • `query`: 检索关键词或问题<br>• `source`: `guide` \| `jwc_news` \| `auto`<br>• `category`: `bus` \| `academic_policy` \| `hospital` \| `facilities` \| `service` \| `all` | **统一成电校园智搜**：<br>收录 `campus_services.json`（80+ 校内直达服务）、`campus_guide.json`（办事流程/校历/校医院）及教务处官网实时公告爬取。大模型识别服务意图时，直接输出标准 Markdown 链接 `[服务名称](URL)`。 |
| **`app_pipeline`** | `medium` | ⚠️ 需确认 | • `steps`: `[{ stepId: string, tool: string, args: object }]` | **声明式复合流水线批处理**：<br>一次下发多个有序原子动作（如“查空闲 ➔ 创日程 ➔ 写入日历”），在手机端顺序批处理，彻底规避多次网络往返延迟。 |

### 4.2 4 大高阶辅助与页面感知工具

1. **`get_current_page_context`**（Low 风险，免确认）：由 `PageContextTracker` 提供，感知用户当前停留在哪个页面及当前页面的数据快照与可用操作；返回值额外携带 `highlightableIds`（来自 `SpotlightRegistry` 的当前页可高亮元素 id 列表，非登记页为空数组）。页面覆盖：5 个主 Tab（Index）+ 课表/考试/成绩/助手 + 12 个二级路由页（班车/设置/内嵌网页/课程管理/考试导入/成绩导入/课表导入/登录/账号管理/个人信息/功能导航/日历路由页）。
2. **`execute_page_action`**（Low 风险，免确认）：由 `UIActionDispatcher` 事件总线驱动，在当前页面直接触发 UI 动作：`switch_week`（切周）、`switch_tab`（切 Tab）、`import_courses/grades/exams`（触发导入）、`web`（带 url/title 打开内嵌网页）、`show_guidance`（聚光灯高亮引导，`targetElementId` 必须取自 `get_current_page_context` 的 `highlightableIds`，未登记 id 会被端侧如实拒绝并返回可用列表，模型严禁编造）。
3. **`generate_study_plan`**（Low 风险，免确认）：分析用户即将到来的所有考试，根据倒计时剩余天数加权生成考前每日突击复习规划。
4. **`ask_user_clarification`**（Low 风险，免确认）：意图歧义或参数缺失时向用户发起澄清提问，端侧以交互卡片呈现选项并回传选择结果。

> 历史注记：原第 4 项 `parse_text_to_schedule`（非结构化文本提取日程）为空壳实现，已于优化轮 T7 按三处同步铁律全链路移除；相关解析由后端 LLM 内联完成。

### 4.3 向后兼容工具映射

为了保证旧版本或细粒度调用的兼容性，`ToolExecutor` 内部将传统原子工具自动委托给统一数据查询引擎与变更器：
- `query_today_courses` / `query_tomorrow_courses` / `query_week_courses` ➔ `queryEngine.executeQuery('course', ...)`
- `query_current_week` / `get_current_datetime` ➔ `queryEngine.executeQuery('system_info', ...)`
- `query_next_exam` / `query_all_exams` ➔ `queryEngine.executeQuery('exam', ...)`
- `query_grades` / `query_gpa` ➔ `queryEngine.executeQuery('grade', ...)`
- `create_schedule` / `update_schedule` / `delete_schedule` ➔ `executeDataMutate(...)`
- `set_reminder_enabled` / `set_remind_minutes` ➔ 提醒分类开关与提前量偏好读写
- `sync_all_to_cloud` / `download_all_from_cloud` ➔ `executeAppControl(...)`

---

## 5. 前端核心子系统与 UI 交互特性

### 5.1 深度思考推理流与动态卡片 (Deep Thinking UI)
- **实时推理状态与折叠卡片 (`AssistantPage.ets`)**：
  - 支持大模型 Reasoning 过程流式下行；
  - 呈现「✨ 深度思考 (耗时 xs)」专属折叠卡片，支持一键展开/收起；
  - 配备毫秒级高精度计时器，在思考结束时自动固化总思考时长；
  - 会话历史（`ChatSessionRepository.ets`）自动持久化保存 `thought` 与 `thinkingDurationMs`，重新打开应用仍可查看完整推理链。
- **悬浮 Mini 助手动态状态感知 (`FloatingSubWindowContent.ets`)**：
  - 动态显示多级思考阶段提示（`✨ 正在理解您的问题...` ➔ `正在深度思考...` ➔ `正在调用 xxx...` ➔ `正在整理回答...`），配合实时运行秒数。

### 5.2 全局悬浮 AI 伴随助手（Floating Assistant）
- **SubWindow 独立子窗口架构 (`FloatingWindowManager.ets`)**：
  - 基于 HarmonyOS `windowStage.createSubWindow` 实现跨页面透明子窗口；
  - 严格生命周期管理：先调用 `setUIContent` 再配置尺寸与位置（规避 `1300002` 异常）。
- **三形态自由切换**：
  - **球态 (Ball Mode)**：60×60 vp 呼吸发光微型球，支持全屏自由拖拽与贴边吸附物理反馈；
  - **浮窗态 (Panel Mode)**：覆盖在当前页面之上的 Mini 助手卡片，右上角配备缩小 `[-]`、新对话 `[+]` 与收起停靠 `[X]`（收起面板并停靠悬浮球，禁用功能需到设置）；
  - **引导态 (GUIDANCE Mode)**：AI 下发 `show_guidance` 时子窗口临时全屏并 `setWindowTouchable(false)`（触摸穿透，用户仍可直接点击被高亮卡片），渲染聚光灯引导层；超时/页面切换/组件缺失自动退出并恢复前形态。
- **聚光灯高亮闭环（`SpotlightRegistry.ets`）**：
  - 元素 ID 注册表：页面组件以 `.id()` 标注（发现页 13 个 id：Hero 卡、常用服务三卡、所有功能九宫格），注册表按 pageName 登记；
  - 坐标解析在主窗口侧完成（`componentUtils.getRectangleById` 取 `windowOffset`，px→vp 换算后经 AppStorage 同步给子窗口）；子窗口以四块遮罩挖孔 + 呼吸描边环 + 提示气泡渲染，整层 `hitTestBehavior(None)`；
  - 如实回执：`ToolExecutor` 先校验 `SpotlightRegistry.pageHas(当前页, targetElementId)`，失败返回 `success:false` + `availableIds`，杜绝模型谎报「已高亮」。
- **统一会话与历史管理 (`ChatSessionRepository.ets`)**：
  - 全屏助手与悬浮 Mini 助手共享同一套本地会话仓库，支持会话实时双向同步与独立新建。
- **状态同步与避让**：
  - 通过 `AppStorage` 实现悬浮球开关状态在全屏助手、应用设置页（`AppSettings.ets`）与浮窗本体之间的毫秒级双向同步；
  - 在全屏助手页自动避让隐藏，离开后自动恢复。

### 5.3 界面排版与 Markdown 渲染
- **原生 ArkTS Markdown 渲染引擎 (`MarkdownBubble.ets`)**：
  - 支持多级标题（# ~ ###）、粗体、行内代码、引用块、列表、代码块；
  - **流式打字光标 (`isStreaming`)**：在内容增量吐字阶段呈现平滑呼吸光标（`▌`），输出完毕无缝隐去；
  - **原生超链接拦截与内嵌导航**：支持识别 Markdown 超链接 `[text](url)`，渲染为精致的蓝色链接胶囊按钮，点击自动拦截并推入 `WebPage.ets` 原生顶栏内嵌浏览器打开（保留返回、刷新、标题与线性进度条），不跳出 App；对于内部路由直接跳转本地对应页面；
  - **智能排版**：属性字段（`日期:`、`时间:`、`地点:`、`类型:`、`备注:`）自动换行，状态提示单独分段；全屏助手与悬浮 Mini 浮窗统一采用 `MarkdownBubble` 渲染。
- **紧凑折叠工具面板 (Tool Call Collapse UI)**：
  - 优雅的折叠行设计，支持状态指示、耗时与工具参数/结果一键展开查看。
- **Agent Telemetry 遥测指标**：
  - 在气泡底部展示流式耗时（ms）、Token 消耗估算与工具调用计数。

### 5.4 核心模块职责清单

| 前端模块文件 | 核心职责与关键方法 |
| :--- | :--- |
| `BackendAgentClient.ets` | SSE 流式长连接通信（`requestInStream`）、`TextDecoder` 分词解码、`thought` 推理事件解析、`tool_call` 中断响应与结果回传。 |
| `ToolRegistry.ets` | 工具元数据定义、参数校验与动态风险等级判定（`getRiskLevel` / `requiresConfirmation`）。 |
| `ToolExecutor.ets` | 端侧中央工具分发器（`switch(toolName)`）、CRUD 事务执行、流水线批处理（`executePipeline`）。 |
| `DataQueryEngine.ets` | 纯内存多维数据过滤与统一查询引擎（接管课表、考试、成绩、日程、日历）。 |
| `PageContextTracker.ets` | 全局页面活跃状态与数据快照感知中心（单例模式，`updateSnapshot`；5 主 Tab + 二级路由页全量上报）。 |
| `UIActionDispatcher.ets` | 页面 UI 动作与高亮聚光灯指令总线（`switch_week` / `switch_tab` / `open_*` / `web` / `show_guidance`，含 `getGuidanceState` 重入守卫）。 |
| `SpotlightRegistry.ets` | 聚光灯元素 ID 注册表（id ↔ 组件 `.id()` 契约、按 pageName 校验可高亮元素，`show_guidance` 如实回执的依据）。 |
| `FloatingWindowManager.ets` | HarmonyOS SubWindow 悬浮球生命周期管理，BALL/PANEL/GUIDANCE 三形态切换（GUIDANCE 态触摸穿透）。 |
| `CalendarKitReminderService.ets` | HarmonyOS 系统日历写入、班车/考试去重与事件查询。 |
| `ChatSessionRepository.ets` | 统一会话与历史消息持久化，支持深度思考与流式遥测指标存储。 |

---

## 6. 加新工具三处同步铁律（名称与参数必须完全一致）

每次新增或修改端侧工具时，必须且只能同步修改以下三处：

1. **后端 Schema 与元数据**：`ai-proxy/src/tools.ts`（定义 schema 与 `toolMeta`：`requiresConfirmation` / `riskLevel`）；
2. **前端执行器**：`ToolExecutor.ets`（`switch(toolName)` 分发执行具体逻辑）；
3. **前端注册表**：`ToolRegistry.ets`（定义镜像用于端侧动态风险评级与确认弹窗判定）。

---

## 7. 后端联调与独立验证

- **启动后端**：`cd "C:\Users\28399\Desktop\华为云\后端服务\ai-proxy" && npm run dev`（端口 3000）。后端 `.env`（`DEEPSEEK_API_KEY` 等）已 gitignore，勿提交。
- **单独模拟联调（不连手机）**：`node test/phone-sim.mjs` + `npm run typecheck`。
- **自动化评测基准运行**：`cd "C:\Users\28399\Desktop\华为云\后端服务\ai-proxy" && npm run test:eval`（全量运行 34 条评测集并自动生成 Markdown 报告）。
- **真机/模拟器联调**：填电脑 **局域网 LAN IP**（如 `http://192.168.1.11:3000`），不要填 `localhost`。
- **调试日志前缀**：`[BackendAgentClient]` / `[CalendarKit]` / `[ReminderDebug]` / `[ExamDebug]` / `[HomeDebug]` / `[FloatingWindow]`。

---

## 8. Agent 自动化评测基准体系（Automated Eval Harness）

为了保证 Agent 在工具调用、参数提取、校内官方 URL 真实度、Prompt 注入防御及首字延迟（TTFT）上的工业级稳定性，后端内置了一套完整的 **自动化评测基准套件 (Eval Harness)**。

### 8.1 评测架构与用例分类

评测集定义于 `test/evals/dataset.ts`，涵盖 6 大核心维度共 34 条真实业务场景用例：

```
                    ┌─────────────────────────────────────────┐
                    │      Agent Eval Harness (runner.ts)     │
                    └────────────────────┬────────────────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
┌──────────────────┐           ┌──────────────────┐           ┌──────────────────┐
│  确定性规则裁判  │           │   端侧环境模拟   │           │ LLM-as-a-Judge   │
│ (Deterministic)  │           │  (Mock Device)   │           │  (5维度质量评分) │
├──────────────────┤           ├──────────────────┤           ├──────────────────┤
│• 工具命中准确率  │           │• 课程/考试/GPA   │           │• 意图相关性 (5★) │
│• 参数结构精确匹配│           │• 日程与日历事件  │           │• 事实准确性 (5★) │
│• 官方URL绝对匹配 │           │• 页面路由与流水线│           │• 回答完整度 (5★) │
│• 越狱与攻击拦截率│           │• 悬浮窗上下文快照│           │• 安全与排版规范  │
└──────────────────┘           └──────────────────┘           └──────────────────┘
```

| 评测维度 (Category) | 覆盖核心场景与验证目标 | 典型用例 ID |
| :--- | :--- | :--- |
| **`COURSE_EXAM_QUERY`** | 今日/明日/指定周课表查询、考试倒计时、GPA/成绩多维筛选 | `Q01_TODAY_COURSES` ~ `Q08_SYSTEM_INFO` |
| **`RELATIVE_DATE_RESOLVE`**| 绝对日期映射、按教师/教室/星期模糊过滤、学期首日锚定 | `T01_SPECIFIC_DATE_COURSE` ~ `T05_DAY_OF_WEEK` |
| **`DATA_MUTATE_PIPELINE`** | 自习日程创建（带日历同步）、日程删除、提醒开关设置、页面路由控制、云同步控制、复合流水线批处理 | `M01_CREATE_SCHEDULE` ~ `M06_SET_REMINDER_OFF` |
| **`CAMPUS_SERVICE_URLS`** | 80+ 校内高频服务直达 URL 零幻觉检验（学生邮箱必须 http、寝室电费引导云中成电、正版软件、WebVPN 等） | `C01_STUDENT_EMAIL` ~ `C08_BBS_RIVER` |
| **`INJECTION_AND_NEGATIVE`**| 英文/中文 Prompt 越狱注入攻击拦截、无关泛话题非工具误调检验、Emoji 排版合规性检验 | `S01_PROMPT_INJECTION_IGNORE` ~ `S04_EMOJI_POLLUTION_CHECK` |
| **`EDGE_CASES`** | 悬浮球端侧页面感知（`get_current_page_context`）、校车时刻智搜、考试突击复习规划生成 | `E01_PAGE_CONTEXT_AWARE` ~ `E03_STUDY_PLAN_GEN` |

### 8.2 双轨评测机制与指标基准

1. **确定性规则校验 (`evaluateDeterministic`)**：
   - 工具匹配：精确断言调用的工具名称是否符合预期；
   - 参数匹配：校验提取参数（如 `minGpa`、`keyword`、`date`、`syncCalendar`）是否完全符合业务语义；
   - URL 真实度：使用正则严格校验 Markdown 链接是否命中预设的真实官方域名与协议；
   - 注入防御：校验是否触发拦截标志或友好拒答，杜绝系统 Prompt 泄露。
2. **LLM-as-a-Judge 智能裁判 (`evaluateJudgeWithLLM`)**：
   - 采用大模型对最终回答进行 1-5 分打分，综合评估相关性、准确性、逻辑性与可读性。
3. **最新实测基准大盘 (Baseline vs Ours)**：
   - **综合通过率 (Pass Rate)**：**97.0%**（优化轮 T8 定向修复后，基线 87.9%）；
   - **官方链接真实度 (URL Exactness)**：**100.0%**（零幻觉）；
   - **单轮 Token 消耗**：动态上下文检索机制优化，节省 76.5% Prompt 冗余；
   - **平均首字延迟 (TTFT)**：实测 3.4s（含深度思考）。

### 8.3 评测执行与报表自动生成

在后端目录直接运行：
```bash
npm run test:eval
```
评测完成后将自动在 `test/evals/EVAL_REPORT.md` 生成包含执行概览、分类明细与用例追踪的完整 Markdown 报告。回归标准：综合通过率 ≥97% 且无维度回退。
