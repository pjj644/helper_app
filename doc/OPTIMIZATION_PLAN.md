# 成电助手优化实施计划（Phase 0 + Phase 1）

> **版本**：v1.1（2026-08-24）　**状态**：▶ 已获用户批准（同日），按 §7 全部假设执行
> **范围**：P0 安全可靠修复 + P1 质量债清偿（共 10 个任务）。Phase 2（功能扩展）仅列大纲。
> **执行模型**：主 agent 只做整合、测试、git 提交；实现工作由子 agent 团队分波次并行完成。
> **后端约定**：`ai-proxy`（独立仓库）**本轮不部署 ECS**，仅本地 `npm run dev` 测试，改动在该仓库内独立提交。
> **验证基准**：模拟器/预览器 + 自动化（devecocli build/lint、后端 typecheck / phone-sim / eval）。真机项全部标注 🔴 留给用户。

---

## 1. 背景摘要

前期调研（代码全量探索 + 后端检视 + 33 用例评测报告 + 市场竞品对比）发现的核心问题：

| 类别 | 问题 | 证据 |
|---|---|---|
| 安全 | 代理占位密钥硬编码 3 处，其中 2 处绕过用户设置 | `AppConstants.ets:76-77`、`ToolExecutor.ets:619`、`VisionScheduleHelper.ets:76` |
| 安全 | 未注册工具默认免确认/低风险放行，风险评级被旁路 | `ToolRegistry.ets:258-274` |
| 可靠 | SSE 无重试重连；缺 final 事件静默当成功；tool-result 回传失败悬挂 30s | `BackendAgentClient.ets:109-111,129-137,266-268` |
| 正确 | 页面跳转失败仍向模型回报成功 | `ToolExecutor.ets:521-524` |
| 维护性 | 学期锚点日期/学期 ID 硬编码，每学期须发版 | `CourseModel.ets:307,360`、`AppConstants.ets:36`、`ExamAccessRules.ets:6` |
| 维护性 | 校园指南前端硬编码 6 条、班车内置，而后端知识库 JSON 已存在 | `ToolExecutor.ets:532-569`、`model/BusScheduleModel.ets` |
| 质量 | 空壳工具 `parse_text_to_schedule` 误耗轮次（评测 E03 暴露） | `ToolExecutor.ets:588-601` |
| 质量 | 评测短板：EDGE 66.7%、pipeline 从不被选、minGpa/room 参数抽取失败 | `ai-proxy/test/evals/EVAL_REPORT.md` |
| 性能 | 首页每秒 setInterval；提醒循环内逐条 await 读偏好 | `pages/Index.ets:126-128`、`ReminderService.ets:106,113` |
| 整洁 | 模板死代码残留 | `pages/CloudStorage.ets`、`pages/CloudFunction.ets`、CloudDB `Post` 类型 |

---

## 2. 执行与协作模型

### 2.1 团队分工

```
主 agent（整合者）：合并各 agent 产出 → 构建验证 → 逐任务 commit → 更新本文档状态与阻塞表
│
├─ Wave 1（三路并行，文件互不相交）
│   ├─ Agent-A 端侧配置与密钥 …… T1
│   ├─ Agent-B 后端接口与评测 …… T5b/T6b/T7b/T8（ai-proxy 仓库）
│   └─ Agent-C 基线与测试脚手架 … 记录构建/lint/eval 基线数据，扩展 phone-sim 断流场景脚本
│
├─ Wave 2（三路并行，依赖 Wave 1 合入）
│   ├─ Agent-D SSE 可靠性 ………… T3
│   ├─ Agent-E 注册表与执行器 …… T2、T4、T7a
│   └─ Agent-F 数据源切换 ………… T5a、T6a
│
└─ Wave 3（单路）
    └─ Agent-G 清理与卡片 ………… T9、T10
```

### 2.2 Git 管理

- **前端仓**（`D:\harmony\helper_app`）：基于 `feature/merge-ui` 创建分支 **`opt/phase01`**。
- **后端仓**（`ai-proxy`）：创建分支 **`opt/phase01-backend`**，不部署 ECS。
- **提交粒度**：每个任务至少一个独立 commit，消息格式遵循 AGENTS.md：`type: what & why` + 尾行 `Co-Authored-By: Claude <noreply@anthropic.com>`。
- **不 push、不合回 `feature/merge-ui`**——全部留在本地分支，待用户审阅后决定。

### 2.3 验证矩阵

