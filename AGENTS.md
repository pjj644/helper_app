# AGENTS.md

> 给 AI 编码助手（Claude Code / Antigravity / OpenCode / Codex）的统一快速上手指令。
> 详细架构与技术规格见 [`doc/`](./doc/)（均为中文），本文件汇总「无需猜测、开箱即用」的核心规范、开发指令与架构要点。

## 1. 仓库结构（核心事实）

- **Git 仓库在项目根目录 `D:\harmony\helper_app`**（2026-08 由 `Application/` 内迁移而来，历史保留，路径带 `Application/` 前缀）。所有项目文件都在此仓库中统一管理。
- **唯一独立仓库**：AI 助手后端 `C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`（在项目目录之外，独立 Git 仓库）。
- **目录布局**：
  - **`Application/`** — HarmonyOS app（ArkTS / API 6.0.2/22），源码 `entry/src/main/ets/`，入口 `EntryAbility.ets` -> `pages/Index.ets`。
  - **`CloudProgram/`** — 云端 Node.js（Cloud DB schema、云函数）。
  - **`doc/`** — 详细技术与架构文档（`ARCHITECTURE.md`, `AI_AGENT.md`, `BUILD_AND_TEST.md`, `CHANGES.md`）。
  - **`information/`** — EAMS 抓取 HTML 存档（体积大且频繁更新，已 .gitignore 不入库）。
- **提交规范**：在根目录执行 `git add` + `git commit -m "type: what & why"`（`feat/fix/refactor/docs/chore`），消息以 `Co-Authored-By: Claude <noreply@anthropic.com>` 结尾；严禁提交 `.env`、密钥或凭据。

## 2. 工具链与 MCP

- **DevEco CLI（官方，`@deveco/deveco-cli` v1.2.2）**：已全局安装，命令 `devecocli`。自动探测 DevEco Studio（本机 `D:\deveco\DevEco Studio`，也可用环境变量 `DEVECO_CLI_STUDIO_PATH` 显式指定）。
- **DevEco MCP 配置**：根目录 `.opencode/opencode.json` 中配置了 `deveco-mcp`（`devecocli serve mcp`，stdio 本地服务，`PROJECT_PATH` 指向 `Application/`；修改后需重启生效）。
  - `check`：ArkTS / C++ LSP 静态诊断（**首次调用会先做项目 sync，返回 "Project is syncing，请 10s 后重试" 属正常**）。
  - `restart`：LSP 卡死后原地重启。
- **Skills 辅助**：可加载 `.agents/skills/arkts-syntax-assistant` 解决 ArkTS 语法与鸿蒙 API 约束。

## 3. 构建与验证（DevEco 路径含空格）

