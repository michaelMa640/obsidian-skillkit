# Phase 2 - 飞书结果回传消息契约

关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

定义 Gateway 完成任务后发往飞书的结构化消息字段与中文消息模板。

## 本阶段应完成

- 定义成功、部分完成、失败、登录态失效四类消息模板
- 明确必须回传：原始链接、规范化链接、原始分享文本
- 明确不得回传的敏感内容

## 本阶段结论

Phase 2 已定稿，当前仓库里已新增：

- `ios-shortcuts-gateway/references/feishu-callback-message-contract.md`
- `ios-shortcuts-gateway/references/feishu-callback.payload.schema.json`

## 当前定下来的规则

Gateway 仅在以下最终状态触发飞书回传：

- `SUCCESS`
- `PARTIAL`
- `FAILED`
- `AUTH_REQUIRED`

不会在以下状态发消息：

- `ACCEPTED`
- `RUNNING`

## 飞书回传必须包含

- `request_id`
- `action`
- `status`
- `message_zh`
- `source_url`
- `normalized_url`
- `original_source_text`
- `clipper_note`
- `analyzer_note`
- `failed_step`
- `auth_action_required`
- `refresh_command`

## 安全边界

飞书回传中明确禁止包含：

- cookies
- storage state paths
- raw stack traces
- full debug file contents

## 结果

Phase 2 完成后，飞书回传消息格式和回传时机已经固定，后续 Phase 4 可以直接实现发送模块，不需要再回头猜消息字段。