| 手段 | 命令/方式 | 通过标准 | 执行者 |
|---|---|---|---|
| 构建 | `devecocli build --modules entry@default --build-mode debug` | `BUILD SUCCESSFUL` | 主 agent（每次 commit 前） |
| 静态检查 | `devecocli check lint` | 0 error | 主 agent（每次 commit 前） |
| 后端类型 | `cd ai-proxy && npm run typecheck` | 无错误 | 主 agent（后端 commit 前） |
| 对话链路模拟 | `node test/phone-sim.mjs` | 全场景通过 | 主 agent |
| 评测基准 | `npm run eval` | 综合 ≥92%，且不低于基线 | 主 agent（T8 及收尾） |
| 模拟器冒烟 | 五 Tab、AI 对话、班车页、桌面卡片、设置页 | 功能正常 | 🔴 U2（用户配合） |
| 真机回归 | 弱网重连、悬浮球、卡片倒计时、教务抓取 | 见 §6 U3 | 🔴 U3（用户，最终验收前） |

---

## 3. Phase 0 —— 安全与正确性（4 个任务）

### T1 密钥与后端地址治理 `[ ] 待实施`
- **目标**：消灭硬编码端点/密钥，设置页成为唯一配置源；未配置时有清晰引导。
- **现状证据**：默认值 `http://192.168.1.100:3000` + `uestc-helper-proxy-key-change-me` 写死于 `AppConstants.ets:76-77`；`searchJwcNews`（`ToolExecutor.ets:619`）与视觉解析（`VisionScheduleHelper.ets:76`）直接写死请求头，**用户改设置无效**。
- **方案**：
  1. `AppConstants.AI_AGENT_URL/AI_AGENT_KEY` 默认值改为空串；
  2. 新增 `common/agent/AgentEndpointConfig.ets`：统一从 SettingsRepository 读 url/key，`resolve()` 未配置时返回结构化缺失原因；
  3. `BackendAgentClient` / `ToolExecutor.searchJwcNews` / `VisionScheduleHelper` 全部改走该模块；
  4. AssistantPage 检测未配置 → 显示引导卡片（跳设置页）；设置页增加「测试连接」（GET `/health`）。
- **涉及文件**：`AppConstants.ets`、新增 `AgentEndpointConfig.ets`、`BackendAgentClient.ets`、`ToolExecutor.ets`、`VisionScheduleHelper.ets`、`SettingsRepository.ets`、设置页。
- **验证**：grep 全仓无 `change-me` / `192.168` 残留；build+lint 过；模拟器未配置出引导、填入局域网地址后对话正常。
- **提交**：`fix(agent): remove hardcoded proxy endpoint and key, unify config via settings`

### T2 工具风险评级 fail-closed + 注册表补齐 `[ ] 待实施`
- **目标**：任何未注册工具一律按最高风险处理，堵住确认弹窗旁路。
- **现状证据**：Executor 可执行 ~16 个 Registry 未注册的别名工具；查不到定义时默认 `requiresConfirmation=false/riskLevel='low'` 直接放行（`ToolRegistry.ets:258-274`）。
- **方案**：
  1. `getToolDefinition` 未命中 → 返回哨兵定义 `{requiresConfirmation: true, riskLevel: 'high'}`（fail-closed）；
  2. 将 16 个别名工具补入 Registry，风险继承所委托元工具：`query_*/navigate_to_page`→low 免确认，`create/delete_schedule`→medium，`sync_all_to_cloud/download_all_from_cloud`→high；
  3. 导出 `LEGACY_TOOL_NAMES` 常量供 Registry 与 Executor 共用，启动 debug 自检 diff 防再次漂移。
- **涉及文件**：`ToolRegistry.ets`、`ToolExecutor.ets`（仅常量导出）。
- **验证**：build+lint；模拟器下发「帮我改日程」类指令确认弹出确认框。
- **提交**：`fix(agent): fail-closed risk rating for unregistered tools, sync legacy registry`

