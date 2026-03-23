# Phase 6 - Shortcut Submit Only Mode
关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

把 iPhone 快捷指令从“等待最终结果”改成“提交即结束”，只显示 `request_id` 和提交成功提示。

## 本阶段已完成

- Gateway 默认 `ACCEPTED` 文案改为：
  - `任务已提交，正在后台执行。结果将稍后通过飞书返回。`
- README 中将 iPhone 正式交互改为：
  - 只提交任务
  - 立即结束快捷指令
  - 以后续飞书消息作为主结果回传
- 明确保留 `GET /short-video/task/{request_id}`，但仅作为调试或运维接口

## 正式交互

### 快捷指令提交阶段

快捷指令向 Gateway 发送：

- `POST /short-video/task`

请求体保持：

- `action`
- `source_text`
- `client`
- `wait_for_completion = false`

### 快捷指令结束阶段

快捷指令只展示：

- `request_id`
- `message_zh`

然后立即结束，不再做长轮询。

### 结果回传阶段

最终结果通过飞书返回，包括：

- 成功 / 部分完成 / 失败 / 登录态失效
- 原始视频链接
- 规范化链接
- 原始分享文本
- 笔记路径
- `request_id`

## 输出结论

Phase 6 完成后，iPhone 快捷指令正式进入“提交即返回”模式，移动端不再承担长任务等待职责。
