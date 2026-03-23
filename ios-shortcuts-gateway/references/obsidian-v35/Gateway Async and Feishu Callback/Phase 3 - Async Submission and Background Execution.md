# Phase 3 - Gateway异步提交与后台执行

关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

让 `POST /short-video/task` 默认只返回 `ACCEPTED`，实际执行转入后台任务，并把执行过程完整落到 `status.json`。

## 本阶段结论

Phase 3 已完成，当前 `ios-shortcuts-gateway/app.py` 已真正接上异步执行链路。

## 已完成内容

- `POST /short-video/task` 默认异步返回
- 默认立即返回：
  - `status = ACCEPTED`
  - `request_id`
- 后台任务启动后会写入：
  - `status = RUNNING`
- 任务结束后会写入最终状态：
  - `SUCCESS`
  - `PARTIAL`
  - `FAILED`
  - `AUTH_REQUIRED`
- 所有状态都通过 `status.json` 持久化
- `GET /short-video/task/{request_id}` 已可读取当前状态

## 当前实现规则

### 同步模式

仅当请求体显式传入：

```json
"wait_for_completion": true
```

Gateway 才会等待业务任务完成后再返回最终结果。

这条路径主要用于本机 PowerShell 烟雾测试，不推荐 iPhone 快捷指令使用。

### 异步模式

默认情况下：

```json
"wait_for_completion": false
```

Gateway 会：

1. 校验请求
2. 生成 `request_id`
3. 写入 `request.json`
4. 写入 `status.json = ACCEPTED`
5. 立即返回
6. 在后台继续执行 `Clipper / Analyzer`

## 与 Phase 1 契约的对齐

当前实现已按 Phase 1 要求保留：

- `request_id`
- `action`
- `status`
- `message_zh`
- `created_at`
- `updated_at`
- `original_source_text`

并在可获取时保留：

- `source_url`
- `normalized_url`
- `clipper_note`
- `analyzer_note`
- `failed_step`
- `auth_action_required`
- `refresh_command`
- `debug_hint`

## 仓库落点

- `ios-shortcuts-gateway/app.py`
- `ios-shortcuts-gateway/README.md`

## 已验证内容

- `app.py` 已通过 `python -m py_compile`
- `task-status.schema.json` 已通过 JSON 解析校验
- `feishu-callback.payload.schema.json` 已通过 JSON 解析校验

## 结果

Phase 3 完成后，Gateway 已具备真正可用的异步提交与后台执行能力。下一阶段应进入飞书通知发送模块，实现任务结束后的主动结果回传。
