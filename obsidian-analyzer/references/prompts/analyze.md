# Analyze Prompt

## Purpose

Use this prompt for short-form social content analysis.

Supported inputs:
- Douyin short videos
- Xiaohongshu short videos
- other short-form content where packaging, hook, and conversion logic matter

The model must analyze why the content works, not rewrite the source.

## Input

You will receive one structured JSON payload from `analyzer-payload.json`.

Key fields usually include:
- `title`
- `platform`
- `content_type`
- `summary`
- `raw_text`
- `transcript`
- `comments`
- `top_comments`
- `metrics_like`
- `metrics_comment`
- `metrics_share`
- `metrics_collect`
- `video_path`
- `payload_warnings`

## Analysis Goal

Produce a concise and structured breakdown that helps a creator answer:
- what the content is really selling or promising
- what hook pattern it uses
- how the structure keeps attention
- what emotional or trust signals make it persuasive
- what comment feedback reveals about audience reaction
- what reusable formula can be extracted
- what risks or limitations should be noted

## Output Rules

- Output valid JSON only.
- Do not wrap the JSON in markdown fences.
- Do not add explanation before or after the JSON.
- Keep every field grounded in the provided payload.
- If evidence is missing, say so explicitly instead of inventing details.
- Keep bullets short and operational.

## Required Output JSON Shape

```json
{
  "title": "string",
  "analysis_mode": "analyze",
  "source_note_path": "string",
  "capture_json_path": "string",
  "source_url": "string",
  "normalized_url": "string",
  "platform": "string",
  "content_type": "string",
  "capture_id": "string",
  "analyzed_at": "YYYY-MM-DD",
  "model": "string",
  "analysis_status": "success|partial|insufficient_evidence",
  "prompt_template": "references/prompts/analyze.md",
  "output_contract_version": "analyze-v1",
  "core_conclusion": "1-3 sentence verdict on why this content works or does not work",
  "hook_breakdown": "short explanation of the opening hook",
  "structure_breakdown": [
    "3-6 short bullets describing the sequence and pacing"
  ],
  "emotion_trust_signals": [
    "2-5 short bullets"
  ],
  "comment_feedback": [
    "2-5 short bullets based on visible comments or note that comments are unavailable"
  ],
  "engagement_insights": [
    "2-5 short bullets combining metrics and observed audience response"
  ],
  "reusable_formula": [
    {
      "name": "string",
      "detail": "short operational template"
    }
  ],
  "risk_flags": [
    "2-5 short bullets"
  ],
  "source_highlights": [
    {
      "quote": "short source quote or observation",
      "reason": "why it matters"
    }
  ],
  "metrics_like": "string",
  "metrics_comment": "string",
  "metrics_share": "string",
  "metrics_collect": "string",
  "comments_count": "string or integer",
  "video_path": "string"
}
```

## Style Constraint

- Favor diagnosis over praise.
- Favor concrete mechanisms over vague labels.
- Favor reusable creator logic over generic marketing language.
