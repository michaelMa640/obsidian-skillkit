# 小宇宙剪藏技术方案续聊上下文

对应历史线程：
- 日期：`2026-04-08`
- 主题：`调研小宇宙剪藏技术方案`
- 会话 ID：`019d6af4-2055-7093-b3b4-3d2415cca885`
- 原始会话文件：`C:\Users\VBTvisitor\.codex\sessions\2026\04\08\rollout-2026-04-08T10-37-57-019d6af4-2055-7093-b3b4-3d2415cca885.jsonl`

## 这条线程当时要解决什么

目标是为 `openclaw + Obsidian` 工作流做一个“小宇宙播客剪藏模块”。

用户当时的要求是：
- 先阅读旧报告：`E:\iCloudDrive\iCloudDrive\iCloud~md~obsidian\可乐鸡翅包饭\项目\openclaw结合Obsidian的结构化知识库流程\小宇宙播客批量转写与知识化的可行技术方案与架构深度研究报告.md`
- 再结合网络和开源项目，判断有没有靠谱的技术路线
- 忽略合规，只看技术可行性
- 最后把具体方案写回 Obsidian，并新建以日期开头的文件夹

## 当时得出的核心结论

不是从零做一个全新的“小宇宙专用插件”，而是直接增强现有 `obsidian-clipper` 里的 `podcast` 路由。

推荐路线是：
1. 用现有 `podcast` 路由接收小宇宙链接。
2. 先做页面元数据 + show notes + RSS + transcript/audio hint 的稳定提取。
3. 再把结果统一落到：
   - Obsidian note
   - `capture.json`
   - `metadata.json`
   - 可选 `episode.mp3`
   - 可选 transcript 文件
4. 后续再交给 analyzer 做知识化。

换句话说，这条线程最后选择的是“增量改造现有链路”，不是“新开一个独立工程”。

## 参考过的开源方向

线程里明确参考过这些方向：
- `obsidianmd/obsidian-clipper`
- `LGiki/cosmos-enhanced`
- `ultrazg/xyz`
- `ultrazg/horizon`
- `ephes/podcast-transcript`
- `djmango/obsidian-transcription`
- `lstrzepek/obsidian-yt-transcript`

结论是：
- 没找到一个已经完整做完“小宇宙链接 -> 音频/转录 -> Obsidian 笔记”的现成项目。
- 但“入口抓取、音频定位、转录、Obsidian 写入”这四段都能找到成熟参考，因此拼装成本可控。

## 当时已经落地到仓库里的改动

这条线程最后实际做到了 `Phase 2`。

已改文件：
- [run_clipper.ps1](E:/Codex_project/obsidian-skillkit/obsidian-clipper/scripts/run_clipper.ps1)
- [render_clipping_note.py](E:/Codex_project/obsidian-skillkit/obsidian-clipper/scripts/render_clipping_note.py)
- [local-config.example.json](E:/Codex_project/obsidian-skillkit/obsidian-clipper/references/local-config.example.json)
- [platform-routing.md](E:/Codex_project/obsidian-skillkit/obsidian-clipper/references/platform-routing.md)

已经实现的能力：
- `podcast` 路由会在存在 `enclosure_url` 时下载音频到 `Attachments/Podcasts/{platform}/{capture_id}/`
- 把 `audio_path` 和 `audio_download_status` 写回最终结果对象
- 同步写入 `capture.json` 和 `metadata.json`
- 在 note 里增加本地音频嵌入 `![[...episode.mp3]]`
- 配置里增加：
  - `routes.podcast.download_audio`
  - `routes.podcast.download_timeout_sec`

## 当时验证到了什么程度

验证通过了，但范围是“本地 mock 端到端”，不是线上真实小宇宙页面回归。

验证内容：
- PowerShell 语法校验
- `python -m py_compile`
- 本地 mock fixture 端到端回归

线程里记录的关键验证结果：
- `final_run_status = SUCCESS`
- `route = podcast`
- `platform = xiaoyuzhou`
- `capture_level = enhanced`
- `source_strategy = page+rss`
- `transcript_status = available`
- `audio_download_status = success`
- `audio_path = Attachments/Podcasts/xiaoyuzhou/xiaoyuzhou_8a1ee68f8f9b38a5/episode.mp3`

## 当时生成的文档

线程里已经把方案和执行详情写进 Obsidian：
- `E:\iCloudDrive\iCloudDrive\iCloud~md~obsidian\可乐鸡翅包饭\项目\openclaw结合Obsidian的结构化知识库流程\260408-小宇宙剪藏模块方案\260408-小宇宙剪藏模块技术方案.md`
- `E:\iCloudDrive\iCloudDrive\iCloud~md~obsidian\可乐鸡翅包饭\项目\openclaw结合Obsidian的结构化知识库流程\260408-小宇宙剪藏模块方案\260408-小宇宙剪藏模块Phase1执行详情.md`
- `E:\iCloudDrive\iCloudDrive\iCloud~md~obsidian\可乐鸡翅包饭\项目\openclaw结合Obsidian的结构化知识库流程\260408-小宇宙剪藏模块方案\260408-小宇宙剪藏模块Phase2执行详情.md`

## 当时还没做完的部分

线程结束时，明确还没做完的是：
- 真实线上小宇宙页面回归验证
- transcript 缺失时的 ASR fallback
- 下载失败后的更细粒度重试策略
- 大音频的分段处理
- 音频指纹去重或附件缓存复用
- transcript 的进一步结构化，供 analyzer 下游使用

## 这条线程最后停在什么地方

最后结论是：
- `Phase 2` 已完成
- 下一步建议直接进入 `Phase 3`
- `Phase 3` 的核心任务是：`transcript` 缺失时接入 ASR fallback

建议优先顺序：
1. 先做 transcript 缺失时的 ASR fallback
2. 再细化音频下载状态和重试策略
3. 再补真实小宇宙页面回归
4. 最后再做 transcript 的结构化输出，接到 analyzer

## 现在如果继续聊，可以直接继承这些前提

你可以默认我们已经接受下面这些前提：
- 小宇宙链路归属 `podcast` 路由
- 当前方案以 `obsidian-clipper` 增强为主，不另起炉灶
- `Phase 1` 和 `Phase 2` 已完成
- 当前最合理的主线任务是 `Phase 3: ASR fallback`
- 当前代码里已经有 podcast 音频下载和 note 音频嵌入能力

## 可以直接接着下的指令

如果要继续做，这几种说法都可以直接接上：
- “继续做小宇宙 Phase 3，给 transcript 缺失场景加 ASR fallback。”
- “先别做 ASR，先给小宇宙链路补真实页面回归测试。”
- “把小宇宙 Phase 3 拆成具体开发任务。”
- “先检查当前仓库里小宇宙相关代码和上次线程是否一致。”
