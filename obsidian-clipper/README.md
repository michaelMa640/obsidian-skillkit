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

### Current Capture Strategy

- article pages: browser + article extraction
- Xiaohongshu / Douyin: browser page capture
- Bilibili / YouTube: metadata + subtitles first
- Xiaoyuzhou / podcasts: transcript + show notes first

Default principle:
- clip first
- keep it light
- avoid heavy media downloads unless explicitly needed

### Files In This Skill

- `SKILL.md`: agent-facing operating instructions
- `agents/openai.yaml`: UI metadata for the skill
- `references/local-config.example.json`: local machine config template
- `references/platform-routing.md`: routing reference for supported source types

### Dependencies

Depending on the route your deployment chooses, the machine may need:
- OpenClaw
- PowerShell
- Python
- an accessible Obsidian vault path
- browser automation tooling such as Playwright
- metadata/subtitle tooling such as `yt-dlp`
- article extraction tooling

This repository does not vendor those external tools.

### Deployment Model

1. Deploy this skill into the OpenClaw skill environment.
2. Copy `references/local-config.example.json` to `local-config.json` locally.
3. Fill in your vault path and route-specific commands.
4. Test clipping a URL into `Clippings/`.
5. Keep `obsidian-analyzer` available for the second stage.

### Thanks

Thanks to the projects this skill is expected to integrate with:
- [Obsidian](https://obsidian.md/)
- OpenClaw
- [Playwright](https://playwright.dev/)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)

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

### 当前抓取策略

- 文章网页：浏览器 + 正文提取
- 小红书 / 抖音：浏览器页面抓取
- Bilibili / YouTube：元数据 + 字幕优先
- 小宇宙 / 播客：transcript + show notes 优先

默认原则：
- 先剪藏
- 保持轻量
- 除非显式需要，否则不做重型媒体下载

### 这个 skill 目录里的文件

- `SKILL.md`：给代理看的说明
- `agents/openai.yaml`：skill 的元数据
- `references/local-config.example.json`：本地配置模板
- `references/platform-routing.md`：平台路由参考

### 依赖

根据不同路由，目标机器可能需要：
- OpenClaw
- PowerShell
- Python
- 可访问的 Obsidian vault
- 浏览器自动化工具，例如 Playwright
- 元数据/字幕工具，例如 `yt-dlp`
- 正文提取工具

仓库本身不内置这些外部依赖。

### 部署方式

1. 把这个 skill 部署到 OpenClaw 环境。
2. 在本地复制 `references/local-config.example.json` 为 `local-config.json`。
3. 配置 vault 路径和各路由命令。
4. 先测试一条 URL 能否写入 `Clippings/`。
5. 再搭配 `obsidian-analyzer` 使用第二阶段分析。

### 致谢

感谢这个 skill 预期会集成的项目：
- [Obsidian](https://obsidian.md/)
- OpenClaw
- [Playwright](https://playwright.dev/)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)