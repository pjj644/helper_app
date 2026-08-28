# 变更日志 (CHANGES.md)

记录 UESTC Helper（成电校园助手）的重大演进、功能重构、架构演进与特性落地记录。
当前执行计划见 [`PHASE2_PLAN.md`](./PHASE2_PLAN.md)；历史阶段计划（Phase 0/1 优化轮）完成后已归档删除，其结果摘要保留于下方条目。

---

## 2026-08: 桌面卡片矩阵扩展、个人信息页与后端简单通知

- **桌面卡片矩阵扩展（3 → 5 张卡片）**：
  - 新增 **考试倒计时卡 2x2**（最近一场考试名称/时间/地点与天级倒计时，3 天内红色强调）与 **考试日程卡 2x4**（最近三场考试列表）；
  - 新增 **成电班车卡 2x4**（双校区下一班发车时间与实时倒计时，与 BusDataService「远端 last-good → 内置兜底表」同口径）；
  - 卡片数据源统一收敛：新增纯 TS `model/widget/WidgetDataModel.ets`（考试/班车倒计时改为读取时基于原始存储数据实时计算，免疫缓存过期）与 `service/WidgetUpdateService.ets`（唯一事件驱动推送通道；CourseService/ExamService/BusDataService/SyncService 数据变更后统一接线，推送全量 formData 避免多卡片互相覆盖字段）；
  - 卡片点击直达：EntryAbility 消费 postCardAction `targetPage`（考试卡 → 考试页，班车卡 → 班车页，冷启动与热启动 onNewWant 均支持）。
- **「我的-个人信息」页落地（`pages/mine/PersonalInfoPage.ets`）**：替换占位 toast；展示 AGC 账号信息（邮箱/用户 ID 可复制/登录时间）、本机校园数据概况（课表课程数/待考场次/日程条数）与数据隐私说明。
- **「消息通知」接通后端简单通知**：
  - ai-proxy 新增 `GET /api/v1/notifications`（`?since=<id>` 增量）与 `POST/DELETE /api/v1/admin/notifications`（发布/撤回；JSON 文件存储 `data/notifications.json`，x-proxy-key 鉴权）；
  - 端侧新增 `service/BackendNoticeService.ets`：回前台 1 小时节流轮询 + 开关开启立即拉取，单次最多发布 3 条系统通知（notificationManager）；
  - 设置页「消息通知」开关从空开关变为真实生效：开启时申请通知授权并立即拉取。
- **工程治理**：
  - 清理旧版首页死代码与假数据：`HomeViewModel.ets`/`HomeModel.ets`、`ModelTypes.ets` 冗余类型及 MessageList/TodoList/ServiceGrid/AnnouncementSwiper/ExamCard/CourseCard/StateComponents 等 8 个未引用组件（QuickStatComponent 经核实仍被首页引用，保留）；
  - 版本号改读 bundle 信息（`bundleManager.getBundleInfoForSelfSync`），移除 Index 两处硬编码 `v1.0.0`；
  - 后端 `tools.ts` toolMeta 移除端侧不存在的 5 个漂移别名（`check_time_conflict`/`add_to_calendar`/`add_exam_to_calendar`/`add_course_to_calendar`/`remove_calendar_event`），与端侧 ToolRegistry 严格对齐，幻觉工具名继续走 fail-closed 双闸门。

---

## 2026-08: Phase 2 完成——云同步全量落地、会话加密上云与导入预览

> 承接上一条目「Phase 2 进行中」；本轮在 `opt/phase02` 分支推进（自 `opt/phase01` 切出）。范围裁定：晨报卡片 / 实况窗 / 小艺意图均移出本轮（小艺调研归档 [`RESEARCH_XIAOYI.md`](./RESEARCH_XIAOYI.md)）。

