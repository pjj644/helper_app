# AI 助手后端化改造方案 (plan.md)

> 将"成电校园助手"的 AI 助手从 **设备端 Agent（ArkTS）+ 薄代理（ECS 转发 DeepSeek）** 改造为
> **本地电脑后端 Agent（LangGraph.js）+ ArkTS 前端（仅展示 + 工具执行）**。

---

## 1. 背景与现状

### 1.1 现有架构

```
手机(ArkTS)                          ECS(121.36.101.82:3000)
┌─────────────────────────┐          ┌──────────────────────┐
│ AssistantPage.ets       │          │ ai-proxy (Express)   │
│  ├─ 会话/历史/气泡UI     │          │  ├─ X-Proxy-Key 鉴权 │
│  ├─ 确认弹窗             │          │  └─ 透传 -> DeepSeek  │
│                          │  SSE    │     (持密钥)          │
│ AgentOrchestrator.ets ◀─│──────────│                      │
│  ├─ Agent 循环(≤5轮)     │          │  无 Agent 大脑        │
│  ├─ SSE 解析             │          │  无 工具              │
│  ├─ tool_calls 累积      │          │  无 状态              │
│  └─ 调 DeepSeek(透传)    │          └──────────────────────┘
│                          │
│ ToolRegistry.ets (21工具)│
│ ToolExecutor.ets          │ ← 工具直接读写手机本地 Preferences
│  ├─ CourseService         │   (课表/考试/成绩/日程/设置)
│  ├─ ExamService           │
│  ├─ GradeService          │
│  ├─ ScheduleService       │
│  ├─ SyncService(->CloudDB) │
│  ├─ AuthService           │
│  └─ ReminderService       │
└─────────────────────────┘
```

**关键事实**：当前 Agent 大脑（LLM 循环、工具调度、SSE 解析）全部跑在 **手机端 ArkTS** 里；ECS 上的 `ai-proxy` 只是个"钥匙保管箱 + 转发器"，没有任何 Agent 逻辑。21 个工具几乎全部读写**手机本地 Preferences 数据**，后端本身没有任何用户数据。

### 1.2 相关文件清单

| 角色 | 文件 | 说明 |
|---|---|---|
| UI 页面 | `entry/.../pages/quick/AssistantPage.ets` | 聊天 UI、会话管理、气泡、确认弹窗、结果格式化 |
| Agent 大脑 | `entry/.../common/agent/AgentOrchestrator.ets` | **本次要删除/替换**：Agent 循环 + SSE 解析 |
| 工具元数据 | `entry/.../common/agent/ToolRegistry.ets` | 21 工具定义 + 风险等级 + 确认标志 + schema |
| 工具执行 | `entry/.../common/agent/ToolExecutor.ets` | **本次保留**：工具实际执行逻辑（读写本地数据） |
| 常量 | `entry/.../common/constants/AppConstants.ets` | `AI_PROXY_URL` / `AI_PROXY_KEY` 等 |
| 旧后端 | `CloudProgram/ai-proxy/`（仓库内） | 薄代理，改造后**直接删除** |
| **新后端目录** | `C:\Users\28399\Desktop\华为云\后端服务\ai-proxy` | 当前是该薄代理的一份拷贝，本方案在此演进为 LangGraph.js Agent |

---

## 2. 目标

1. 把 Agent 大脑（LLM 调用、推理循环、工具调度、流式解析）从手机搬到**本地电脑后端**，用 **LangGraph.js** 实现，获得状态机、检查点、可中断/可恢复、可观测等能力。
2. 手机端**只保留** ArkTS 前端：聊天 UI + 工具执行层（`ToolExecutor`，因为数据在本地）。
3. 数据**不离开手机**：后端需要数据时回调手机执行工具，结果回传。
4. LLM 继续用 **DeepSeek 云端 API**（`deepseek-v4-flash`），密钥由本地后端持有，手机不再接触密钥。
5. 本地同 WiFi 开发/自用：手机走电脑局域网 IP 访问后端。

### 2.1 必须点破的取舍（预期对齐）

