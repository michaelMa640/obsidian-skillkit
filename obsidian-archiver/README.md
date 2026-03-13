# Obsidian Archiver (Legacy)

## English

### Status

This skill is retained as a legacy compatibility path.
It represents the earlier one-step workflow built around OpenClaw, x-reader, and Obsidian.

For new work, prefer:
- `obsidian-clipper/`
- `obsidian-analyzer/`

### What This Legacy Skill Does

- accepts a source input
- calls x-reader through a local wrapper
- turns the result into a Markdown note
- writes the note into an Obsidian vault

### Why It Is Legacy

The repository now prefers a two-stage architecture:
1. clip quickly into `Clippings/`
2. analyze later into structured knowledge

That model is a better fit for user wait time, reuse of captured content, and platform-specific routing.

### Kept Files

This legacy skill still includes:
- `SKILL.md`
- `agents/openai.yaml`
- `references/local-config.example.json`
- `scripts/run_archiver.ps1`
- `scripts/invoke_x_reader.ps1`

### Dependency Reminder

This path still depends on x-reader being installed separately.

## 中文

### 当前状态

这个 skill 现在作为 legacy 兼容方案保留。
它代表的是之前那套基于 OpenClaw、x-reader 和 Obsidian 的一体式归档链路。

对于新的开发，请优先使用：
- `obsidian-clipper/`
- `obsidian-analyzer/`

### 这个 legacy skill 做什么

- 接收输入源
- 通过本地包装层调用 x-reader
- 把结果转成 Markdown 笔记
- 写入 Obsidian vault

### 为什么它现在是 legacy

仓库已经转向新的两阶段架构：
1. 先快速剪藏进 `Clippings/`
2. 后续再分析成结构化知识

这套模型更适合真实等待时间、内容复用和平台分路处理。

### 当前保留文件

这个 legacy skill 仍保留：
- `SKILL.md`
- `agents/openai.yaml`
- `references/local-config.example.json`
- `scripts/run_archiver.ps1`
- `scripts/invoke_x_reader.ps1`

### 依赖提醒

这条 legacy 路线依然要求单独安装 x-reader。