# 成电助手 Phase 2 实施计划

> **版本**：v1.0（2026-08-24）　**状态**：📋 草案，待用户审阅批准
> **前置**：Phase 0 + Phase 1 已交付（`OPTIMIZATION_PLAN.md`，评测 97.0%、U2 冒烟 6/7 通过且唯一失败项已修复）。
> **范围裁定**：应用户要求，**生活服务四件套**（空闲教室/全校课查/一卡通/电费）与 **Push Kit 成绩发布推送**不纳入本轮。
> **执行模型**：与 Phase 0/1 相同——主 agent 只做整合、测试、git 提交；实现由子 agent 分波次并行。
> **验证基准**：devecocli build/lint、后端 typecheck / phone-sim / `npm run test:eval`（≥97% 不回归）。真机项标注 🔴 留给用户。

---

## 1. 任务总览

| 编号 | 任务 | 优先级 | 规模 | 依赖 | 交付形态 |
|---|---|---|---|---|---|
| P2-1a | 校园指南 preferences 持久化缓存（清偿 B-03） | P0 | 小 | 无 | 代码 |
| P2-1b | `set_reminder_enabled` 行为修复（清偿 B-05） | P0 | 小 | 无 | 前后端代码 |
| P2-1c | 日志降噪与 Date 复用清理 | P0 | 小 | 无 | 代码 |
| P2-2 | 课表/成绩单截图一键导入（GLM-4V） | P1 | 中 | 🔴 截图样例 | 前后端代码 |
| P2-3 | 云同步升级（自动同步 + 冲突解决 + idGenerator + 范围扩展） | P1 | 大 | 🔴 云函数部署 | 前后端+云函数 |
| P2-4 | 晨报卡片（今日课表 + 考试倒计时 + 班车） | P2 | 中 | P2-1a 数据链路 | 卡片+可选通知 |
| P2-5 | 实况窗 Live View Kit 倒计时（调研 + PoC） | P3 | 小 | 🔴 资质申请 | 报告/PoC |
| P2-6 | 小艺 Skill 接入（调研 + PoC） | P3 | 中 | 🔴 平台入驻 | 报告/PoC |

**波次安排**：
- **Wave P2-A**（三路并行）：P2-1 三小项 ∥ P2-2 ∥ P2-3 步骤①②
- **Wave P2-B**（两路并行）：P2-3 步骤③④ ∥ P2-4
- **Wave P2-C**（随时穿插）：P2-5 / P2-6 调研产出文档

---

## 2. 任务详单

### P2-1a 校园指南持久化 last-good 缓存 `[待实施]`

- **现状证据**：`queryCampusGuide` 走 `/api/v1/knowledge/guides` 三级降级（backend → **内存缓存** → 最小兜底集），进程退出内存缓存即失，冷启动断网时只剩最小集（B-03）。
- **方案**：完全复刻 `BusDataService` 已验证的模式——
  1. `AppConstants` 新增 `PREF_CAMPUS_GUIDES_JSON_KEY = 'campus_guides_last_good_json'`；
  2. 拉取成功后将全量指南 JSON（含 `fetchedAt` 时间戳）写入 preferences；
  3. 启动/查询时优先读持久化 last-good，内存缓存仅作本次会话加速；
  4. 兜底顺序变为四级：backend → 内存 → **preferences last-good** → 内置最小集。
- **涉及文件**：`common/agent/ToolExecutor.ets`（或对称抽出 `repository/GuideRepository.ets`）、`common/constants/AppConstants.ets`。
- **验证**：联网拉取一次 → 杀进程重进 → 断开后端 → 指南查询仍返回完整 last-good 数据；build+lint 双绿。
- **提交**：`feat(agent): persist campus guides last-good cache across launches`

### P2-1b `set_reminder_enabled` 行为修复 `[待实施]`