你提到"只在 DevEco 用 ArkTS 写前端"。在选定"手机执行工具"的前提下：
- **搬走的**：`AgentOrchestrator`（LLM 循环、SSE 解析、tool_calls 累积、API 调用）-> 全部进后端。
- **保留的**：`ToolExecutor`（工具执行）、`ToolRegistry` 的 UI 元数据部分（展示名/风险/确认标志/结果格式化）、`AssistantPage` 的 UI。
- 原因：21 个工具全部读写手机本地数据或执行设备动作（导航、通知、日历、云同步），后端无法直接执行。若要让前端"纯粹无逻辑"，必须把数据也搬到后端（被否决的方案 B）。
- 净效果：手机代码**变薄**（删掉最复杂的 Orchestrator），但不是"零逻辑"。

---

## 3. 关键决策（已全部确认）

| 决策项 | 选择 | 理由 |
|---|---|---|
| 数据访问架构 | **手机执行工具（远程工具执行）** | 数据留在手机；现有数据层与 `ToolExecutor` 几乎不动；迁移成本最低；隐私好 |
| LLM | **DeepSeek 云端 API（`deepseek-v4-flash`）** | 复用现有模型与密钥（key 已有该模型权限）；无需本地 GPU |
| 后端框架 | **LangGraph.js (TypeScript)** | 与现有 Node/TS ai-proxy 一致；单语言栈；可直接演进现有代码；前后端可共享类型 |
| 部署 | **仅本地同 WiFi** | 最简起步；无需隧道；手机走电脑 LAN IP |
| 对话持久化 | **持久化检查点（SQLite）** | 后端重启不丢对话上下文；开发期频繁重启友好；代价是多一个 .db 文件 |
| 后端地址 | **AppSettings 可填，存 Preferences** | LAN IP 随 DHCP 变，改地址免重编译；复用现有 SettingsRepository |
| 明文 HTTP | **全局 allowsCleartext，无需改配置** | API 22 默认放行明文；全项目无 networkConfig，当前对 ECS 明文可用已证实 |
| 旧 ECS 代理 | **直接停服并删除旧代码** | 本地后端上线后不再被引用；ECS 服务器保留供未来远程部署 |
| 会话历史 | **维持本地双存储** | 手机存显示用历史，后端 SQLite 存 LLM 上下文；暂不做单一源 |

---

## 4. 总体架构（改造后）

```
手机(ArkTS)                         本地电脑后端(LangGraph.js)
┌──────────────────────────┐       ┌──────────────────────────────┐
│ AssistantPage.ets (UI)    │       │ Express                       │
│  └─ 会话/气泡/确认弹窗     │       │  ├─ POST /api/chat   (SSE)    │
│                            │       │  ├─ POST /api/tool-result     │
│ BackendAgentClient.ets ◀──│───────│  └─ GET  /health              │
│  (替代 AgentOrchestrator)  │       │                               │
│  ├─ 发起会话 + 收事件流    │       │ LangGraph StateGraph          │
│  ├─ 解析 typed SSE 事件    │       │  ├─ agent node                │
│  └─ 路由到 AgentCallbacks  │       │  │   └─ DeepSeek.bindTools    │
│                            │       │  ├─ tools node (interrupt)    │
│ ToolExecutor.ets (保留)    │       │  └─ SQLite checkpointer       │
│  └─ 读写本地 Preferences   │       │                               │
│                            │       │ DeepSeek API (密钥在此)        │
└──────────────────────────┘       └──────────────────────────────┘
          ▲                                      │
          │  数据流（单轮对话）                    │
          │                                      │
  1. POST /api/chat {session_id, message} ───────▶
  2. ◀── SSE: text_chunk (流式文本) ──────────────
  3. ◀── SSE: tool_call {tool_calls, batch_id} ───  (graph 中断)
  4. 本地执行 ToolExecutor (含确认弹窗)
  5. POST /api/tool-result {session_id, results} ─▶ (恢复 graph)
  6. ◀── SSE: text_chunk ... ─────────────────────
  7. ◀── SSE: final ──────────────────────────────
```

**核心机制**：用 LangGraph 的 `interrupt()` 把"工具执行"做成**人机协同中断点**--后端在 tools 节点暂停、把工具调用事件推给手机、手机执行完回传结果、后端 `Command({resume})` 恢复 graph 继续 LLM 推理。一问多工具合并为一次中断/一次回传。

