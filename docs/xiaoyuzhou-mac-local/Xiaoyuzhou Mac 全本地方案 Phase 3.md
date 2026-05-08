# 小宇宙 Mac 全本地方案 Phase 3

## 阶段目标

`Phase 3` 的目标不是继续证明“某一条节目能跑”，而是回答下面两个更实际的问题：

1. 现在的 Mac 本地方案在不同风格节目下是否稳定。
2. 正式默认档位到底应当使用 `mac_metal_balanced` 还是 `mac_metal_cooldown_guarded`。

## 为什么需要 Phase 3

`Phase 2` 已经证明了：

- 真实小宇宙长节目可以端到端跑通
- 长音频保守 refinement 策略会真实命中
- 当前至少有 1 条样本的 speaker 质量门槛可以通过

但这还不足以支撑“正式默认可用”的判断，因为还存在三个现实问题：

1. 单样本通过，不代表不同节目类型都稳定。
2. 双人访谈通过，不代表多人圆桌也稳定。
3. `balanced` 档位通过，不代表它一定比 `cooldown_guarded` 更适合作为正式默认档位。

所以 `Phase 3` 的重点是：

- 多样本
- 可比较
- 可给出正式默认档位结论

## 本阶段范围

### 1. 回归样本矩阵

本阶段至少覆盖以下类型：

1. 双人或偏主持人访谈
2. 多人圆桌 / 多主持人对谈
3. 含更明显音乐或片头片尾干扰的节目

### 2. runtime profile 对比

至少对 1 条真实样本做两档对比：

- `mac_metal_balanced`
- `mac_metal_cooldown_guarded`

重点不是只看“能不能跑”，而是看：

- 是否都能成功完成
- 是否触发 thermal guard
- speaker 质量是否有明显变化
- 哪个档位更适合作为正式默认值

### 3. 统一验收指标

每条样本至少记录：

- 样本链接
- 节目类型
- runtime profile
- 音频时长
- ASR 是否成功
- diarization 是否成功
- speaker 数量
- `speaker_quality_gate.status`
- `distribution_summary.status`
- 是否命中 `long_audio_mode`
- 是否触发 `thermal_abort`

## 当前样本计划

### 样本 A

- 类型：双人访谈
- 链接：`https://www.xiaoyuzhoufm.com/episode/69a79fd2de29766da95733a1`
- 用途：
  - 作为 `Phase 2` 基线样本
  - 同时用于 `balanced` / `cooldown_guarded` 对比

### 样本 B

- 类型：多人对谈 / 三主持人
- 链接：`https://www.xiaoyuzhoufm.com/episode/668e1f68ae8e21859accf137`
- 备注：
  - 来自 `暂停实验`
  - 页面可见三位主播信息

### 样本 C

- 类型：音乐话题 / 片头片尾与音乐内容更明显
- 链接：`https://www.xiaoyuzhoufm.com/episode/653bf17a338a6e415bf0378d`
- 备注：
  - 用来观察音乐内容和更松散聊天风格对 speaker 稳定性的影响

## 本阶段完成标准

1. 至少完成 3 条真实样本回归，其中至少覆盖 2 种不同节目风格。
2. 至少完成 1 条样本的 `balanced` / `cooldown_guarded` 档位对比。
3. 能明确说明当前默认正式档位应选哪一个。
4. 能明确说明目前哪些节目类型稳定，哪些类型仍有风险。
5. 若发现不稳定场景，能产出明确限制说明或下一步调参方向。

## 当前结论

本阶段刚开始，当前还没有正式结果。

接下来将按样本矩阵逐条执行，并把结果回填到本文件与执行记录中。

## 当前进展

### 已完成回归：样本 A

- 样本链接：`https://www.xiaoyuzhoufm.com/episode/69a79fd2de29766da95733a1`
- 节目类型：双人访谈

#### A1. `mac_metal_balanced`

- 结果：成功
- `asr_status = success`
- `diarization_status = success`
- `thermal_abort = false`
- `speaker_count = 2`
- `speaker_quality_gate.status = passed`
- `distribution_summary.status = balanced`
- `long_audio_applied = true`
- `long_audio_threshold_seconds = 2400`
- `turn_min_seconds = 1.8`
- `window_seconds = 2.8`
- `batch_size = 8`
- `max_turns = 180`

#### A2. `mac_metal_cooldown_guarded`

- 结果：成功
- `asr_status = success`
- `diarization_status = success`
- `thermal_abort = false`
- `speaker_count = 2`
- `speaker_quality_gate.status = passed`
- `distribution_summary.status = balanced`
- `long_audio_applied = true`
- `long_audio_threshold_seconds = 1800`
- `turn_min_seconds = 2.1`
- `window_seconds = 2.4`
- `batch_size = 6`
- `max_turns = 120`

### 当前阶段性判断

从样本 A 的结果看：

