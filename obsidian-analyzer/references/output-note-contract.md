# Output Note Contract

## Purpose

This document defines the note contract emitted by `obsidian-analyzer`.

## Target folders

- `爆款拆解/` for `analyze`
- `Insights/知识解读/` for `knowledge`
- `Insights/知识卡/` for knowledge cards
- `Insights/主题地图/` for topic maps

## Required frontmatter

- `title`
- `note_type`
- `source_url`
- `normalized_url`
- `source_note_path`
- `source_note_link`
- `capture_json_path`
- `video_path`
- `analysis_mode`
- `analysis_goal`
- `platform`
- `content_type`
- `route`
- `capture_id`
- `author`
- `published_at`
- `analyzed_at`
- `provider`
- `provider_reported_model`
- `model`
- `analysis_status`
- `prompt_template`
- `output_contract_version`
- `output_language`

## Knowledge note frontmatter additions

Recommended for `knowledge` notes:

- `topic_names`
- `knowledge_card_titles`
- `speaker_names`
- `knowledge_card_candidate_count`
- `topic_candidate_count`
- `speaker_count`
- `timestamp_count`
- `has_audio`
- `has_transcript`
- `has_timestamps`
- `has_speakers`
- `tags`

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

## Knowledge routing baseline

- `analysis_mode` remains the current runtime implementation switch.
- `analysis_goal` is the content-intent switch.
- For Step 0, the baseline mapping is:
  - `analysis_mode = analyze` -> `analysis_goal = analyze`
  - `analysis_mode = learn` -> `analysis_goal = knowledge`
- The dedicated `knowledge` renderer will be introduced in the follow-up implementation step.

## Renderer rules

- Source note, capture JSON, and local video should render as Obsidian links when the files are inside the vault.
- If the local video is inside the vault, the renderer should include an Obsidian embed in the `来源` section.
- For `knowledge` notes, the top of the note should provide a direct backlink to the source clipping note.
- For `knowledge` notes, frontmatter paths should prefer vault-relative paths when the files are inside the vault.
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

## Knowledge note sections

Required section order:

- `# 标题`
- `## 回链入口`
- `## 分析元数据`
- `## 内容总结`
- `## 核心观点`
- `## 关键概念`
- `## 提到的方法论`
- `## 小技巧与小知识点`
- `## 可沉淀知识卡候选`
- `## 关联主题`
- `## 可行动建议`
- `## 待确认问题`
- `## 精华引用`
- `## 时间戳索引`
- `## 人物与说话人`
- `## 来源`
