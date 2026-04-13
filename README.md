# Obsidian Skillkit

## Document Status

- Last Updated: `2026-04-13`

## 中文说明

### 这是一个什么项目

`Obsidian Skillkit` 是一套围绕 Obsidian 搭建的短视频与网页知识归档工具链。

它的目标不是只“保存一个链接”，而是把来自抖音、小红书等平台的分享内容，尽量转成：

- 可长期保存的剪藏笔记
- 可复用的结构化 sidecar 数据
- 可落盘的本地视频附件
- 可继续进入分析流程的知识资产

当前日常主入口是：

- `飞书 -> OpenClaw -> skills`

可选远程入口是：

- `iPhone Shortcut -> ios-shortcuts-gateway -> skills`

### 适合谁

这个项目主要面向使用者：

- 想把抖音、小红书、网页内容稳定收进 Obsidian
- 希望通过飞书直接发“剪藏”“拆解”指令
- 希望视频、评论、互动数据尽量一起保存

### 当前已经验证的能力

截至 `2026-04-08`，当前仓库已经验证这些能力：

- `obsidian-clipper/`
  - 可处理抖音、小红书分享文本或链接
  - 产出 `Clippings/` 下的结构化剪藏笔记
  - 产出 `Attachments/ShortVideos/...` 下的媒体与 sidecar
- `obsidian-analyzer/`
  - 可读取已有剪藏笔记或 `capture.json`
  - 产出 `爆款拆解/` 下的结构化分析笔记
- 小红书当前主路径
  - 已切到“内建 extractor 优先”
  - 视频下载主路径是 extractor 解析出的 canonical media
  - `XHS-Downloader` 只作为 fallback backend 保留
- 小红书当前已修复的问题
  - `xhslink.com/o/<id>` 短链提取
  - 独立于抖音的 auth 文件
  - `website-login/error` / `300012` 拦截识别
  - OpenClaw 错误把“小红书剪藏”分流到 `web_fetch` 的入口规则
  - 本地视频在笔记中的直接嵌入

### 典型工作流

#### 1. 只做剪藏

用户在飞书中发送：

```text
剪藏：<抖音或小红书分享文本/链接>
```

系统执行：

1. OpenClaw 识别为剪藏任务
2. 调用 `obsidian-clipper`
3. 在 Obsidian 中写入 `Clippings/` 笔记
4. 尝试落盘本地视频、封面图、评论 JSON、元数据 JSON

#### 2. 剪藏后继续拆解

用户在飞书中发送：

```text
拆解视频：<抖音或小红书分享文本/链接>
```

系统执行：

1. 先调用 `obsidian-clipper`
2. 再把返回的 `note_path` 或 `sidecar_path` 交给 `obsidian-analyzer`
3. 在 `爆款拆解/` 中写入分析笔记

### 项目结构

- `obsidian-clipper/`
  - 第一阶段，负责剪藏、结构化捕获、媒体落盘
- `obsidian-analyzer/`
  - 第二阶段，负责分析和知识提炼
- `ios-shortcuts-gateway/`
  - 可选的远程 HTTP 入口，给 iPhone Shortcut 用
- `obsidian/`
  - 通过官方 Obsidian CLI 做 vault 操作
- `obsidian-archiver/`
  - 旧的一步式网页归档路径，当前主要用于兼容与迁移
- `tools/`
  - 本地辅助工具，包括 `XHS-Downloader` 的启动脚本

### 你作为使用者最需要知道的事

#### 飞书是当前主入口

如果你日常在用飞书发内容给 OpenClaw，当前推荐只记住这两种表达：

```text
剪藏：<分享文本或链接>
```

```text
拆解视频：<分享文本或链接>
```

#### 小红书当前下载策略

当前小红书视频下载顺序是：

1. 内建 extractor 提供的 resolved media
2. `XHS-Downloader` fallback backend
3. `yt-dlp` fallback

这意味着：

- 不开 `XHS-Downloader` 时，笔记通常仍能生成
- 但小红书视频的本地落盘成功率会更依赖主路径和兜底路径

#### 当前最常见的运维问题

如果飞书里的行为和这份仓库代码不一致，先检查是不是运行了另一份 OpenClaw runtime copy：

- 开发仓库：
  - `E:\Codex_project\obsidian-skillkit\obsidian-clipper`
- OpenClaw 运行副本：
  - `C:\Users\<user>\.openclaw\workspace\skills\obsidian-clipper`

很多“我明明改了代码但飞书没变”的问题，本质上都是 runtime copy 没同步。

### 当前仍需注意的边界

- 小红书 DOM 结构仍可能变化
- 互动数据并非每条都能 100% 拿全
- `XHS-Downloader` 仍是第三方依赖
- OpenClaw 会话上下文有时会影响技能选择，所以 skill 规则和 runtime copy 同步都很关键

### 推荐阅读顺序

- [obsidian-clipper/README.md](./obsidian-clipper/README.md)
- [obsidian-analyzer/README.md](./obsidian-analyzer/README.md)
- [ios-shortcuts-gateway/README.md](./ios-shortcuts-gateway/README.md)
- [openclaw-short-video-integration.md](./openclaw-short-video-integration.md)

---

## English Guide

### What this project is

`Obsidian Skillkit` is a local workflow toolkit for turning short-video shares and web content into reusable assets inside an Obsidian vault.

