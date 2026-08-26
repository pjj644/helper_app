# 成电助手 Phase 2 实施计划

> **版本**：v2.1（2026-08-26）　**状态**：✅ 关键决策已确认，可开工
> **前置**：Phase 0 + Phase 1 已交付（评测 97.0%、U2 冒烟全过）；本计划 v1.0 的 Wave 前半已执行完毕（见 §1 盘点）。
> **范围裁定（2026-08-26 用户逐项确认）**：
> - ❌ **晨报卡片**（原 P2-4）、❌ **实况窗 Live View Kit**（原 P2-5）、❌ **小艺意图接入**（原 P2-8/P2-6）**本轮均不做**；小艺调研结论已归档 [`RESEARCH_XIAOYI.md`](./RESEARCH_XIAOYI.md)，随时可另立轮次启动；
> - ✅ ID 治理采纳建议方案（§3 P2-7c）；P2-7d 仅做 **AI 会话加密上云**，日程不纳入同步；
> - 生活服务四件套与 Push Kit 维持排除。
> **执行模型**：与 Phase 0/1 相同——主 agent 只做整合、测试、git 提交；实现由子 agent 分波次并行。
> **验证基准**：devecocli build/lint 双绿、后端 typecheck / phone-sim / `npm run test:eval`（≥97% 不回归）。真机项标注 🔴 留给用户。

---

## 1. v1.0 执行盘点（截至 2026-08-26）

| 编号 | 任务 | 状态 | 提交 |
|---|---|---|---|
| P2-1a | 校园指南 preferences 持久化 last-good 缓存 | ✅ 完成（B-03 清偿） | `f74dbaf` |
| P2-1b | `set_reminder_enabled` 行为修复 | ✅ 完成（B-05 清偿） | 前端 `f0f684c` · 后端 `a4968ff` |
| P2-1c | 日志降噪与 Date 卫生 | ✅ 完成 | `4acf33a` |
| P2-2 | 课表/成绩单截图导入（GLM-4V） | ✅ 完成* | 前端 `0f79c3e` · 后端 `36b0721` |
| P2-3 | 云同步升级 | ◐ **部分完成** | `a043aaf` |
| P2-4 | 晨报卡片 | ❌ 移出本轮 | — |
| P2-5 | 实况窗 Live View Kit | ❌ 移出本轮 | — |
| P2-6 | 小艺 Skill 接入 | ❌ 移出本轮（调研已归档） | 见 RESEARCH_XIAOYI.md |

\* P2-2 与原计划的偏差：当前实现为「选图→解析→直接入库」，**入库前预览修正 UI 未做**，转立新任务 P2-9；真图实测已通过（20 门课置信度 0.95）。

**P2-3 剩余缺口（本计划 P2-7 的现状证据）**：
- `SETTING_AUTO_SYNC_SCHEDULE_KEY` 开关现绑定的是**本地**日程/日历自动同步（`ScheduleService.syncCoursesToSchedule`），**不是云端上传**——云端自动同步仍为零；
- `SyncService.generateUniqueId`（时间戳+随机熵）已实现但**未被使用**，云端记录 ID 仍为 hash 截断（`buildId`），id-generator 云函数未接入；
- 上传映射已注入 `updatedAt` 时间戳，但**下载侧没有按条目 LWW 合并逻辑**，仍是整包覆盖；
- 同步范围仍仅课程+考试，日程与 AI 会话未纳入。

---

## 2. 任务总览

| 编号 | 任务 | 优先级 | 规模 | 依赖 | 交付形态 |
|---|---|---|---|---|---|
| P2-7a | 云端自动同步（debounce 上传队列 + 断网补传） | P0 | 中 | 无 | ✅ `aada984` |
| P2-7b | 条目级 LWW 下载合并 | P0 | 中 | 无（可与 a 并行） | ✅ `c165f9b` |
| P2-7c | ID 治理：维持现状 + 新实体本地 UUID 约定 | P1 | 小 | 无（决策已定） | ✅ `aada984` |
| P2-7d | AI 会话加密上云（仅会话，日程不纳入） | P1 | 大 | 7a/7b 合入 | ◐ 进行中（schema 已提交 `a1cce25`） |
| P2-9 | 截图导入入库前预览修正 UI | P1 | 小 | 无 | ✅ `f02d750` |

**波次安排**：
- **Wave P2-A**（三路并行）：P2-7a ∥ P2-9 ∥ P2-7c
- **Wave P2-B**（两路并行）：P2-7b ∥ P2-7d
- **Wave P2-C**：收尾冒烟复测（🔴 U-P2-x）

---

## 3. 任务详单

### P2-7a 云端自动同步 `[已完成 · aada984]`

