# 华为小艺第三方应用接入调研（RESEARCH_XIAOYI.md）

> **调研日期**：2026-08-26　**调研对象**：本项目（HarmonyOS NEXT 校园工具 App，API 6.0.2/22，未上架，个人开发者）
> **状态**：✅ 结论有效期为平台现状（小艺生态 2025–2026 快速迭代，建议半年内复核）
> **用途**：支撑 [`PHASE2_PLAN.md`](./PHASE2_PLAN.md) 中 P2-8 任务的技术选型。

## 1. 结论先行

**受限可行**：短期可在真机上本地调试验证意图链路（不需要上架）；但要让用户真正对小艺说「我的下一节课」并唤起本 App，必须 **App 先在 AGC 上架 + 在小艺开放平台完成意图注册并通过审核（约 3–5 个工作日）**。老一代 Intents Kit 流程不对个人开发者开放（需企业账号 + 白名单，多源社区证实、官方未明文）。

本项目 SDK 为 API 22（≥ 装饰器要求的 API 20 / HarmonyOS 6.0.0），且为 Stage 模型，**技术条件已满足**。

## 2. 四种接入方式对比

| 维度 | A. 传统 Intents Kit | B. 装饰器式意图 ⭐推荐 | C. 小艺开放平台 Skill | D. 深链跳转 |
|---|---|---|---|---|
| 形态 | `insight_intent.json` 配置垂域意图 | `@InsightIntentLink/Page/Function/Entry` 装饰既有代码 | 平台云端 Skill/智能体 | DeepLink/AppLink uri 拉起 |
| API 要求 | API 12+ | **API 20+，仅手机、仅 Stage** | 云侧为主；Skill 真机测试需 HarmonyOS 7 + Beta 小艺 | API 9+ |
| 触发入口 | 小艺建议卡片；语音须验收上架 | **小艺语音**、AI 入口跳转 | 小艺对话语音、智能体市场 | 仅「打开 XX 应用」级拉起 |
| 后台无 UI 执行 | 支持 | 支持（Function 静态方法 / Entry 后台模式） | 云端天然无 UI | 不支持 |
| 结果回传展示 | 卡片模板 | `resultDesc` 生成小艺回复话术；前台半模态窗展示 | 结构化卡片 | 无 |
| 个人开发者 | ❌ 不开放 | 未明文禁止；上架环节需过审 | 实名可注册体验 | 无门槛 |
| 未上架可否验证 | 否 | **可以**（开发者选项「意图框架调试」手动执行） | 需 Beta 小艺 App | 可以 |
| 本项目适配度 | 低（垂域不含课程表类） | **高**（NextCourse/TodayExam 自定义意图） | 中（适合纯对话型助手） | 高但体验弱 |

## 3. 关键机制（装饰器式意图）

- **`@InsightIntentLink` / `@InsightIntentPage`**：前台执行。Link 在已有 DeepLink/AppLink 上加声明；Page 装饰 Navigation 页面。小艺命中后拉起对应页面。
- **`@InsightIntentFunction`(+Method)**：后台执行。约束：export 类静态函数、参数仅基本类型、不得参与代码混淆（release 混淆会静默失效）。返回 `ExecuteResult.resultDesc` 直接生成小艺话术——如「下一节课是高等数学，10:00 在品学楼 A410」。
- **`@InsightIntentEntry`**：装饰 `InsightIntentEntryExecutor` 子类，`intentName/displayName/llmDescription/keywords/executeMode/parameters(JSON Schema)` 全参数化；`llmDescription` 与 `keywords` 的措辞质量直接决定语音命中率。
- **本地调试路径**：设置 → 系统 → 开发者选项 → 开启「意图框架调试」→ 查看设备上所有意图 → 配参数 → 执行。仅要求 HarmonyOS 6.0+ 真机，**不要求上架**。验证的是意图实现正确性，非语音识别链路。
- DevEco Studio CodeGenie 可辅助生成五类装饰器骨架。

## 4. 资质与门槛要点

- 真实语音触发的硬前提：**AGC 上架** → 华为开发者联盟管理中心 → 生态服务 → 智慧服务 → 小艺开放平台 → 意图框架注册 → 审核 3–5 工作日。
- 传统意图框架白名单申请：邮件 hagservice@huawei.com（账号 ID、App ID、Client ID、包名、意图名、华为账号 UID、图标、场景说明）。
- 教育类目上架可能涉及额外资质文件，需按 AGC 类目清单核实。
- **个人开发者能否走装饰器式意图的上架流程官方未明文——投入前应先邮件书面确认。**

## 5. 对自建后端（ai-proxy）的含义：A2A 与 MCP

- **云 A2A 协议**（鸿蒙 Agent 通信协议）：Streamable HTTP + JSON-RPC（8 个标准方法，SSE 回传），鉴权 AK/SK / OAuth2 / API-Key。ECS 上的 DeepSeek 服务理论上可包装成 Remote Agent 接入小艺对话，但该模式官方定位面向**企业开发者**——留作中期方向。
- **MCP 插件**：小艺开放平台支持将标准 MCP 服务封装为 Skill；其中「外部平台导入（魔搭自部署）」**仅限本账号调试、零审核**——若想让 ai-proxy 的 Agent 能力被小艺调用，这是当前阶段成本最低的试验通道（标准注册发布则需人工审核 3–5 工作日）。

## 6. 风险点

1. 上架是绕不过的门：一切真实语音触发都以 AGC 上架 + 平台审核为前提；
2. 个人开发者准入不明朗：存在「开发可以、上架卡壳」的可能，务必先邮件确认再投入大成本；
3. 语音命中率无官方保障：自定义意图靠 LLM 匹配 `llmDescription/keywords`，需真机反复调措辞;
4. 平台变动极快：本报告结论半年内可能过时；
5. release 混淆静默打断 Function 类意图；
6. 旧设备（非 HarmonyOS NEXT）完全不在覆盖范围。

## 7. 主要信息来源（抓取于 2026-08-26）

- 装饰器概述：https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/intents-skill-all-rec-decorator-overview
- Function 装饰器约束：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/intents-skill-all-rec-decorator-function
- 意图标准协议上架指导：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/intents-kit-listing-standard-protocol
- 意图本地调试（OpenHarmony 镜像，原文核对）：https://gitee.com/openharmony/docs/raw/master/zh-cn/application-dev/application-models/insight-intent-debug.md
- InsightIntentDecorator API 参考：https://gitcode.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-ability-kit/js-apis-app-ability-InsightIntentDecorator.md
- 小艺开放平台门户：https://developer.huawei.com/consumer/cn/celia ；能力体系：https://developer.huawei.com/consumer/cn/doc/service/platform-strength-0000001193466742
- Agent Framework Kit 指南 / 最佳实践：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/harmony-agent-framework-kit-guide 、https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-agent
- 社区实测（个人开发者限制、白名单流程，时效存疑已标注）：https://bbs.itying.com/topic/6a2d644babdd1e00552d4bc1
- A2A 协议规范镜像：https://github.com/YuniQiao/developer_hos ；京东 Agent 云案例：https://ost.51cto.com/posts/54751
