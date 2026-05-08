# 小宇宙 Mac 全本地总体方案

## 文档目的

这份文档用于汇总当前 Mac 端小宇宙全本地改造的整体规划，避免信息分散在 `Phase 1`、`Phase 2` 单独文档里，不方便从全局回看。

## 总体目标

目标不是只让某一条节目“偶尔能跑”，而是把小宇宙链路逐步推进到：

1. Mac Apple Silicon 上可正式运行。
2. 正式运行时不静默降级到 CPU。
3. 高温持续时能主动中断并给出明确原因。
4. 长音频下 speaker 区分结果有可接受的稳定性。
5. 最终能接回 Obsidian 知识流程，而不是只停留在单点脚本验证。

## 核心原则

- 本地优先
- 高性能后端优先
- CPU 不作为正式执行路径
- 环境不满足时 fail closed
- 热保护必须可中断、可报告
- 先把主链路做稳，再扩大样本，再接完整知识流程

## 阶段划分

### Phase 1

目标：

- 把 Mac Apple Silicon 的本地执行主链路接起来
- 建立 CPU 禁用策略
- 建立热保护框架

已完成内容：

- 新增 Mac runtime profile
- ASR 接入 `mlx-whisper`
- diarization 接入 `pyannote + mps`
- fail-closed no-CPU 执行策略
- thermal guard 结构化中断与报告

当前结论：

- `Phase 1` 已完成

对应文档：

- [Xiaoyuzhou Mac 全本地方案 Phase 1.md](/Users/michael_user/Documents/vibe%20coding/ObsidianSkillkit/docs/xiaoyuzhou-mac-local/Xiaoyuzhou%20Mac%20%E5%85%A8%E6%9C%AC%E5%9C%B0%E6%96%B9%E6%A1%88%20Phase%201.md)

### Phase 2

目标：

- 用真实长节目验证 Mac 全本地主链路
- 对长音频 speaker refinement 做保守化降载
- 判断 speaker 质量是否达到可接受水平

已完成内容：

- 长音频保守 refinement 策略正式接入
- 真实小宇宙长节目端到端验证通过
- `speaker_quality_gate` 通过
- 长音频保守模式真实命中
- 真实验收中暴露出的 Mac 路径与外部命令传参问题已修复

当前结论：

- `Phase 2` 已完成

对应文档：

- [Xiaoyuzhou Mac 全本地方案 Phase 2.md](/Users/michael_user/Documents/vibe%20coding/ObsidianSkillkit/docs/xiaoyuzhou-mac-local/Xiaoyuzhou%20Mac%20%E5%85%A8%E6%9C%AC%E5%9C%B0%E6%96%B9%E6%A1%88%20Phase%202.md)

### Phase 3

目标：

- 从“单条真实样本可用”推进到“多样本下可稳定使用”

已完成内容：

1. 完成 3 条真实小宇宙样本回归。
2. 已覆盖以下场景：
   - 双人对谈
   - 多人圆桌
   - 背景音乐更重
   - 节目时长明显更长
3. 已完成 runtime profile 对比：
   - `mac_metal_balanced`
   - `mac_metal_cooldown_guarded`
4. 当前已验证结果表明：
   - `asr` 成功
   - `diarization` 成功
   - `speaker_quality_gate` 通过
   - 未触发 `thermal_abort`
5. 已明确正式默认档位结论：
   - 默认首选：`mac_metal_balanced`
   - 保守备选：`mac_metal_cooldown_guarded`

当前状态：

- 已完成

当前结论：

- 在当前已验证样本范围内，Mac 本地小宇宙方案已经具备稳定可用性。
- `balanced` 可以作为正式默认档位。
- `cooldown_guarded` 适合作为更稳妥的备选档位。

对应文档：

- [Xiaoyuzhou Mac 全本地方案 Phase 3.md](/Users/michael_user/Documents/vibe%20coding/ObsidianSkillkit/docs/xiaoyuzhou-mac-local/Xiaoyuzhou%20Mac%20%E5%85%A8%E6%9C%AC%E5%9C%B0%E6%96%B9%E6%A1%88%20Phase%203.md)

### Phase 4

目标：

- 把已经跑通的小宇宙本地主链路，重新接回整个 Obsidian 结构化知识流程

计划范围：

1. 检查 `knowledge summary` 当前为什么仍是 `mock`。
2. 把小宇宙主流程成功结果稳定交给后续知识分析链路。
3. 明确：
   - 哪一步依赖真实模型
   - 哪一步依赖本地文件
   - 哪一步会写回 Obsidian 知识目录
4. 让“播客转录成功”进一步变成“知识卡片与结构化沉淀成功”。

完成标准：

1. 小宇宙主流程成功后，知识分析链路不再停留在 `mock`。
2. 产物能稳定写回目标 Obsidian 目录。
3. 整条链路的失败点与回退策略可解释。

当前状态：

- 进行中

当前已确认入口问题：

1. `run_clipper.ps1` 已经会自动调用 `obsidian-analyzer/scripts/run_analyzer.ps1`，所以主链路接线不是当前阻塞点。
2. 当前本机 `obsidian-analyzer/references/local-config.json` 已创建，但仍只是联调骨架配置。
3. 当前环境变量 `DASHSCOPE_API_KEY` 仍未配置。
4. 按现有 `run_analyzer.ps1` 逻辑，只要没有可用的真实 LLM 凭据，就会回退生成 `mock` 输出。

## 当前总状态

截至 `2026-05-08`：

- `Phase 1`：已完成
- `Phase 2`：已完成
- `Phase 3`：已完成
- `Phase 4`：进行中

## 现在最合理的下一步

如果继续推进，优先级建议如下：

1. 做 `Phase 4`
   - 给 analyzer 补齐真实 LLM 配置
   - 让 `knowledge summary` 退出 `mock`
2. 再做知识链路联调
   - 把稳定的小宇宙结果真正写回 Obsidian 知识目录

原因很简单：

- 现在主链路样本覆盖已经够用
- 当前真正剩下的主要缺口已经集中在知识分析链路的真实模型配置上

## 一句结论

截至现在：

- `Phase 1`、`Phase 2`、`Phase 3` 都已完成
- `Phase 4` 已经开始
- 当前第一阻塞点不是音频主链路，而是 analyzer 虽已具备本机配置骨架，但仍缺少真实 LLM 凭据，因此 `knowledge summary` 仍会回退为 `mock`
