# Obsidian Clipper

## English

### Overview

Obsidian Clipper is the first-stage OpenClaw skill for fast content capture.
It saves a link into an Obsidian vault as a reusable clipping note without forcing a long AI analysis chain.

This skill is designed for the new two-stage workflow:
- Stage 1: `obsidian-clipper`
- Stage 2: `obsidian-analyzer`

### What This Skill Does

- accepts a source URL from OpenClaw
- detects the source platform and content type
- routes the request to the appropriate capture path
- saves a clipping note into `Clippings/`
- preserves enough structure for later analysis

### Current Runnable Version

The current implementation includes real entrypoints:
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`
- `scripts/capture_social_playwright.py`

This version already supports:
- URL input
- platform detection
- route selection
- standardized clipping note generation
- direct write into an Obsidian vault in filesystem mode
- built-in article page fetch + main-text extraction
- built-in Playwright-driven social capture for Xiaohongshu / Douyin, with platform-specific selectors and fallback clipping
- real `yt-dlp` integration for the `video_metadata` route, with fallback clipping when remote extraction fails
- built-in podcast page metadata capture, RSS hint extraction, transcript-link discovery, and show-notes-style text extraction for the `podcast` route

What is still incomplete in this version:
- advanced platform-specific selectors for more Xiaohongshu / Douyin layouts
- login-state reuse for restricted social content
- richer article extraction heuristics

### Current Capture Strategy

- article pages: built-in page fetch + main-text extraction, with fallback clipping when the page cannot be reached
- Xiaohongshu / Douyin: Playwright page capture with platform-specific selectors, wait strategy, and graceful fallback when browser extraction fails
- Bilibili / YouTube: `yt-dlp` metadata + subtitles first, and fallback to minimal clipping if remote extraction fails
- Xiaoyuzhou / podcasts: page metadata + RSS/transcript hint discovery + show-notes-style text extraction, with graceful fallback when the page cannot be reached

Default principle:
- clip first
- keep it light
- avoid heavy media downloads unless explicitly needed

### Files In This Skill

- `SKILL.md`: agent-facing operating instructions
- `agents/openai.yaml`: UI metadata for the skill
- `references/local-config.example.json`: local machine config template
- `references/platform-routing.md`: routing reference for supported source types
- `scripts/run_clipper.ps1`: main PowerShell entrypoint
- `scripts/detect_platform.ps1`: platform routing helper
- `scripts/capture_social_playwright.py`: Playwright-based social capture helper

### Dependencies

Current runnable version needs:
- OpenClaw
- PowerShell
- an accessible Obsidian vault path
- Python
- Playwright
- `yt-dlp` available on `PATH` for the `video_metadata` route
- web access for article, social, and podcast routes

This repository does not vendor those external tools.

## 中文

### 概览

Obsidian Clipper 是新的两阶段工作流里的第一阶段 skill，负责快速剪藏内容。
它会把链接保存到 Obsidian 的 `Clippings/` 目录中，先完成稳定入库，而不是一开始就强制走完整的 AI 深度分析链路。

这套工作流分为两步：
- 第一阶段：`obsidian-clipper`
- 第二阶段：`obsidian-analyzer`

### 这个 Skill 会做什么

- 接收 OpenClaw 传入的 URL
- 识别平台和内容类型
- 把请求路由到合适的抓取路径
- 在 Obsidian 中生成一篇 `Clippings` 笔记
- 保留后续分析所需的结构化基础信息

### 当前可运行版本

当前已经有真实可运行的入口：
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`
- `scripts/capture_social_playwright.py`

这一版已经支持：
- URL 输入
- 平台识别
- 路由选择
- 标准化 `Clippings` 笔记生成
- 文件系统模式下直接写入 Obsidian vault
- 内建文章页面抓取和正文提取
- 小红书 / 抖音的 Playwright 抓取，带平台专用 selector、等待策略和失败降级
- `video_metadata` 路由真实调用 `yt-dlp`，失败时自动降级
- `podcast` 路由内建页面 metadata、RSS 线索、transcript 线索和 show notes 风格文本提取

这一版还不够完善的地方：
- 小红书 / 抖音还需要更多页面形态的专用 selector
- 受限社交内容还没有接入登录态复用
- 文章正文提取还可以继续加强

### 当前抓取策略

- 文章网页：内建页面抓取 + 主体正文提取，页面不可达时自动降级
- 小红书 / 抖音：Playwright 页面抓取，带平台专用 selector、等待策略和自动降级
- Bilibili / YouTube：优先走 `yt-dlp` 获取元数据和字幕，失败时降级为最小 clipping
- 小宇宙 / 播客：抓页面 metadata、RSS/transcript 线索和 show notes 风格文本，页面不可达时自动降级

默认原则是：
- 先剪藏
- 保持轻量
- 除非明确需要，否则不下载重型媒体文件

### 目录中的主要文件

- `SKILL.md`：给代理使用的说明
- `agents/openai.yaml`：skill 元数据
- `references/local-config.example.json`：本地配置模板
- `references/platform-routing.md`：平台路由说明
- `scripts/run_clipper.ps1`：主入口脚本
- `scripts/detect_platform.ps1`：平台识别辅助脚本
- `scripts/capture_social_playwright.py`：社交平台 Playwright 抓取辅助脚本

### 依赖

当前可运行版本需要：
- OpenClaw
- PowerShell
- 可访问的 Obsidian vault
- Python
- Playwright
- `PATH` 中可用的 `yt-dlp`，用于 `video_metadata` 路由
- 可访问目标网页的网络环境，用于文章、社交和播客抓取

仓库本身不内置这些外部工具。