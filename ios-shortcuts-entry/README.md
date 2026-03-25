# iOS Shortcuts Entry

## Purpose

`ios-shortcuts-entry` is the older Feishu-forwarding entry design for the short-video workflow.

It does not download media or analyze content by itself.

Its job is to define how iPhone shortcuts can hand off tasks into the existing system through:

- iOS Shortcuts
- Feishu bot
- OpenClaw
- `obsidian-clipper`
- `obsidian-analyzer`

## Current status

This module is now a reference design, not the primary recommended mobile route.

Current recommended mobile route:

`iPhone Shortcut -> Tailscale -> ios-shortcuts-gateway -> Clipper / Analyzer`

This module remains useful if you explicitly want the shortcut to send text into Feishu/OpenClaw instead of calling the local Gateway.

## Supported intents

- `剪藏视频：<share text>`
- `拆解视频：<share text>`

Expected routing:

- `剪藏视频` -> `obsidian-clipper`
- `拆解视频` -> `obsidian-clipper -> obsidian-analyzer`

## References

- [Feishu Message Contract](E:\Codex_project\obsidian-skillkit\ios-shortcuts-entry\references\feishu-message-contract.md)
- [OpenClaw Routing Contract](E:\Codex_project\obsidian-skillkit\ios-shortcuts-entry\references\openclaw-routing-contract.md)
- [iOS Shortcuts 1.0 Design](E:\Codex_project\obsidian-skillkit\ios-shortcuts-entry\references\ios-shortcuts-v1-design.md)
- [Mobile Feedback Contract](E:\Codex_project\obsidian-skillkit\ios-shortcuts-entry\references\mobile-feedback-contract.md)
- [Integration Test Matrix](E:\Codex_project\obsidian-skillkit\ios-shortcuts-entry\references\integration-test-matrix.md)
