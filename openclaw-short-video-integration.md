# OpenClaw 短视频接入说明

## 目标

让 OpenClaw 通过两个 skill 完成短视频工作流：

- `obsidian-clipper`
- `obsidian-analyzer`

对应两类用户意图：

- `剪藏（链接）`
- `拆解视频（链接）`

## 推荐意图映射

### 1. 只剪藏

用户说法示例：

- 帮我剪藏这个视频
- 请帮我保存这个抖音链接到 Obsidian
- 帮我收录这个短视频

OpenClaw 应执行：

- 只调用 `obsidian-clipper`

### 2. 拆解视频

用户说法示例：

- 帮我拆解这个视频
- 分析这个抖音短视频
- 拆解视频：https://...

OpenClaw 应执行：

- 如果输入已经是 clipping note 或明确 `note_path`，直接调用 `obsidian-analyzer`
- 如果输入是 URL 或分享文本，先调用 `obsidian-clipper`
- 取得 `note_path` 后，再调用 `obsidian-analyzer`

也就是：

1. clip first
2. analyze second

这个意图的完成条件不是“剪藏成功”，而是：

1. clipping note 已生成
2. `obsidian-analyzer` 已运行
3. `爆款拆解/` 下生成了拆解笔记

如果只完成了第 1 步，OpenClaw 不能把任务当作完成。

## 首次运行前先做配置预检

OpenClaw 在首次运行，或在流程进入正式抓取前失败时，先检查本机配置。

### Clipper 预检

脚本：

- `obsidian-clipper/scripts/validate_local_config.ps1`

检查项：

- `obsidian.vault_path`
- `routes.social.script`
- `routes.social.auth.storage_state_path`
- `routes.social.auth.cookies_file`

配置文件：

- `obsidian-clipper/references/local-config.json`

如果必填项缺失，OpenClaw 应该：

- 不继续执行剪藏
- 告诉用户去改哪个文件
- 明确指出缺失字段

### Analyzer 预检

脚本：

- `obsidian-analyzer/scripts/validate_local_config.ps1`

检查项：

- `obsidian.vault_path`
- `analyzer.default_analyze_folder`
- `llm.provider`
- `llm.model`
- `llm.api_key` 或环境变量

配置文件：

- `obsidian-analyzer/references/local-config.json`

## 抖音登录状态怎么来

OpenClaw 不会自己登录抖音。
当前方案是：先在本机生成可复用的本地登录态文件，然后让 `Clipper` 复用。

生成方式：

```powershell
python "E:\Codex_project\obsidian-skillkit\obsidian-clipper\scripts\bootstrap_social_auth.py" --platform douyin
```

这个步骤会生成：

- `obsidian-clipper/.local-auth/douyin-storage-state.json`
- `obsidian-clipper/.local-auth/douyin-cookies.txt`

然后在 `obsidian-clipper/references/local-config.json` 里配置：

- `routes.social.auth.storage_state_path`
- `routes.social.auth.cookies_file`

## cookies 失效时怎么处理

如果结果里出现：

- `auth_action_required = refresh_douyin_auth`

或者错误里出现：

- `Fresh cookies are needed`

说明：

- 页面捕获可能已经成功
- 视频 ID 可能也已经拿到
- 但下载或后续访问需要更新登录态

这时 OpenClaw 应明确告诉用户：

- 当前抖音登录态已失效或缺失
- 需要先刷新本地登录态
- 刷新命令是：

```powershell
python "E:\Codex_project\obsidian-skillkit\obsidian-clipper\scripts\bootstrap_social_auth.py" --platform douyin
```

## 应返回给用户的关键字段

### Clipper

- `note_path`
- `debug_directory`
- `support_bundle_path`
- `final_run_status`
- `failed_step`
- `final_message_zh`

如果需要刷新登录态，再额外返回：

- `auth_action_required`
- `auth_refresh_command`
- `auth_guidance_zh`

### Analyzer

- `note_path`
- `debug_directory`
- `support_bundle_path`
- `final_run_status`
- `failed_step`
- `final_message_zh`

## debug 信息如何传给用户

出错时，OpenClaw 默认让用户上传：

- `support-bundle/`

如果 `support-bundle/` 不够，再补充：

- 整个 `debug_directory`

## 推荐中文自然语言用法

### 剪藏

```text
请使用 Obsidian-Clipper 帮我剪藏这个抖音短视频到 Obsidian：
https://v.douyin.com/xxxxxxx/
```

### 拆解视频

```text
请帮我拆解这个抖音短视频。
如果它还没有被剪藏，请先用 Obsidian-Clipper 剪藏，再用 Obsidian-Analyzer 生成爆款拆解：
https://v.douyin.com/xxxxxxx/
```

更直接的说法也应该被当成同一个工作流：

```text
拆解视频：0.25 复制打开抖音，看看…… https://v.douyin.com/xxxxxxx/ ...
```
