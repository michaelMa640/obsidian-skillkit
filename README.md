# Obsidian Skill

This skill teaches the agent how to work with Obsidian vaults through the official Obsidian CLI on desktop.

## What this skill is for

Use this skill when the agent needs to work with an Obsidian vault from the terminal, including:

- Searching notes
- Reading note contents
- Creating notes
- Appending or prepending content
- Moving or renaming notes
- Deleting notes
- Inspecting links, backlinks, tags, and tasks

This skill is designed around the official `obsidian` command, not the older third-party `obsidian-cli` tool.

## What it can do

Typical supported operations:

- `obsidian search query="keyword"`
- `obsidian read path="Folder/Note.md"`
- `obsidian create path="Inbox/New note.md" content="# Title"`
- `obsidian append path="Daily/2026-03-12.md" content="- Item"`
- `obsidian prepend path="Daily/2026-03-12.md" content="# Daily note"`
- `obsidian move path="old/path/note.md" to="new/path/note.md"`
- `obsidian delete path="Folder/Old note.md"`
- `obsidian links path="Folder/Note.md"`
- `obsidian backlinks path="Folder/Note.md"`
- `obsidian tags query="#tag"`
- `obsidian tasks path="Projects/Plan.md"`

## Deployment and dependencies

Required:

- Obsidian desktop installed
- Official Obsidian CLI enabled in `Settings -> General -> Command line interface`
- `obsidian` available on `PATH`

Windows-specific requirements:

- `Obsidian.com` must exist in the same directory as `Obsidian.exe`
- `obsidian` should resolve to `Obsidian.com`, not `Obsidian.exe`
- After enabling CLI, restart the terminal before testing again

Recommended validation commands:

```powershell
Get-Command obsidian
where.exe obsidian
obsidian search query="welcome"
```

Expected Windows result:

- `Get-Command obsidian` points to `Obsidian.com`
- `where.exe obsidian` lists `Obsidian.com` before `Obsidian.exe`

## How the skill is intended to be used

The normal workflow is:

1. Change directory into the target vault.
2. Run `obsidian` commands relative to the vault root.
3. Prefer CLI operations for search, read, and vault-aware refactors.
4. Prefer direct file edits for simple markdown content changes when appropriate.

Example:

```powershell
cd "C:\path\to\vault"
obsidian search query="welcome"
obsidian read path="welcome.md"
obsidian create path="Inbox/Test.md" content="# Test"
```

## Current verified status on this machine

Validated during setup:

- The official CLI is installed and resolvable as `obsidian`
- On Windows, `obsidian` now resolves to `D:\Obsidian\Obsidian.com`
- Running `obsidian search query="欢迎"` from inside a vault returned matching notes

Observed behavior:

- `obsidian help` may print startup logs instead of a help screen in `cmd.exe` or PowerShell
- Some hosted or sandboxed terminals may fail to capture CLI stdout even when the command works in a normal local terminal

Because of that, if a command works in a normal Windows terminal but appears silent in an agent terminal, treat it as an output-capture issue rather than a CLI failure.

## Known limitations

- This skill depends on the official desktop CLI behavior
- Output behavior may vary by terminal environment
- The agent may still need the user to run commands in a normal local terminal if stdout is not captured in the current session
- This skill does not replace careful file-level review for large or risky content edits

## Files in this skill

- `SKILL.md`: agent-facing operating instructions
- `README.md`: human-facing explanation, deployment notes, and usage guide

## Reference

- Official docs: https://help.obsidian.md/cli

---

# Obsidian Skill 中文说明

这个 skill 的作用，是让代理通过 Obsidian 官方 CLI 在桌面端操作 Obsidian vault。

## 这个 skill 是做什么的

当代理需要在终端里操作 Obsidian 笔记库时，就应该使用这个 skill，例如：

- 搜索笔记
- 读取笔记内容
- 创建新笔记
- 在笔记开头或结尾追加内容
- 移动或重命名笔记
- 删除笔记
- 查看链接、反链、标签和任务

这个 skill 基于官方 `obsidian` 命令，不再使用旧的第三方 `obsidian-cli`。

## 它能做到什么

常见支持的操作包括：

- `obsidian search query="关键词"`
- `obsidian read path="Folder/Note.md"`
- `obsidian create path="Inbox/New note.md" content="# 标题"`
- `obsidian append path="Daily/2026-03-12.md" content="- 条目"`
- `obsidian prepend path="Daily/2026-03-12.md" content="# 日记标题"`
- `obsidian move path="old/path/note.md" to="new/path/note.md"`
- `obsidian delete path="Folder/Old note.md"`
- `obsidian links path="Folder/Note.md"`
- `obsidian backlinks path="Folder/Note.md"`
- `obsidian tags query="#tag"`
- `obsidian tasks path="Projects/Plan.md"`

## 部署依赖

基础要求：

- 已安装 Obsidian 桌面版
- 已在 `Settings -> General -> Command line interface` 中启用官方 CLI
- `obsidian` 命令已经加入 `PATH`

Windows 额外要求：

- `Obsidian.com` 必须和 `Obsidian.exe` 在同一目录
- `obsidian` 应该解析到 `Obsidian.com`，而不是 `Obsidian.exe`
- 刚启用 CLI 后，通常需要重开终端再测试

推荐验证命令：

```powershell
Get-Command obsidian
where.exe obsidian
obsidian search query="welcome"
```

Windows 下理想结果：

- `Get-Command obsidian` 指向 `Obsidian.com`
- `where.exe obsidian` 中 `Obsidian.com` 排在 `Obsidian.exe` 前面

## 这个 skill 平时怎么使用

推荐工作流：

1. 先切换到目标 vault 目录。
2. 再执行相对于 vault 根目录的 `obsidian` 命令。
3. 搜索、读取、重构类操作优先用 CLI。
4. 简单 Markdown 内容修改可以直接改文件。

示例：

```powershell
cd "C:\path\to\vault"
obsidian search query="welcome"
obsidian read path="welcome.md"
obsidian create path="Inbox/Test.md" content="# Test"
```

## 这台机器上的当前验证情况

已经验证：

- 官方 CLI 已安装并且可以通过 `obsidian` 调用
- 在 Windows 上，`obsidian` 现在解析到 `D:\Obsidian\Obsidian.com`
- 在 vault 目录内执行 `obsidian search query="欢迎"` 可以正常返回匹配笔记

已观察到的现象：

- `obsidian help` 在 `cmd.exe` 或 PowerShell 里可能只输出启动日志，不一定显示帮助正文
- 某些托管终端或沙箱终端即使命令实际成功，也可能抓不到 CLI 的 stdout

因此，如果命令在普通 Windows 终端里能跑通，但在代理终端里看起来没有输出，应优先判断为输出捕获问题，而不是 CLI 失效。

## 已知限制

- 这个 skill 依赖官方桌面版 CLI 的实际行为
- 不同终端环境下，输出表现可能不一致
- 如果当前代理会话抓不到 stdout，仍可能需要让用户在本机普通终端执行命令
- 对于大范围或高风险内容修改，仍需要结合文件级检查，不应完全依赖 CLI

## 这个 skill 目录里的文件

- `SKILL.md`：给代理看的操作说明
- `README.md`：给人看的说明文档、部署依赖和使用指南

## 参考资料

- 官方文档：https://help.obsidian.md/cli