- **现状证据**：端侧实现只消费 `type`+`minutes` 两参——`enabled` 参数被忽略、`minutes≤0` 直接报错（B-05）；注册表按真实行为登记（诚实但语义拧巴），后端 schema 却向 LLM 承诺了 `enabled` 开关语义。
- **方案**（推荐让 `enabled` 真正生效）：
  1. 端侧：`type` 对应的提醒总开关按 `enabled` 设置；`enabled=true` 时 `minutes>0` 一并更新提前量，`enabled=false` 时允许 `minutes≤0`（仅关开关不改时长）；
  2. 遵守三处同步铁律：后端 `tools.ts` schema 描述 ↔ 端侧 `ToolExecutor.ets` case ↔ `ToolRegistry.ets` 注册三处同改；`prompt.ts` 提及同步核对；
  3. eval 数据集中该工具相关用例补充 `enabled=false` 分支断言。
- **验证**：`npm run test:eval` 综合 ≥97% 且 REMINDER 维度无回归；phone-sim 全过。
- **提交**：前端 `fix(reminder): honor enabled flag in set_reminder_enabled`；后端 `fix(tools): align set_reminder_enabled schema with device behavior`。

### P2-1c 日志降噪与 Date 卫生 `[待实施]`

- **现状证据**：`CountdownCard.ets` 内 4 条 `[CountdownDebug]` console 日志在生产卡片渲染路径刷屏；`CalendarKitReminderService` / `ScheduleService` 存在复用同一 `Date` 实例再逐字段改写的存量写法（时区与状态残留陷阱）。
- **方案**：debug 日志删除或降为 `hilog.debug`；Date 复用点改为每次 `new Date()` 或显式 clone。
- **提交**：`chore(cleanup): silence countdown debug logs and stop mutating shared Date instances`

---

### P2-2 课表/成绩单截图一键导入（GLM-4V）`[待实施]`

- **现状证据**：
  - 后端视觉解析端点已存在：`POST /api/vision/parse-schedule`（`src/index.ts:383`，限流 10/min + HMAC 鉴权），当前仅支持课表模式；
  - 端侧 `VisionScheduleHelper.ets` 已有完整 GLM-4V 调用链路（Phase 0 已收编走 `AgentEndpointConfig` 统一鉴权），但**没有任何页面入口在用它**——属「有引擎没方向盘」；
  - 课程导入现依赖 WebView 教务抓取（`pages/classTablePages/Index.ets`），对新生/转专业/跨校选课等教务里没有的场景无解；成绩单同理（`gradePages/GradeImport.ets`）。
- **方案**：
  1. **后端**：`parse-schedule` 增加 `mode: 'course_table' | 'grade_report'` 参数；成绩单模式提示词输出统一结构化 JSON（课程名/学期/成绩/学分/GPA 数组），低置信度字段带 `confidence` 标记供端侧高亮；
  2. **端侧导入入口**：课程导入页与成绩导入页各新增「截图导入」方式 → `photoAccessHelper.PhotoViewPicker` 选图或相机拍摄 → 本地压缩（长边 ≤1600px JPEG）→ base64 → 经 `VisionScheduleHelper` 上传解析 → 结果进入**现有预览编辑表格**（复用既有确认入库 UI，用户可手动修正错漏字段）→ 确认后走 `CourseService`/`GradeService` 常规入库；
  3. **失败降级**：解析失败/非课表图片/置信度过低 → 明确文案建议改用 WebView 教务抓取，不静默入库半吊子数据。
- **涉及文件**：后端 `src/vision.ts`、`src/index.ts`、`src/prompt.ts`；前端 `VisionScheduleHelper.ets`、`pages/classTablePages/Index.ets`、`pages/gradePages/GradeImport.ets`、新增通用 `ScreenshotImportSection` 组件。
- **验证**：样例截图全流程（选图→解析→预览→修正→入库）；模糊图/非课表图明确报错；GLM-4V 不可用时降级路径可用；build+lint 双绿。
- 🔴 **需用户配合**：提供 2~3 张真实课表/成绩单截图（含清晰版与拍歪版各一）用于联调与验收。
- **提交**：后端 `feat(vision): add grade report parsing mode to parse-schedule`；前端 `feat(import): screenshot-based course and grade import via GLM-4V`。