- **1. 云端自动同步（P2-7a, `SyncService.ets`, `ReminderService.ets`, `AppSettings.ets`, `tableUI.ets` 等）**：
  - 课程/考试落盘后 debounce 30s 静默上传，频率上限 5 分钟/轮；失败指数退避（30s×2^n，上限 30min），未成功变更持久化待传队列，启动与回前台补传；
  - 默认仅 WiFi 自动，蜂窝需显式开关（NetworkKit 连接判定）；设置页新增「云端自动同步」主开关 + 蜂窝子开关；运行状态（上次成功时间）持久化。
- **2. 条目级 LWW 下载合并（P2-7b, `SyncService.ets`, `CourseRepository.ets`, `ExamRepository.ets`, `CourseModel.ets`, `ExamModel.ets`）**：
  - 下载合并从整包覆盖改为按业务键条目级裁决：updatedAt 新者胜、相等云端优先；Repository 落盘前集中盖章时间戳（内容未变继承原戳），合并写回走跳过盖章的 Raw 通道防误刷新；
  - 实际冲突写入本地日志（上限 50），设置页「数据同步」卡片新增「同步状态」折叠区展示上次成功时间与最近 ≤5 条裁决；手动「下载」按钮改为「从云端合并」；
  - 已知限制：无删除墓碑（单端删除会被另一端本地存量复活）；课程业务键不含 validWeeks（改周次生成新云 ID，LWW 兜底）。
- **3. ID 治理（P2-7c）**：课程/考试维持确定性哈希 ID（幂等覆盖价值 > 理论碰撞）；id-generator 云函数退役（保留仓库不部署不接入），`generateUniqueId` 清除；新实体约定 String 主键 + 端侧 UUID。
- **4. AI 会话加密上云（P2-7d, 新增 `SessionCryptoUtil.ets`, `SessionSyncService.ets`, `ChatSessionRecord.ets` + schema `ChatSessionRecord.json`）**：
  - PBKDF2-HMAC-SHA256×10000 由登录账号 UID 派生 AES-256 密钥，AES-GCM 加密整会话 JSON 后 base64 上行（IV‖密文‖tag + AAD），服务端只见密文；密钥丢失不可恢复已在设置页明示；
  - 每会话一条 CloudDB 记录（String 主键复用 session.id 幂等 upsert，Text 密文字段），15s 独立防抖双向同步，上传后裁剪云端多余记录（20 条上限语义传播），下载 LWW 合并经无钩子通道回写防循环；未登录全程 no-op；对象类型未建时软降。
- **5. 截图导入预览修正 UI（P2-9, 新增 `VisionImportModel.ets`, `components/import/VisionImportPreviewDialog.ets`）**：
  - 课表/成绩截图解析完成后先弹预览确认表：逐行可编辑、勾选剔除、低置信度条目琥珀色高亮，确认后才入库；失败路径行为不变。

**验证**：每任务 commit 前 `devecocli build` 成功 + `devecocli check lint` 0 error（63 条既有 warning 与基线一致）。🔴 用户侧验收项见 [`PHASE2_PLAN.md`](./PHASE2_PLAN.md) §5（AGC 建表、双实例互同步、密文核验）。

---

## 2026-08: Phase 2 进行中——截图导入、同步增强与遗留清偿

> 执行模型延续 Phase 0/1：主 agent 整合验证提交，子 agent 并行实现。分支 `opt/phase01` / 后端 `opt/phase01-backend`。

- **1. 校园指南 preferences 持久化 last-good 缓存 (`ToolExecutor.ets`, `AppConstants.ets`)**：
  - 指南降级链路升级为四级：后端实时检索（成功落盘）→ 内存缓存 → **preferences 持久化 last-good** → 内置最小兜底集；
  - 解决冷启动断网时指南只剩最小集的问题（清偿 Phase 0/1 遗留阻塞项 B-03）。
- **2. `set_reminder_enabled` 行为修复 (`ReminderService.ets`, `ToolExecutor.ets`, `ToolRegistry.ets` + 后端 `tools.ts`)**：
  - 端侧真正消费 `enabled` 参数：关闭对应分类提醒开关；`enabled=true` 且 `minutes>0` 时一并更新提前量；
  - 修复课程提醒提前分钟数存储键误指开关键的存量 bug；后端 schema 与端侧行为对齐（清偿 B-05）；
  - eval 数据集新增 `M06_SET_REMINDER_OFF` 用例覆盖「关闭课程提醒」意图。