### T3 SSE 连接可靠性 `[ ] 待实施`（依赖 Wave 1 合入）
- **目标**：断线可恢复、失败有反馈、不再静默吞错。
- **现状证据**：连接失败即终止（`:129-137`）；流结束缺 final 静默成功（`:109-111`）；tool-result 回传失败仅 console.error、依赖后端 30s interrupt 超时导致对话悬挂（`:266-268`）。
- **方案**：
  1. 首包 watchdog 45s，可取消；
  2. 尚未收到任何事件时的连接失败 → 指数退避自动重试 2 次（1s/3s），UI 显示「连接中(第 N 次)」；
  3. 已收部分内容后中断 → 标记中断态，气泡提供「重新发送」按钮（同 session_id 重发末条消息，借后端 checkpoint 幂等续接）;
  4. 结束缺 final → `completed_with_warning` 态 + 轻提示「回复可能不完整」；
  5. tool-result 回传失败 → 本地重试 2 次（0.5s/2s），仍失败则明确报错并解锁输入框。
- **涉及文件**：`BackendAgentClient.ets`、`AssistantPage.ets`（状态机与 UI）、必要时 `FloatingSubWindowContent.ets`。
- **验证**：phone-sim 扩展场景（中途 kill 服务、延迟首包、缺 final 帧）；typecheck+eval 不回归；🔴 真机弱网体验留 U3。
- **提交**：`fix(agent): add sse retry, watchdog and explicit failure states to backend client`

### T4 页面跳转结果如实回传 `[ ] 待实施`
- **现状证据**：`pushUrl` 异步失败仅打日志仍返回 success（`ToolExecutor.ets:521-524`），模型误判已跳转。
- **方案**：捕获路由失败回调，返回 `success:false` + 错误描述，让模型可向用户解释。
- **提交**：`fix(agent): report navigation failure instead of fake success`

---

## 4. Phase 1 —— 质量债与维护性（6 个任务）

### T5 学期参数云端化 `[ ] 待实施`
- **目标**：学期锚点/学期 ID 改为云端下发 + 本地缓存兜底，消除「每学期发版」。
- **现状证据**：`new Date(2026,7,31)`（`CourseModel.ets:307,360`）、`SCHOOL_SEMESTER_START`（`AppConstants.ets:36`）、`BASE_SEMESTER_ID=503`（`ExamAccessRules.ets:6`）。
- **后端（T5b）**：新增 `GET /api/v1/config/app-config` 返回 `{semesterStartDate, baseSemesterId, semesterLabel}`，数据源 `src/config/appConfig.json`。
- **前端（T5a）**：model 层新增纯 TS `SemesterConfig`（参数注入式周次换算）；启动时拉取 → preferences 存 last-good；`CourseModel`/`ExamAccessRules` 消费注入值，内置常量降级为最终兜底。注意桌面卡片 `EntryFormAbility` 只读 preferences 缓存、不走网络。
- **验证**：模拟器修改后端 json 学期起点 → 课表周次联动变化正确；断开后端 → 缓存生效。
- **提交**：后端 `feat(config): serve app config endpoint for semester parameters`；前端 `feat(model): load semester anchors from backend config with cached fallback`。

### T6 校园数据单一来源化（班车时刻 + 校园指南）`[~] 后端已完成 · 前端 Wave 2 进行中`
- **目标**：删除前端硬编码知识副本，统一由后端知识库下发。
- **现状证据**：前端硬编码 6 条指南（`ToolExecutor.ets:532-569`）；班车内置（`BusScheduleModel.ets`）；后端 `src/knowledge/data/` 已有 `bus_schedule.json` 等 7 个 JSON。
- **后端（T6b）**：新增 `GET /api/v1/knowledge/bus-schedule`、`GET /api/v1/knowledge/guides`。
- **前端（T6a)**：`campus_search` 本地指南逻辑删除、改走后端检索（preferences 缓存 last-good）；班车页数据远端获取；**保留一份标注生成日期的最小内置兜底集**应对首次安装离线场景。
- **提交**：后端 `feat(knowledge): expose bus schedule and guide endpoints`；前端 `refactor(agent): source campus guides and bus schedule from backend with offline fallback`。

### T7 移除空壳工具 `parse_text_to_schedule` `[ ] 待实施`
- **理由**：不做任何解析只返回提示（`ToolExecutor.ets:588-601`），后端 LLM 本就内联解析，误选浪费轮次（评测 E03）。
- **遵守三处同步铁律**：`tools.ts` schema/toolMeta、`ToolExecutor.ets` case、`ToolRegistry.ets` 注册三处同删；`prompt.ts` 相关提及与 eval 数据集同步清理。
- **提交**：前后端各一条 `refactor(agent): drop shell tool parse_text_to_schedule`。
- ⚠️ **假设 A4**：默认删除。若你想保留并真正实现，审阅时注明。