---

## 5. 通信协议设计

### 5.1 端点

| 方法 | 路径 | 说明 |
|---|---|---|
| `POST` | `/api/chat` | 发起一轮对话。`Accept: text/event-stream`，响应为 SSE 事件流。**长连接保持到本轮结束。** |
| `POST` | `/api/tool-result` | 回传工具执行结果。响应 `202 Accepted`（无 body）。触发挂起的 `/api/chat` 流继续。 |
| `GET` | `/health` | 存活检查。 |

- 鉴权：保留 `X-Proxy-Key` 头（共享密钥，沿用现有 `PROXY_AUTH_KEY`）。本地 WiFi 够用。
- 所有 body/json 均为 UTF-8 JSON。

### 5.2 请求体

**`POST /api/chat`**
```json
{
  "session_id": "1719xxxxxxx",     // 作为 LangGraph thread_id
  "message": "我今天有几节课？",
  "context": { "detailed": true }  // 可选；后端据此决定是否注入 APP_KNOWLEDGE
}
```

**`POST /api/tool-result`**
```json
{
  "session_id": "1719xxxxxxx",
  "batch_id": "b-xxxx",            // 对应 tool_call 事件的 batch_id
  "results": [
    { "tool_call_id": "call_1", "success": true,  "data": "{...json string...}" },
    { "tool_call_id": "call_2", "success": false, "data": "未登录，请先登录" }
  ]
}
```
- `success=false` 时 `data` 为错误说明；`data` 始终是字符串（与现有 `ToolResult` 一致）。
- 用户在确认弹窗点"拒绝" -> 该工具 `success=false, data="用户拒绝了此操作"`（与现有行为一致，模型据此告知用户已取消）。

### 5.3 SSE 事件格式

每条事件：`data: {JSON}\n\n`，JSON 带 `type` 字段。

| type | 字段 | 说明 |
|---|---|---|
| `text_chunk` | `content: string` | 流式文本片段（直接追加到当前 assistant 气泡） |
| `tool_call` | `batch_id, tool_calls[]` | 请求手机执行一批工具。每个 tool_call: `{tool_call_id, name, args, requires_confirmation, risk_level}` |
| `final` | `content?: string` | 本轮结束（可选附带最终聚合文本） |
| `error` | `message: string` | 出错，本轮终止 |

**示例流**：
```
data: {"type":"text_chunk","content":"让我查一下"}

data: {"type":"tool_call","batch_id":"b-a1","tool_calls":[{"tool_call_id":"call_1","name":"query_today_courses","args":{},"requires_confirmation":false,"risk_level":"low"}]}

data: {"type":"text_chunk","content":"你今天有 3 节课：\n1. 高等数学..."}

data: {"type":"final"}
```

> 手机收到 `tool_call` -> 执行（含确认弹窗）-> POST `/api/tool-result` -> 后端恢复 -> 继续 `text_chunk`/`final`。
> `/api/chat` 的 SSE 连接在等待工具结果期间**保持打开**（后端在 `await` 挂起的 promise）。

---

## 6. 后端设计（LangGraph.js）

目录：`C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`（在现有 Node/TS 项目上演进）。

### 6.1 依赖

```jsonc
// package.json (新增)
"dependencies": {
  "express": "^4.21.0",
  "dotenv": "^16.4.5",
  "@langchain/core": "^0.3.x",
  "@langchain/langgraph": "^0.2.x",
  "@langchain/openai": "^0.4.x",          // DeepSeek 是 OpenAI 兼容
  "@langchain/langgraph-checkpoint-sqlite": "^0.0.x"  // 持久化检查点（后端重启不丢上下文）
}
```
> DeepSeek 通过 `@langchain/openai` 的 `ChatOpenAI` 接入：`baseURL: 'https://api.deepseek.com'`，`model` 走环境变量。

### 6.2 目录结构