- **3. 日志降噪与 Date 卫生 (`CountdownCard.ets`, `CalendarKitReminderService.ets`, `ScheduleService.ets`)**：
  - 移除生产卡片渲染路径的 `[CountdownDebug]` 刷屏日志；共享 Date 实例原地改写改为显式新构造。
- **4. 课表/成绩单截图一键导入（GLM-4V 视觉多模态）(`VisionScheduleHelper.ets`, `CourseManage.ets`, `GradePage.ets` + 后端 `vision.ts`, `index.ts`)**：
  - 后端 `POST /api/vision/parse-schedule` 支持 `mode: schedule | course_table | grade_report` 三种识别模式与专用 System Prompt；
  - 课表管理页与成绩页新增「截图导入」入口：选图 → GLM-4V 解析 → 结构化转换 → 自动入库刷新；
  - 真图实测：课表格 20 门/置信度 0.95，微信截屏 7 门全部识别。遗留优化：入库前预览确认 UI（见 PHASE2_PLAN）。
- **5. 云同步增强（部分完成）(`SyncService.ets`, `AppSettings.ets`)**：
  - 设置页「自动同步」开关绑定既有常量真正生效并持久化；
  - 云端实体映射注入 `updatedAt` 时间戳，为 LWW 冲突裁决提供时序依据；新增带随机熵的 `generateUniqueId`；
  - 未竟事项（自动上传队列、下载合并 LWW、id-generator 云函数接入、范围扩展至日程与会话）移交新一轮计划。

---

## 2026-08: Phase 0 + Phase 1 优化轮完成（安全修复 + 质量债清偿）

> 完整任务书见当时版本历史（原 `doc/OPTIMIZATION_PLAN.md`，v1.3，已完成归档）。评测基线 87.9% → **97.0%**，U2 模拟器冒烟 7/7 通过。

**Phase 0 —— 安全与正确性（T1–T4）**：
- 密钥与端点治理：消灭硬编码代理地址/密钥，新增 `AgentEndpointConfig.ets` 统一从设置页解析，未配置出引导卡片与「测试连接」（T1）；
- 工具风险评级 fail-closed：未注册工具一律最高风险需确认，16 个别名工具补齐注册表，导出 `LEGACY_TOOL_NAMES` 防漂移（T2）；
- SSE 可靠性：首包 watchdog 45s、连接失败指数退避重试、中断态「重新发送」按钮、缺 final 帧警告、tool-result 回传本地重试（T3）;
- 页面跳转失败如实回报模型而非假成功（T4）。

**Phase 1 —— 质量债与维护性（T5–T10）**：
- 学期参数云端化：`GET /api/v1/config/app-config` 下发学期锚点，端侧纯 TS `SemesterConfig` 注入式换算 + last-good 缓存兜底（T5）；
- 校园数据单一来源化：班车时刻与校园指南改由 `/api/v1/knowledge/*` 端点下发，前端删硬编码副本留最小内置兜底（T6）；
- 移除空壳工具 `parse_text_to_schedule` 三处同步全链路清理（T7）；
- 评测定向修复：prompt few-shot 强化路由与参数抽取，综合通过率 87.9% → 97.0%，EDGE_CASES 66.7% → 100%（T8）；
- 性能与整洁：首页秒级 setInterval 改指纹门控节拍、提醒批量预载、模板死代码清理净删 475 行（T9）；
- 桌面卡片事件驱动即时推送刷新 + T10b 调研结论：API 22 卡片秒级倒计时不可行（updateDuration 最小 30 分钟粒度），Live View Kit 为替代通道但需资质申请（T10）。

**U2 冒烟回归修复**：悬浮球浮窗高危操作零确认短路 + 后端未知工具 meta fail-open 两处补为 fail-closed（真弹窗）；`ask_user_clarification` 补端侧实现与注册表登记及交互澄清卡片。

