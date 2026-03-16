# Obsidian Skillkit

## English

### Overview

This repository is a skillkit for OpenClaw workflows built around Obsidian.
It currently follows a two-stage architecture for structured knowledge capture:
- `obsidian-clipper`: capture raw source records into `Clippings/`
- `obsidian-analyzer`: turn clipped records into formal knowledge
- `obsidian/`: direct Obsidian vault operations through the official CLI

A legacy skill is still present for compatibility:
- `obsidian-archiver/`: the older x-reader based one-step archive flow

### Recommended Architecture

Preferred current workflow:
1. OpenClaw receives a link
2. `obsidian-clipper` stores a raw record into Obsidian `Clippings/`
3. for short social video, the clipper stage owns raw capture, media download, and attachment-sidecar landing
4. `obsidian-analyzer` reads that stored record
5. the analyzer writes structured output into `Insights/`, `Breakdowns/`, or another formal knowledge folder

This replaces the older one-step archiver-first model for new development.

### Included Skills

- `obsidian/`: basic Obsidian vault operations through the official Obsidian CLI
- `obsidian-clipper/`: first-stage clipping skill for raw-content capture
- `obsidian-analyzer/`: second-stage analysis skill for structured knowledge generation
- `obsidian-archiver/`: legacy archival skill kept for compatibility and reference

### Repository Layout

- `obsidian/SKILL.md`
- `obsidian-clipper/SKILL.md`
- `obsidian-analyzer/SKILL.md`
- `obsidian-archiver/SKILL.md`
- `*/README.md`
- `*/agents/`
- `*/references/`
- `obsidian-archiver/scripts/`

### Dependency Overview

For `obsidian/`:
- Obsidian desktop with the official CLI enabled

For `obsidian-clipper/`:
- OpenClaw
- PowerShell
- Python
- an accessible Obsidian vault
- route-specific tools such as Playwright, `yt-dlp`, or article extraction tooling depending on deployment

For `obsidian-analyzer/`:
- OpenClaw
- PowerShell or another local execution path
- an accessible Obsidian vault
- a configured LLM provider or local model path

For `obsidian-archiver/` legacy flow:
- x-reader installed separately

### Thanks

Thanks to the main projects this skillkit depends on:
- [Obsidian](https://obsidian.md/)
- OpenClaw
- [Playwright](https://playwright.dev/)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [x-reader](https://github.com/runesleo/x-reader) for the legacy archiver path

## 中文

### 仓库说明

这是一个围绕 Obsidian 搭建、面向 OpenClaw 工作流的 skill 仓库。
当前采用两阶段内容处理架构：
- `obsidian-clipper`：把原始内容快速写入 `Clippings/`
- `obsidian-analyzer`：把剪藏内容转成正式知识资产
- `obsidian/`：通过官方 CLI 直接操作 Obsidian

仓库中仍保留一套旧方案用于兼容与参考：
- `obsidian-archiver/`：基于 x-reader 的旧一体式归档链路

### 推荐架构

当前推荐流程：
1. OpenClaw 接收链接
2. `obsidian-clipper` 先把原始记录写入 Obsidian 的 `Clippings/`
3. 对短视频内容，clipper 阶段负责原始 capture，后续再承接视频下载与附件落盘
4. `obsidian-analyzer` 读取已剪藏内容
5. analyzer 将结果写入 `Insights/`、`Breakdowns/` 或其他正式知识目录

这套流程作为后续新开发的主路径。

### 当前包含的 Skill

- `obsidian/`：基础 Obsidian vault 操作
- `obsidian-clipper/`：第一阶段原始内容剪藏
- `obsidian-analyzer/`：第二阶段结构化知识分析
- `obsidian-archiver/`：保留作兼容与参考的 legacy x-reader 方案

### 仓库结构

- `obsidian/SKILL.md`
- `obsidian-clipper/SKILL.md`
- `obsidian-analyzer/SKILL.md`
- `obsidian-archiver/SKILL.md`
- 各 skill 的 `README.md`
- 各 skill 的 `agents/`
- 各 skill 的 `references/`
- `obsidian-archiver/scripts/`

### 依赖情况

对于 `obsidian/`：
- 需要启用官方 Obsidian CLI

对于 `obsidian-clipper/`：
- OpenClaw
- PowerShell
- Python
- 可访问的 Obsidian vault
- 根据路由配置选择 Playwright、`yt-dlp` 或正文提取工具

对于 `obsidian-analyzer/`：
- OpenClaw
- PowerShell 或其他本地执行路径
- 可访问的 Obsidian vault
- 已配置好的大模型提供方或本地模型能力

对于 legacy 的 `obsidian-archiver/`：
- 仍需单独安装 x-reader

### 致谢

感谢这个 skillkit 依赖的主要项目：
- [Obsidian](https://obsidian.md/)
- OpenClaw
- [Playwright](https://playwright.dev/)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [x-reader](https://github.com/runesleo/x-reader) for the legacy archiver path