import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any


def load_json(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def has_value(value: Any) -> bool:
    return value is not None and str(value).strip() != ""


def string_value(*values: Any, default: str = "") -> str:
    for value in values:
        if has_value(value):
            return str(value).strip()
    return default


def yaml_scalar(value: Any) -> str:
    if value is None:
        return "''"
    return "'" + str(value).replace("'", "''") + "'"


def safe_file_name(value: str) -> str:
    invalid = set('<>:"/\\|?*')
    sanitized = "".join("_" if ch in invalid else ch for ch in value)
    return sanitized.strip() or "untitled.md"


def markdown_title(title: str) -> str:
    if not has_value(title):
        return "未命名拆解"
    return "\\" + title if title.startswith("#") else title


def normalize_list(values: Any) -> list[str]:
    if values is None:
        return []
    if isinstance(values, list):
        items = values
    else:
        items = [values]
    return [string_value(item) for item in items if has_value(item)]


def lines_from_list(values: Any, empty_text: str) -> list[str]:
    cleaned = normalize_list(values)
    return [f"- {item}" for item in cleaned] if cleaned else [empty_text]


def lines_from_formula_items(values: Any, empty_text: str, fallback_name: str) -> list[str]:
    if not isinstance(values, list) or not values:
        return [empty_text]
    lines: list[str] = []
    for item in values:
        if isinstance(item, dict):
            name = string_value(item.get("name"), item.get("formula"), default=fallback_name)
            detail = string_value(item.get("detail"), item.get("explanation"))
            lines.append(f"- {name}" + (f": {detail}" if has_value(detail) else ""))
        else:
            text = string_value(item)
            if has_value(text):
                lines.append(f"- {text}")
    return lines or [empty_text]


def lines_from_source_quotes(values: Any, empty_text: str, reason_label: str) -> list[str]:
    if not isinstance(values, list) or not values:
        return [empty_text]
    lines: list[str] = []
    for item in values:
        if isinstance(item, dict):
            quote = string_value(item.get("quote"), item.get("text"))
            reason = string_value(item.get("reason"))
            if has_value(quote):
                suffix = f" | {reason_label}: {reason}" if has_value(reason) else ""
                lines.append(f"- {quote}{suffix}")
        else:
            text = string_value(item)
            if has_value(text):
                lines.append(f"- {text}")
    return lines or [empty_text]


def metric_line(label: str, value: Any) -> str:
    text = string_value(value, default="0")
    return f"- {label}: {text}"


def language_pack(language: str) -> dict[str, str]:
    normalized = (language or "").strip().lower()
    if normalized in {"en", "en-us", "english"}:
        return {
            "untitled": "Untitled Breakdown",
            "none_bullet": "- None",
            "unnamed_formula": "Unnamed Formula",
            "reason_label": "Reason",
            "sections.core": "Core Conclusion",
            "sections.hook": "Hook Breakdown",
            "sections.structure": "Structure Breakdown",
            "sections.emotion": "Emotion and Trust Signals",
            "sections.comments": "Comment Feedback",
            "sections.metrics": "Engagement Metrics",
            "sections.formula": "Reusable Formula",
            "sections.risks": "Risk Flags",
            "sections.evidence": "Source Highlights",
            "sections.source": "Sources",
            "metrics.like": "Likes",
            "metrics.comment": "Comments",
            "metrics.share": "Shares",
            "metrics.collect": "Collects",
            "metrics.visible_comments": "Visible Comments",
            "sources.clipping": "Clipping Note",
            "sources.capture": "Capture JSON",
            "sources.video": "Local Video",
        }
    return {
        "untitled": "未命名拆解",
        "none_bullet": "- 无",
        "unnamed_formula": "未命名公式",
        "reason_label": "理由",
        "sections.core": "爆点结论",
        "sections.hook": "开头钩子",
        "sections.structure": "结构拆解",
        "sections.emotion": "情绪与信任信号",
        "sections.comments": "评论反馈",
        "sections.metrics": "互动指标",
        "sections.formula": "可复用公式",
        "sections.risks": "风险提示",
        "sections.evidence": "原文证据",
        "sections.source": "来源",
        "metrics.like": "点赞",
        "metrics.comment": "评论",
        "metrics.share": "分享",
        "metrics.collect": "收藏",
        "metrics.visible_comments": "可见评论",
        "sources.clipping": "Clipping Note",
        "sources.capture": "Capture JSON",
        "sources.video": "Local Video",
    }


def build_note(analysis: dict[str, Any], folder: str) -> dict[str, Any]:
    analyzed_at = string_value(analysis.get("analyzed_at"), default=datetime.now().strftime("%Y-%m-%d"))
    output_language = string_value(analysis.get("output_language"), default="zh-CN")
    labels = language_pack(output_language)
    title = string_value(analysis.get("title"), default=labels["untitled"])
    mode = string_value(analysis.get("analysis_mode"), default="analyze")
    model = string_value(analysis.get("model"), default="mock-analyzer")
    analysis_status = string_value(analysis.get("analysis_status"), default="mock_generated")
    file_name = safe_file_name(f"{analyzed_at} {title}.md")

    lines = [
        "---",
        f"title: {yaml_scalar(title)}",
        f"source_url: {yaml_scalar(string_value(analysis.get('source_url')))}",
        f"normalized_url: {yaml_scalar(string_value(analysis.get('normalized_url')))}",
        f"source_note_path: {yaml_scalar(string_value(analysis.get('source_note_path')))}",
        f"analysis_mode: {yaml_scalar(mode)}",
        f"platform: {yaml_scalar(string_value(analysis.get('platform')))}",
        f"content_type: {yaml_scalar(string_value(analysis.get('content_type')))}",
        f"capture_id: {yaml_scalar(string_value(analysis.get('capture_id')))}",
        f"analyzed_at: {yaml_scalar(analyzed_at)}",
        f"model: {yaml_scalar(model)}",
        f"analysis_status: {yaml_scalar(analysis_status)}",
        f"prompt_template: {yaml_scalar(string_value(analysis.get('prompt_template')))}",
        f"output_contract_version: {yaml_scalar(string_value(analysis.get('output_contract_version')))}",
        f"output_language: {yaml_scalar(output_language)}",
        "---",
        "",
        f"# {markdown_title(title)}",
        "",
        f"## {labels['sections.core']}",
        string_value(analysis.get("core_conclusion"), default="(none)"),
        "",
        f"## {labels['sections.hook']}",
        string_value(analysis.get("hook_breakdown"), default="(none)"),
        "",
        f"## {labels['sections.structure']}",
        *lines_from_list(analysis.get("structure_breakdown"), empty_text=labels["none_bullet"]),
        "",
        f"## {labels['sections.emotion']}",
        *lines_from_list(analysis.get("emotion_trust_signals"), empty_text=labels["none_bullet"]),
        "",
        f"## {labels['sections.comments']}",
        *lines_from_list(analysis.get("comment_feedback"), empty_text=labels["none_bullet"]),
        "",
        f"## {labels['sections.metrics']}",
        metric_line(labels["metrics.like"], analysis.get("metrics_like")),
        metric_line(labels["metrics.comment"], analysis.get("metrics_comment")),
        metric_line(labels["metrics.share"], analysis.get("metrics_share")),
        metric_line(labels["metrics.collect"], analysis.get("metrics_collect")),
        metric_line(labels["metrics.visible_comments"], analysis.get("comments_count")),
        *lines_from_list(analysis.get("engagement_insights"), empty_text=labels["none_bullet"]),
        "",
        f"## {labels['sections.formula']}",
        *lines_from_formula_items(
            analysis.get("reusable_formula"),
            empty_text=labels["none_bullet"],
            fallback_name=labels["unnamed_formula"],
        ),
        "",
        f"## {labels['sections.risks']}",
        *lines_from_list(analysis.get("risk_flags"), empty_text=labels["none_bullet"]),
        "",
        f"## {labels['sections.evidence']}",
        *lines_from_source_quotes(
            analysis.get("source_highlights"),
            empty_text=labels["none_bullet"],
            reason_label=labels["reason_label"],
        ),
        "",
        f"## {labels['sections.source']}",
        f"- {labels['sources.clipping']}: {string_value(analysis.get('source_note_path'), default='n/a')}",
        f"- {labels['sources.capture']}: {string_value(analysis.get('capture_json_path'), default='n/a')}",
        f"- {labels['sources.video']}: {string_value(analysis.get('video_path'), default='n/a')}",
    ]
    return {
        "title": title,
        "folder": folder,
        "file_name": file_name,
        "note_body": "\n".join(lines).strip() + "\n",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-json", required=True)
    parser.add_argument("--vault-path")
    parser.add_argument("--folder", required=True)
    parser.add_argument("--output-json")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    analysis = load_json(args.analysis_json)
    note = build_note(analysis, args.folder)
    result = {
        **note,
        "analysis_mode": string_value(analysis.get("analysis_mode"), default="analyze"),
        "analysis_status": string_value(analysis.get("analysis_status"), default="mock_generated"),
        "model": string_value(analysis.get("model"), default="mock-analyzer"),
        "source_url": string_value(analysis.get("source_url")),
        "normalized_url": string_value(analysis.get("normalized_url")),
        "prompt_template": string_value(analysis.get("prompt_template")),
        "output_contract_version": string_value(analysis.get("output_contract_version")),
        "output_language": string_value(analysis.get("output_language"), default="zh-CN"),
    }

    if not args.dry_run and has_value(args.vault_path):
        target_dir = Path(args.vault_path).joinpath(*[part for part in args.folder.replace("\\", "/").split("/") if part])
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / note["file_name"]
        target_path.write_text(note["note_body"], encoding="utf-8")
        result["note_path"] = str(target_path)
    else:
        result["note_path"] = ""

    output_text = json.dumps(result, ensure_ascii=False, indent=2)
    if has_value(args.output_json):
        Path(args.output_json).write_text(output_text, encoding="utf-8")
    print(output_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