---

## 2026-08: 深度思考（Reasoning）流式下行、Agent 自动化评测基准套件与 MiMo 大模型接入

- **1. 大模型深度思考（Reasoning / Thought）流式下行与折叠展示 (`AssistantPage.ets`, `FloatingSubWindowContent.ets`, `BackendAgentClient.ets`, `MarkdownBubble.ets`)**：
  - 后端适配 DeepSeek-R1 / MiMo-Reasoning 推理标签与 `reasoning_content`，新增 SSE `thought` 事件流式下发；
  - 前端 `BackendAgentClient.ets` 新增 `onThoughtChunk` 回调，`AssistantPage.ets` 渲染「✨ 深度思考 (耗时 xs)」专属折叠卡片与高精度毫秒计时器；
  - 悬浮 Mini 助手（`FloatingSubWindowContent.ets`）引入动态状态指示（`✨ 正在理解您的问题...` ➔ `正在深度思考...` ➔ `正在调用 xxx...`）与实时秒数指示；
  - `MarkdownBubble.ets` 引入打字机呼吸光标（`isStreaming`），`ChatSessionRepository.ets` 支持完整推理链与耗时持久化。
- **2. Agent 自动化评测基准套件 (Automated Eval Harness) 与报表自动生成 (`test/evals/*`, `EVAL_REPORT.md`)**：
  - 打造包含 6 大核心维度（课表/考试查询、相对日期推导、数据变更与流水线、80+ 服务 URL 真实度、Prompt 注入防御、页面感知与边缘用例）共 33+ 条真实业务测试用例集（`dataset.ts`）；
  - 落地确定性规则校验（`evaluateDeterministic`）与 LLM-as-a-Judge 智能裁判（`evaluateJudgeWithLLM`）双轨评估机制；
  - 自动化评测大盘实测：综合通过率 **87.9%** (+15.9%)，官方链接真实度 **100.0%** (零幻觉)，Prompt 冗余降低 76.5%；CLI 运行 `npm run eval` 自动生成全量 `EVAL_REPORT.md`。
- **3. 小米 MiMo 大模型底座集成与延迟基准测试 (`src/llm.ts`, `test/test-mimo-*`)**：
  - 新增 Xiaomi MiMo 系列模型支持（`mimo-v2-flash`、`mimo-v2-pro`、`mimo-v2-reasoning`），结合动态 Token 预算与流式解析；
  - 编写 TTFT 首字延迟、网络 RTT、流式吞吐量与 Chunk 碎片率压测脚本。
- **4. 动态上下文检索引擎 (Dynamic Context Engine) 与校内 URL 严格标定 (`src/prompt.ts`)**：
  - 重构 System Prompt 构建管线，由静态大段注入改为按用户提问语义动态检索 80+ 官方服务链接、App 模块操作指南及生活指南；
  - 标定学生邮箱（HTTP 协议）、寝室电费（云中成电门户引导）等敏感校内服务，杜绝模型幻觉。

---

## 2026-08: 发现页门户升级、80+ 服务直达库、班车日历联动与桌面卡片动态化

- **1. 发现页（Quick）重构与「云中成电」核心入口 (`QuickLinksGrid.ets`, `Index.ets`, `AppConstants.ets`)**：
  - 移除非必要占位卡片（计算器、天气等），打造「云中成电」Hero Banner 核心推广位与精简响应式 4 列功能网格；
  - 引入统一外链与路由常量规范，打通校内各系统门户（云中成电、校园地图、清水河畔、图书馆等）。
- **2. 80+ 校内服务直达知识库与大模型直达链接输出 (`campus_services.json`, `store.ts`, `prompt.ts`)**：
  - 提取并清洗「云中成电」80 项高频校内服务（迎新、教务、财务、后勤、场馆、党建、科研等）；
  - 升级 `CampusKnowledgeStore` 支持服务名称/拼音/类别快速匹配；
  - 大模型 System Prompt 约束产出 Markdown 超链接 `[服务名称](URL)`。
