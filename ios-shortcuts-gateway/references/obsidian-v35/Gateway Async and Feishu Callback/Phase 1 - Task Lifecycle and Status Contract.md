# Phase 1 - 异步任务生命周期与状态文件契约

关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

定义 Gateway 从 `ACCEPTED` 到最终状态的完整异步任务生命周期，并明确 `status.json` 的字段与状态迁移规则。

## 本阶段应完成

- 定义状态集合：`ACCEPTED / RUNNING / SUCCESS / PARTIAL / FAILED / AUTH_REQUIRED`
- 定义 `status.json` 最小字段
- 定义请求目录的标准文件集
- 定义最终状态的收束规则

## 本阶段结论

Phase 1 已定稿，当前仓库里已新增：

- `ios-shortcuts-gateway/references/task-status-contract.md`
- `ios-shortcuts-gateway/references/task-status.schema.json`

## 当前定下来的规则

- 每个请求目录固定为：
  - `.tmp/gateway/runs/<request_id>/`
- 当前状态文件固定为：
  - `status.json`
- 允许状态：
  - `ACCEPTED`
  - `RUNNING`
  - `SUCCESS`
  - `PARTIAL`
  - `FAILED`
  - `AUTH_REQUIRED`
- 最终状态只能是：
  - `SUCCESS`
  - `PARTIAL`
  - `FAILED`
  - `AUTH_REQUIRED`
- 一旦进入最终状态，不允许再被降级覆盖

## 必保留字段

- `request_id`
- `action`
- `status`
- `message_zh`
- `created_at`
- `updated_at`

如可获取，还必须保留：

- `source_url`
- `normalized_url`
- `original_source_text`

## 结果

Phase 1 完成后，异步 Gateway 已有清晰、可实现、可校验的状态文件契约，后续 Phase 3 可以直接按这份契约落实现。
