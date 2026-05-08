# 小宇宙 Mac 全本地方案 Phase 1

## 结论摘要

本阶段目标是让小宇宙解析链路在 Mac Apple Silicon 设备上优先走全本地高性能路径运行，不允许静默降级到 CPU，并在运行期间加入热保护，避免长时间高温导致设备体验和稳定性下降。

本阶段策略如下：

- 优先目标：全本地运行
- 设备策略：Mac 端默认禁止 CPU 作为正式执行路径
- 失败策略：不满足设备条件时 fail closed，不自动降级到 CPU
- 温度策略：加入运行期热保护，满足阈值时主动中断并报告
- hosted pyannote：作为后备方案，不纳入本阶段主路径

## 关于 hosted pyannote

hosted pyannote 指的是使用 pyannote 官方托管服务运行 speaker diarization，而不是在本机本地执行。

对当前需求的判断：

- hosted pyannote 通常需要付费
- 它适合作为本地方案不稳定时的 Plan B
- 当前阶段不采用 hosted pyannote 作为默认方案
- 当前阶段仍以全本地优先

## 当前项目现状

当前仓库里的 podcast / 小宇宙链路本质上是 Windows CUDA 方案，主要特点如下：

- ASR 默认是 `faster-whisper + large-v3 + cuda + float16`
- diarization 默认是 `pyannote/speaker-diarization-3.1 + cuda + refinement`
- `run_clipper.ps1` 会在不是 `cuda` 时直接终止
- runtime profile 目前只有 GPU CUDA 相关档位
- 当前实现的失败策略是 GPU 不可用则中断，而不是做跨平台适配

这说明目前不是模型思路错了，而是工程实现尚未扩展到 Apple Silicon 路线。

## 本阶段目标

本阶段只解决以下问题：

1. 让 Mac Apple Silicon 可以尝试全本地执行小宇宙 ASR 与 speaker diarization。
2. 明确禁止 CPU 成为正式执行路径。
3. 加入热保护机制，在高温持续时主动中断任务。
4. 让系统在中断时返回清晰报告，说明正在执行什么、为何中断。
5. 保持现有 sidecar / transcript / speaker_map / capture metadata 的产物结构尽量不变。

本阶段不解决的问题：

- 不做 hosted diarization 默认切换
- 不先追求所有机型统一最优性能
- 不先追求跨 Windows / Mac 的完全统一 runtime 实现细节
- 不先做 UI 层面的温度可视化

## 推荐技术路线

### 1. ASR 路线

推荐优先级：

1. `MLX Whisper`
2. `whisper.cpp`
3. 保留现有 `faster-whisper` 仅用于 Windows CUDA 路径

推荐理由：

- `MLX Whisper` 更贴近 Apple Silicon 原生高性能路径
- `whisper.cpp` 在 Apple Silicon / Metal 上成熟度高，部署稳健
- 现有 `faster-whisper` 方案在本项目内已经与 CUDA 设计强耦合，不适合作为 Mac 正式路径直接平移

本阶段建议：

- Mac 端先实现 `mlx-whisper` provider
- Windows 端继续保留 `faster-whisper`
- 如果 `mlx-whisper` 落地过程中遇到兼容性问题，再补一个 `whisper.cpp` provider 作为 Mac 备选

### 2. Speaker diarization 路线

推荐优先级：

1. 本地 pyannote 新路线
2. 若本地效果或热负载不可接受，再讨论 hosted pyannote

模型建议：

- 从 `pyannote/speaker-diarization-3.1` 升级到当前更合适的社区模型线
- 保留当前 speaker refinement 思路，但增加条件触发控制，避免长音频上热负载过重

设备策略建议：

- Mac 端优先尝试 `mps`
- 不允许静默降级到 CPU
- 若本机环境不支持可接受的本地高性能路径，则直接返回不可执行状态

## 设备策略设计

### 核心原则