- **3. Markdown 原生超链接解析与内嵌 WebPage 拦截 (`MarkdownBubble.ets`, `WebPage.ets`)**：
  - 原生 ArkTS 实现 Markdown `[text](url)` 超链接分词解析与胶囊按钮渲染；
  - 拦截点击事件在 App 内嵌的原生顶栏浏览器（`WebPage.ets`）中平滑加载，保留返回、刷新与进度指示，不跳出 App。
- **4. 清水河↔沙河双校区班车时刻与日历联动 (`BusScheduleModel.ets`, `BusSchedulePage.ets`, `CalendarKitReminderService.ets`)**：
  - 构建纯 TS 班车模型 `BusScheduleModel`，包含双校区工作日/周末全部发车时刻与倒计时算法；
  - 构建 `BusSchedulePage`：双向校区切换、下一班车 Hero 倒计时、时刻表列表；
  - 扩展 `CalendarKitReminderService.createBusReminder`：发车前 15 分钟写入 HarmonyOS 系统日历并强力去重。
- **5. 鸿蒙桌面万能服务卡片（Form Widget）全面动态化 (`form_config.json`, `EntryFormAbility.ets`, `CourseWidgetCard2x2.ets`, `CourseWidgetCard2x4.ets`, `CourseService.ets`)**：
  - 升级 2x2 动态卡片：最近一门课程、教室地点与发车/上课实时倒计时；
  - 新建 2x4 全天课表卡片：全览今日 1-12 节课程排期与进行中/已结束状态指示；
  - `EntryFormAbility` 与 `CourseService.updateNextCourseCache` 实现全状态动态绑定与数据静默更新。
- **6. 历史冗余代码清理与工程 0-Lint 全量验证**：
  - 彻底清理 `pages/CloudDb/` 下冗余历史演示文件（`ClassCourse.ts`, `ClassExam.ts`, `DbInsert.ets`, `CloudDb.ets`, `Post.ts`）；
  - 严格通过 `devecocli check lint`（0 error）与 DevEco 全流程增量编译验证。

---

## 2026-08: 教务系统登录态判定与 500 会话恢复流转优化

- **登录态与 500 异常拦截脚本增强 (`WebScrapeService.ets`)**：
  - 增强 `buildLoginCheckScript()` 注入检测，全面识别「重复登录」、「已将之前的登录踢出」、「会话已失效/超时」、「点击此处」以及指向 `home.action` 的 500 错误与踢出确认页；
  - 统一识别 `repeat_login_prompt` 状态，自动清洗并升格为 HTTPS 安全主站链接。
- **500 会话失效恢复机制重构 (`Index.ets`, `ExamImport.ets`, `GradeImport.ets`)**：
  - 彻底废除 500 报错时直接重试二级子页面的死循环缺陷；
  - 遇到 HTTP 500 错误时，先导航至教务系统主页 `home.action`（VPN 模式下为 `VpnEncoder.buildVpnHomeUrl()`）激活主 Session 会话；
  - 待主页加载完成确立登录态（`logged_in`）后，再平滑流转跳转至课表（`courseTableForStd.action`）、考试（`stdExamTable!examTable.action`）或成绩（`person!search.action`）页面执行数据提取。

---

## 2026-08: 华为应用市场上架合规与端云体验 8 大核心优化

- **1. 首次启动隐私授权弹窗与 SDK 延迟初始化 (`PrivacyDialogComponent.ets`, `AuthService.ets`, `EntryAbility.ets`)**：
  - 移除非法自启第三方 SDK 行为，增加启动阶段合规弹窗展示权限用途并提供《用户服务协议》与《隐私政策》长文本详情查阅；
  - 用户点击「同意」后持久化状态并执行 `AuthService.initSDK()` 延迟初始化，点击「不同意」安全退出应用。