```
ai-proxy/
├─ src/
│  ├─ index.ts          # Express + SSE 端点 + 挂起结果注册表
│  ├─ graph.ts          # StateGraph 定义（agent/tools 节点 + 边 + checkpointer）
│  ├─ llm.ts            # ChatOpenAI(DeepSeek) 实例 + bindTools
│  ├─ tools.ts          # 21 个工具的 schema（仅 schema，执行在手机）
│  ├─ prompt.ts         # SYSTEM_PROMPT + APP_KNOWLEDGE + 关键词判断
│  ├─ state.ts          # MessagesAnnotation / 自定义 state
│  └─ registry.ts       # PendingToolRegistry：session_id -> {resolve, batch_id, timer}
├─ .env                 # DEEPSEEK_API_KEY / PORT / PROXY_AUTH_KEY / DEEPSEEK_MODEL / DEEPSEEK_BASE_URL
└─ package.json
```

### 6.3 Graph 结构

```
State = MessagesAnnotation  // messages: BaseMessage[]

START ──▶ agent ──┬──(有 tool_calls)──▶ tools ──▶ agent (循环)
                  └──(无 tool_calls)──▶ END
```

**`agent` 节点**：用 `llm.bindTools(toolSchemas)` 调 DeepSeek，返回 `{ messages: [aiMessage] }`。
支持流式：`streamMode: ['messages']` 产出 token -> 后端转发为 `text_chunk` 事件。

**`tools` 节点**（核心，自定义，不用 `ToolNode`）：
```ts
async function toolsNode(state) {
  const last = state.messages.at(-1);
  const toolCalls = last.tool_calls;          // 本轮 LLM 想调的全部工具
  // ① 中断：把工具调用交给手机执行
  const results = interrupt({ toolCalls });   // 暂停；手机回传后 resume
  // ② 收到 results（数组），构造 ToolMessage
  const msgs = results.map(r => new ToolMessage({
    tool_call_id: r.tool_call_id,
    content: r.success ? r.data : `错误: ${r.data}`,
  }));
  return { messages: msgs };
}
```
- 一轮 LLM 的多个 tool_calls **合并为一次中断、一次回传**（与现有 Orchestrator 顺序执行等价，但减少往返）。
- `interrupt()` 暂停后，后端从 `graph.getState(config).tasks[0].interrupts[0].value` 取 `{toolCalls}`，包装成 SSE `tool_call` 事件发给手机；手机回传后调 `graph.stream({ command: { resume: results } }, config)` 恢复。

**Checkpointer**：持久化检查点（`@langchain/langgraph-checkpoint-sqlite`，落盘 `./checkpoints.sqlite`）。`thread_id = session_id`，跨轮保留完整对话历史，**后端重启不丢上下文**（开发期频繁重启友好）。
**递归上限**：`recursionLimit: 25`（≈ 12 轮工具循环，远超现有 5 轮上限，留余量）。

### 6.4 `/api/chat` 处理流程（伪代码）

```ts
app.post('/api/chat', async (req, res) => {
  if (!checkAuth(req, res)) return;
  const { session_id, message, context } = req.body;
  const config = { configurable: { thread_id: session_id }, recursionLimit: 25 };
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  let input = { messages: [new HumanMessage(message)] };
  const sys = buildSystemPrompt(message, context); // 注入 SYSTEM_PROMPT (+可选 APP_KNOWLEDGE)

  while (true) {
    const stream = await graph.stream(input, { ...config, streamMode: ['messages', 'updates'] });
    let interrupted = false;
    for await (const [mode, chunk] of stream) {
      if (mode === 'messages') {
        // chunk: { message, chunk } - 流式 token
        const text = chunk?.content;
        if (text) res.write(`data: ${JSON.stringify({ type: 'text_chunk', content: text })}\n\n`);
      }
      if (/* 检测到 interrupt */) {
        const { toolCalls } = graph.getState(config).tasks[0].interrupts[0].value;
        const batch_id = `b-${Date.now()}`;
        res.write(`data: ${JSON.stringify({ type: 'tool_call', batch_id, toolCalls })}\n\n`);
        // 等待手机回传（带超时）
        const results = await registry.waitFor(session_id, batch_id, TOOL_TIMEOUT_MS);
        input = { command: { resume: results } };
        interrupted = true;
        break;
      }
    }
    if (!interrupted) break; // 到达 END
  }
  res.write(`data: ${JSON.stringify({ type: 'final' })}\n\n`);
  res.end();
});
```

