# AI 助手子系统 (AI_AGENT.md)

> 当前架构：**后端 LangGraph 大脑（本地电脑）+ ArkTS 前端（展示 + 工具执行）**。
> 迁移过程见 [AI_AGENT_PLAN.md](./AI_AGENT_PLAN.md)；逐阶段改动见 [CHANGES.md](./CHANGES.md)。

## 架构

```
手机(ArkTS)                           本地电脑(后端 ai-proxy)
┌──────────────────────────┐         ┌──────────────────────────────┐
│ AssistantPage.ets        │  SSE ↓  │ Express + LangGraph.js       │
│  ├─ 会话/历史/气泡 UI      │────────▶│  ├─ POST /api/chat -> SSE 流  │
│  ├─ 确认弹窗              │         │  ├─ StateGraph(Messages)      │
│  └─ BackendAgentClient    │         │  │   ├─ agentNode(DeepSeek)   │
│     ├─ SSE 解析            │  POST ↑ │  │   └─ toolsNode(interrupt)  │
│     └─ ToolExecutor(30工具)│────────▶│  ├─ SqliteSaver 检查点        │
│        读写手机本地数据     │         │  └─ DeepSeek API(云)          │
└──────────────────────────┘         └──────────────────────────────┘
```

- **大脑在后端**：LangGraph 编排、DeepSeek 推理、SQLite 持久化会话状态。手机只发用户新消息（`{session_id, message}`），**历史由后端检查点管理**。
- **工具在手机端执行**：30 个工具全部读写设备本地数据（课表/考试/成绩/日程/日历）。后端 `tools.ts` 只定义 schema + stub，执行时走 interrupt，把 `tool_calls` 推给手机，手机跑完 POST 回结果，后端 `Command({resume})` 继续。

## 协议（SSE 下行 + HTTP POST 上行）

1. `POST /api/chat` `{session_id, message}` -> 后端开 SSE 流，事件类型：
   - `text_chunk` - LLM 增量文本
   - `tool_call` - `{batch_id, tool_calls:[{tool_call_id,name,args,requiresConfirmation}], ...}` 后端挂起等待工具结果
   - `final` - 正常结束
   - `error` - 错误
2. 手机收到 `tool_call`：按 `requiresConfirmation` 决定是否弹确认框；执行 `ToolExecutor.execute(name, args)`；把结果 `POST /api/tool-result` `{session_id, batch_id, results:[{tool_call_id,success,data}]}`。
3. 后端收到结果 -> `graph.stream(new Command({resume: results}), config)` 唤醒 `toolsNode`，继续推理。
4. 断开检测：`res.on('close')` + `finished` 守卫；超时由 `PendingToolRegistry`（`TOOL_TIMEOUT_MS`）处理，超时回填错误结果。

## 代码位置

- **后端**（独立 git 仓库）：`C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`
  - `src/index.ts` - Express，`/api/chat` + `/api/tool-result` + `/health`
  - `src/graph.ts` - StateGraph：`agentNode`（注入 system prompt）、`toolsNode`（interrupt/resume）、`SqliteSaver`
  - `src/llm.ts` - `createLLM()` -> `ChatOpenAI`（DeepSeek OpenAI 兼容）
  - `src/tools.ts` - **30 个工具的 schema + `toolMeta`**（requiresConfirmation / riskLevel）
  - `src/prompt.ts` - `SYSTEM_PROMPT` / `APP_KNOWLEDGE` / `DETAIL_KEYWORDS` / `buildSystemPrompt`
  - `src/registry.ts` - `PendingToolRegistry`（挂起工具的超时与清理）
  - `.env`（gitignored）- `DEEPSEEK_API_KEY` / `DEEPSEEK_BASE_URL` / `DEEPSEEK_MODEL=deepseek-v4-flash` / `PROXY_AUTH_KEY` / `PORT=3000` / `CHECKPOINT_DB_PATH`
  - 运行：`npm run dev`（tsx watch）
- **前端**（根仓库 `D:\harmony\helper_app`，代码在 `Application/`）：`entry/src/main/ets/common/agent/`
  - `BackendAgentClient.ets` - SSE 流 + tool-result 回传 + 断开/取消/重入保护
  - `ToolExecutor.ets` - 30 个工具的实际执行（switch 分发到各 service）
  - `ToolRegistry.ets` - 工具定义镜像 + `getRiskLevel`（确认弹窗显示风险等级用）
