# 改造变更记录 (CHANGES.md)

> AI 助手后端化改造的逐阶段变更记录。方案见 `plan.md`。
> - **后端**仓库：`C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`（独立 git 仓库）
> - **前端**仓库：`D:\harmony\helper_app`（项目根，2026-08 由 `Application/` 内迁移而来，历史保留）

---

## 阶段 0：后端脚手架 ✅

**位置**：后端目录 `C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`
**Commit**：`9648e3e feat: phase 0 后端脚手架`

### 做了什么
把原"薄代理"目录改造成 LangGraph.js Agent 后端项目骨架，跑通最小 HTTP 服务。

### 新增/修改文件
| 文件 | 说明 |
|---|---|
| `.gitignore` | 排除 `node_modules/` `dist/` `.env` `checkpoints.sqlite*` `*.log` |
| `tsconfig.json` | ESM 配置（`module: ESNext`、`moduleResolution: Bundler`、`strict`） |
| `package.json` | `type: module`；脚本 `dev`(tsx watch)/`start`(tsx)/`typecheck`(tsc --noEmit) |
| `.env` | 本地真实密钥 + 新增 `DEEPSEEK_BASE_URL`/`DEEPSEEK_MODEL`/`TOOL_TIMEOUT_MS`/`CHECKPOINT_DB_PATH`（不入库） |
| `.env.example` | 配置模板（占位密钥） |
| `src/index.ts` | Express 服务：`GET /health`、`POST /api/chat`（占位 501）、`POST /api/tool-result`（占位 501）、`checkAuth`（X-Proxy-Key） |

### 依赖（已安装）
`@langchain/core@1.2.5` `@langchain/langgraph@1.4.9` `@langchain/openai@1.5.6` `@langchain/langgraph-checkpoint-sqlite@1.0.3` + `express` `dotenv` `tsx` `typescript`

### 验证
- `npm run start` -> `[ai-agent] listening on port 3000`
- `curl http://localhost:3000/health` -> `200 {"status":"ok",...}`
- `curl -X POST .../api/chat`（无 auth）-> `401 Unauthorized`

---

## 阶段 1：后端 Graph + LLM + mock 执行器 ✅

**位置**：后端目录
**Commit**：`84a05a1 feat: phase 1 LangGraph graph + LLM + mock 执行器`（已 amend 修正 .gitignore）

### 做了什么
实现 LangGraph Agent 大脑：agent/tools 节点 + interrupt 工具中断 + DeepSeek LLM + SQLite 持久化检查点 + SSE 流式。`/api/chat` 用 **mock 执行器**（自动回假数据）跑通完整闭环，暂不接手机。

### 新增/修改文件
| 文件 | 说明 |
|---|---|
| `src/llm.ts` | `ChatOpenAI` 接 DeepSeek（`deepseek-v4-flash`，OpenAI 兼容 baseURL）+ `streaming` |
| `src/tools.ts` | 21 工具 zod schema（stub func，仅给 `bindTools`）+ `toolMeta`（确认标志/风险等级，给 SSE 事件用） |
| `src/prompt.ts` | 从 `AssistantPage.ets` 迁入 `SYSTEM_PROMPT`/`APP_KNOWLEDGE`/`DETAIL_KEYWORDS`/`buildSystemPrompt`（关键词决定是否注入知识库） |
| `src/graph.ts` | `StateGraph`(MessagesAnnotation)：`agent` 节点（注入 system 提示词 + 调 LLM）、`tools` 节点（`interrupt` 把工具调用交给手机）、条件边、`SqliteSaver.fromConnString` 持久化检查点 |
| `src/index.ts` | `/api/chat`：SSE 流式 + `streamMode:['messages']` 取 token + `getState` 检测中断 + 发 `tool_call` 事件 + mock 执行器 `Command({resume})` 恢复；`/api/tool-result` 仍占位（阶段 2） |
| `src/index.ts`（bug 修复） | `import 'dotenv/config'` 置首行--原 `dotenv.config()` 在 import 后执行，导致顶层 `createLLM()` 读不到密钥 |

### 关键设计点
- **agent 节点**每次按最近一条 human 消息重建 system 提示词（不写入 state，避免历史膨胀）。
- **tools 节点**用 `interrupt({toolCalls})`，一轮多个 tool_calls **合并为一次中断/一次回传**（减少往返）。
- **检查点**用 SQLite（`checkpoints.sqlite`），后端重启不丢对话上下文。
- **SSE 事件**：`text_chunk`（流式 token）/ `tool_call`（含 batch_id + 每工具的 requiresConfirmation/riskLevel）/ `final` / `error`。