- **2. 包名与元信息规范化 (`app.json5`, `string.json`)**：
  - 统一规范应用厂商 `vendor: "uestc_campus"`、应用显示名 `成电助手` 与 EntryAbility 描述信息。
- **3. 账号注销全量清空 (`AccountManage.ets`, `AppSettings.ets`, `AuthService.ets`)**：
  - 在账号管理与设置页中新增「注销账号」危险操作，配备二次确认风险弹窗；
  - 一键登出云端账号并彻底清空本地用户凭据（`classtable_login_pref`）、业务数据库（`course_table_local_db`）及 AI 会话历史（`chat_sessions_db` / `chat_messages_db`）。
- **4. 生成式 AI 内容免责声明 (`AssistantPage.ets`, `FloatingSubWindowContent.ets`)**：
  - 依据《生成式人工智能服务管理暂行办法》，在全屏 AI 助手页与全局悬浮 Mini 助手底部常驻展示「⚠️ AI 生成内容仅供参考，课程与考试安排请以教务处官方系统为准」。
- **5. 权限动态按需申请 (`PermissionHelper.ets`)**：
  - 封装 `PermissionHelper`，将日历读写等敏感权限统一收归为触发操作时按需申请，并提供用户拒绝后的友好引导。
- **6. 大模型 API 防盗刷与安全加固 (`ai-proxy/src/security.ts`, `BackendAgentClient.ets`)**：
  - 后端引入 HMAC-SHA256 请求签名校验、5 分钟 Anti-Replay Nonce 防重放、IP 滑动窗口限流（对话 30 次/分，视觉 10 次/分）及 4000 字符 Payload 边界防护；端侧自动注入安全请求头。
- **7. 教务认证异常与验证码全屏手动接管 (`WebScrapeTakeoverBar.ets`, `Index.ets`, `ExamImport.ets`, `GradeImport.ets`)**：
  - 封装通用手动接管条 `WebScrapeTakeoverBar`，在课表、考试、成绩抓取中遇到统一身份认证、滑块验证码或异常时自动解除遮罩，允许用户手动操作后一键「立即抓取当前页」。
- **8. 多学期课表归档与离线切换 (`CourseRepository.ets`, `CourseService.ets`, `tableUI.ets`, `CourseManage.ets`)**：
  - 课表页学期下拉菜单实时展示各学期归档课程门数，切换已归档学期支持秒级离线渲染；切换未导入学期展示友好空状态与一键导入入口；本地课表管理支持针对各学期独立维护。

---

## 2026-08: 日程日历唯一性保证与双向联动同步

- **系统日历（CalendarKit）去重与唯一性保证 (`CalendarKitReminderService.ets`)**：
  - 修复向系统日历写入日程时可能发生的重复事件问题；
  - 建立唯一事件键与本地映射校验，防止重复点击或多端同步导致的日历事件冗余。
- **双向联动与状态一致性删除 (`ScheduleService.ets`, `ToolExecutor.ets`)**：
  - 在删除本地日程（`deleteSchedule` / `app_data_mutate`）时，自动检索并同步清除系统日历中关联的 Calendar Event；
  - 保证本地数据库（Preferences）与 HarmonyOS 系统日历状态始终严格一致。

---

## 2026-08: 原生 Markdown 渲染组件与浮窗富文本适配

- **ArkTS 原生 Markdown 渲染引擎 (`MarkdownBubble.ets`)**：
  - 纯原生 ArkTS 实现 Markdown 解析与排版渲染，支持标题（# ~ ### 多级标题与紧凑间距）、粗体、行内代码、引用块、有序/无序列表及代码块。
  - 优化段落智能换行：支持紧凑属性文本（如 `日期:`、`时间:`、`地点:`、`类型:`、`备注:`）自动换行排版，以及操作状态提示（如 `已同步至系统日历`）独立分段。
- **全局悬浮 Mini 助手 Markdown 适配 (`FloatingSubWindowContent.ets`)**：
  - 将悬浮 Mini 助手的原始 Text 替换为 `MarkdownBubble` 组件，实现全屏与浮窗统一的高质量排版体验。
