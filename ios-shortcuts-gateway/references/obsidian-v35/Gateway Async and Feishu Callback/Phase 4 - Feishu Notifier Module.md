# Phase 4 - Feishu Notifier Module
关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

实现一个独立的飞书通知模块，用于在任务进入最终状态时发送标准化结果消息。

## 本阶段已完成

- 定义飞书回调模块边界
- 新增 `ios-shortcuts-gateway/feishu_notifier.py`
- 定义 `FeishuConfig`
- 定义 `FeishuCallbackPayload`
- 固定飞书文本消息格式
- 固定只允许最终状态发送：
  - `SUCCESS`
  - `PARTIAL`
  - `FAILED`
  - `AUTH_REQUIRED`
- 补充 gateway 本地配置契约中的 `feishu.*` 字段

## 新增配置字段

- `feishu.enabled`
- `feishu.webhook_url`
- `feishu.timeout_seconds`
- `feishu.message_prefix`

## 当前模块职责

- 校验飞书 webhook 配置
- 校验最终状态回调 payload
- 生成统一的飞书文本消息
- 发送 webhook 请求

## 当前阶段明确不做

- 不在本阶段把 notifier 接入任务完成回调
- 不在本阶段发送飞书消息
- 不在本阶段处理重试、退避或失败告警升级

这些会在 Phase 5 处理。

## 输出结论

Phase 4 的交付物是“可被集成的飞书通知模块”，不是“已经接线的飞书回调流程”。
