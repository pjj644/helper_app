# AGENTS.md

> 给 AI 编码助手的快速上手指令。详细规格见 [CLAUDE.md](./CLAUDE.md) 与 [doc/](./doc/)（均为中文），本文件只写「不查就会猜错」的关键事实。

## 仓库结构（最反直觉的一点）

- **git 仓库在项目根目录 `D:\harmony\helper_app`**（2026-08 由 `Application/` 内迁移而来，历史保留，路径加了 `Application/` 前缀）。所有项目文件都在这个仓库里。
- 唯一的例外：AI 助手后端 `C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`（在项目目录之外）是独立仓库。
- `information/`（EAMS 抓取页面 HTML 存档）体积大且频繁更新，**已 .gitignore 不入库**；`playwright/`、`doc/`、`CLAUDE.md`、`AGENTS.md`、`_*.bat`、`icon/` 均已入库。
- 提交在根目录：`git add` + `git commit`，消息格式 `type: what & why`（feat/fix/refactor/docs/chore），以 `Co-Authored-By: Claude <noreply@anthropic.com>` 结尾；勿提交 `.env` 或密钥。可用 `devecocli` 无关，git 直接在根目录操作。

## 工具链（DevEco CLI + MCP）

- **DevEco CLI（官方，`@deveco/deveco-cli` v1.2.2）已全局安装**，命令 `devecocli`。自动探测 DevEco Studio（本机 `D:\deveco\DevEco Studio`，也可用环境变量 `DEVECO_CLI_STUDIO_PATH` 显式指定）。
- **MCP 已配置**：根目录 `.opencode/opencode.json` 中 `deveco-mcp`（`devecocli serve mcp`，stdio 本地服务，`PROJECT_PATH` 环境变量指向 `Application/`；改动后需重启 opencode 生效）。工具：`check`（ArkTS / C++ LSP 静态诊断，**首次调用会先做项目 sync，返回 "Project is syncing，请 10s 后重试" 属正常**）、`restart`（卡死后原地重启 LSP）；可选工具组 `emulator_manager` / `ui_integration_test`（需 `ADDITIONAL_TOOL_GROUPS` 环境变量开启，未启用）。
- `devecocli` 常用：
  - `devecocli build [--modules entry@default] [--build-mode debug]` — 构建；`devecocli build clean` — 清产物
  - `devecocli check lint` — 运行 code-linter.json5 的 lint（**可在 CLI 跑，不再只限于 DevEco**）；`devecocli check compat` — 跨 SDK API 兼容扫描；MCP `check` 工具则是单文件语法诊断
  - `devecocli device list` / `devecocli emulator list` / `devecocli run` / `devecocli log` / `devecocli ui` — 设备/模拟器/运行/日志/UI 操作
  - `devecocli docs search <关键词>` / `docs read <id>` — 本地 2000 万字官方文档检索
  - `devecocli signature generate` — 自动生成调试签名
- `devecocli skills`：安装鸿蒙官方 Skills 到本机 AI Agent（如 `hmos-arkts-syntax-checker`）；本项目 `arkts-syntax-assistant` skill 仍可用。

## 构建（DevEco 路径含空格，不要直接跑 hvigorw）

- DevEco 装在 `D:\deveco\DevEco Studio\`。**首选 `devecocli build`**（自动处理 SDK / JAVA 环境），或根目录批处理：
  - `_build.bat` — 增量 debug 构建（日常验证用，内部优先 devecocli，回退 hvigorw）
  - `_clean_build.bat` — 干净构建
  - `_lint.bat` — CLI 跑 lint（`devecocli check lint`）
- 调用：PowerShell 用 `& "D:\harmony\helper_app\_build.bat"`（git bash 用 `cmd //c`）。**不要**直接敲 `hvigorw`，会因空格路径或环境变量失败；`.bat` 内不要 `setlocal`（会让 devecocli 找不到工程）.
- 成功标志：`BUILD SUCCESSFUL`。`@hw-agconnect/auth` 的 `sourceMapsPath` 警告是预先存在的，无关紧要。
- App 代码**没有自动化测试**；验证手段 = 构建 0 error + DevEco Previewer + 真机 Logcat。Lint 现在有独立 CLI：`devecocli check lint`（或 `_lint.bat`）。

## 架构速记（Application/entry/src/main/ets/）

- 分层 `pages → service → repository → model → common`；数据流 Pages → Service → Repository → Preferences / Cloud DB。
- **`model/` 是纯 TS，禁止 `@kit.*` 导入**，只做解析/过滤/排序——硬约束，改模型时别引 HarmonyOS API。
- `common/constants/AppConstants.ets` 是所有偏好键 / URL / 魔法数字的唯一来源，不要新增散落常量。
- 本地存储：preferences `classtable_login_pref`（鉴权）、`course_table_local_db`（全部应用数据）。
- 学期/周次：`CourseModel.getCurrentWeek()` 锚定 `2026-08-31` 周一（2026-2027 第一学期）；考试学期 ID 由 `ExamAccessRules.calculateSemesterId()` 按 base 503 步长 20 计算——**不要硬编码学期号**。

## AI 助手（加工具必须三处同步）

- 新增/修改工具要同步 3 个文件，工具名必须一致：
  1. 后端 `src/tools.ts` — schema + `toolMeta`（requiresConfirmation / riskLevel）
  2. 前端 `ToolExecutor.ets` — switch 分发执行
  3. 前端 `ToolRegistry.ets` — 定义镜像（确认弹窗读风险等级）
- 后端开发：`cd "C:\Users\28399\Desktop\华为云\后端服务\ai-proxy" && npm run dev`（端口 3000）。`.env`（`DEEPSEEK_API_KEY` 等）已 gitignore，勿提交。
- 后端单独验证（不接手机）：`node test/phone-sim.mjs` + `npm run typecheck`。
- 真机/模拟器连后端用**局域网 IP**（应用设置里填，如 `http://192.168.1.11:3000`），不是 localhost；明文 HTTP 已全局 `allowsCleartext`，勿动 module.json5。
- 调试日志前缀：`[BackendAgentClient]` / `[CalendarKit]` / `[ReminderDebug]` / `[ExamDebug]` / `[HomeDebug]`。

## 其他

- ArkTS 语法/迁移问题可加载 `arkts-syntax-assistant` skill（位于 `.agents/skills/`）。
- 按需查阅：`doc/ARCHITECTURE.md`（架构）、`doc/AI_AGENT.md`（协议/工具清单）、`doc/BUILD_AND_TEST.md`（构建/联调/提交）、`doc/CHANGES.md`（变更日志）。