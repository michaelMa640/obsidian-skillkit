# Obsidian Clipper

## English

### Overview

Obsidian Clipper is a first-stage OpenClaw skill for fast content capture.
It saves a link into an Obsidian vault as a reusable clipping note, without forcing a long AI analysis chain.

This skill is designed for the new two-stage workflow:
- Stage 1: `obsidian-clipper`
- Stage 2: `obsidian-analyzer`

### What This Skill Does

- accepts a source URL from OpenClaw
- detects the source platform and content type
- routes the request to the appropriate capture path
- saves a clipping note into `Clippings/`
- preserves enough structure for later analysis

### First Runnable Version

The current implementation includes a real PowerShell entrypoint:
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`

This first runnable version already supports:
- URL input
- platform detection
- route selection
- standardized clipping note generation
- direct write into an Obsidian vault in filesystem mode
- real `yt-dlp` integration for the `video_metadata` route, with fallback clipping when remote extraction fails

What is still placeholder-based in this version:
- article full-text extraction
- browser-based social capture
- transcript/show-notes acquisition for podcast routes

### Current Capture Strategy

- article pages: browser + article extraction planned, light placeholder capture for now
- Xiaohongshu / Douyin: browser page capture planned, light placeholder capture for now
- Bilibili / YouTube: `yt-dlp` metadata + subtitles first, and fallback to minimal clipping if remote extraction fails
- Xiaoyuzhou / podcasts: page metadata + show-notes-style text capture, with transcript reserved for a later step

Default principle:
- clip first
- keep it light
- avoid heavy media downloads unless explicitly needed

### Files In This Skill

- `SKILL.md`: agent-facing operating instructions
- `agents/openai.yaml`: UI metadata for the skill
- `references/local-config.example.json`: local machine config template
- `references/platform-routing.md`: routing reference for supported source types
- `scripts/run_clipper.ps1`: first runnable entrypoint
- `scripts/detect_platform.ps1`: platform routing helper

### Dependencies

Current first runnable version needs:
- OpenClaw
- PowerShell
- an accessible Obsidian vault path
- `yt-dlp` available on `PATH` for the `video_metadata` route
- web access for the built-in podcast metadata route

Future route-specific integrations may additionally need:
- Python
- Playwright
- article extraction tooling

This repository does not vendor those external tools.

## 中文

### 说明

Obsidian Clipper 是一个面向 OpenClaw 的第一阶段快速剪藏 skill。
它的目标是把链接尽快保存到 Obsidian 中，而不是在第一步就跑完整的 AI 深度分析。

这个 skill 服务于新的两阶段工作流：
- 第一阶段：`obsidian-clipper`
- 第二阶段：`obsidian-analyzer`

### 它做什么

- 接收 OpenClaw 提交的链接
- 识别平台和内容类型
- 路由到合适的抓取路径
- 把结果写进 `Clippings/`
- 保留后续分析所需的结构

### 当前第一版可运行实现

当前已经有真实可运行的 PowerShell 入口：
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`

这第一版已经支持：
- URL 输入
- 平台识别
- 路由选择
- 标准化 Clippings 笔记生成
- 文件系统模式下直接写入 Obsidian vault
- `video_metadata` 路由真实调用 `yt-dlp`

这一版还没有真正接好的部分：
- 文章正文完整抓取
- 社交平台浏览器抓取
- 播客 transcript 获取

### 当前抓取策略

- 文章网页：先预留正文路由，当前用轻量占位剪藏
- 小红书 / 抖音：先预留浏览器抓取路由，当前用轻量占位剪藏
- Bilibili / YouTube：已接入 `yt-dlp`，优先抓元数据和字幕
- 小宇宙 / 播客：已接入页面元数据和 show-notes 风格文本抓取，transcript 作为后续增强

默认原则：
- 先剪藏
- 保持轻量
- 除非显式需要，否则不做重型媒体下载

### 这个 skill 目录里的文件

- `SKILL.md`：给代理看的说明
- `agents/openai.yaml`：skill 的元数据
- `references/local-config.example.json`：本地配置模板
- `references/platform-routing.md`：平台路由参考
- `scripts/run_clipper.ps1`：第一版可运行入口
- `scripts/detect_platform.ps1`：平台识别辅助脚本

### 依赖

当前这版最小可运行实现需要：
- OpenClaw
- PowerShell
- 可访问的 Obsidian vault
- `PATH` 中可用的 `yt-dlp`，用于 `video_metadata` 路由
- 可访问小宇宙页面的网络环境，用于播客 metadata 路由

后续接入真实路由时，可能还需要：
- Python
- Playwright
- 正文提取工具