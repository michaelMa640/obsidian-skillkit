# Phase 7 - End-to-End Validation and User Docs
关联总计划：[[v3.5 Gateway Async and Feishu Callback PRD]]

## 目标

完成从 iPhone 提交任务到飞书收到结果的端到端联调，并整理最终用户文档。

## 本阶段已完成

- 将联调测试矩阵更新为正式异步模式
- 将远程 iPhone 验收标准更新为“提交成功 + 飞书回调成功”
- 新增最终用户文档：
  - `ios-shortcuts-gateway/references/ios-shortcuts-submit-mode-user-guide.md`
- README 增加最终用户文档入口

## 最终用户工作流

1. Windows 电脑启动 Gateway
2. iPhone 快捷指令提交 `clip` 或 `analyze`
3. 快捷指令立即显示：
   - `request_id`
   - `任务已提交，正在后台执行。结果将稍后通过飞书返回。`
4. 用户等待飞书回调
5. 如需排障，再查看本地 `status.json` 与 `feishu-callback.json`

## 最终验收口径

### 成功路径

- 本地 `clip` 成功
- 本地 `analyze` 成功
- iPhone 远程提交 `clip` 成功，且飞书收到结果
- iPhone 远程提交 `analyze` 成功，且飞书收到结果

### 失败路径

- 至少确认一次 `AUTH_REQUIRED` 或配置失败路径
- 失败时可通过 request 目录定位原因

## 输出结论

Phase 7 完成后，v3.5 方案已具备：

- 本地 Gateway
- Tailscale 远程提交
- 异步后台执行
- 飞书结果回传
- 最终用户使用文档