---

### P2-3 云同步升级 `[待实施]`

- **现状证据**：
  - `SETTING_AUTO_SYNC_SCHEDULE_KEY` 常量已定义但**零消费**（设置页开关是死的）；
  - `cloud_objects/src/main/ets/id-generator` 云函数已存在但未接入，客户端用 hash 截断生成数据 ID，多设备并发写入有碰撞风险；
  - 同步范围仅课程+考试（`sync_all_to_cloud`/`download_all_from_cloud` 手动高危操作），日程与 AI 会话不在内；
  - 无 updatedAt/冲突解决——双设备先后写，后到者整包覆盖。
- **方案**（四步递进，每步独立可交付）：
  1. **ID 治理**：写入路径接 id-generator 云函数批量取号（本地预取缓存一批降低延迟）；存量 hash ID 不迁移表结构，惰性升级（下次变更该条时换新号）；🔴 云函数需用户在 AGC 控制台部署一次。
  2. **自动同步**：设置页开关绑定既有常量真正生效；本地数据变更后 debounce 30s 静默上传；失败指数退避并在下次启动补传（本地待同步队列落 preferences）；默认仅 WiFi 自动，蜂窝需显式开启（假设 A-P2-3）。
  3. **冲突解决**：同步实体统一加 `updatedAt`（本地时钟）+ `deviceId`；下载合并按条目级 LWW（last-writer-wins），服务器接收时间为最终裁决兜底时钟漂移；冲突事件写本地日志可在设置页查看。
  4. **范围扩展**：纳入日程（`schedule_data_json`）与 AI 会话历史；会话上云前用账号 UID 派生密钥做对称加密，服务端只见密文（假设 A-P2-2）。
- **风险与护栏**：CloudDB 免费档配额与延迟——自动同步加频率上限（如最快 5 分钟一次全量 diff）；会话加密密钥丢失即数据不可读，需在设置页明示。
- **验证**：双模拟器实例互同步（A 改→B 拉）；断网操作恢复后补传；冲突场景构造双写验证 LWW 裁决正确；eval/phone-sim 不回归。
- **提交**：分四步各自独立 commit（`feat(sync): wire id-generator cloud function` / `feat(sync): background auto upload with retry queue` / `feat(sync): entry-level lww conflict resolution` / `feat(sync): extend sync scope to schedules and encrypted sessions`）。

---

### P2-4 晨报卡片 `[待实施]`

- **目标**：桌面一张 2x4「今日晨报」卡片，聚合当日最重要的三件事，无需打开 App。
- **方案**：
  1. 新增 `MorningReportCard` 卡片（form_config 注册 2x4），三个区块：**今日课程（前 3 节）· 最近考试倒计时 · 下一班班车**；
  2. 数据聚合全部离线完成（EntryFormAbility 内读 preferences 缓存：课程卡片缓存、考试数据、`BusDataService` last-good），卡片进程不发网络请求——沿用 T5/T10 已建立的「主 App 拉取落盘、卡片只读」架构；
  3. 刷新策略复用 T10 通道：`updateDuration` 定时 + 课程缓存变更事件推送 + 回前台校准；跨日边界（凌晨 0 点换天）由指纹门控节拍检测日期变化触发重建；
  4. **可选子项**早间通知：NotificationKit 端侧定时（默认 7:30 可关），每日拉起晨报摘要通知。注意这是纯端侧调度，**不依赖 Push Kit 服务端通道**（Push Kit 已排除在本轮外）。🔴 通知权限首次需引导授权。
- **验证**：卡片三区块数值与 App 内一致；模拟器改系统日期验证跨日轮转；通知到达时间准确、关闭开关后不再打扰。
- **提交**：`feat(widget): morning report card aggregating courses exams and bus`；（若做子项）`feat(notification): optional daily morning briefing notification`

---

### P2-5 实况窗 Live View Kit（调研 + PoC）`[待实施]`