### T8 评测定向修复 `[x] 已完成 · 综合 97.0%，两轮达标（da199db）`
- **目标**：综合通过率 87.9% → **≥92%**；EDGE_CASES ≥85%；M05（pipeline 不被选）、E03（study_plan 误路由）、Q07（minGpa 丢失）、T04（room→keyword）转通过，且其余维度不回归。
- **手段**：`prompt.ts` 强化 `app_pipeline`/`generate_study_plan` 的适用场景描述与 few-shot；`tools.ts` 参数描述加取值示例（如 room 格式）；必要时 DataQueryEngine 增加 room 写法归一（前端配合）。
- **流程**：`npm run eval` 迭代循环直至达标；更新后的 `EVAL_REPORT.md` 入库。
- **提交**：`fix(prompt): improve pipeline/study-plan routing and argument extraction`

### T9 性能优化与死代码清理 `[ ] 待实施`
- 1. 首页每秒 `setInterval`（`Index.ets:126-128`）改为按需刷新/降频时钟组件；
- 2. `ReminderService.refreshScheduleReminders` 循环内逐条 await 读偏好（`:106,113`）改批量预载；
- 3. 生产日志降噪（冗余 console.info 收敛）；
- 4. 删除模板遗留：`pages/CloudStorage.ets`、`pages/CloudFunction.ets`、CloudDB `Post` 类型及引用。
- ⚠️ 「我的-个人信息」占位页**默认保留不动**，去留属产品决策（U5）。
- **提交**：`perf(home)/perf(reminder)/chore(cleanup)` 三条独立 commit。

### T10 桌面卡片刷新及时性 `[ ] 待实施`
- **现状**：仅 30 分钟定时刷新（`form_config.json:17,34` `updateDuration:1`），倒计时误差大。
- **方案**：
  a) 事件驱动即时刷新：课程数据变更落盘后经 `FormProvider.updateForm` 主动推送；应用进前台时同步刷新缓存；
  b) ⚠️ 调研子项：卡片内秒级倒计时的系统能力边界（API 22 卡片动效/实况能力）。**允许结论为「不可行，维持静态文案」**，调研结论写入本文档附录。
- **验证**：模拟器改课程数据 → 卡片立即更新。
- **提交**：`feat(widget): push immediate card refresh on course cache updates`

---

## 5. Phase 2 大纲（本轮不实施，仅备忘）

1. 生活服务四件套：空闲教室、全校课程/教师查询、一卡通余额+流水、电费查询（🔴 需用户提供入口页面结构或授权抓包分析）；
2. 课表/成绩单截图一键导入（GLM-4V 扩展，降低 WebView 抓取门槛）；
3. 晨报卡片：今日课表+考试倒计时+班车的主动式每日简报；
4. 云同步升级：自动同步、updatedAt 冲突解决、接入已有 idGenerator 云函数替换 hash 截断 ID、纳入日程与会话；
5. Push Kit 成绩发布推送（🔴 需 AGC 控制台开通）；
6. 长期：小艺开放平台 Skill/A2A 接入、跨会话记忆、华为应用市场上架。

---

## 6. 🔴 用户操作清单（提前标注）

| # | 时机 | 内容 |
|---|---|---|
| U1 | **现在** | 审阅本计划，答复 §7 假设 A1–A5，批准后开工 |
| U2 | Wave 合入后 | 在 DevEco Studio 启动**模拟器**并保持在线（CLI 拉起能力待验证，见 A2），按我给出的冒烟清单逐项确认 |
| U3 | 最终验收前 | 真机回归：弱网断连重连体验、悬浮球贴边交互、卡片倒计时观感、真实教务抓取 |
| U4 | T8 开始前 | 确认 ai-proxy 本地 `.env`（`DEEPSEEK_API_KEY` 等）有效可跑 eval，否则评测迭代无法进行 |
| U5 | T9 期间 | 「我的-个人信息」占位页：保留 / 隐藏 / 给出实现方向 |
| U6 | Phase 2 前 | （预告）AGC Push Kit 开通；一卡通/电费等页面结构资料 |

---

## 7. 我方假设（审阅时请逐条确认或纠正）

- **A1**：ai-proxy 本地 `.env` 密钥当前有效，`npm run dev` 与 `npm run eval` 可直接运行（关联 U4）。
- **A2**：DevEco 模拟器可能无法由命令行拉起，冒烟需你在 Studio 中手动启动一次。
- **A3**：T10b 卡片秒级倒计时受系统 API 限制，允许以「30 分钟定时 + 事件驱动即时刷新」为最终形态。
- **A4**：`parse_text_to_schedule` 默认**删除**而非实现。
- **A5**：前端分支 `opt/phase01` 基于 `feature/merge-ui` 创建；所有 commit 仅留本地，不 push 不合并。