- Windows：保持 CPU 禁止
- Mac：同样禁止 CPU 作为正式执行路径
- 任何平台都不允许偷偷降级到 CPU
- 只要运行环境不满足正式条件，就中止并报告

### 建议 runtime profile

新增以下 profile：

- `windows_cuda_balanced`
- `windows_cuda_memory_saver`
- `mac_metal_balanced`
- `mac_metal_cooldown_guarded`

其中：

- `mac_metal_balanced`：优先性能
- `mac_metal_cooldown_guarded`：在更保守的并发 / batch / refinement 策略下运行，优先温控与稳定性

### 运行设备抽象

建议把当前 `device` 从仅有的 `cuda` 语义，扩展为运行能力抽象：

- `cuda`
- `mps`
- `metal`
- `coreml`
- `unsupported`

同时区分两个概念：

- provider 支持什么
- 当前机器允许什么

## 温度保护方案

## 需求解释

用户要求：

- 当设备温度高于 90 摄氏度并持续 30 秒时，中断进程
- 中断后必须报告：
  - 正在进行什么
  - 因为什么原因中断

## 工程现实

在 macOS 上，绝对温度读取不一定像 Windows 某些硬件工具那样稳定统一。官方更稳定的系统级信号通常是 thermal state，而不是保证可直接获得的单一 CPU 温度数值。

因此本阶段建议做成双层保护：

### 第一层：绝对温度保护

若运行环境可稳定读取温度，则执行：

- 每 2 到 5 秒采样一次
- 若温度 > 90 摄氏度，记录超阈值开始时间
- 若连续超阈值 >= 30 秒，则标记热保护触发
- 立即终止当前子进程
- 返回结构化错误结果

### 第二层：系统热状态保护

若无法稳定拿到绝对温度，则读取 macOS 系统 thermal state：

- nominal
- fair
- serious
- critical

建议规则：

- thermal state 达到 `serious` 并持续一定时长时进入预警
- thermal state 达到 `critical` 时直接中止
- 若绝对温度与热状态都可用，则以更严格者为准

### 中断后返回内容

中断报告至少包含：

- `status = thermal_abort`
- `stage = asr | diarization | refinement | probe`
- `provider`
- `model`
- `runtime_profile`
- `device_backend`
- `reason`
- `temperature_celsius` 或 `thermal_state`
- `threshold`
- `duration_seconds`
- `action = process_terminated`

示例：

```json
{
  "success": false,
  "status": "thermal_abort",
  "stage": "diarization",
  "provider": "pyannote",
  "model": "pyannote speaker diarization local",
  "runtime_profile": "mac_metal_balanced",
  "device_backend": "mps",
  "reason": "temperature_above_threshold_for_30s",
  "temperature_celsius": 92.4,
  "threshold": 90,
  "duration_seconds": 31,
  "action": "process_terminated",
  "error": "Thermal protection aborted diarization after temperature stayed above 90C for 30 seconds."
}
```

## 程序改造范围

### 一、配置层

需要新增或调整以下配置：

- `routes.podcast.runtime_profile`
- `routes.podcast.execution_policy`
- `routes.podcast.asr.provider`
- `routes.podcast.asr.device_policy`
- `routes.podcast.diarization.provider`
- `routes.podcast.diarization.device_policy`
- `routes.podcast.thermal_guard.enabled`
- `routes.podcast.thermal_guard.temperature_celsius`
- `routes.podcast.thermal_guard.duration_seconds`
- `routes.podcast.thermal_guard.poll_interval_seconds`
- `routes.podcast.thermal_guard.fallback_to_thermal_state`

建议默认值：

```json
{
  "routes": {
    "podcast": {
      "runtime_profile": "mac_metal_balanced",
      "execution_policy": "fail_closed_no_cpu",
      "thermal_guard": {
        "enabled": true,
        "temperature_celsius": 90,
        "duration_seconds": 30,
        "poll_interval_seconds": 3,
        "fallback_to_thermal_state": true
      }
    }
  }
}
```

