# Obsidian Skillkit

This repository is a skillkit for Obsidian-related agent workflows.

## Included skills

- `obsidian/`: Basic Obsidian vault operations through the official Obsidian CLI

## Structure

- `obsidian/SKILL.md`: agent-facing instructions for the Obsidian skill
- `obsidian/README.md`: human-facing documentation for the Obsidian skill
- `obsidian/_meta.json`: package metadata for the Obsidian skill

## Purpose

The repository is structured to support multiple skills over time. Each skill should live in its own subfolder with its own `SKILL.md`, documentation, and metadata.

---

# Obsidian Skillkit 中文说明

这个仓库现在按 skillkit 方式组织，用来容纳多个和 Obsidian 相关的 skill。

## 当前包含的 skill

- `obsidian/`：通过官方 Obsidian CLI 执行基础的 Obsidian vault 操作

## 当前目录结构

- `obsidian/SKILL.md`：给代理使用的 Obsidian skill 说明
- `obsidian/README.md`：给人看的 Obsidian skill 文档
- `obsidian/_meta.json`：Obsidian skill 的元数据

## 结构约定

后续如果继续增加 skill，建议每个 skill 都放在独立子目录下，并各自维护 `SKILL.md`、`README.md` 和 `_meta.json`。