DevEco 安装在 `D:\deveco\DevEco Studio\`（路径含空格）。**严禁直接敲 `hvigorw`**（会因空格或环境变量解析失败）。

### 推荐构建方式（官方 CLI）：
```bash
devecocli build --modules entry@default --build-mode debug   # debug 增量构建
devecocli build clean                                        # 清理产物
devecocli check lint                                         # 运行 code-linter (0 error)
devecocli check compat                                       # 跨 SDK API 兼容扫描
```
- **构建成功标志**：`BUILD SUCCESSFUL`。`@hw-agconnect/auth` 的 `sourceMapsPath` 警告为预先存在，无关紧要。
- **验证手段**：构建 0 error + `devecocli check lint` 0 error + DevEco Previewer / 真机 Logcat。

## 4. 架构速记（`Application/entry/src/main/ets/`）

- **分层模式**：`pages → components → service → repository → model → common`；
- **数据流向**：`Pages / FloatingWindow → Service → Repository → Preferences / Cloud DB`；
- **纯 TS Model 约束**：**`model/` 是纯 TS，严禁任何 `@kit.*` 导入**，只做数据接口定义、JSON 解析与排序计算；
- **常量唯一收归**：`common/constants/AppConstants.ets` 是所有偏好键、URL 路径、路由常量、魔法数字的**唯一来源**，禁止在代码中散落常量；
- **五 Tab 导航**：`pages/Index.ets` 包含发现（Quick，含「云中成电」Hero 入口与「成电班车」时刻）、AI助手（Assistant）、课程（Class）、日历（Calendar）、我的（Mine）；
- **校车时刻与日历联动**：`model/BusScheduleModel.ets`（纯 TS 班车模型）+ `pages/schedulePages/BusSchedulePage.ets`（双校区切换、倒计时卡片）+ `CalendarKitReminderService.createBusReminder`（提前 15 分钟写入日历并强力去重）；
- **桌面万能服务卡片（Form Widget）**：
  - `CourseWidgetCard2x2.ets`：下一节课动态倒计时与教室地点；
  - `CourseWidgetCard2x4.ets`：今日 1-12 节课全天排期与状态时间线；
  - `EntryFormAbility.ets` + `CourseService.updateNextCourseCache`：全状态动态绑定与静默刷新；
- **本地存储**：基于 `@kit.ArkData` preferences：
  - `classtable_login_pref`：用户认证鉴权；
  - `course_table_local_db`：应用核心业务数据（课表、考试、成绩、日程、设置、桌面卡片缓存）；
  - `chat_sessions_db` / `chat_messages_db`：AI 助手统一会话历史（`ChatSessionRepository`）。
- **学期与周次计算**：
  - `CourseModel.getCurrentWeek()` / `getWeekForDate(date)`：锚定到含行课首日的周一（当前学期：`2026-08-31`，2026-2027 第一学期）；
  - `ExamAccessRules.calculateSemesterId()`：按 base 503（2025-2026 第二学期）步长 20 计算学期 ID，**禁止硬编码学期号**。
- **教务抓取与会话恢复**：
  - 登录判定优先检测统一身份认证（CAS / IDAS），输入阶段等待用户登录；
  - 遇 HTTP 500 报错、多端踢出或「点击此处」页面时，**禁止直接重试二级子页面**，必须先跳转 `home.action`（`VpnEncoder.buildVpnHomeUrl()`）激活主 Session 会话，待登录态确立后再平滑跳转至课表/考试/成绩页面解析数据。

## 5. AI 助手开发（加工具必须三处同步）

### 架构模式
- **后端大脑**：LangGraph 编排 + 多模型推理（DeepSeek / 小米 MiMo / 智谱 GLM-4V）+ 深度思考（Reasoning / Thought）流式下行 + 成电 80+ 服务直达库与生活指南动态 RAG 知识库（`campus_services.json`）+ 教务处官网实时检索 + SQLite 会话持久化 + 自动化评测基准体系（Eval Harness）。
- **端侧统一控制引擎**：`BackendAgentClient`（SSE 长连接客户端）+ `DataQueryEngine`（纯内存多维查询）+ `ToolExecutor`（5 大元工具、流水线批处理、系统日历联动）+ `FloatingWindowManager`（SubWindow 全局伴随悬浮窗）+ `MarkdownBubble`（原生 Markdown 解析、流式打字光标、超链接拦截与内嵌 `WebPage.ets` 浏览器打开）+ 深度思考折叠卡片（毫秒计时）。

### 加工具的三处同步铁律（名称与参数必须完全一致）
1. **后端 Schema 与元数据**：`ai-proxy/src/tools.ts`（定义 schema 与 `toolMeta`：`requiresConfirmation` / `riskLevel`）；
2. **前端执行器**：`ToolExecutor.ets`（`switch(toolName)` 分发执行具体逻辑）；
3. **前端注册表**：`ToolRegistry.ets`（定义镜像用于端侧动态风险评级与确认弹窗判定）。

### 后端开发与验证
- **启动后端**：`cd "C:\Users\28399\Desktop\华为云\后端服务\ai-proxy" && npm run dev`（端口 3000）。后端 `.env`（`DEEPSEEK_API_KEY` 等）已 gitignore，勿提交。
- **单独模拟联调**（不连手机）：`node test/phone-sim.mjs` + `npm run typecheck`。
- **自动化评测基准**：`cd "C:\Users\28399\Desktop\华为云\后端服务\ai-proxy" && npm run test:eval`（33 条用例回归评测并生成 `test/evals/EVAL_REPORT.md`）。
- **真机/模拟器联调**：填电脑 **局域网 LAN IP**（如 `http://192.168.1.11:3000`），不要填 `localhost`。
- **调试日志前缀**：`[BackendAgentClient]` / `[CalendarKit]` / `[ReminderDebug]` / `[ExamDebug]` / `[HomeDebug]` / `[FloatingWindow]`。

## 6. 常用命令速查（Slash Commands）

| 命令 | 对应操作 / 作用 |
|---|---|
| `/build` | 构建 HAP 并报告结果（`devecocli build --modules entry@default --build-mode debug`） |
| `/clean` | 干净全量构建（`devecocli build clean`） |
| `/lint` | 运行代码静态检查（`devecocli check lint`） |
| `/commit` | 按规范提交改动（`type: what & why` + `Co-Authored-By`） |
| `/add-tool` | AI 助手加工具三处同步流程（后端 `tools.ts` + 前端 `ToolExecutor.ets` + `ToolRegistry.ets`） |
| `/dev-backend` | 启动 `ai-proxy` 后端开发服务（端口 3000）并进行健康检查 |
| `/eval` | 运行 AI Agent 自动化评测基准套件（`npm run test:eval`，生成 `EVAL_REPORT.md`） |

## 7. 按需查阅详细文档

| 需要了解的模块 | 详细文档路径 |
|---|---|
| 完整架构 / 分层 / 数据流 / 五 Tab 结构 / 抓取 / 学期计算 | [`doc/ARCHITECTURE.md`](./doc/ARCHITECTURE.md) |
| AI 助手：架构图 / 状态机 / 5大元工具 / 悬浮窗 / Markdown渲染 / 日历联动 | [`doc/AI_AGENT.md`](./doc/AI_AGENT.md) |
| 构建 / 运行 / 联调 / 签名 / 权限 / 完整测试用例清单 | [`doc/BUILD_AND_TEST.md`](./doc/BUILD_AND_TEST.md) |
| 逐阶段变更日志（功能演进、重构与修复历史） | [`doc/CHANGES.md`](./doc/CHANGES.md) |