- **紧凑折叠工具调用面板 (Tool Call Collapse UI)**：
  - 借鉴现代 Agent 交互设计（如 Claude Code / Antigravity），对工具调用和执行结果提供优雅的紧凑折叠指示条，支持实时状态旋转、执行耗时显示与一键展开明细。
- **Agent 遥测性能指标 (Telemetry Metrics)**：
  - 在 AI 回复气泡底部展示流式推理耗时（ms）、Token 消耗估算与工具调用计数指标卡片。

---

## 2026-08: 前端界面体验与多端 UI 细节深度优化

- **课表网格 (`tableUI.ets`)**：
  - 新增实时当前时间线指示器（Current Time Indicator），直观标明当前所处节次；
  - 修复 AI 助手课程卡片宽度溢出与过长课名折叠问题。
- **AI 助手欢迎页 (`AssistantPage.ets`)**：
  - 新增快捷场景胶囊按钮（Prompt Chips：`查今天课表` / `查最近考试` / `查GPA` / `查校车时刻` / `建自习日程`），一键快速交互。
- **考试卡片 (`ExamPage.ets`, `ExamCountdownCard.ets`)**：
  - 新增紧急考试倒计时（<24h）呼吸高亮视觉动效与考场地图快捷入口。
- **成绩页 (`GradePage.ets`)**：
  - 升级 GPA 概览 Hero 仪表盘卡片与分类成绩卡片流。
- **日历页 (`CalendarPage.ets`)**：
  - 优化月视图事件标记点排布，防止多事件圆点超出单元格边界。

---

## 2026-08: 全局悬浮 AI 伴随助手与会话统一持久化

- **会话统一持久化中心 (`ChatSessionRepository.ets`)**：
  - 统一全屏助手页（`AssistantPage`）与悬浮 Mini 助手（`FloatingSubWindowContent`）的会话存储与消息历史。
  - 悬浮窗顶部新增「➕ 新对话」按钮，点击立即重置上下文并给出即时 Toast 提示。
- **多端开关状态联动**：
  - 基于 `AppStorage` 实现悬浮球开关状态在全屏助手侧边栏、应用设置页（`AppSettings.ets`）与悬浮窗本体之间的毫秒级双向同步与持久化（`setting_floating_ball_enabled`）。
- **HarmonyOS 子窗口架构 (`FloatingWindowManager.ets`)**：
  - 基于 `windowStage.createSubWindow` 实现全局跨页面透明子窗口；
  - **球态 (Ball Mode)**：60×60 vp 发光呼吸球，支持自由全屏拖拽与贴边吸附物理反馈；
  - **浮窗态 (Panel Mode)**：覆盖在当前页面的 Mini 助手卡片，右上角配备 `[-]` 缩小至悬浮球与 `[X]` 关闭悬浮球；
  - 修复子窗口初始化生命周期（必须先 `setUIContent` 再配置尺寸与位置，规避 `1300002` 错误码）与 CalendarKit 权限前置检查（规避 `201` 拒绝异常）。
- **页面上下文感知与 UI 动作总线 (`PageContextTracker.ets`, `UIActionDispatcher.ets`)**：
  - 课表、成绩、考试及首页各 Tab 实时向感知中心上报数据快照；
  - Mini 助手与后端 Agent 对话时自动注入当前页面快照，赋予 AI 敏锐的实时感知能力；
  - 支持通过 `execute_page_action` 直接控制页面切周、切换 Tab、触发数据导入或展示高亮聚光灯引导（Spotlight Guidance）。

---

## 2026-08: 教务系统登录与导入状态机健壮性升级

- **统一身份认证状态机优化**：
  - 修复用户输入凭证阶段提前自动跳转问题，在输入账号密码时暂停自动跳转逻辑；
  - 修复多设备重复登录拦截提示（`home.action`）时明文 HTTP 导致的会话丢失，使用原生 `loadUrl` 自动确认放行。
