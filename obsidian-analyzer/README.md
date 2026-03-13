# Obsidian Analyzer

## English

### Overview

Obsidian Analyzer is the second-stage OpenClaw skill in the new workflow.
It reads an existing clipping note from Obsidian and turns it into formal knowledge.

### What This Skill Does

- reads a clipping note from `Clippings/`
- chooses `learn` or `analyze`
- prepares structured model input
- writes a finished knowledge note into the vault

### Supported Modes

- `learn`: articles, educational videos, podcasts, Xiaoyuzhou, experience-sharing content
- `analyze`: Xiaohongshu and Douyin style short content only

### Not In Scope

- direct web capture
- long-video viral breakdown
- podcast viral breakdown

### Files In This Skill

- `SKILL.md`: agent-facing instructions
- `agents/openai.yaml`: UI metadata
- `references/local-config.example.json`: local config template
- `references/prompts/`: prompt placeholders for analysis modes

### Thanks

Thanks to the projects this skill is expected to integrate with:
- [Obsidian](https://obsidian.md/)
- OpenClaw
- your configured LLM provider

## 中文

### 说明

Obsidian Analyzer 是这套新工作流里的第二阶段 skill。
它读取已经存在于 Obsidian 中的剪藏内容，并把它转化成正式知识结果。

### 它做什么

- 读取 `Clippings/` 中的剪藏笔记
- 选择 `learn` 或 `analyze`
- 组织模型输入
- 把结果写回正式知识目录

### 支持模式

- `learn`：文章、知识视频、播客、小宇宙、经验分享内容
- `analyze`：只面向小红书、抖音等短内容

### 不在范围内

- 直接网页抓取
- 长视频爆款拆解
- 播客爆款拆解

### 这个 skill 目录里的文件

- `SKILL.md`：给代理看的说明
- `agents/openai.yaml`：skill 元数据
- `references/local-config.example.json`：本地配置模板
- `references/prompts/`：分析 prompt 占位文件

### 致谢

感谢这个 skill 预期会集成的项目：
- [Obsidian](https://obsidian.md/)
- OpenClaw
- 你配置的大模型提供方