---

## 8. 阻塞与待决问题记录表

> 执行过程中遇到无法当场解决的问题记录于此，等待后续轮次补充修改。

| 编号 | 关联任务 | 问题描述 | 已尝试 | 状态 | 后续处理 |
|---|---|---|---|---|---|
| B-01 | T8 | M04_SYNC_CLOUD 在 R2 被裁判方差判负（工具选择与全部确定性校验均正确） | 复核确定性校验通过，维度通过率与基线持平（80%） | 🟡 低风险 | 下一轮评测观察；不视为能力回归 |
| B-02 | 文档 | AGENTS.md 记载的评测命令 `npm run eval` 实际为 `npm run test:eval` | 已确认 package.json 无 eval 脚本 | 🟡 待修正 | 收尾阶段统一修正 AGENTS.md 与计划文档命令 |
| B-03 | T6a | 校园指南的持久化 last-good 缓存因 Wave 2 并行文件归属限制，本轮先做内存缓存+内置兜底 | 端点契约已定 | 🟡 待补 | 收尾或下一轮补 preferences 持久化 |
| B-04 | T2 | **确认弹窗真正闸门在 BackendAgentClient.handleToolCall（读后端 SSE 事件 requiresConfirmation 字段），注册表哨兵不覆盖「后端显式下发 false」的场景** | 执行器侧已 fail-closed；需在 handleToolCall 并入端侧裁决：`backend字段 \|\| ToolRegistry.requiresConfirmation(name)` | 🔴 集成必办 | Agent-D 完成后由主 agent 一行补齐并回归验证 |
| B-05 | 存量 | set_reminder_enabled 实现只消费 type+minutes（enabled 参数无效、minutes≤0 报错），注册已按真实行为写 | 属既有行为缺陷非本轮引入 | 🟢 记录 | 后续轮次决定修行为或改 schema |
| B-06 | T7a | AssistantPage.ets:314 残留 parse_text_to_schedule 显示名死映射 | 文件被 Agent-D 占用未动 | 🟢 无害 | 集成时顺手删除 |

---

## 9. 验收标准汇总

- [ ] grep 全仓无 `change-me` / `192.168` 硬编码残留（T1）
- [ ] 未注册工具调用必弹高危确认框（T2）
- [ ] phone-sim 断流/缺帧/慢响应场景全部有明确 UI 反馈（T3）
- [ ] 路由失败如实回报模型（T4）
- [ ] 修改后端 `appConfig.json` 学期起点，模拟器周次联动正确；离线走缓存（T5）
- [ ] 班车/指南来自后端接口，断后端缓存兜底可用（T6）
- [ ] 三处同步铁律下 `parse_text_to_schedule` 全链路移除（T7）
- [ ] `npm run eval` 综合 ≥92% 且无维度回归，报告入库（T8)
- [ ] 首页无秒级空转 tick、提醒批量加载、死代码清零（T9）
- [ ] 课程数据变更后卡片 ≤ 数秒内更新（T10）
- [ ] 全程：每次 commit 前 build + lint 双绿；后端 typecheck 绿；分支不 push

---

## 10. 执行日志

- **2026-08-24 Wave 1 完成**：
  - T1 前端密钥治理已提交（前端仓 `8d7e296`，build+lint 双绿，硬编码残留清零）。行为变化：旧版内置默认密钥清空，升级后首次使用需在设置页配置地址+密钥（有引导卡片）。
  - 后端 T5b/T6b/T7b/T8 已提交（后端仓 `3197674`/`97cd4ef`/`da199db`）。三个新只读端点经真机式冒烟验证（鉴权 401/200、字段形状、中文 keyword 过滤正常）。评测综合 **87.9% → 97.0%**（两轮达标，EDGE_CASES 66.7%→100%）。
  - 测试脚手架已提交（后端 `cd48f9c`、前端 `151640e`）：phone-sim 六个线级失败场景（含自检退出码）+ U2 模拟器冒烟清单 `doc/SMOKE_CHECKLIST_U2.md`。
  - 披露：T8 过程中补齐了评测 harness 中 generate_study_plan 的 mock 返回契约（对齐端侧真实返回结构，评估器与数据集未改动）。