### 二、run_clipper 调度层

需要调整：

- runtime probe 从 `CUDA-only` 改成跨平台能力探测
- runtime profile 选项增加 Mac 路线
- CPU-only 状态下直接 fail closed
- 调用 ASR / diarization 子进程时附带 thermal guard 上下文
- 中断结果能回写 capture metadata 与最终任务结果

### 三、ASR runner

建议新增：

- `mlx-whisper` provider
- 热保护监控包装器
- 运行中状态标记，例如 `stage = asr`

建议保留：

- 现有 transcript / segments / normalization 输出结构

### 四、speaker diarization runner

建议调整：

- provider 继续保留 `pyannote`
- 放开对 `mps` 路径的适配
- refinement 增加条件约束
- 在运行阶段显式标记 `stage = diarization` 或 `stage = refinement`
- 纳入热保护监控

### 五、结果与日志

需要新增：

- 热保护触发日志
- capture metadata 中记录 thermal_abort 信息
- 任务回调或 CLI 输出中展示中断阶段与原因

## 实施阶段

### 1：设备策略与热保护框架

目标：

- 禁 CPU
- 支持 Mac runtime profile
- 增加 thermal guard 骨架
- 能在调度层中断任务并返回结构化错误

产出：

- 新配置字段
- 新 runtime probe 结构
- 新 thermal guard 结果格式

### 2：Mac 本地 ASR

目标：

- 接入 Mac 本地高性能 ASR provider
- 保持 transcript / segments 兼容
- 纳入 thermal guard

建议优先：

- `mlx-whisper`

### 3：Mac 本地 diarization

目标：

- 接入本地 pyannote Mac 路线
- 评估长音频热负载
- refinement 增加保守策略
- 纳入 thermal guard

### 4：验证与回归

验证点：

- GPU / Metal 路径可执行
- CPU 不会被静默启用
- 超温可触发中断
- 中断信息完整
- sidecar 产物结构不被破坏

## 风险与应对

### 风险 1：Mac 上绝对温度读取不稳定

应对：

- 优先做双层保护
- 绝对温度能读则按温度阈值执行
- 读不到则使用 thermal state 兜底

### 风险 2：本地 diarization 热负载过高

应对：

- 先限制 refinement 的触发条件
- 对超长音频采用保守批处理参数
- 必要时增加 `mac_metal_cooldown_guarded` 档位

### 风险 3：不同 provider 输出结构不一致

应对：

- 保持统一的 JSON 结果契约
- provider 只负责生成标准结构化产物

### 风险 4：Apple Silicon 本地链路存在依赖安装复杂度

应对：

- 把 provider 适配层与主流程隔离
- 允许逐步验证 ASR 与 diarization，而不是一次性切全链路

## 验收标准

本阶段完成的标准：

1. Mac 端存在正式 runtime profile，且默认不允许 CPU 正式执行。
2. 小宇宙链路在 Mac 上可尝试全本地运行。
3. 若环境不满足要求，会直接失败，而不是静默降级到 CPU。
4. 运行中出现高温持续超阈值时，系统能主动中止任务。
5. 中止后会报告当前阶段、模型、设备后端和中断原因。
6. 现有 transcript / speaker sidecar 结构保持兼容。

## 当前建议决策

建议立即执行的顺序：

1. 先做 `1`：禁 CPU + Mac runtime profile + thermal guard 框架
2. 再做 `2`：Mac 本地 ASR
3. 再做 `3`：Mac 本地 diarization
4. 最后做 `4`：整链路验证

## 文档保存说明

本文件当前已先保存到项目仓库中的阶段文档目录：

- `docs/xiaoyuzhou-mac-local-phase1/`

后续如果需要同步到正式 Obsidian vault `michael内容库` 的项目文件夹，需要补充该 vault 在当前 Mac 上的实际本地路径。