- **全链路 HTTP 500 容错与重试**：
  - 课表与成绩导入全链路增加 HTTP 500 自动重试与指数退避机制，大幅提升弱网/高峰期教务导入成功率。
- **动态学期计算与 GPA 过滤**：
  - 成绩筛选支持相邻上下 10 学期动态换算，默认回退至已出分学期（base 503），修复历史成绩动态学期解析与 GPA 绩点分母计算逻辑。

---

## 2026-08: 统一控制引擎与内存数据查询引擎

- **统一端侧元工具架构 (Universal App Control Engine)**：
  - 将过去 33+ 个分散原子工具收敛为 **5 大核心元工具**（`app_data_query`, `app_data_mutate`, `app_control`, `campus_search`, `app_pipeline`）与 4 大高阶辅助工具（`get_current_page_context`, `execute_page_action`, `generate_study_plan`, `parse_text_to_schedule`）。
  - 新增教务处官网实时公告抓取工具（`search_jwc_news`）。
- **纯内存级多维查询引擎 (`DataQueryEngine.ets`)**：
  - 接管课表、考试、成绩、日程、系统日历、提醒配置与教学周系统信息，支持日期/周次换算、GPA 实时计算与多维组合过滤。
- **声明式复合流水线批处理 (`executePipeline`)**：
  - 支持端侧顺序批处理多步复合指令（如查空闲 ➔ 创日程 ➔ 写日历），彻底消除多轮网络往返。

---

## 2026-08: 评奖升级与多模态智能体演进

- **交互多模态化（语音 ASR + 智谱视觉日程识别）**：
  - **鸿蒙原生语音识别 (CoreSpeechKit)**：引入 `SpeechRecognizerHelper.ets` 对接 `@kit.CoreSpeechKit`，输入栏集成「🎙️ 语音输入」。
  - **智谱 GLM-4V 多模态海报/截图日程提取**：后端接入 `glm-4v-plus` 视觉大模型（`src/vision.ts`），前端通过 `VisionScheduleHelper.ets` 免权限选择图片并自动提取日程。
- **成电深度场景 RAG 知识库解耦 (`CampusKnowledgeStore`)**：
  - 后端模块化知识库：`bus_schedule.json`（班车）、`academic_policy.json`（缓考/补考/保研GPA）、`hospital_guide.json`（校医院/医保）、`facilities_guide.json`（图书馆/场馆）、`campus_life.json`（一卡通/水电/校园网）。
- **鸿蒙桌面万能服务卡片 (Widget)**：
  - 声明 `EntryFormAbility`，支持 2x2 与 2x4 万能课表服务卡片，倒计时下节课并支持点击直达。
- **折叠屏与平板一多自适应**：
  - `BreakpointUtils.ets` 监听窗口断点（sm/md/lg），首页解耦为四大子组件（`HomeHeaderComponent`、`NextCourseCardComponent`、`ExamCountdownCard`、`QuickLinksGrid`），自适应呈现双栏/多列栅格。

---

## 2026-08: 首页五 Tab 架构重构

- 主界面重构为五大 Tab：**发现（Quick）/ AI助手（Assistant）/ 课程（Class）/ 日历（Calendar）/ 我的（Mine）**。
- 今日课程卡片增加门数文案与切换图标（`switch.svg`），点击可自由在课程与考试倒计时卡片之间切换。
- 我的页新增意见反馈弹窗（支持一键复制开发者邮箱 `pjj644@users.noreply.github.com`）与版本信息展示。

---

## 2026-08: 仓库根目录迁移与工程级工具链升级

- **Git 仓库根目录迁移**：仓库根迁移至 `D:\harmony\helper_app`，统一纳管 `Application/`、`CloudProgram/`、`doc/`、脚本及素材。
- **官方 DevEco CLI 与 MCP 接入**：集成 `@deveco/deveco-cli`（`devecocli`）与 `deveco-mcp`（ArkTS/C++ LSP 静态诊断），提供根目录标准构建批处理脚本（`_build.bat`、`_clean_build.bat`、`_lint.bat`）。
