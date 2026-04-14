# 小宇宙线程恢复笔记

对应线程：
- 日期：`2026-04-09 13:13`
- 主题：`小宇宙模块技术方案 / ASR fallback`
- 会话 ID：`019d70a9-5640-74d0-94d5-6eea12fdabce`
- 原始文件：`C:\Users\VBTvisitor\.codex\sessions\2026\04\09\rollout-2026-04-09T13-13-59-019d70a9-5640-74d0-94d5-6eea12fdabce.jsonl`

## 这条线程当时在聊什么

用户当时问的是：
- 小宇宙模块目前的技术方案是什么
- `ASR fallback` 是什么
- 当前 ASR 到底是“CPU 本地跑”还是“已经支持 GPU”

这条线程是建立在前一条 `2026-04-08` 小宇宙方案线程之上的，等于是在确认：
- 现在代码到底落到哪一步了
- Phase 3 的 `ASR fallback` 具体意味着什么
- 当前实现是不是本地模型、是不是支持 GPU

## 当时确认下来的技术方案

核心结论：
- 小宇宙不是单独新开一个工程，而是继续增强现有 `obsidian-clipper` 的 `podcast` 路由。
- 推荐链路是：小宇宙链接识别 -> 页面/RSS 元数据提取 -> 可下载音频 -> transcript 获取或补齐 -> 写入 Obsidian note 和 metadata。
- 当时已经完成 `Phase 1` 和 `Phase 2`，下一步主线就是 `Phase 3: transcript 缺失时的 ASR fallback`。

当时已经落地的能力：
- `podcast` 路由可处理小宇宙链接。
- 存在 `enclosure_url` 时会下载音频到 `Attachments/Podcasts/{platform}/{capture_id}/`。
- 会把 `audio_path` 和 `audio_download_status` 写回结果对象、`capture.json`、`metadata.json`。
- 笔记中会嵌入本地音频，例如 `![[...episode.mp3]]`。

相关文件：
- [run_clipper.ps1](/E:/Codex_project/obsidian-skillkit/obsidian-clipper/scripts/run_clipper.ps1)
- [render_clipping_note.py](/E:/Codex_project/obsidian-skillkit/obsidian-clipper/scripts/render_clipping_note.py)
- [local-config.example.json](/E:/Codex_project/obsidian-skillkit/obsidian-clipper/references/local-config.example.json)
- [platform-routing.md](/E:/Codex_project/obsidian-skillkit/obsidian-clipper/references/platform-routing.md)

## ASR fallback 当时的定义

`ASR fallback` 的意思是：
- 如果上游没有直接提供 transcript，或者 transcript 不完整，就拿已经下载到本地的音频走一遍自动语音识别，补出 transcript。
- 它是兜底链路，不是主链路的第一选择。

当时确认的实现方式是：
- 默认 provider 是 `faster-whisper`
- `run_clipper.ps1` 会调用 [podcast_asr_fallback.py](/E:/Codex_project/obsidian-skillkit/obsidian-clipper/scripts/podcast_asr_fallback.py)
- 这个脚本直接使用 `WhisperModel` 做本地推理
- 也就是说，当时不是调用云端 ASR API，而是依赖本机 Python 环境里的本地模型

## CPU 还是 GPU

这条线程最后把这个问题讲清楚了：
- 当前实现“支持 GPU”，但默认不是写死 GPU
- 当前实现也“能落到 CPU”，但默认不是写死 CPU
- 更准确地说，是“本地跑，设备自动选择”

当时确认的语义是：
- 默认配置是 `device = "auto"`、`compute_type = "auto"`
- 如果本机环境具备可用 GPU 推理依赖，通常会走 GPU
- 如果没有可用 GPU，通常会退回 CPU
- 仓库本身没有额外做“强制 GPU”或“强制 CPU”的锁定逻辑

一句话总结：
- 当时的 `ASR fallback` 是“本地音频 + 本地 faster-whisper 模型 + 自动设备选择”的方案

## 当时还没做完的部分

线程里明确还没完成的是：
- 真实小宇宙线上页面回归验证
- transcript 缺失场景下的 ASR fallback 完整接入
- 下载失败后的更细粒度重试策略
- 大音频的分段处理
- 音频指纹去重或附件缓存复用
- transcript 的进一步结构化输出，供 analyzer 使用

## 线程最后停在哪里

最后停在两个层面：
- 方案层面：已经认定下一步应该进入 `Phase 3`
- 实现层面：重点是把 transcript 缺失时的 `ASR fallback` 做扎实

当时最后一轮问答结论是：
- 不是“只跑 CPU”
- 也不是“必须 GPU”
- 而是“支持 GPU，但默认自动选择设备”

## 如果现在继续做

可以直接继承这些前提：
- 小宇宙归属 `podcast` 路由
- 方案以增强 `obsidian-clipper` 为主，不另起炉灶
- `Phase 1` 和 `Phase 2` 已完成
- 最合理的主线任务仍然是 `Phase 3: ASR fallback`