### 验证（curl 实测）
- `"我今天有几节课"` -> `tool_call`(query_today_courses) -> mock 回 2 节课 -> 逐 token 流式回答 -> `final` ✅
- 同 session 第二轮 `"那本周呢"` -> 一次 `tool_call` 含 **2 个工具**（query_week_courses + query_current_week），验证批量中断/回传 + 跨轮记忆 ✅
- `"你好"`（非工具问题）-> 无 tool_call，直接 `final`，条件边正确路由到 END ✅
- `checkpoints.sqlite` 落盘存在 ✅
- `tsc --noEmit` 0 error ✅

### 未做（留给后续阶段）
- `/api/tool-result` 真实端点 + `PendingToolRegistry`（阶段 2，替换 mock 执行器）
- 手机端接线（阶段 3）

---

## 阶段 2：后端 SSE + 工具回传 + 注册表 ✅

**位置**：后端目录
**Commit**：`33dd4e4 feat: phase 2 /api/tool-result + PendingToolRegistry + 断开检测`

### 做了什么
把 Phase 1 的 mock 执行器换成真实的"中断 -> 等手机回传 -> resume"流程；加 `/api/tool-result` 端点和挂起结果注册表；修复断开检测。

### 新增/修改文件
| 文件 | 说明 |
|---|---|
| `src/registry.ts` | `PendingToolRegistry`：按 session_id 索引；`register`(返回 promise)/`resolve`(回传到达)/`cleanup`(断开)；超时返回 null |
| `src/index.ts` | 去掉 mock 执行器；`/api/chat` 中断时 `registry.register`+await 手机回传；`/api/tool-result` 端点 `registry.resolve`；超时/断开用错误结果 resume 避免 graph 卡死；**修复断开检测**（`res.on('close')`+finished 守卫替代 `req.on('close')`） |
| `test/phone-sim.mjs` | 模拟手机联调脚本：POST /api/chat -> 解析 SSE -> 收 tool_call 回传假结果 -> 收最终回答 |
| `test/phone-disconnect.mjs` | 断开测试：收到 tool_call 后 abort，验证服务端立即清理 |

### 关键设计点
- `/api/chat` 的 SSE 连接在等待工具结果期间保持打开；`/api/tool-result` 是独立 POST，到达后 resolve 挂起的 promise，`/api/chat` 恢复并继续 `graph.stream({command:{resume}})`。
- 超时（30s）或客户端断开 -> registry 返回 null -> 调用方用 `success=false` 的错误结果 resume，graph 收尾，检查点不卡死。
- 断开检测用 `res.on('close')`（响应流关闭）+ `finished` 守卫，只在未正常结束时 cleanup；`req.on('close')` 会在请求体读完后误触发，已弃用。

### 验证
- 单工具 + 2 工具批量：`tool_call` -> `/api/tool-result` 回传 -> `resume` -> 流式回答 -> `final`（~3-5s）✅
- 断开测试：abort 后服务端**立即**打印 `client disconnected mid-turn` -> `cleanup` -> 错误结果 resume（不傻等超时）✅
- 正常完成不再误报断开 ✅
- `tsc --noEmit` 0 error ✅

### 未做（留给后续阶段）
- 手机端接线（阶段 3）：`BackendAgentClient` + 精简 `ToolRegistry` + `AssistantPage` 改造 + 后端地址设置项

---

## 阶段 3：前端 BackendAgentClient + 接线 ✅

**位置**：前端仓库 `Application/`（commit 到原有 git）
**Commit**：`7d1d52a feat: phase 3 前端接线 BackendAgentClient + 后端地址设置`

### 做了什么
手机端从"设备端 Agent"改为"薄客户端 + 工具执行"：删除 `AgentOrchestrator`，新增 `BackendAgentClient` 对接后端 LangGraph Agent；提示词/LLM 调用/工具调度全部移至后端。加"助手后端地址"设置项（IP 变免重编译）。