### 6.5 挂起结果注册表 `registry.ts`

```ts
class PendingToolRegistry {
  // session_id -> { resolve, batch_id, timer }
  register(sessionId, batchId, timeoutMs): Promise<ToolResult[]>;
  resolve(sessionId, batchId, results): void;     // /api/tool-result 调用
  reject(sessionId, batchId, err): void;
  cleanup(sessionId): void;                        // 连接断开时
}
```
- 超时（如 30s）未回传 -> 自动 resolve 一个 `success=false, data="工具执行超时"` 的结果，避免 graph 永久挂起。
- `/api/chat` 的 `req.on('close')` 触发 `cleanup`（手机断开/取消）-> reject，后端停止本轮。

### 6.6 工具 schema（`tools.ts`）

- 用 `@langchain/core/tools` 的 `tool()` + zod 定义 21 个工具的**入参 schema**（与现有 `ToolRegistry` 一一对应）。
- `.func` 为 stub（`throw new Error('executed on device')`）--**永远不会被后端调用**，因为自定义 `tools` 节点用 `interrupt` 接管了执行。schema 仅用于 `bindTools` 让 LLM 知道工具签名。
- 工具清单（沿用现有 21 个）：`query_today_courses` / `query_week_courses` / `query_current_week` / `query_next_exam` / `query_all_exams` / `query_grades` / `query_gpa` / `query_schedule` / `check_login_status` / `check_time_conflict` / `query_reminder_settings` / `has_course_data` / `create_schedule` / `delete_schedule` / `sync_courses_to_cloud` / `sync_exams_to_cloud` / `sync_all_to_cloud` / `download_all_from_cloud` / `set_reminder_enabled` / `set_remind_minutes` / `refresh_reminders` / `navigate_to_page`。

### 6.7 系统提示词（`prompt.ts`）

- 把 `AssistantPage.ets` 里的 `SYSTEM_PROMPT` + `APP_KNOWLEDGE` + `DETAIL_KEYWORDS` 关键词判断逻辑**整体迁到后端**。
- 后端依据用户消息命中关键词决定是否追加 `APP_KNOWLEDGE`（复刻现有 `needsDetailedContext` 行为）。
- 手机不再持有提示词（减少反编译泄露 + 便于迭代不用重打包）。

### 6.8 环境变量（`.env`）

```env
DEEPSEEK_API_KEY=sk-...              # 已有
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash     # key 已有该模型权限，沿用
PROXY_AUTH_KEY=uestc-helper-proxy-key-change-me
PORT=3000
TOOL_TIMEOUT_MS=30000
CHECKPOINT_DB_PATH=./checkpoints.sqlite
```

---

## 7. 前端改造（ArkTS）

### 7.1 删除 / 新增 / 保留

| 文件 | 动作 | 说明 |
|---|---|---|
| `common/agent/AgentOrchestrator.ets` | **删除** | 大脑搬到后端。其 `AgentCallbacks` 接口保留（迁到新 client 文件） |
| `common/agent/BackendAgentClient.ets` | **新增** | 薄客户端：发请求、收 typed SSE、执行工具、回传结果。对外暴露与 `AgentOrchestrator` 相同的 `run()`/`cancel()` + `AgentCallbacks` |
| `common/agent/ToolExecutor.ets` | **保留不动** | 工具执行逻辑不变（仍由 `BackendAgentClient` 调用） |
| `common/agent/ToolRegistry.ets` | **精简** | 移除 `getToolsSchema`/入参 schema（后端职责）；保留 `getToolDisplayName`/`getRiskLevel`/`requiresConfirmation`（UI 用） |
| `pages/quick/AssistantPage.ets` | **小改** | `sendMessage()` 里把 `new AgentOrchestrator(...)` 换成 `new BackendAgentClient(...)`；其余 UI/会话/格式化逻辑不变 |
| `common/constants/AppConstants.ets` | **改值** | `AI_PROXY_URL`/`AI_PROXY_KEY` -> `AI_AGENT_URL`(默认值)/`AI_AGENT_KEY`；实际地址从 Settings 读取 |
| `repository/SettingsRepository.ets` | **新增字段** | `agentBackendUrl` 读写 Preferences |
| `pages/classTablePages/AppSettings.ets` | **加 UI** | 新增"助手后端地址"文本框，存 SettingsRepository |