- **背景**：Phase 1 T10b 调研结论——普通卡片无法秒级倒计时，Live View Kit 是唯一系统能力通道，当时留作备选。
- **方案**：先调研（资质类目限制、API 形态、开发工作量），输出可行性结论；可行则做一个最小 PoC：**下一场考试倒计时实况窗**（锁屏/状态栏常驻、分钟级跳动）。
- **产出**：可行性报告（含资质申请材料清单）或 PoC 代码；若资质受阻仅交报告，不阻塞主线。
- 🔴 **需用户配合**：华为开发者 Live View Kit 资质申请（有类目审核）。

### P2-6 小艺 Skill 接入（调研 + PoC）`[待实施]`

- **目标**：让用户对小艺说「我的下一节课」「今天有什么考试」能唤起本 App 能力。
- **方案**：
  1. 调研小艺开放平台意图接入方式（App Skills / 深链映射），圈定首批 3~5 个免登录只读意图（下一节课/今日考试/班车时刻/今日课表/GPA）;
  2. 评估将 ai-proxy 的 Agent 能力经华为 A2A 协议暴露的可行性（鉴权传递、配额、延迟预算）；
  3. 产出可行性报告 + 最小 PoC（至少一个意图端到端打通）。
- 🔴 **需用户配合**：小艺开放平台入驻审核；部分意图可能要求 App 已上架。

---

## 3. 假设（审阅时请逐条确认或纠正）

- **A-P2-1**：GLM-4V 密钥继续有效且截图导入调用量（个人使用级别）在配额内。
- **A-P2-2**：AI 会话云同步默认开启端侧加密；若实现成本超预期，退化为「默认不同步会话，设置页手动开启（明文）」。
- **A-P2-3**：自动同步默认仅 WiFi 生效，蜂窝网络需用户显式开启。
- **A-P2-4**：Live View Kit / 小艺平台若资质受阻，对应任务仅交付调研报告，不影响其余任务。

## 4. 🔴 用户操作清单

| # | 时机 | 内容 |
|---|---|---|
| U-P2-1 | **现在** | 审阅本计划，答复 §3 假设，批准后开工 |
| U-P2-2 | P2-2 开始前 | 提供 2~3 张真实课表/成绩单截图（清晰+模糊各一） |
| U-P2-3 | P2-3 步骤① | AGC 控制台部署 id-generator 云函数（我会给出部署步骤清单） |
| U-P2-4 | P2-4 验收 | 模拟器授权通知权限，验证晨报通知 |
| U-P2-5 | P2-5/P2-6 | 华为开发者资质材料准备（Live View 类目、小艺平台入驻） |
| U-P2-6 | 各 Wave 后 | 模拟器冒烟复测（沿用 U2 清单格式，我按任务增量出清单） |

## 5. 验收标准汇总

- [ ] 断网冷启动后校园指南仍可用完整 last-good 数据（P2-1a）
- [ ] 「明天 8 点提醒我 X」与「关闭课程提醒」两类指令均行为正确（P2-1b）
- [ ] 生产路径无 [CountdownDebug] 刷屏（P2-1c）
- [ ] 样例截图→解析→修正→入库全流程可用，坏图明确报错（P2-2）
- [ ] 双实例互同步、断网补传、LWW 冲突裁决正确；会话上云为密文（P2-3）
- [ ] 晨报卡片三区块数据准确、跨日轮转正常（P2-4）
- [ ] P2-5/P2-6 至少交付可行性报告（PoC 为加分项）
- [ ] 全程：commit 前 build+lint 双绿、后端 typecheck 绿、`npm run test:eval` ≥97%、分支不 push

## 6. Git 约定

延续 Phase 0/1：前端基于 `opt/phase01` 叠加新分支 `opt/phase02`（或经你审阅合并后再行切出，开工前确认）；后端同理由 `opt/phase01-backend` 叠加。每任务至少一个独立 commit，消息 `type: what & why` + `Co-Authored-By: Claude <noreply@anthropic.com>` 尾行；不 push 待审。