### 新增/修改/删除文件
| 文件 | 动作 | 说明 |
|---|---|---|
| `common/agent/BackendAgentClient.ets` | **新增** | 薄客户端：`AgentCallbacks`/`AgentMessage`（从 AgentOrchestrator 迁入，签名不变）；POST `/api/chat` 收 typed SSE 路由到回调；收 `tool_call` 时本地执行 `ToolExecutor`（含确认弹窗）+ POST `/api/tool-result` 回传；后端地址从 `SettingsRepository` 读，`AppConstants` 默认回退；`cancel()`/断开/超时/无法连接兜底（`finish` 防重复回调） |
| `common/agent/AgentOrchestrator.ets` | **删除** | 大脑搬到后端 |
| `common/constants/AppConstants.ets` | 改 | `AI_PROXY_URL/KEY` → `AI_AGENT_URL/KEY` + `AI_CHAT_PATH`/`AI_TOOL_RESULT_PATH`/`SETTING_AGENT_BACKEND_URL_KEY` |
| `repository/SettingsRepository.ets` | 改 | 新增 `getAgentBackendUrl`/`saveAgentBackendUrl` |
| `common/agent/ToolRegistry.ets` | 改 | 移除 `getToolsSchema`（工具 schema 现由后端 `tools.ts` 提供） |
| `pages/quick/AssistantPage.ets` | 改 | 换实例化 `new BackendAgentClient(context, executor, callbacks)` + `client.run(sessionId, history)`；移除 `systemContent` 拼装 |
| `pages/classTablePages/AppSettings.ets` | 改 | 新增"助手后端"卡片（`TextInput` 配置后端地址，`onChange` 持久化到 Preferences） |

### 关键设计点
- `AgentCallbacks` 接口签名不变 -> `AssistantPage` 的回调实现（气泡/确认弹窗/格式化）一字未改，只换实例化那一行。
- 手机只发用户新消息（`{session_id, message}`），不发历史--后端 SQLite 检查点是 LLM 上下文唯一真实源。
- `BackendAgentClient` 与 `phone-sim.mjs`（阶段 2）走同一协议，已用 phone-sim 验证过后端，前端只是把模拟器换成真 UI。
- 后端地址默认 `http://192.168.1.100:3000`，用户在"应用设置-助手后端"填实际 LAN IP。

### 验证
- `clean assembleHap` **0 error**（`CompileArkTS` 重跑通过；警告主要为 `@hw-agconnect/auth` 模块预先存在的 `sourceMapsPath` 警告，与本次改动无关）✅
- 真机/模拟器端到端联调 = 阶段 4（需用户在 DevEco 运行 + 后端同 WiFi）。

### 已知遗留（留给阶段 5 清理）
- `AssistantPage.ets` 里的 `SYSTEM_PROMPT`/`APP_KNOWLEDGE`/`DETAIL_KEYWORDS`/`needsDetailedContext` 现为死代码（提示词已迁后端），编译不报错但待删。

---

## 阶段 5：加固与清理（部分完成）

### 已完成
**Commit**：`c1ea4f1 chore: 移除 AssistantPage 死代码`（Application 仓库）
- 删除 `AssistantPage.ets` 中现已无引用的 `SYSTEM_PROMPT`/`APP_KNOWLEDGE`/`DETAIL_KEYWORDS`/`needsDetailedContext`（提示词与关键词判断已迁后端 `prompt.ts`）。
- `clean assembleHap` 0 error。
- **删除旧代理源码** `CloudProgram/ai-proxy/`（未被任何 git 跟踪；新前端走 `/api/chat`，旧薄代理 `/v1/chat/completions` 透传已不兼容，退役）。`clouddb`/`cloudfunctions` 保留（云同步仍用）。
- 后端不可达友好提示：`BackendAgentClient` 在连接失败时提示"请确认电脑已开机且在同一 WiFi，地址在应用设置-助手后端中配置"。
- 后端日志：每轮打印 session/batch/工具名/等待/恢复/超时/断开。

### 待办（需用户参与）
- **停 ECS 上的旧 `ai-proxy.service`**：本地源码已删，但 ECS（121.36.101.82）上 systemd 服务仍在运行。**建议等阶段 4 真机联调通过、新 app 装到手机后再停**（停服会使旧版 app 的 AI 助手失效直到切换）。确认后我可 SSH 执行 `systemctl stop ai-proxy && systemctl disable ai-proxy`。
- **弱网重试**：当前 `BackendAgentClient` 连接失败直接报错；如需弱网下自动重试可后续加。
- **阶段 4 真机/模拟器 E2E 联调**：见下方测试指引。

---

## 阶段 4 修复：课表默认学期 + 首页日志刷屏（Commit `d0b4bfc`）

### 问题
1. **课表仍显示上学期**：`CourseModel.getCurrentWeek()` 硬编码 `new Date(2026, 2, 2)`（2026-03-02，春季行课日），2026-08-07 算出第 23 周，课表/首页都停在 2025-2026 第二学期。
2. **"Home: 无未来考试" 日志刷屏**：`Index.ets` 1s `tickTimer` 每 5s 调一次 `getNextExam()`，`getUpcomingExams` 在无未来考试时打印一条**无 gate** 的日志。春季考试全过期后每 5s 打一条。**不是重复查询**——tick 只做内存过滤，考试数据仅在 `loadPageData`（进页面时）加载一次，无存储/网络访问。

