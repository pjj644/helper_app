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

- 已配置于根目录 `.opencode/opencode.json`（`deveco-mcp`，stdio：`devecocli serve mcp`，`PROJECT_PATH` 指向 `Application/`），**改配置后需重启 opencode 生效**。
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

用法：`cmd //c "D:\harmony\helper_app\_build.bat"` 或 PowerShell `& "D:\harmony\helper_app\_build.bat"`。成功标志：`BUILD SUCCESSFUL`。警告通常来自 `@hw-agconnect/auth` 的 `sourceMapsPath`（预先存在，无关）。

## 模拟器 / 真机

1. DevEco Studio -> Tools -> Device Manager -> 加 Phone 模拟器镜像（API 6.0.2+）。
2. 签名有效后点 **Run (▶)** 构建/安装/启动。
3. 模拟器走 NAT，**访问本机后端用真实 LAN IP**，不是 `localhost`。优先用真机联调。
4. 所需权限：`INTERNET`（抓取/云）、`NOTIFICATION`（提醒）、`READ_CALENDAR` / `WRITE_CALENDAR`（Calendar Kit）。
5. 调试日志：DevEco Logcat 面板或 `hilog` CLI。关键前缀：`[CalendarKit]` / `[ReminderDebug]` / `[ExamDebug]` / `[HomeDebug]` / `[BackendAgentClient]` / `[FloatingWindow]`。

## AI 助手与系统联调测试用例

前置：后端在本机运行，手机与电脑**处于同一局域网 WiFi**。

1. 启动后端：`cd "C:\Users\28399\Desktop\华为云\后端服务\ai-proxy" && npm run dev`。`curl http://localhost:3000/health` 应返回 200。
2. 查电脑 WLAN IP（`ipconfig`，如 `192.168.1.11`）。防火墙放行 3000 端口。
3. DevEco 装新 hap 到真机。打开「应用设置 -> 助手后端」填 `http://192.168.1.11:3000`。
4. 核心用例测试：
    - **基础查询类**：`今天有几节课` / `明天呢` / `我这周课表` / `高数在哪上` / `下次考试什么时候` / `我GPA多少` / `现在第几周`
    - **校园智搜与服务直达**：`清水河去沙河的班车有哪些` / `缓考怎么申请` / `校医院急诊电话` / `教务处有什么新通知` / `我要评教` / `网费怎么充值`（验证大模型输出 Markdown 链接 `[服务名称](URL)`，点击触发内嵌 `WebPage.ets` 浏览器打开）
    - **成电班车时刻与日历联动**：在「发现」Tab 点击「成电班车」进入 `BusSchedulePage`，测试双校区切换、倒计时 Hero 卡片，点击「🔔 设为提醒」验证发车前 15 分钟写入系统日历与去重。
    - **日历与提醒联动**：`把下次考试加到日历，提前30分钟提醒` / `明天14:00在学生活动中心开例会，创建日程并同步日历`
    - **日历去重与双向删除**：`把刚才那个开会日程删了`（验证系统日历中对应事件被同步清除）
    - **页面控制与感知**：停留在课表页提问 `切到第5周` / `帮我导入成绩` / `给我高亮显示导入按钮`
    - **全局悬浮球与浮窗**：
      - 在「设置」或助手侧边栏开启悬浮球；
      - 拖拽呼吸悬浮球贴边吸附；
      - 点击展开 Mini 浮窗，输入 `这学期几门课`，验证流式 Markdown 排版与打字机效果；
      - 点击 Mini 浮窗顶部「➕」重置会话，验证 Toast 提示与历史会话同步；
      - 进入全屏「AI助手」Tab，验证悬浮球自动避让隐藏；切出后自动恢复。
    - **多模态提取**：在助手页点击相册选择讲座通知海报，验证 GLM-4V 自动提取时间地点并生成日程卡片。
    - **桌面万能服务卡片 (Widget)**：
      - 在鸿蒙桌面添加 2x2 服务卡片，验证下一节课倒计时、教室地点展示与点击跳转课表；
      - 添加 2x4 服务卡片，验证全天 1-12 节课表排期与「上课中/未开始/已结束」实时状态；
      - 导入新课表后验证桌面卡片无感静默更新。
5. 日志关注：后端打印 session/batch/工具名/等待/恢复/超时/断开；前端关注 `[BackendAgentClient]`、`[CalendarKit]` 与 `[FloatingWindow]`。

## 后端单独验证与自动化评测 (Automated Eval Harness)

- **`npm run eval`** - **自动化评测套件 (Eval Harness)**：全量跑 33 条评测用例（`test/evals/dataset.ts`），执行确定性规则裁判与 LLM-as-a-Judge 5 维度评分，自动生成 `test/evals/EVAL_REPORT.md`。
- **`npm run typecheck`** - `tsc --noEmit`，验证 TypeScript 类型系统与 Schema 改动。
- **`test/phone-sim.mjs`** - 模拟手机端：POST `/api/chat`、解析 SSE（含 `thought` 深度思考流与 `text_chunk`）、收到 `tool_call` 后 POST `/api/tool-result` 回传 mock 数据。覆盖单工具 / 批量流水线 / 非工具 / 断线重连。
- **`test/test-mimo-latency.ts`** - 大模型推理延迟与 TTFT（首字响应时间）压测基准。
- **`test/test-mimo-breakdown.ts`** - 阶段耗时拆解（预处理、Prompt 动态检索、网络传输、模型解码）。

## 提交规范

- **git 仓库在项目根目录 `D:\harmony\helper_app`**（2026-08 由 `Application/` 内迁移而来，历史保留；`Application/`、`CloudProgram/`、`doc/`、脚本、素材统一在此仓库）。**唯一独立仓库**是后端 `ai-proxy`（`C:\Users\28399\Desktop\华为云\后端服务\ai-proxy`）。
- 改完在根目录 `git add` + `git commit -m "type: what & why"`。类型：`feat` / `fix` / `refactor` / `docs` / `chore`。
- commit 消息以 `Co-Authored-By: Claude <noreply@anthropic.com>` 结尾。
- **不要提交密钥**：后端 `.env`（含 `DEEPSEEK_API_KEY`）已 gitignore；`checkpoints.sqlite*` 也已忽略；`information/`（抓取存档）不入库。
