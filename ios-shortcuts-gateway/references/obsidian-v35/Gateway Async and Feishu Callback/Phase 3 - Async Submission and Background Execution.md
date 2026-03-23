# Phase 3 - Gateway异步提交与后台执行

关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

让 `POST /short-video/task` 默认只返回 `ACCEPTED`，实际执行转入后台任务。

## 本阶段应完成

- Gateway 默认异步模式
- 立即返回 `request_id`
- 后台执行 `Clipper / Analyzer`
- 正确更新 `status.json`
