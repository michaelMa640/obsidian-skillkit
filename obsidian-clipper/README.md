# Obsidian Clipper

## English

### Overview

Obsidian Clipper is the first-stage OpenClaw skill for fast content capture.
It saves a source into an Obsidian vault as a reusable raw-content note without forcing a long AI analysis chain.

This skill is designed for the new two-stage workflow:
- Stage 1: `obsidian-clipper`
- Stage 2: `obsidian-analyzer`

### What This Skill Does

- accepts a source URL from OpenClaw
- detects the source platform and content type
- routes the request to the appropriate capture path
- saves a clipping note into `Clippings/`
- preserves enough structure for later analysis
- emits stable capture metadata for downstream automation

### Current Architectural Contract

The Phase 3 contract is now explicit:
- `obsidian-clipper` owns raw source capture
- short social video capture is asset-first at the architecture level
- short social video download, attachment landing, and sidecar JSON writing belong to `obsidian-clipper`
- `obsidian-analyzer` should read stored records and stored media references instead of re-downloading social sources

### Current Runnable Version

The current implementation includes real entrypoints:
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`
- `scripts/capture_social_playwright.py`
- `scripts/download_social_media.ps1`

This version already supports:
- URL input
- platform detection
- route selection
- standardized clipping note generation
- direct write into an Obsidian vault in filesystem mode
- built-in article page fetch + main-text extraction
- built-in Playwright-driven social capture for Xiaohongshu / Douyin, with structured social payloads, downloader handoff, attachment landing, and graceful fallback clipping
- real `yt-dlp` integration for the `video_metadata` route, with fallback clipping when remote extraction fails
- built-in podcast page metadata capture, RSS hint extraction, transcript-link discovery, and show-notes-style text extraction for the `podcast` route

What is still incomplete in this version:
- advanced platform-specific selectors for more Xiaohongshu / Douyin layouts
- login-state reuse for restricted social content
- Feishu Bitable upsert is still outside the current runnable clipper path
- remote object storage sync for downloaded binaries is not wired yet
- richer article extraction heuristics

### Current Capture Strategy

- article pages: built-in page fetch + main-text extraction, with fallback clipping when the page cannot be reached
- Xiaohongshu / Douyin: Playwright page capture with platform-specific selectors, structured comments and engagement hints, candidate video references, `yt-dlp` first download, direct-candidate fallback download, local attachment landing, and graceful fallback when browser or downloader steps fail
- Bilibili / YouTube: `yt-dlp` metadata + subtitles first, and fallback to minimal clipping if remote extraction fails
- Xiaoyuzhou / podcasts: page metadata + RSS/transcript hint discovery + show-notes-style text extraction, with graceful fallback when the page cannot be reached

Default principles:
- clip first
- keep the stored record stable
- treat short social video as asset-first at the system boundary
- do not block note creation when a heavy step fails

### Storage Model

Phase 1 to Phase 3 now assume:
- Obsidian is the primary store for raw capture notes
- binary assets live in attachment folders or object storage
- Feishu Bitable is an index and workflow view, not the sole source of truth

Recommended local layout:
- `Clippings/`
- `Attachments/ShortVideos/{platform}/{capture_id}/`
- `Breakdowns/`

### Files In This Skill

- `SKILL.md`: agent-facing operating instructions
- `agents/openai.yaml`: UI metadata for the skill
- `references/local-config.example.json`: local machine config template
- `references/platform-routing.md`: routing reference for supported source types
- `references/capture-data-model.md`: capture contract for short social video records
- `references/capture-record.schema.json`: sidecar JSON schema for capture records
- `scripts/run_clipper.ps1`: main PowerShell entrypoint
- `scripts/detect_platform.ps1`: platform routing helper
- `scripts/capture_social_playwright.py`: Playwright-based social capture helper
- `scripts/download_social_media.ps1`: downloader + attachment landing helper for short social video

### Dependencies

Current runnable version needs:
- OpenClaw
- PowerShell
- an accessible Obsidian vault path
- Python
- Playwright
- `yt-dlp` available on `PATH` for the social and `video_metadata` routes
- `ffprobe` on `PATH` is recommended for local video metadata enrichment
- web access for article, social, and podcast routes

This repository does not vendor those external tools.

## 中文

### 概述

Obsidian Clipper 是这套两阶段工作流里的第一阶段 skill，负责把来源内容快速、稳定地剪藏进 Obsidian，而不是一开始就强制执行完整的 AI 深度分析链路。

当前推荐流程：
- 第一阶段：`obsidian-clipper`
- 第二阶段：`obsidian-analyzer`

### 这个 Skill 现在负责什么

- 接收 OpenClaw 传入的 URL
- 识别平台与内容类型
- 把请求路由到正确的抓取路径
- 在 Obsidian 中写入一篇 `Clippings/` 笔记
- 生成稳定的 capture 元数据，供后续分析和自动化使用

### 当前已经明确的职责边界

从 Phase 2 开始，系统职责已经明确：
- `obsidian-clipper` 负责原始事实入库
- 抖音 / 小红书这类短视频在架构上属于 asset-first，由 clipper 阶段负责后续下载与存储
- `obsidian-analyzer` 负责读取已入库的笔记、sidecar JSON 和媒体引用，不再承担重新抓取短视频来源的职责

目前短视频 downloader 还没有完全接进 clipper 主流程，但数据结构和职责边界已经先固定下来。

### 当前可运行版本

当前实现已包含这些真实入口：
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`
- `scripts/capture_social_playwright.py`
- `scripts/download_social_media.ps1`

当前版本已经支持：
- URL 输入
- 平台识别
- 路由选择
- 标准化 `Clippings` 笔记生成
- 文件系统模式下直接写入 Obsidian vault
- 内建文章抓取和正文提取
- 小红书 / 抖音的 Playwright 页面抓取，返回结构化的描述、评论、互动提示和候选视频引用
- `video_metadata` 路由对 `yt-dlp` 的接入
- `podcast` 路由对页面 metadata、RSS 和 transcript 线索的提取

### 当前抓取策略

- 文章：抓页面正文，失败时降级为最小 clipping
- 小红书 / 抖音：用 Playwright 抓可见内容、评论、互动提示和候选视频引用，失败时降级
- Bilibili / YouTube：优先抓 metadata 和字幕
- 播客：优先抓 metadata、show notes、RSS 和 transcript 线索

默认原则：
- 先完成稳定入库
- 保持记录结构稳定
- 短视频在系统边界上按 asset-first 对待
- 重步骤失败时不要阻塞 clipping note 写入

### 存储建议

当前方案默认：
- `Obsidian` 是原始事实的主存储
- 二进制媒体放附件目录或对象存储
- `飞书多维表格` 只做索引层和流程看板

推荐目录结构：
- `Clippings/`
- `Attachments/ShortVideos/{platform}/{capture_id}/`
- `Breakdowns/`