### 7.2 `BackendAgentClient` 设计要点

- 复用现有 `http.requestInStream` + `on('dataReceive')` + `TextDecoder` 消费 SSE（与 `AgentOrchestrator.callAPIStream` 同款机制），但解析的是 §5.3 的 typed 事件，而非 OpenAI delta。
- 事件路由到 `AgentCallbacks`：
  - `text_chunk` -> `onTextChunk(content)`
  - `tool_call` -> 对每个 tool_call：`onToolCallStart` -> 若 `requires_confirmation` 调 `onConfirmationNeeded` -> `ToolExecutor.execute()` -> `onToolCallResult`；收集全部结果后 `POST /api/tool-result` 回传
  - `final` -> `onComplete()`
  - `error` -> `onError(message)`
- 后端地址从 `SettingsRepository` 读取（用户在 AppSettings 填），`AppConstants.AI_AGENT_URL` 仅作默认回退。
- `cancel()`：`httpRequest.destroy()` 关闭 SSE（后端 `req.on('close')` 触发清理）。
- **并发**：SSE 长连接 + 独立的 `/api/tool-result` POST 连接并存，互不阻塞。
- `AgentCallbacks` 接口签名不变 -> `AssistantPage` 的回调实现一字不改，只换实例化那一行。

### 7.3 `AssistantPage.ets` 改动点（最小化）

```diff
- import { AgentOrchestrator, AgentCallbacks, AgentMessage } from '../../common/agent/AgentOrchestrator';
+ import { BackendAgentClient, AgentCallbacks } from '../../common/agent/BackendAgentClient';
  ...
- const orchestrator: AgentOrchestrator = new AgentOrchestrator(executor, callbacks);
+ const client: BackendAgentClient = new BackendAgentClient(executor, callbacks);
- orchestrator.runStream(systemContent, history);
+ client.run(history);   // systemPrompt 由后端注入，不再前端拼装
```
- `SYSTEM_PROMPT` / `APP_KNOWLEDGE` / `DETAIL_KEYWORDS` / `needsDetailedContext` 从本文件**移除**（迁后端）。
- 会话历史仍存本地 Preferences 用于 UI 展示（见 §8.4）。
- `requestConfirmation` / `formatToolResult` / `getToolDisplayName` 等 UI 方法**保留**。

---

## 8. 网络与配置

### 8.1 电脑侧

1. **查 LAN IP**：`ipconfig` -> "无线局域网适配器 WLAN" 的 IPv4（如 `192.168.1.100`）。
2. **Windows 防火墙**：放行入站 TCP 3000（或设 `PORT`）。PowerShell（管理员）：
   ```powershell
   New-NetFirewallRule -DisplayName "ai-agent" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
   ```
3. **启动后端**：`npm run dev`（监听 `0.0.0.0:3000`，不要只听 `127.0.0.1`）。Express 默认 `app.listen(PORT)` 监听全部网卡即可。
4. （建议）路由器给电脑做 DHCP 静态绑定，避免 IP 漂移。

### 8.2 手机侧

- 在 **AppSettings** 的"助手后端地址"填 `http://192.168.1.100:3000`（存 Preferences，IP 变了改这里即可，免重编译）；`AppConstants.AI_AGENT_URL` 仅作默认回退。
- 手机与电脑连同一 WiFi。
- 自测：手机浏览器访问 `http://192.168.1.100:3000/health` 应返回 `{"status":"ok"}`。

### 8.3 HarmonyOS 明文 HTTP 配置（已确认无需改动）

- 全项目 grep 无 `networkConfig`/`cleartextTraffic`/`securityConfig`，且当前 app 对 `http://121.36.101.82:3000` 明文 HTTP 可用 -> **全局 `allowsCleartext`**（API 22 默认放行明文）。
- 换 LAN IP **无需改 `module.json5` 或任何配置**。（后续若上远程/隧道再考虑 HTTPS。）

### 8.4 会话/历史存储策略（双存储，务实选择）

