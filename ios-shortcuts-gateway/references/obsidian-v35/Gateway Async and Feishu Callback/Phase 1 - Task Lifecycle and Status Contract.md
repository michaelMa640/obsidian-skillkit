# Phase 1 - 异步任务生命周期与状态文件契约

关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

定义 Gateway 从 `ACCEPTED` 到最终状态的完整异步任务生命周期，并明确 `status.json` 的字段与状态迁移规则。

## 本阶段应完成

- 定义状态集合：`ACCEPTED / RUNNING / SUCCESS / PARTIAL / FAILED / AUTH_REQUIRED`
- 定义 `status.json` 最小字段
- 定义请求目录的标准文件集
- 定义最终状态的收束规则
