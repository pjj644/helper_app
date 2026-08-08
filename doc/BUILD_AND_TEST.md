# 构建与测试 (BUILD_AND_TEST.md)

## DevEco Studio

- 用 DevEco Studio 打开 `Application/` 作为 HarmonyOS 工程。
- 工程级 `build-profile.json5` 定义 products / 签名配置 / 模块。
- Entry 模块 stage model（`entry/build-profile.json5` 里 `apiType: "stageMode"`）。
- 签名材料在 `D:/harmony/mykey/helper_app/`（cert / p12 / profile，key alias `mykey`）。**签名必须有效**，否则装不上。
- 改完代码用 DevEco 的 **Previewer** 标签页快速看布局（不用开模拟器）。
- Lint：`code-linter.json5` 对 `**/*.ets` 启用 `@performance/recommended` + `@typescript-eslint/recommended`。

## DevEco CLI（官方命令行工具，推荐）

`@deveco/deveco-cli`（命令 `devecocli`，v1.2.2）已全局安装。它统一封装 hvigor / ohpm / hdc / emulator / hilog，自动探测 DevEco Studio（本机 `D:\deveco\DevEco Studio`，非默认路径也能自动探测，或用环境变量 `DEVECO_CLI_STUDIO_PATH` 显式指定）。

| 命令 | 用途 |
|---|---|
| `devecocli build [--modules entry@default] [--build-mode debug]` | 构建（先自动 ohpm install） |
| `devecocli build clean` | 清产物 |
| `devecocli check lint` | 跑 `code-linter.json5` lint（0 error 才算过） |
| `devecocli check compat` | 扫描跨 SDK 版本 API 兼容性 |
| `devecocli device list` / `emulator list` / `run` / `log` / `ui screenshot` | 设备/模拟器/运行/日志/UI |
| `devecocli docs search <关键词>` | 检索本地官方文档（2000+ 万字） |
| `devecocli signature generate` | 自动生成调试签名 |
| `devecocli init --mcp --agent opencode --project ./` | 向 AI 智能体注入 MCP 配置 |

### DevEco MCP（AI 助手用）

- 已配置于 `Application/.opencode/opencode.json`（`deveco-mcp`，stdio：`devecocli serve mcp`），**改配置后需重启 opencode 生效**。
- 工具 `check`：对 `.ets` / `.c` / `.cpp` 文件做 LSP 静态诊断；**首次调用先做项目 sync，返回 "Project is syncing，请 10s 后重试" 属正常**。
- 工具 `restart`：LSP 卡死后原地重启。
- 可选工具组（需 `ADDITIONAL_TOOL_GROUPS=ui_integration_test,emulator_manager`）：UI 自动化测试 / 模拟器镜像管理。

## 命令行构建（不装 CLI 时）

从 `Application/` 目录运行：

```bash
hvigorw assembleHap                      # debug
hvigorw assembleHap -p buildMode=release # release
hvigorw clean assembleHap                # clean build
```

Hvigor daemon 能加速增量构建。

### Windows 构建脚本（路径含空格）

DevEco 装在 `D:\deveco\DevEco Studio\`（路径含空格），直接在 bash 里 `cd` / 转义容易出错。仓库根目录提供批处理（**内部优先 `devecocli`，未安装时回退 hvigorw**；不要 `setlocal`，会找不到工程）：

- `_build.bat` - 增量 debug 构建（日常验证 0 error）
- `_clean_build.bat` - clean + 全量构建
- `_lint.bat` - `devecocli check lint`

用法：`cmd //c "D:\harmony\helper_app\_build.bat"`。成功标志：`BUILD SUCCESSFUL`。警告通常来自 `@hw-agconnect/auth` 的 `sourceMapsPath`（预先存在，无关）。

## 模拟器 / 真机

1. DevEco Studio -> Tools -> Device Manager -> 加 Phone 模拟器镜像（API 6.0.2+）。
2. 签名有效后点 **Run (▶)** 构建/安装/启动。
3. 模拟器走 NAT，**访问本机后端用真实 LAN IP**，不是 `localhost`。优先用真机联调。
4. 所需权限：`INTERNET`（抓取/云）、`NOTIFICATION`（提醒）、`READ_CALENDAR` / `WRITE_CALENDAR`（Calendar Kit）。
5. 调试日志：DevEco Logcat 面板或 `hilog` CLI。关键前缀：`[CalendarKit]` / `[ReminderDebug]` / `[ExamDebug]` / `[HomeDebug]` / `[BackendAgentClient]`。

## AI 助手 E2E 联调

前置：后端在本机运行，手机与电脑**同一 WiFi**。

1. 启动后端：`cd "C:\Users\28399\Desktop\华为云\后端服务\ai-proxy" && npm run dev`。`curl http://localhost:3000/health` 应返回 200。
2. 查电脑 WLAN IP（`ipconfig`，如 `192.168.1.11`）。防火墙放行 3000 端口。
3. DevEco 装新 hap 到真机。打开「应用设置 -> 助手后端」填 `http://192.168.1.11:3000`。
4. 进 AI 助手测试用例：
   - 查询类：`今天有几节课` / `明天呢` / `我这周课表` / `高数在哪上` / `下次考试什么时候` / `我GPA多少` / `现在第几周`
   - 写日历（首次会弹日历权限框）：`把下次考试加到日历，提前30分钟提醒` / `把今天的高数加到日历` / `明天 14:00 开会，建个日程并加到日历，提前15分钟提醒`
   - 日历管理：`我日历里有哪些事` / `把刚才那个考试提醒删了`
   - 跳转：`打开课表` / `帮我导入成绩`
5. 日志关注：后端打印 session/batch/工具名/等待/恢复/超时/断开；前端 `[BackendAgentClient]` 与 `[CalendarKit]`。

## 后端单独验证（不接手机）

- `test/phone-sim.mjs` - 模拟手机：POST `/api/chat`、解析 SSE、收到 `tool_call` 后 POST `/api/tool-result` 回 mock 数据。覆盖单工具 / 批量工具 / 非工具 / 断开。
- `npm run typecheck` - `tsc --noEmit`，验证 schema 改动。

## 提交规范

- **`Application/` 是 git 仓库**，`CloudProgram/`、后端 `ai-proxy`（`C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`）是各自独立仓库。
- 改完在对应仓库 `git add` + `git commit -m "type: what & why"`。类型：`feat` / `fix` / `refactor` / `docs` / `chore`。
- commit 消息以 `Co-Authored-By: Claude <noreply@anthropic.com>` 结尾。
- **不要提交密钥**：后端 `.env`（含 `DEEPSEEK_API_KEY`）已 gitignore；`checkpoints.sqlite*` 也已忽略。
- 顶层工作区（`CLAUDE.md` / `doc/` / `_build.bat` 等）**不在 git 内**，是工作笔记。