- **后端**：持久化检查点（SQLite）是 LLM 上下文的**唯一真实源**（按 `session_id`/thread_id），重启不丢。
- **手机**：继续在 Preferences 存 `displayMessages`（仅用于 UI 展示/历史面板/离线查看）。
- 两者无需强同步：每轮手机消息->后端轮次->流式回显，天然保持显示一致。
- "新建对话" -> 生成新 `session_id`（既是本地会话 id 也是后端 thread_id）。
- （可选增强，§11）后端加 `GET /api/history/:session_id` 让手机从后端拉取真实历史。

---

## 9. 分阶段实施计划

> 每阶段独立可验收。建议每完成一阶段就 `git commit`（仓库在 `Application/` 内）。
> 编译验证：改完 ArkTS 跑 `build.bat`（增量 ~5s）；每阶段收尾跑 `D:\harmony\helper_app\_clean_build.bat`（全量 ~26s）确认 0 error。

### 阶段 0：基线与脚手架
- [ ] 在目标目录 `npm install` LangGraph 依赖。
- [ ] 保留旧 `index.ts` 为 `index.legacy.ts`（备份），新建 `src/` 结构。
- [ ] `.env` 补充 `DEEPSEEK_MODEL` / `DEEPSEEK_BASE_URL` / `TOOL_TIMEOUT_MS` / `CHECKPOINT_DB_PATH`。
- **验收**：`npm run dev` 启动无报错；`/health` 200。

### 阶段 1：后端 Graph + LLM（不接手机）
- [ ] `llm.ts`：`ChatOpenAI` 接 DeepSeek，`bindTools`。
- [ ] `tools.ts`：21 工具 schema（stub func）。
- [ ] `prompt.ts`：迁入 `SYSTEM_PROMPT` + `APP_KNOWLEDGE` + 关键词判断。
- [ ] `graph.ts`：`agent`/`tools` 节点 + 条件边 + SQLite 持久化 checkpointer。
- [ ] 临时 `/api/chat`：遇到 `interrupt` 时先用**本地 mock 执行器**（自动回假数据）跑通。
- **验收**：用 curl/Postman 发 `POST /api/chat`，能看到 SSE `text_chunk` + `tool_call` + 流式回答；多轮工具调用正常。

### 阶段 2：后端 SSE + 工具回传 + 注册表
- [ ] `registry.ts`：`PendingToolRegistry`（含超时、cleanup）。
- [ ] `/api/chat` 改为"中断 -> 等待手机回传 -> resume"真实流程。
- [ ] `/api/tool-result` 端点。
- [ ] 写一个 Node 测试脚本模拟手机：收 `tool_call` -> 回传假结果 -> 收最终回答。
- **验收**：测试脚本跑通完整"消息->工具中断->回传->最终回答"闭环；超时/断开路径正确清理。

### 阶段 3：手机端 `BackendAgentClient` + 接线
- [ ] 新增 `common/agent/BackendAgentClient.ets`（typed SSE 解析 + 工具回传）。
- [ ] 精简 `ToolRegistry.ets`（去 schema，留 UI 元数据）。
- [ ] `AssistantPage.ets`：换实例化、删提示词常量、`sendMessage` 改调用。
- [ ] `AppConstants`：改 `AI_AGENT_URL`/`AI_AGENT_KEY`（默认值）。
- [ ] `SettingsRepository` + `AppSettings`：新增"助手后端地址"配置项（存 Preferences）。
- [ ] `module.json5`：明文放行已确认无需改（§8.3）。
- [ ] 删除 `AgentOrchestrator.ets`（单独 commit，便于回退）。
- **验收**：DevEco 真机/模拟器连后端，发"我今天有几节课"能流式返回并展示工具气泡与结果；确认弹窗对高风险工具正常弹出；导航/同步等副作用工具执行正确。（Previewer 不能发网络请求，必须用模拟器/真机。）

### 阶段 4：端到端联调与体验
- [ ] 真机（同 WiFi）跑通 21 个工具的典型问法。
- [ ] 取消（发到一半退出页面）、超时、后端关停等异常路径。
- [ ] 多会话切换、历史保留。
- **验收**：体验与改造前持平或更优（流式更顺、模型不变）；无回归。

