# 小宇宙 Mac 全本地方案 Phase 2

## 阶段目标

本阶段目标不是再证明“本地链路能跑”，而是把它推进到“真实节目可用”。

重点包括：

1. 用真实长节目样本验证 Mac 全本地链路。
2. 提升长音频下的 speaker 区分稳定性。
3. 控制 diarization refinement 的长时热负载。
4. 为后续真实节目验收建立明确的质量门槛与诊断信息。

## 为什么需要 Phase 2

`Phase 1` 已经完成了这些事情：

- Mac 本地 ASR 已真实跑通
- Mac 本地 diarization 已真实跑通
- CPU 正式禁用
- 热保护可触发并可报告

但 `Phase 1` 仍然保留了两个现实风险：

1. 最小样本跑通，不代表真实长节目 speaker 区分质量足够稳定。
2. diarization refinement 在长音频下可能带来更高热负载与更长运行时。

所以 `Phase 2` 的重点是从“技术通路成立”进入“真实可用性验证与保守优化”。

## 本阶段范围

### 1. 长音频 refinement 保守策略

目标：

- 对长音频自动切换到更保守的 refinement 参数
- 降低批处理热负载
- 控制候选 turn 数量，避免无上限放大计算量

建议策略：

- 保留现有 refinement 默认策略
- 新增长音频保守模式：
  - `long_audio_mode`
  - `long_audio_threshold_seconds`
  - `long_audio_turn_min_seconds`
  - `long_audio_window_seconds`
  - `long_audio_batch_size`
  - `long_audio_max_turns`

默认思路：

- 短音频保持现有精度优先策略
- 长音频自动切到保守参数
- `mac_metal_cooldown_guarded` 档位比 `mac_metal_balanced` 更早进入保守模式

### 2. 真实节目样本验收

目标：

- 用真实小宇宙节目完成一轮端到端验证
- 观察 speaker 分离质量、运行时长、热保护触发情况

建议至少记录：

- 节目时长
- 是否命中长音频保守模式
- ASR 总耗时
- diarization 总耗时
- refinement 是否启用
- 最终 speaker 数量
- speaker quality gate 是否通过
- 是否触发 thermal abort

### 3. 质量门槛与诊断

目标：

- 让“结果是否可信”变得更可判断
- 让“为什么不可信”变得更可定位

重点观察：

- `distribution_summary`
- `speaker_quality_gate`
- `intro_diagnostics`
- `sparse_speaker_turn_rescue`
- `refinement.runtime_settings`

### 4. 后续分流决策

如果真实节目验证后结果较好：

- 继续维持全本地正式路线

如果真实节目验证后结果一般但可接受：

- 优先继续调 refinement 与长音频保守参数

如果真实节目验证后质量或热负载都明显不可接受：

- 再讨论备选方案
- 包括：
  - 更保守的本地配置
  - 更换本地 diarization 路线
  - 最后才讨论 hosted 方案

## 当前实施顺序

1. 先把长音频保守 refinement 策略正式接入代码与配置。
2. 再准备一份真实节目验证用的本地配置。
3. 然后做第一轮真实节目长样本验收。
4. 最后根据结果决定是否继续调参或进入下一阶段。

## 本阶段完成标准

1. 长音频自动保守策略已正式接入代码与配置。
2. 至少完成 1 条真实节目样本的端到端本地验证。
3. 能明确判断 speaker 质量是否达到可接受水平。
4. 能明确判断长音频下热负载是否可接受。
5. 若结果不理想，能给出下一步调参或替代路线，而不是停留在模糊描述。

## 实际验收结果

### 真实样本

- 平台：小宇宙
- 单集链接：`https://www.xiaoyuzhoufm.com/episode/69a79fd2de29766da95733a1`
- 单集标题：`2026第一期`
- 播客名称：`Being and Becoming`
- 本地音频时长：`2697.247` 秒，约 `44 分 57 秒`

### 端到端结果

- ASR：成功
  - provider：`mlx-whisper`
  - model：`mlx-community/whisper-large-v3-turbo`
  - device：`mps`
  - transcript segments：`1010`
  - transcript chars：`19197`
- speaker diarization：成功
  - provider：`pyannote`
  - model：`pyannote/speaker-diarization-community-1`
  - speaker segments：`227`
  - detected speakers：`2`
- thermal guard：未触发中断
  - `thermal_abort = false`

### speaker 质量诊断

- `speaker_quality_gate.status = passed`
- `speaker_quality_gate.status_detail = speaker_context_allowed`
- `distribution_summary.status = balanced`
- `intro_diagnostics.status = not_applicable`
- `sparse_speaker_turn_rescue.status = not_applicable`

本次真实样本的 speaker 分布结果为：

- `老王`
  - `107` 段
  - `366.144` 秒
  - 占比 `13.81%`
- `小庄`
  - `108` 段
  - `2285.166` 秒
  - 占比 `86.19%`

这说明当前长音频样本下，speaker 标签没有出现明显塌缩，也没有被质量门槛判定为不可信。

### 长音频保守模式命中情况

`refinement.runtime_settings` 实际结果为：

- `audio_duration_seconds = 2697.247`
- `long_audio_mode = conservative`
- `long_audio_threshold_seconds = 2400`
- `long_audio_applied = true`
- `turn_min_seconds = 1.8`
- `window_seconds = 2.8`
- `batch_size = 8`
- `max_turns = 180`

这说明 `phase2` 中设计的长音频自动降载策略已经在真实样本中实际命中，而不是只停留在配置层。

### 本轮额外修复

在真实样本验收过程中，额外暴露并修复了两处 Mac 兼容性问题：

1. 修复了 `Get-VaultRelativePath` 的跨平台 URI 构造问题。
   - 原问题会导致 macOS 下本地绝对路径被当成相对 URI，进而在播客链路里触发 `MakeRelativeUri` 错误。
2. 修复了 `Start-Process` 外部命令参数传递问题。
   - 原问题会导致带空格的脚本路径在 macOS 下被拆断，进而使本地 ASR / diarization 无法正常启动。

这两处修复都属于 `phase2` 的真实价值，因为它们只会在 Mac 本地真实节目验收时暴露出来。

## 当前结论

按本阶段定义的完成标准，`phase2` 现在可以标记为完成。

已满足的标准包括：

- 长音频自动保守策略已正式接入代码与配置
- 已完成 1 条真实小宇宙长节目样本的端到端本地验证
- 已能明确判断 speaker 质量达到当前可接受水平
- 已能明确判断长音频下本轮热负载可接受，且没有触发温控中断
- 当真实样本暴露出 Mac 兼容性阻塞时，已经修复到可继续正式运行

仍需单独记录的剩余观察项：

- 还应继续增加更多不同节目类型样本，观察多嘉宾、串场更复杂、背景音乐更重时的 speaker 稳定性
- 当前知识速览步骤仍是 `mock` 输出，这不阻塞本次 podcast 本地主流程验收，但不应误记为知识分析链路已完成
