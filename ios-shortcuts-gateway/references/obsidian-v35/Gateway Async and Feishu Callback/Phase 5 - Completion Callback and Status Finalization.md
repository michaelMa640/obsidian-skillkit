# Phase 5 - Completion Callback and Status Finalization
关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

把后台执行结果、状态收敛和飞书回调真正串起来。

## 本阶段已完成

- 在 `app.py` 中接入 `feishu_notifier.py`
- 异步任务结束后统一进入最终状态收敛
- 最终状态写入 `status.json` 后再触发飞书回调
- 新增 `feishu-callback.json` 保存飞书发送结果
- 将回调结果写回 `status.json`：
  - `callback_attempted_at`
  - `callback_sent`
  - `callback_error`
- 增加终态保护：
  - 一旦进入 `SUCCESS / PARTIAL / FAILED / AUTH_REQUIRED`
  - 后续不得再把任务状态降级覆盖

## 关键行为

### 状态优先

任务真实执行结果先成为最终状态。

### 回调次之

飞书发送成功或失败只影响 callback 字段，不影响任务最终状态。

例如：

- 任务已经 `SUCCESS`
- 但飞书 webhook 发送失败

此时仍然保持：

- `status = SUCCESS`

不会因为回调失败而改写成 `FAILED`。

## 新增调试产物

每个请求目录现在会额外包含：

- `feishu-callback.json`

用于保存飞书发送结果或错误摘要。

## 输出结论

Phase 5 完成后，Gateway 已经具备：

- 异步接收任务
- 后台执行任务
- 写入最终状态
- 发送飞书回调
- 保持状态收敛稳定