- **方案**：
  1. 设置页「数据同步」卡片新增独立的**「云端自动同步」开关**（与现有本地日历自动同步开关并存，互不干扰），持久化新偏好键；
  2. 课程/考试数据变更落盘后 debounce 30s 触发静默上传；频率上限最快 5 分钟一次 diff 上传（CloudDB 免费档配额护栏）；
  3. 失败指数退避；未成功条目进入本地待同步队列（preferences 落盘），下次启动与网络恢复时补传；
  4. 默认仅 WiFi 自动，蜂窝需显式开启（连接管理模块判断网络类型）。
- **涉及文件**：`SyncService.ets`、`AppSettings.ets`、`AppConstants.ets`、新增轻量 `AutoSyncScheduler`（或并入 SyncService）。
- **验证**：模拟器改课程数据 → ≤30s 云端可见；断网操作恢复后补传；开关关闭零上传。
- **提交**：`feat(sync): background auto upload with debounce queue and offline retry`

### P2-7b 条目级 LWW 下载合并 `[已完成 · c165f9b]`

- **方案**：
  1. 下载合并从「整包覆盖」改为**条目级比较**：以 `(courseId, semesterId, dayOfWeek, startSection)` / 考试业务键对齐双端条目；
  2. 双方都有 → 比较 `updatedAt` 新者胜（本地时钟），时间戳相同再比 `deviceId` 兜底排序；仅一端有 → 按删除墓碑语义处理（本期简化：仅一端有即保留，冲突日志记录）；
  3. 服务器接收时间为最终裁决兜底（防时钟漂移）；冲突事件写本地日志，设置页「同步状态」入口可查最近 N 条。
- **涉及文件**：`SyncService.ets`（下载合并路径）、`CourseRepository.ets`/`ExamRepository.ets`（批量 upsert）、`AppSettings.ets`。
- **验证**：双模拟器实例构造双写冲突 → LWW 裁决正确；单端删除/新增场景数据一致。🔴 双实例验收留 U-P2-4。
- **提交**：`feat(sync): entry-level lww merge on download with conflict log`

### P2-7c ID 治理：维持现状 + 新实体本地 UUID `[已完成 · aada984]`

> 2026-08-26 用户确认采纳建议方案。

- **事实基础**：现有 `ClassCourse`/`ClassExam` 的 CloudDB 主键为 Integer；`buildId()` 是对业务键的**确定性**哈希——同一门课重复上传恒得同一云 ID（幂等覆盖而非插重），双设备写同一门课天然收敛。碰撞仅发生在「不同业务键哈希同值」，Integer 约 21 亿空间、单用户数百条数据规模下概率约十万分之一量级，且即便碰撞 LWW 合并仍可工作。id-generator 云函数实现仅为返回 `crypto.randomUUID()`，无号段分配，「集中发号」无实质增益。
- **决策落地**：
  1. 课程/考试同步**维持确定性哈希 ID 不动**（幂等性价值 > 理论碰撞风险），存量数据零迁移；
  2. 本轮新增实体（见 P2-7d 的会话表）一律新建对象类型、**String 主键 + 端侧 `util.generateRandomUUID()`**；
  3. id-generator 云函数**退役**（保留在仓库但不部署、不接入）；`SyncService.generateUniqueId` 若无调用方一并清理。
- **提交**：`docs/chore(sync): keep deterministic hash ids, retire id-generator function`

### P2-7d AI 会话加密上云 `[进行中 · schema 已提交 a1cce25，端侧实现中]`

> 2026-08-26 用户确认：日程不同步，只做会话同步。容量评估：本地会话硬顶 20 个（`AI_CHAT_MAX_SESSIONS=20`），单用户全量加密后 ≤7MB，占 CloudDB 免费档 2GB 存储 <0.5%；自动同步频率远低于免费档 10 OPS/s 上限。**容量不是约束，设计约束如下。**

- **CloudDB 设计**：
  1. 新增对象类型 `ChatSessionRecord` / `ChatMessageRecord`：String 主键（UUID）、`userId`/`sessionId`/`role`/`updatedAt` 普通字段（可索引）、消息正文用 **Text 字段**存加密 payload（String 字段上限 200 字符，Text 不能做主键/索引）；
  2. 按「一条消息一条记录」存储，天然满足单记录 ≤2MB 限制；
  3. ⚠️ **permissions 收紧为 Authenticated + Creator，删除 World 角色读写删权限**（现有课程/考试表的 World 权限是存量问题，本轮至少保证新表不带 World）。
- **端侧设计**：
  1. 加密密钥由登录账号 UID 派生（HKDF/PBKDF2），AES 对称加密后 base64 上行，服务端只见密文；
  2. 复用 P2-7a 的 debounce 队列与断网补传通道；本地 20 条裁剪语义同步到云端（删除多余记录）；
  3. 密钥丢失即历史不可读——设置页同步开关处明示；未登录状态不同步会话。