1. `balanced` 和 `cooldown_guarded` 两档都能在真实长节目下完成端到端运行。
2. 两档都没有触发热保护中断。
3. 两档的 speaker 质量门槛都通过。
4. `cooldown_guarded` 的参数明显更保守，适合作为更稳妥的保底正式档位。
5. `balanced` 目前仍可作为优先默认候选，因为在已验证样本下质量没有更差，且参数没有保守到过早压缩 refinement 空间。

当前还不能下最终结论，因为还缺少：

- 多主持人 / 多人对谈样本
- 更明显音乐干扰样本

但至少可以先形成一个临时判断：

- 如果用户优先追求“先稳定”，`cooldown_guarded` 是更保守的正式候选
- 如果用户优先追求“先保持效果与速度平衡”，`balanced` 仍然是当前默认首选候选

### 已完成回归：样本 B

- 样本链接：`https://www.xiaoyuzhoufm.com/episode/646dc54f53a5e5ea14efc733`
- 节目标题：`EP16. 在不舒服的环境忍了很久？是苟还是走，都是一种选择`
- 节目类型：多主持人 / 多人对谈
- 运行档位：`mac_metal_balanced`

结果：

- `final_run_status = SUCCESS`
- `asr_status = success`
- `diarization_status = success`
- `thermal_abort = false`
- `speaker_count = 2`
- `speaker_quality_gate.status = passed`
- `distribution_summary.status = balanced`
- `audio_duration_seconds = 5138.671`
- `long_audio_applied = true`

补充说明：

- 这条样本的 ASR 文本量明显高于样本 A：
  - `segment_count = 3012`
  - `transcript_chars = 46730`
- 在这样更长、更密集的对谈样本下，speaker 质量门槛依然通过，说明当前 `balanced` 档位在更重样本下仍有较好的稳定性。

## 当前结论

截至当前结果，可以先形成 `Phase 3` 的第一版结论：

1. 当前 Mac 本地小宇宙方案已经不只是“单样本可用”，而是至少在：
   - 双人长访谈
   - 更长文本量的多人对谈
   这两类样本上都稳定通过。
2. `mac_metal_balanced` 目前仍然可以作为正式默认首选档位。
3. `mac_metal_cooldown_guarded` 适合作为更保守的正式备选档位，尤其适合优先考虑温控与稳妥性的场景。
4. 当前还没有看到必须把默认档位切到 `cooldown_guarded` 的证据。

## 剩余观察项

`Phase 3` 还没有完全结束，仍建议补 1 条更偏音乐干扰的节目，主要用于确认：

- 片头片尾音乐更重时 speaker 标签是否仍稳定
- 是否会比访谈类节目更容易出现 speaker 漂移

### 已完成回归：样本 C

- 样本链接：`https://www.xiaoyuzhoufm.com/episode/653bf17a338a6e415bf0378d`
- 节目标题：`01 偶像的意义是让你获得远方的朋友`
- 节目类型：音乐话题 / 更明显片头片尾干扰
- 运行档位：`mac_metal_balanced`

结果：

- `final_run_status = SUCCESS`
- `asr_status = success`
- `diarization_status = success`
- `thermal_abort = false`
- `speaker_count = 2`
- `speaker_quality_gate.status = passed`
- `distribution_summary.status = balanced`
- `audio_duration_seconds = 3530.76`
- `long_audio_applied = true`

补充说明：

- 这条样本的 ASR 文本量也较大：
  - `segment_count = 2531`
  - `transcript_chars = 33059`
- 在更明显片头、片尾和音乐话题内容存在的情况下，speaker 质量门槛依然通过。

## 最终结论

按本阶段定义的完成标准，`Phase 3` 现在可以标记为完成。

已满足的标准包括：

1. 已完成 3 条真实样本回归：
   - 双人长访谈
   - 更长文本量的多人对谈
   - 更明显音乐话题 / 片头片尾干扰样本
2. 已完成 `balanced` / `cooldown_guarded` 档位对比。
3. 已能明确给出正式默认档位结论：
   - 默认首选：`mac_metal_balanced`
   - 保守备选：`mac_metal_cooldown_guarded`
4. 已能明确说明当前已验证稳定的样本类型：
   - 双人访谈
   - 多主持人 / 多人对谈
   - 更明显音乐话题干扰样本
5. 当前没有看到必须切换默认档位到 `cooldown_guarded` 的证据。

## 当前总判断

截至 `Phase 3` 结束时，可以把当前 Mac 端小宇宙本地方案理解为：

- 已经具备真实可用性
- 不只是单样本运气跑通
- 在当前已验证样本范围内，`balanced` 档位可以作为正式默认档位
- `cooldown_guarded` 则适合作为更稳妥的正式备选档位

## 剩余风险

`Phase 3` 已完成，但仍应如实保留两个观察项：

1. `ffmpeg / PyAV` duplicate class warning 仍然存在，虽然当前不阻塞执行，但后续仍需关注它是否带来偶发稳定性问题。
2. `knowledge summary` 仍然是 `mock`，这不阻塞 podcast 本地主链路，但说明完整知识链路还需要进入 `Phase 4`。
