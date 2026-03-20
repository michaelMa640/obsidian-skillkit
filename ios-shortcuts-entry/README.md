# iOS Shortcuts Entry

## Purpose

`ios-shortcuts-entry` is an entry-layer module for the existing `OpenClaw + Obsidian SkillKit` workflow.

It does not download media or analyze content by itself.

Its job is to define how iPhone shortcuts should hand off short-video tasks into the existing system through:

- iOS Shortcuts
- Feishu bot
- OpenClaw
- `obsidian-clipper`
- `obsidian-analyzer`

This keeps the mobile entry flow separate from the core skill implementations.

## Current recommended path

Phase 1 and Phase 2 standardize the following path:

`iOS Shortcuts -> Feishu bot -> OpenClaw -> Clipper / Analyzer`

This path is preferred over:

- direct local HTTP entry
- direct cloud webhook entry

for the current MVP stage.

## Module scope

This module defines:

- the mobile-entry boundary
- the Feishu message contract
- the OpenClaw intent-routing contract
- expected result fields returned back to the user

This module does not define:

- video downloading internals
- analyzer prompt internals
- LLM provider internals

## User intents

Only two mobile intents are first-class:

### 1. Clip only

Examples:

- `剪藏视频：<share text>`
- `帮我剪藏这个视频`

Expected routing:

- `obsidian-clipper` only

### 2. Analyze video

Examples:

- `拆解视频：<share text>`
- `帮我拆解这个视频`

Expected routing:

- `obsidian-clipper` first
- `obsidian-analyzer` second

The workflow is not complete after clipping alone.

## References

- [Feishu Message Contract](references/feishu-message-contract.md)
- [OpenClaw Routing Contract](references/openclaw-routing-contract.md)