- **验证**：双实例会话列表一致；抓包/云端控制台确认存储为密文；登出后云端不再新增记录。
- **提交**：`feat(sync): encrypted ai session sync via clouddb`（schema 变更单独一笔 `feat(cloud): add chat session object types`）

### P2-9 截图导入入库前预览修正 UI `[已完成 · f02d750]`

- **背景**：P2-2 当前为解析结果直接入库，识别错漏无法在落库前修正（子 agent 收尾建议，原 v1.0 计划本就有此项）。
- **方案**：课表/成绩两处「截图导入」在解析完成后插入**预览确认表格**：识别条目列表（课程名/教师/教室/节次周次 或 成绩/学分/GPA）逐行可编辑，低置信度字段高亮提示，支持整行剔除；确认后才走 `CourseService`/`GradeService` 入库。复用现有导入预览组件风格，不引入新依赖。
- **验证**：故意改错一个字段保存 → 库中为修改后值；剔除某条目 → 不入库；低置信度字段正确高亮。
- **提交**：`feat(import): preview and correct vision results before saving`

---

## 4. 假设

- **A-P2-5**：GLM-4V 密钥继续有效且截图导入调用量在配额内。
- **A-P2-6**：云端自动同步默认仅 WiFi 生效，蜂窝网络需显式开启。
- **A-P2-7**：CloudDB 免费档配额以 AGC 控制台「项目设置 → 项目配额」实时显示为准（调研口径：存储 2GB / 并发 150 / 10 OPS/s），会话上云体量占用量极低。

## 5. 🔴 用户操作清单

| # | 时机 | 内容 |
|---|---|---|
| U-P2-1 | P2-7d 验收前 | AGC 控制台创建并导出对象类型 **ChatSessionRecord**——schema 已提交至 `CloudProgram/clouddb/objecttype/ChatSessionRecord.json`（每会话一条记录，非按消息拆表；创建时直接导入该 JSON 或按字段抄录），并部署到云数据库后端侧方可联调 |
| U-P2-2 | P2-7 验收 | 启动两个模拟器实例互同步：A 改 → B 拉、断网补传、双写冲突 LWW、会话密文核验 |
| U-P2-3 | 各 Wave 后 | 模拟器冒烟复测（按任务增量出新清单，格式沿用已归档的 U2 清单） |

## 6. 验收标准汇总

- [ ] WiFi 下课程/考试数据变更 ≤30s 自动上云，断网恢复自动补传，开关关闭零上传（P2-7a）
- [ ] 双实例双写冲突按 LWW 正确裁决，冲突可在设置页查看日志（P2-7b）
- [ ] 课程/考试 ID 维持现状无迁移；新会话表为 String 主键 + 本地 UUID；id-generator 未接入任何调用链（P2-7c）
- [ ] 会话双端一致；云端控制台可见记录均为密文；新表 permissions 无 World 角色；登出后不再上行（P2-7d）
- [ ] 截图导入可预览、修正、剔除后再入库（P2-9）
- [ ] 全程：commit 前 build+lint 双绿、后端 typecheck 绿、`npm run test:eval` ≥97%、分支不 push

## 7. Git 约定

延续现状：前端在 `opt/phase02` 分支叠加提交（Phase 2 中段自 `opt/phase01` 切出）；后端同在 `opt/phase01-backend`。每任务至少一个独立 commit，消息 `type: what & why` + 尾行 `Co-Authored-By: Claude <noreply@anthropic.com>`；不 push 待审。

## 8. 后续观察项（不入本轮验收）

- **小艺意图接入**（本轮移出）：技术路径已明确——装饰器式意图（API 20+，本项目 SDK API 22 满足）、未上架可真机本地调试验证；真实语音触发须 AGC 上架 + 平台注册审核，个人开发者准入建议先邮件 hagservice@huawei.com 书面确认。完整对比与来源见 [`RESEARCH_XIAOYI.md`](./RESEARCH_XIAOYI.md)，启动即有现成方案；
- 小艺开放平台 MCP 插件（魔搭导入、仅限本账号调试、零审核）作为 ai-proxy 能力被小艺调用的低成本试验通道；
- 云 A2A 协议包装 ai-proxy 为 Remote Agent（企业主体就绪后再评估）；
- 晨报卡片与实况窗：维持搁置，若日后重启，实况窗仍受 Live View Kit 资质申请制约；
- 存量 `ClassCourse`/`ClassExam` 表的 World 权限收紧（本轮先保证新表不带 World，旧表另行处理）。