- **入口页**：`pages/quick/AssistantPage.ets`
- **后端地址**：用户在「应用设置 -> 助手后端」填写（默认 `http://192.168.1.100:3000`，填实际 LAN IP）。存 `SettingsRepository.getAgentBackendUrl`。明文 HTTP 已全局 `allowsCleartext`，无需改 module.json5。

## 工具清单（30 个）

**查询 / 上下文（低风险，无需确认）**
- `get_current_datetime` - 日期/时间/星期/教学周/学期（**LLM 时间上下文，涉及"今天/本周"先调它**）
- `query_today_courses` / `query_tomorrow_courses` / `query_week_courses` / `query_courses_by_date` - 课表查询
- `query_course_by_name` - 按课名查时间/教室/周次
- `query_current_week` - 当前教学周
- `query_next_exam` / `query_all_exams` - 考试
- `query_grades` / `query_gpa` - 成绩
- `query_schedule` - 日程（可按日期）
- `check_time_conflict` - 时间冲突检测
- `check_login_status` / `has_course_data` - 状态
- `query_reminder_settings` - 提醒设置
- `list_calendar_events` - 列出系统日历事件

**写入（中/高风险，需确认）**
- `create_schedule` / `update_schedule` / `delete_schedule` - 应用内日程 CRUD
- `add_to_calendar` - 建日程并写入系统日历，带"提前 X 分钟提醒"
- `add_exam_to_calendar` / `add_course_to_calendar` - 考试/课程写入系统日历
- `remove_calendar_event` - 从系统日历移除
- `set_reminder_enabled` / `set_remind_minutes` / `refresh_reminders` - 提醒设置
- `sync_courses_to_cloud` / `sync_exams_to_cloud` / `sync_all_to_cloud` / `download_all_from_cloud` - 云同步（high）
- `navigate_to_page` - 跳转页面（course_table/exam/grade/schedule/settings/course_import/exam_import/grade_import/assistant/home）

## 添加一个新工具（改 3 处）

1. **后端 `src/tools.ts`**：加 `tool()` schema + `toolMeta[name] = {requiresConfirmation, riskLevel}`。
2. **前端 `ToolExecutor.ets`**：加 `switch` case + 私有执行方法（调对应 service）。
3. **前端 `ToolRegistry.ets`**：加 `ToolDefinition`（参数 / required / requiresConfirmation / riskLevel）--确认弹窗读 `getRiskLevel`，必须与后端 meta 一致。

> schema 只在后端给 LLM `bindTools`；执行只在手机端；`ToolRegistry` 是风险等级镜像。三者工具名必须一致。

## 确认与风险

- 是否弹确认：后端在 `tool_call` 事件里带 `requiresConfirmation`（来自 `toolMeta`），`BackendAgentClient` 据此调 `onConfirmationNeeded`。用户拒绝则回填"用户拒绝了此操作"。
- 风险等级显示：`AssistantPage` 调 `ToolRegistry.getRiskLevel(name)` 在确认弹窗展示 low/medium/high。
- 默认：未知工具 = low / 不确认。

## 系统日历工具要点

- 权限：写日历的工具先 `ensureCalendarPermission()`（`context as common.UIAbilityContext` 请求 `READ_CALENDAR` / `WRITE_CALENDAR`）。拒绝则返回失败，不崩溃。
- 关联：`add_to_calendar` 写完日历后回填 `calendarEventId` 到应用内日程；`remove_calendar_event` 同步把应用内日程的 `calendarEventId` 清零；`update_schedule` 对已关联的做 `upsertEventReminder`。
- 考试 / 课程写日历**不另建应用内日程**（避免与 `buildExamEvents` / `buildCourseEvents` 自动生成的重复），仅写系统日历。
- `CalendarKitReminderService.listEvents(context,start,end)` - 读系统日历事件（`calendarManager.Event` 字段为 optional，已 `|| 0` 兜底）。

## 会话历史

- 后端 SQLite 检查点是 LLM 上下文**唯一真实源**（`thread_id = session_id`）。
- 前端**额外**在本地 preferences 双存储一份历史（仅用于 UI 气泡回显，不发给后端）。

## 已知交互

- `refresh_reminders`（`ReminderService`）会先 `CalendarKitReminderService.clearAllEvents` 再重建提醒--这是**原有行为**。通过 `add_to_calendar` 写入且 `addToCalendar=true` 的事件会在 refresh 时被重新纳入（仅当通知代理失败才走日历）。本次扩充未改此逻辑。
- 弱网下 `BackendAgentClient` 连接失败直接报错（提示去设置检查后端地址），未做自动重试。

## 端到端测试

见 [BUILD_AND_TEST.md](./BUILD_AND_TEST.md) 的「AI 助手 E2E」一节。
