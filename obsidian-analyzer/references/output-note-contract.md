# Output Note Contract

## Purpose

This document defines the note contract emitted by `obsidian-analyzer`.

## Target folders

- `爆款拆解/` for `analyze`
- `Insights/` for `learn`

## Required frontmatter

- `title`
- `source_url`
- `normalized_url`
- `source_note_path`
- `capture_json_path`
- `video_path`
- `analysis_mode`
- `platform`
- `content_type`
- `capture_id`
- `analyzed_at`
- `provider`
- `provider_reported_model`
- `model`
- `analysis_status`
- `prompt_template`
- `output_contract_version`
- `output_language`

## Analyze note sections

Required section order:

- `# 标题`
- `## 分析元数据`
- `## 爆点结论`
- `## 开头钩子`
- `## 结构拆解`
- `## 情绪与信任信号`
- `## 评论反馈`
- `## 互动指标`
- `## 可复用公式`
- `## 风险提示`
- `## 原文证据`
- `## 来源`

## Renderer rules

- Source note, capture JSON, and local video should render as Obsidian links when the files are inside the vault.
- If the local video is inside the vault, the renderer should include an Obsidian embed in the `来源` section.
- Breakdown title should follow the resolved clipping note title when `source_note_path` is available.
- Output file name is derived from:
  - actual analysis run date
  - plus the cleaned breakdown title
- `analyzed_at` should reflect the actual analysis run date, not a model-supplied historical date.
- Default `output_language` is `zh-CN`.

## Analyze result contract

The renderer expects these semantic fields from the analysis result:

- `core_conclusion`
- `hook_breakdown`
- `structure_breakdown`
- `emotion_trust_signals`
- `comment_feedback`
- `engagement_insights`
- `reusable_formula`
- `risk_flags`
- `source_highlights`

`reusable_formula` should be an array of short actionable formulas.
Object form is preferred:

```json
{
  "name": "问题开场 + 场景解释 + 证明收口",
  "detail": "先抛用户问题，再解释使用场景，最后用专业身份或技术细节收口。"
}
```

`source_highlights` should capture direct evidence from the payload:

```json
{
  "quote": "蒸汽发生器是干什么用的？",
  "reason": "直接使用问题句式做开头，有助于匹配搜索意图。"
}
```