The goal is not just to save a URL. The goal is to convert shared content from Douyin, Xiaohongshu, and similar sources into:

- stable clipping notes
- reusable structured sidecars
- locally landed media files
- analyzer-ready knowledge records

The main production entry today is:

- `Feishu -> OpenClaw -> skills`

The optional remote/mobile entry is:

- `iPhone Shortcut -> ios-shortcuts-gateway -> skills`

### Important podcast first-run rule

Podcast clipping now includes a first-run runtime profile step for ASR / speaker processing.

This means:

- the first podcast run on a new machine must be started from a local entry that can show a device-selection prompt
- recommended first-run entries are:
  - `Feishu -> OpenClaw -> skills`
  - direct local terminal execution such as `obsidian-clipper/scripts/run_clipper.ps1`
- after that first local run writes the selected device profile into `references/local-config.json`, iPhone Shortcut can use the same machine normally

iOS Shortcut is not the right place for the first podcast setup because it cannot reliably present the local machine's CPU / GPU choice flow.

### Who this is for

This repository is written mainly for end users:

- people who want to archive Douyin, Xiaohongshu, or web content into Obsidian
- people who want to trigger clipping and analysis from Feishu
- people who want local media, comments, and engagement metadata whenever possible

### What is currently verified

As of `2026-04-08`, the repository has verified support for:

- `obsidian-clipper/`
  - captures Douyin and Xiaohongshu share text or URLs
  - writes structured clipping notes into `Clippings/`
  - writes media and sidecars under `Attachments/ShortVideos/...`
- `obsidian-analyzer/`
  - reads a clipping note or `capture.json`
  - writes structured analysis notes into `爆款拆解/`
- Xiaohongshu current primary path
  - built-in extractor first
  - canonical media resolution before fallback tools
  - `XHS-Downloader` retained only as a fallback backend
- Xiaohongshu fixes already landed
  - short-link extraction for `xhslink.com/o/<id>`
  - separate auth files from Douyin
  - blocked-access detection for `website-login/error` and `300012`
  - OpenClaw routing hardening so clipping does not fall through to generic `web_fetch`
  - direct embedded local video in the clipping note

### Typical workflows

#### 1. Clip only

The user sends:

```text
剪藏：<Douyin or Xiaohongshu share text / URL>
```

The system then:

1. routes the request into `obsidian-clipper`
2. creates a note in `Clippings/`
3. attempts to land local video, cover image, comments JSON, and metadata JSON

#### 2. Clip and then analyze

The user sends:

```text
拆解视频：<Douyin or Xiaohongshu share text / URL>
```

The system then:

1. runs `obsidian-clipper`
2. passes the returned `note_path` or `sidecar_path` into `obsidian-analyzer`
3. writes an analysis note into `爆款拆解/`

### Repository layout

- `obsidian-clipper/`
  - stage 1, clipping, structured capture, media landing
- `obsidian-analyzer/`
  - stage 2, analysis and knowledge extraction
- `ios-shortcuts-gateway/`
  - optional HTTP entry layer for iPhone Shortcut
- `obsidian/`
  - direct Obsidian CLI operations
- `obsidian-archiver/`
  - legacy one-step webpage archival path, now mostly for compatibility
- `tools/`
  - helper tools, including `XHS-Downloader` launch scripts

### What end users should know

#### Podcast first setup must be local

If this is the first time a machine is handling podcast content, do not start from iPhone Shortcut first.

Use one of these local entries first:

- `Feishu -> OpenClaw -> skills`
- local terminal / PowerShell entry into `obsidian-clipper`

Why:

- podcast ASR and diarization now support first-run device detection
- the machine may need to choose a runtime profile such as `GPU ASR + CPU diarization` or `CPU compatibility`
- that choice is written back into `references/local-config.json`

After the first local setup is completed, the same machine can accept podcast tasks from iPhone Shortcut normally.

#### Feishu is the main entry

In daily use, the main commands to remember are:

```text
剪藏：<share text or URL>
```

```text
拆解视频：<share text or URL>
```

#### Current Xiaohongshu download order

The current Xiaohongshu download order is:

1. built-in extractor resolved media
2. `XHS-Downloader` fallback backend
3. `yt-dlp` fallback

In practice this means:

- clipping notes can still be created even if the fallback backend is not running
- local Xiaohongshu video landing is more reliable when the fallback backend is available

#### Runtime copy matters

If Feishu behavior does not match this repository, check whether the OpenClaw runtime copy was synced.

The two most important locations are:

- development repo:
  - `E:\Codex_project\obsidian-skillkit\obsidian-clipper`
- OpenClaw runtime copy:
  - `C:\Users\<user>\.openclaw\workspace\skills\obsidian-clipper`

### Current boundaries

- Xiaohongshu DOM can still change
- not every engagement field will be available on every capture
- `XHS-Downloader` is still a third-party dependency
- OpenClaw session context can affect skill selection, so skill rules and runtime sync matter

### Recommended reading order

- [obsidian-clipper/README.md](./obsidian-clipper/README.md)
- [obsidian-analyzer/README.md](./obsidian-analyzer/README.md)
- [ios-shortcuts-gateway/README.md](./ios-shortcuts-gateway/README.md)
- [openclaw-short-video-integration.md](./openclaw-short-video-integration.md)