### 阶段 5：加固与清理
- [ ] 错误信息中文化、连接重试（弱网）、后端不可达友好提示。
- [ ] 后端日志（每轮消息数/工具/耗时）。
- [ ] 退役旧 `CloudProgram/ai-proxy`：直接停 `ai-proxy.service` + 删除旧代码。
- **验收**：日志可观测；旧代理代码已删除、手机无残留引用。

---

## 10. 风险与取舍

### 10.1 手机必须保持长连接
- SSE 连接在等待工具结果期间持续打开；若手机杀后台/退页面，本轮中断。后端靠 `req.on('close')` 清理。
- 取舍：可接受（对话只在页面打开时发生）。若需后台持续对话，未来可上推送/WS。

### 10.2 DeepSeek 模型名（已定）
- 用户 key 已有 `deepseek-v4-flash` 权限，**沿用不变**（`DEEPSEEK_MODEL=deepseek-v4-flash`）。
- 备选：`deepseek-chat`(V3) 也支持 function calling；`deepseek-reasoner`(R1) 工具调用支持差、不适合。
- 联调时验证一次 `deepseek-v4-flash` 的工具调用是否正常；若异常改 env 切 `deepseek-chat`。

### 10.3 旧 ECS 代理的去留（已定：直接停服并删除）
- 本地后端上线后，`CloudProgram/ai-proxy`（ECS）不再被手机引用 -> **直接停 `ai-proxy.service` 并删除旧代码**。
- ECS 服务器（121.36.101.82）保留，未来若上远程可把 LangGraph 后端部署上去（见 §11）。

### 10.4 工具 schema 双份维护
- 后端 `tools.ts`（给 LLM）与手机 `ToolRegistry`（给 UI）存在重复定义。
- 取舍：先各自维护 + 注释标明"需同步"；后续可用共享 JSON schema 文件统一（§11）。

### 10.5 明文 HTTP + 共享密钥
- 本地 WiFi 下 `X-Proxy-Key` 明文传输可接受。若扩展到不可信网络需上 HTTPS + 真鉴权（每用户 token）。

### 10.6 `reasoning_content`
- 现有 app 捕获 DeepSeek 的 `reasoning_content` 但不展示。LangChain 的 OpenAI 适配默认不透传该字段。
- 取舍：本期不展示思考链（与现状一致）；若要展示，后端单独捕获并加 `reasoning_chunk` 事件（§11）。

---

## 11. 后续可选增强（本期不做）

1. **后端历史 API**：`GET /api/history/:session_id`，手机从后端拉真实历史，去掉本地双存储。
2. **共享工具 schema**：单一 JSON 定义，前后端各自生成（TS schema + ArkTS UI 元数据），消除重复。
3. **思考链展示**：`reasoning_chunk` 事件 + UI 折叠区。
4. **远程访问**：把 LangGraph 后端部署到 ECS，或本地 + frp/ngrok/Cloudflare Tunnel；上 HTTPS + 用户级鉴权。
5. **多 Agent / 规划**：用 LangGraph 的 subgraph、planner、memory 做更复杂任务（如"整理本周学业并设提醒"多步规划）。
6. **可观测**：LangSmith / LangGraph Studio 接入，可视化状态机与 trace。

---

## 12. 开放问题（已全部确认）

> 所有关键决策已定，可开工：
> - 数据访问=手机执行工具 / LLM=DeepSeek(`deepseek-v4-flash`) / 框架=LangGraph.js / 部署=本地同 WiFi
> - 持久化=SQLite 检查点 / 后端地址=设置页可填 / 明文=全局 allowsCleartext 无需改
> - 旧 ECS 代理=直接停服删代码 / 会话历史=维持本地双存储

联调时仅需验证：`deepseek-v4-flash` 工具调用是否正常（异常则切 `deepseek-chat`）。

---

## 13. 一句话总结

> 后端用 **LangGraph.js** 在本地电脑跑 Agent 大脑（DeepSeek + interrupt 式工具中断），手机 ArkTS 只做**展示 + 工具执行**；工具调用通过 **SSE 下行 + HTTP POST 回传**桥接，数据不离手机，现有 `ToolExecutor`/UI 几乎全保留，删除 `AgentOrchestrator`、新增薄客户端 `BackendAgentClient`。
