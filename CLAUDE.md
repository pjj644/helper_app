# CLAUDE.md

Guidance for Claude Code. **详细规格在 [`doc/`](./doc/) 里，按需查阅**，本文件只放最关键的入口信息。

## 项目

UESTC Helper（成电校园助手）- HarmonyOS（ArkTS，stage model，API 6.0.2/22）端云一体应用。WebView JS 注入抓取教务系统（EAMS）课表 / 考试 / 成绩，本地存储（preferences），同步华为 Cloud DB。含 AI 助手（后端 LangGraph 大脑 + 设备端工具执行）。

## 目录布局

- **git 仓库在根目录**（`D:\harmony\helper_app`，2026-08 由 `Application/` 内迁移，历史保留），提交直接在根目录做。
- **`Application/`** - HarmonyOS app（ArkTS），源码 `entry/src/main/ets/`，分层 `pages/ components/ service/ repository/ model/ common/`。入口 `EntryAbility.ets` -> `pages/Index.ets`。
- **`CloudProgram/`** - 云端 Node.js（Cloud DB schema、云函数）。同在根仓库内。
- **`doc/`** - 详细文档（架构 / AI 助手 / 构建测试 / 变更日志 / 迁移方案）。同在根仓库内。
- **`information/`** - EAMS 抓取 HTML 存档（参照物，.gitignore 不入库）。
- AI 助手后端 `C:\Users\28399\Desktop\华为云\后端服务\ai-proxy` 是唯一独立仓库（在项目目录外）。

## 构建

DevEco Studio 打开 `Application/`。**首选官方 DevEco CLI**（已全局安装，命令 `devecocli`，自动探测本机 DevEco Studio）：

```bash
devecocli build --modules entry@default --build-mode debug   # debug（推荐）
devecocli build clean                                        # 清产物
devecocli check lint                                         # lint（0 error）
devecocli check compat                                       # 跨 SDK API 兼容扫描
```

- 工程级 MCP（`deveco-mcp`，ArkTS/C++ LSP 诊断）已配到 `Application/.opencode/opencode.json`；首次调用会先 sync 工程，返回 "请 10s 后重试" 属正常。
- 需要原始 hvigorw 时（未装 CLI）：`hvigorw assembleHap`（debug）/ `-p buildMode=release` / `clean assembleHap`。
- Windows 路径含空格时用根目录的 `_build.bat`（增量，内部优先 devecocli）/ `_clean_build.bat`（干净）/ `_lint.bat`（lint）。**批处理内不要 `setlocal`**。
- 签名材料在 `D:/harmony/mykey/helper_app/`。详见 [`doc/BUILD_AND_TEST.md`](./doc/BUILD_AND_TEST.md)（含模拟器 / 真机 / 权限 / AI 助手 E2E / CLI 速查）。

## 常用命令（slash commands）

| 命令 | 作用 |
|---|---|
| `/build` | 构建 HAP 并报告结果（`_build.bat`，可换 `/clean` 风格用 `_clean_build.bat`） |
| `/commit` | 按规范提交 `Application/` 改动（type: what & why + Co-Authored-By） |
| `/add-tool` | AI 助手加工具的三处同步流程（后端 tools.ts + 前端 ToolExecutor + ToolRegistry） |
| `/dev-backend` | 启动 ai-proxy 后端 dev server + 健康检查 |

## 关键约定

- `common/constants/AppConstants.ets` 是所有偏好键 / URL / 魔法数字的**唯一来源**。
- Models（`model/`）是纯 TS，**无 HarmonyOS 导入**，只做解析 / 过滤 / 排序。
- 数据流：Pages -> Service -> Repository -> Preferences / Cloud DB。
- 本地存储：`@kit.ArkData` preferences，`classtable_login_pref`（鉴权）/ `course_table_local_db`（全部应用数据）。
- 学期 / 周次：`CourseModel.getCurrentWeek()` / `getWeekForDate(date)` 锚定到含行课首日的周一（当前 `2026-08-31`，2026-2027 第一学期）；`ExamAccessRules.ets` 由 base 503 步长 20 算学期 ID。
- 改完在 `Application/` 内 `git add` + `git commit -m "type: what & why"`（`feat/fix/refactor/docs/chore`），消息以 `Co-Authored-By: Claude <noreply@anthropic.com>` 结尾。**勿提交密钥**（后端 `.env` 已 gitignore）。

## AI 助手

后端大脑（LangGraph.js，本地电脑）+ 手机执行工具（数据留在设备）。

- 后端（独立 git）：`C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`，`npm run dev` 起，端口 3000。
- 前端：`common/agent/` - `BackendAgentClient`（SSE + POST）、`ToolExecutor`（33 工具）、`ToolRegistry`（风险等级镜像）、`VisionScheduleHelper`（智谱 GLM-4V 视觉识别）、`common/speech/SpeechRecognizerHelper`（CoreSpeechKit 语音输入）。
- 后端知识库：`src/knowledge/store.ts` (`CampusKnowledgeStore`) 支持校车/教务/医院/场馆/生活多模块检索。
- 桌面卡片：`EntryFormAbility.ets` + `CourseWidgetCard2x2.ets` 支持鸿蒙 2x2/2x4 万能课表服务卡片。
- 后端地址在「应用设置 -> 助手后端」配置（填 LAN IP）。明文 HTTP 已全局 `allowsCleartext`。
- **加一个工具要改 3 处**：后端 `src/tools.ts`（schema + meta）、前端 `ToolExecutor.ets`（执行）、`ToolRegistry.ets`（风险镜像）。详见 [`doc/AI_AGENT.md`](./doc/AI_AGENT.md)。

## 按需查阅

| 需要了解 | 文件 |
|---|---|
| 完整架构 / 分层 / 数据流 / 各功能文件 | [`doc/ARCHITECTURE.md`](./doc/ARCHITECTURE.md) |
| AI 助手：协议 / 工具清单 / 加工具 / 日历工具 | [`doc/AI_AGENT.md`](./doc/AI_AGENT.md) |
| 构建 / 运行 / 测试 / 签名 / 权限 | [`doc/BUILD_AND_TEST.md`](./doc/BUILD_AND_TEST.md) |
| 逐阶段变更日志 | [`doc/CHANGES.md`](./doc/CHANGES.md) |
| AI 助手后端化迁移方案（历史） | [`doc/AI_AGENT_PLAN.md`](./doc/AI_AGENT_PLAN.md) |