### 改动
- `model/classTableModel/CourseModel.ets` `getCurrentWeek`：锚点 `2026-03-02` → `2026-08-31`（2026-2027 第一学期含 9-01 的**周一**；validWeeks 按周一~周日，用周二 9-01 会整学期错位一周）。开学前 `diffMs<0` 返回第 1 周。
- `common/constants/AppConstants.ets`：`SCHOOL_SEMESTER_START` `2026-02-23`→`2026-09-01`，`SCHOOL_SEMESTER_END` `2026-07-05`→`2027-01-18`（估测放假日，逻辑未使用，可按校历修正）。这两个常量目前未被逻辑引用，仅作文档；真实周次计算在 `getCurrentWeek`。
- `pages/Index.ets` `getUpcomingExams`：新增 `lastNoFutureExamKey` 字段，仅当 `total/zeroTime/past` breakdown 变化时打印一次，消除 tick 刷屏。

### 验证
- `hvigorw assembleHap` **BUILD SUCCESSFUL**，0 error（警告均为预先存在的 `getContext`/`back` deprecated，与本次无关）。

### 说明
- 考试学期默认（`calculateSemesterId()`）对 2026-08 已返回 2026-2027 第一学期，无需改。
- 课表显示的仍是旧导入数据（按 `selectedSemesterId` 本地加载）；新学期需重新导入课表。

---

## 阶段 6：扩充 AI agent 工具集（前端 `743a37b` / 后端 `813bbae`）

### 目标
让 AI 尽可能覆盖整个 app 功能，补齐"基础上下文 + 系统日历读写"两大缺口。

### 新增 9 工具 + 扩展 navigate_to_page

| 工具 | 风险/确认 | 作用 |
|---|---|---|
| get_current_datetime | low/否 | 返回日期/时间/星期/教学周/学期（LLM 之前没有时间上下文，无法正确理解"今天/本周"） |
| query_courses_by_date | low/否 | 任意日期的课表（自动换算周次+星期） |
| query_tomorrow_courses | low/否 | 明天的课 |
| query_course_by_name | low/否 | 按课名模糊查上课时间/教室/教师/生效周次 |
| list_calendar_events | low/否 | 列出系统日历里本应用写入的事件（默认未来30天） |
| add_to_calendar | medium/是 | 建日程并写入系统日历，带"提前 X 分钟提醒"（应用内日程+系统日历各一份并关联） |
| add_exam_to_calendar | medium/是 | 把考试写入系统日历（可指定课名或默认最近一场） |
| add_course_to_calendar | medium/是 | 把课程写入系统日历（可指定课名或当天全部） |
| remove_calendar_event | medium/是 | 按系统日历事件ID移除，并清理应用内日程的关联引用 |
| update_schedule | medium/是 | 编辑已有日程字段，已关联日历的同步 upsert |

`navigate_to_page` 新增页面：course_import / exam_import / grade_import / assistant / home。

### 改动文件
- 后端 `src/tools.ts`：9 个工具 schema + toolMeta + navigate_to_page 描述（`tsc --noEmit` 0 error）。
- 前端 `ToolExecutor.ets`：9 个执行方法 + 辅助（dayLabel/parseDate/ensureCalendarPermission），扩展 navigateToPage。
- 前端 `ToolRegistry.ets`：同步 9 个 ToolDefinition（确认弹窗读 `getRiskLevel`，需保持镜像）。
- 前端 `CalendarKitReminderService.ets`：新增 `listEvents` + `CalendarEventSummary`（calendarManager.Event 字段为 optional，已 `|| 0` 兜底）。
- 前端 `CourseModel.ets`：抽出 `getWeekForDate(date)`，`getCurrentWeek` 复用（按日期查课表需要）。

### 关键设计
- **确认机制**：`BackendAgentClient` 用后端事件里的 `requiresConfirmation` 决定是否弹确认；`AssistantPage` 读 `ToolRegistry.getRiskLevel` 显示风险等级。两者都已同步。
- **日历权限**：写日历的工具先 `ensureCalendarPermission`（cast 为 `common.UIAbilityContext` 请求 READ/WRITE_CALENDAR），拒绝则返回失败但不崩溃；`add_to_calendar` 即使日历失败也会先建应用内日程。
- **关联**：`add_to_calendar` 写完日历回填 `calendarEventId` 到应用内日程；`remove_calendar_event` 同步把应用内日程的 `calendarEventId` 清零；`update_schedule` 对已关联的做 `upsertEventReminder`。
- 考试/课程写日历不另建应用内日程（避免与 `buildExamEvents`/`buildCourseEvents` 自动生成的重复），仅写系统日历。

