# doc/

成电校园助手（UESTC Helper）项目核心技术文档集。统一极速上手指令见根目录 [`../AGENTS.md`](../AGENTS.md)。

| 文档 | 职责与内容摘要 |
|---|---|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | **整包应用架构**：模块分层 / 数据流 / 五 Tab 导航 / 桌面万能服务卡片 / 班车日历联动 / 数据持久化 / 教务 500 会话恢复 / 学期周次算法 |
| [AI_AGENT.md](./AI_AGENT.md) | **AI 助手权威规格**：端云一体协同 / LangGraph 状态机 / 5 大核心元工具与 4 大感知工具 / SSE 协议 / Eval Harness / 悬浮伴随系统 / 原生 Markdown 渲染 / 三处同步铁律 |
| [BUILD_AND_TEST.md](./BUILD_AND_TEST.md) | **构建与验证指南**：DevEco CLI / Windows 批处理脚本 / 模拟器与真机调试 / 全场景 E2E 测试用例 / 提交规范 |
| [CHANGES.md](./CHANGES.md) | **项目演进记录**：逐阶段版本更新日志、架构重构与特性落地历史（含已归档 Phase 0/1 优化轮结果摘要） |
| [PHASE2_PLAN.md](./PHASE2_PLAN.md) | **当前阶段执行计划**：Phase 2 任务详单、波次安排、假设与用户操作清单 |
| [RESEARCH_XIAOYI.md](./RESEARCH_XIAOYI.md) | **小艺接入调研**：意图框架四种接入方式对比、资质门槛、本地调试路径与风险（后续小艺轮次的现成方案） |

> 已完成的历史阶段计划（`OPTIMIZATION_PLAN.md`）与一次性冒烟记录（`SMOKE_CHECKLIST_U2.md`）已归档删除，结果摘要并入 `CHANGES.md`，原文可查 git 历史。
> Git 仓库位于项目根目录 `D:\harmony\helper_app`，本目录随仓库统一进行版本管理。
