# Output Note Contract

## Purpose

This document defines the output note contract for `obsidian-analyzer`.

Phase 4 fixes the `analyze` note shape before a real LLM adapter is connected.

## Target Folders

- `Breakdowns/` for `analyze`
- `Insights/` for `learn`

## Required Frontmatter

- `title`
- `source_url`
- `normalized_url`
- `source_note_path`
- `analysis_mode`
- `platform`
- `content_type`
- `capture_id`
- `analyzed_at`
- `model`
- `analysis_status`
- `prompt_template`
- `output_contract_version`

## Analyze Note Sections

Required section order:

- `# 标题`
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

## Analyze Result Contract

The renderer expects these semantic fields from the model result:

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
  "name": "问题开场 + 场景解释 + 产品可信度",
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

## Current Constraint

The current runnable implementation may still emit deterministic mock analysis content,
but the output structure should already match the final `analyze` contract.
