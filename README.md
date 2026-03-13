# Obsidian Skillkit

## English

### Overview

This repository is a skillkit for Obsidian-related agent workflows.
It contains reusable skills, deployment documentation, and wrapper scripts needed to run those skills in a real local environment.

### Included Skills

- `obsidian/`: basic Obsidian vault operations through the official Obsidian CLI
- `obsidian-archiver/`: archive URL-based content from OpenClaw into Obsidian with the help of x-reader

### Repository Layout

- `obsidian/SKILL.md`: agent-facing instructions for the Obsidian skill
- `obsidian/README.md`: human-facing documentation for the Obsidian skill
- `obsidian-archiver/SKILL.md`: agent-facing orchestration instructions for the archiver skill
- `obsidian-archiver/README.md`: deployment and usage guide for the archiver skill
- `obsidian-archiver/agents/openai.yaml`: metadata for the archiver skill
- `obsidian-archiver/references/`: examples and rule references
- `obsidian-archiver/scripts/`: PowerShell entrypoints and compatibility wrappers

### Dependency Overview

This repository does not include every runtime dependency.
Different skills depend on different external tools.

For `obsidian/`:
- Obsidian CLI is expected on the target machine if your workflow uses the official CLI path.

For `obsidian-archiver/`:
- OpenClaw should already be running locally.
- At least one IM channel should already be connected to OpenClaw.
- Python should be available in `PATH`.
- PowerShell should be available on the target machine.
- x-reader must be installed separately by the deployer.
- An accessible Obsidian vault path is required.

Dependency boundary:
- This repository contains the skill logic and wrapper scripts.
- This repository does not vendor x-reader.
- This repository does not include your machine-specific `local-config.json`.
- This repository does not include your local Python environment, logs, temp files, or test vaults.

### Deployment Entry Points

A deployer should be able to learn from this repository:
- what each skill is for
- which external dependencies must be installed separately
- which files should be copied and edited locally
- which script is the local entrypoint
- where to find deployment instructions

For the full deployment guide of the archiver skill, see:
- [obsidian-archiver/README.md](/E:/Codex_project/obsidian-skillkit/obsidian-archiver/README.md)

### Commit Policy

Commit:
- skill definitions
- deployment documentation
- reference examples
- wrapper scripts that other deployers need

Do not commit:
- `.venv/`
- `.x-reader-site/`
- `.tmp/`
- `obsidian-archiver/.tmp/`
- `obsidian-archiver/.x-reader-runtime/`
- `obsidian-archiver/references/local-config.json`
- test vault outputs
- inbox files and logs

### Thanks

Thanks to the main projects this skillkit depends on:
- [Obsidian](https://obsidian.md/) for the vault model and tooling ecosystem
- [x-reader](https://github.com/runesleo/x-reader) for the extraction layer used by `obsidian-archiver`
- OpenClaw for the orchestration context this skillkit is designed for

## 中文

### 仓库说明

这是一个面向 Obsidian 相关 Agent 工作流的 skill 仓库。
仓库里包含可复用的 skills、部署文档，以及在本地环境运行这些 skills 所需的包装脚本。

### 当前包含的 Skill

- `obsidian/`：通过官方 Obsidian CLI 执行基础的 vault 操作
- `obsidian-archiver/`：借助 OpenClaw 和 x-reader，把基于 URL 的内容归档到 Obsidian 中

### 仓库结构

- `obsidian/SKILL.md`：Obsidian skill 的代理说明
- `obsidian/README.md`：Obsidian skill 的人工文档
- `obsidian-archiver/SKILL.md`：归档 skill 的代理编排说明
- `obsidian-archiver/README.md`：归档 skill 的部署与使用说明
- `obsidian-archiver/agents/openai.yaml`：归档 skill 的元数据
- `obsidian-archiver/references/`：样例配置和规则参考
- `obsidian-archiver/scripts/`：PowerShell 入口脚本和兼容包装器

### 依赖情况

这个仓库不包含所有运行时依赖。
不同 skill 依赖的外部工具也不同。

对于 `obsidian/`：
- 如果你的工作流走官方 CLI 路径，那么目标机器需要安装 Obsidian CLI。

对于 `obsidian-archiver/`：
- 目标机器上需要已经运行 OpenClaw。
- OpenClaw 需要已经连接至少一个 IM 渠道。
- `PATH` 中需要可用的 Python。
- 目标机器需要 PowerShell。
- x-reader 需要由部署者单独安装。
- 需要一个可访问的 Obsidian vault 路径。

依赖边界可以概括为：
- 仓库提供的是 skill 本身和接线脚本。
- 仓库不内置 x-reader。
- 仓库不包含你机器专用的 `local-config.json`。
- 仓库不包含你的本地 Python 环境、日志、临时文件和测试 vault。

### 部署入口

部署者应该能从这个仓库看懂：
- 每个 skill 是做什么的
- 哪些依赖需要自己安装
- 哪些文件需要复制后在本地修改
- 哪个脚本是真正的本地入口
- 详细部署说明在哪里看

归档 skill 的完整部署说明见：
- [obsidian-archiver/README.md](/E:/Codex_project/obsidian-skillkit/obsidian-archiver/README.md)

### 提交策略

应该提交：
- skill 定义文件
- 部署文档
- 参考样例
- 其他部署者也需要的包装脚本

不应该提交：
- `.venv/`
- `.x-reader-site/`
- `.tmp/`
- `obsidian-archiver/.tmp/`
- `obsidian-archiver/.x-reader-runtime/`
- `obsidian-archiver/references/local-config.json`
- 测试 vault 产物
- inbox 文件和日志

### 致谢

感谢这个 skillkit 依赖的主要项目：
- [Obsidian](https://obsidian.md/)，提供基于 vault 的工作流模型和生态
- [x-reader](https://github.com/runesleo/x-reader)，提供 `obsidian-archiver` 使用的提取能力
- OpenClaw，提供这套 skillkit 面向的编排运行环境