### 验证
- `hvigorw assembleHap` **BUILD SUCCESSFUL**，0 error。
- 真机 E2E 待测（后端运行时让 AI 调用新工具，日历写入需用户在手机上授权日历权限）。

### 说明
- `refresh_reminders` 仍会 `clearAllEvents` 重建提醒（既有行为，本次未改）；通过 `add_to_calendar` 写入且 `addToCalendar=true` 的事件会在 refresh 时被重新纳入。
- 工具数 21 -> 30。

---

## 阶段 10：接入官方 DevEco CLI + MCP，工具链统一 ✅

**位置**：全局 npm（`@deveco/deveco-cli` v1.2.2）+ 工程级 MCP 配置
**Commit**：待补（CLI/MCP 配置不入 git；脚本在顶层工作区，同样不入 git）

### 做了什么
- 全局安装官方 DevEco CLI（`devecocli`），统一封装 hvigor/ohpm/hdc/emulator/hilog，自动探测本机 `D:\deveco\DevEco Studio`。
- 通过 `devecocli init --mcp --agent opencode --project ./` 配置官方 `deveco-mcp` 到 `Application/.opencode/opencode.json`（stdio：`devecocli serve mcp`），提供 ArkTS/C++ LSP 静态诊断工具 `check` / `restart`。
- 根目录批处理重写为「优先 devecocli、回退 hvigorw」：`_build.bat` / `_clean_build.bat`，新增 `_lint.bat`（`devecocli check lint`，lint 首次获得独立 CLI）。

### 验证
- `devecocli build --modules entry@default --build-mode debug` → BUILD SUCCESSFUL。
- `devecocli check lint` → 22 文件 50 warning / 0 error（均为预先存在，非本次引入）。
- `devecocli docs search TextInput` → 本地文档检索正常。
- MCP `check` 工具：首调返回 sync 提示，二次调用返回 `Index.ets` 结构化诊断（含 deprecated 信息级告警）。
- 批处理注意事项：**`.bat` 内不能用 `setlocal`**（会使 devecocli 报 "Not in a valid project directory"）；文件必须 CRLF。

### 关键设计点
- CLI/MCP 配置（`Application/.opencode/`、全局 npm 包）均不入 git；涉及工具链的说明已同步 `AGENTS.md` / `doc/BUILD_AND_TEST.md`。

---

## 阶段 11：文档/脚本同步 DevEco CLI + MCP（2026-08）

**位置**：根目录（`AGENTS.md` / `CLAUDE.md` / `doc/*` / `_*.bat`）
**Commit**：`chore: 工具链文档与脚本同步 devecocli`（随根仓库迁移一并提交）

### 做了什么
- `AGENTS.md` / `CLAUDE.md` / `doc/BUILD_AND_TEST.md` 补充 DevEco CLI 与 MCP 章节（命令速查、bat 限制、MCP check 预热说明）。

---

## 阶段 12：git 仓库根迁移到项目根 + 文档同步 ✅

**位置**：`D:\harmony\helper_app`（原 `Application/` 内的仓库整体迁出）
**Commit**：`324993b chore: 仓库根迁移到项目根目录（Application/ 前缀）`、`ebb7294 chore: 收纳根目录资源（doc/CloudProgram/脚本/图标）入根仓库 & 根 .gitignore`、`40c8bac feat: 首页五 Tab 重构…`（Tab 重构随本次一并提交）

### 做了什么
- 将 `Application/` 内的 git 仓库**整体迁移到项目根目录**：所有历史提交保留，代码路径统一加 `Application/` 前缀（git mv 191 个文件后重新提交）。
- `CloudProgram/`（云端代码）、`doc/`、`CLAUDE.md`、`AGENTS.md`、`_*.bat`、`icon/`、`playwright/` 均纳入根仓库；新增根 `.gitignore`（`information/` 抓取存档、AI 工具配置 `.agents` / `.claude` / `.opencode`、`node_modules`、构建产物不入库）。
- MCP 配置从 `Application/.opencode/` 移到根 `.opencode/opencode.json`（opencode 从项目根读取配置才生效）。
- 恢复 `core.autocrlf` 等配置，构建验证：`BUILD SUCCESSFUL`。

### 回溯
- 迁移前已备份原 `.git`（`C:\Users\28399\AppData\Local\Temp\opencode\backup\application_git`），克隆副本 `repo-migrate` 亦完整。需要时删根 `D:\harmony\helper_app\.git` 并把备份放回 `Application/.git` 即复原。
