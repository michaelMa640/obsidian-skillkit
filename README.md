# Obsidian Skillkit

## English

### Overview

This repository is a skillkit for OpenClaw workflows built around Obsidian.
It now follows a two-stage architecture for structured knowledge capture:
- `obsidian-clipper`: fast capture into `Clippings/`
- `obsidian-analyzer`: turn clippings into formal knowledge
- `obsidian/`: direct Obsidian vault operations through the official CLI

A legacy skill is still present:
- `obsidian-archiver/`: the earlier x-reader based one-step archive flow

### Recommended Architecture

Preferred current workflow:
1. OpenClaw receives a link
2. `obsidian-clipper` stores it into Obsidian `Clippings/`
3. later, `obsidian-analyzer` reads that clipping
4. the analyzer writes structured output into `Insights/`, `Breakdowns/`, or another formal knowledge folder

This replaces the older one-step archiver-first model for new development.

### Included Skills

- `obsidian/`: basic Obsidian vault operations through the official Obsidian CLI
- `obsidian-clipper/`: first-stage clipping skill for raw-content capture
- `obsidian-analyzer/`: second-stage analysis skill for structured knowledge generation
- `obsidian-archiver/`: legacy x-reader based archival skill kept for compatibility and reference

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

### Commit Policy

Commit:
- skill definitions
- deployment documentation
- example configs
- shared wrappers that other deployers need

Do not commit:
- `.venv/`
- `.x-reader-site/`
- `.tmp/`
- machine-specific local configs
- test vault outputs
- runtime logs and inbox files

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
目前仓库已经转向新的“两阶段结构化知识流”架构：
- `obsidian-clipper`：快速剪藏到 `Clippings/`
- `obsidian-analyzer`：把剪藏内容转成正式知识
- `obsidian/`：通过官方 CLI 直接操作 Obsidian

仓库里仍然保留一套旧方案：
- `obsidian-archiver/`：基于 x-reader 的旧一体式归档链路

### 推荐架构

当前推荐的工作流是：
1. OpenClaw 接收到链接
2. `obsidian-clipper` 先把内容写入 `Clippings/`
3. 后续再由 `obsidian-analyzer` 读取剪藏内容
4. analyzer 把结果写入 `Insights/`、`Breakdowns/` 或其他正式知识目录

这套流程将作为后续新开发的主路线。

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
- 配置好的大模型提供方或本地模型能力

对于 legacy 的 `obsidian-archiver/`：
- 仍需要单独安装 x-reader

### 提交策略

应该提交：
- skill 定义文件
- 部署文档
- 示例配置
- 其他部署者也需要的包装层

不应该提交：
- `.venv/`
- `.x-reader-site/`
- `.tmp/`
- 机器专用本地配置
- 测试 vault 产物
- 运行日志和 inbox 文件

### 致谢

感谢这个 skillkit 依赖的主要项目：
- [Obsidian](https://obsidian.md/)
- OpenClaw
- [Playwright](https://playwright.dev/)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [x-reader](https://github.com/runesleo/x-reader)，用于 legacy archiver 路线