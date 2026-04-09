import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


def load_json(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def configure_console_output() -> None:
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream is None:
            continue
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(encoding="utf-8", errors="backslashreplace")


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


def normalize_inline_spaces(value: str) -> str:
    return re.sub(r"\s+", " ", string_value(value)).strip()


def clean_note_title(raw_title: str) -> str:
    text = normalize_inline_spaces(raw_title)
    if not has_value(text):
        return "未命名拆解"
    text = re.sub(r"https?://\S+", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"@\S+", " ", text)
    text = re.sub(r"#\S+", " ", text)
    text = normalize_inline_spaces(text)
    text = re.sub(r"^[\s,.;:!?，。！？@\-_/]+", "", text)
    text = re.sub(r"[\s,.;:!?，。！？@\-_/]+$", "", text)
    text = normalize_inline_spaces(text)
    return text or "未命名拆解"


def title_from_source_note_path(note_path: str) -> str:
    if not has_value(note_path):
        return ""
    stem = Path(note_path).stem
    stem = re.sub(r"^[\u2713\u2714\u221A\u2705]\s*", "", stem)
    stem = re.sub(r"^\d{4}-\d{2}-\d{2}\s+", "", stem)
    return normalize_inline_spaces(stem)


def markdown_title(title: str, fallback: str) -> str:
    value = string_value(title, default=fallback)
    return "\\" + value if value.startswith("#") else value


def normalize_list(values: Any) -> list[str]:
    if values is None:
        return []
    items = values if isinstance(values, list) else [values]
    return [string_value(item) for item in items if has_value(item)]


def lines_from_list(values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values)
    return [f"- {item}" for item in items] if items else [empty_text]


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
    return f"- {label}: {string_value(value, default='0')}"


def language_pack(language: str) -> dict[str, str]:
    normalized = (language or "").strip().lower()
    if normalized in {"en", "en-us", "english"}:
        return {
            "untitled": "Untitled Breakdown",
            "none_bullet": "- None",
            "unnamed_formula": "Unnamed Formula",
            "reason_label": "Reason",
            "sections.meta": "Analysis Metadata",
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
            "meta.platform": "Platform",
            "meta.mode": "Mode",
            "meta.model": "Model",
            "meta.provider": "Provider",
            "meta.status": "Status",
            "meta.capture_id": "Capture ID",
            "sources.clipping": "Clipping Note",
            "sources.capture": "Capture JSON",
            "sources.video": "Local Video",
            "sources.video_embed": "Embedded Video",
        }
    return {
        "untitled": "未命名拆解",
        "none_bullet": "- 无",
        "unnamed_formula": "未命名公式",
        "reason_label": "理由",
        "sections.meta": "分析元数据",
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
        "meta.platform": "平台",
        "meta.mode": "模式",
        "meta.model": "模型",
        "meta.provider": "提供方",
        "meta.status": "状态",
        "meta.capture_id": "Capture ID",
        "sources.clipping": "来源笔记",
        "sources.capture": "Capture JSON",
        "sources.video": "本地视频",
        "sources.video_embed": "视频嵌入",
    }


def relative_vault_path(path_value: str, vault_path: str) -> str:
    if not has_value(path_value) or not has_value(vault_path):
        return ""
    try:
        candidate = Path(path_value).resolve()
        root = Path(vault_path).resolve()
    except OSError:
        return ""
    try:
        return candidate.relative_to(root).as_posix()
    except ValueError:
        return ""


def obsidian_link(path_value: str, vault_path: str, embed: bool = False) -> str:
    relative = relative_vault_path(path_value, vault_path)
    if not has_value(relative):
        return string_value(path_value, default="n/a")
    if embed:
        return f"![[{relative}]]"
    label = Path(relative).name
    return f"[{label}](<{relative}>)"


def build_source_lines(analysis: dict[str, Any], labels: dict[str, str], vault_path: str) -> list[str]:
    source_note_path = string_value(analysis.get("source_note_path"))
    capture_json_path = string_value(analysis.get("capture_json_path"))
    video_path = string_value(analysis.get("video_path"))
    lines = [
        f"- {labels['sources.clipping']}: {obsidian_link(source_note_path, vault_path)}",
        f"- {labels['sources.capture']}: {obsidian_link(capture_json_path, vault_path)}",
        f"- {labels['sources.video']}: {obsidian_link(video_path, vault_path)}",
    ]
    if has_value(relative_vault_path(video_path, vault_path)):
        lines.extend(["", f"### {labels['sources.video_embed']}", obsidian_link(video_path, vault_path, embed=True)])
    return lines


def build_note(analysis: dict[str, Any], folder: str, vault_path: str) -> dict[str, Any]:
    output_language = string_value(analysis.get("output_language"), default="zh-CN")
    labels = language_pack(output_language)
    source_note_path = string_value(analysis.get("source_note_path"))
    raw_title = string_value(
        title_from_source_note_path(source_note_path),
        analysis.get("title"),
        default=labels["untitled"],
    )
    title = clean_note_title(raw_title)
    analyzed_at = datetime.now().strftime("%Y-%m-%d")
    mode = string_value(analysis.get("analysis_mode"), default="analyze")
    model = string_value(analysis.get("model"), default="mock-analyzer")
    provider = string_value(analysis.get("provider"), default="mock")
    provider_reported_model = string_value(analysis.get("provider_reported_model"))
    analysis_status = string_value(analysis.get("analysis_status"), default="mock_generated")
    capture_json_path = string_value(analysis.get("capture_json_path"))
    video_path = string_value(analysis.get("video_path"))
    file_name = safe_file_name(f"{analyzed_at} {title}.md")

    lines = [
        "---",
        f"title: {yaml_scalar(title)}",
        f"source_url: {yaml_scalar(string_value(analysis.get('source_url')))}",
        f"normalized_url: {yaml_scalar(string_value(analysis.get('normalized_url')))}",
        f"source_note_path: {yaml_scalar(source_note_path)}",
        f"capture_json_path: {yaml_scalar(capture_json_path)}",
        f"video_path: {yaml_scalar(video_path)}",
        f"analysis_mode: {yaml_scalar(mode)}",
        f"platform: {yaml_scalar(string_value(analysis.get('platform')))}",
        f"content_type: {yaml_scalar(string_value(analysis.get('content_type')))}",
        f"capture_id: {yaml_scalar(string_value(analysis.get('capture_id')))}",
        f"analyzed_at: {yaml_scalar(analyzed_at)}",
        f"provider: {yaml_scalar(provider)}",
        f"provider_reported_model: {yaml_scalar(provider_reported_model)}",
        f"model: {yaml_scalar(model)}",
        f"analysis_status: {yaml_scalar(analysis_status)}",
        f"prompt_template: {yaml_scalar(string_value(analysis.get('prompt_template')))}",
        f"output_contract_version: {yaml_scalar(string_value(analysis.get('output_contract_version')))}",
        f"output_language: {yaml_scalar(output_language)}",
        "---",
        "",
        f"# {markdown_title(title, labels['untitled'])}",
        "",
        f"## {labels['sections.meta']}",
        f"- {labels['meta.platform']}: {string_value(analysis.get('platform'), default='n/a')}",
        f"- {labels['meta.mode']}: {mode}",
        f"- {labels['meta.provider']}: {provider}",
        f"- {labels['meta.model']}: {model}",
        f"- {labels['meta.status']}: {analysis_status}",
        f"- {labels['meta.capture_id']}: {string_value(analysis.get('capture_id'), default='n/a')}",
        "",
        f"## {labels['sections.core']}",
        string_value(analysis.get("core_conclusion"), default=labels["none_bullet"][2:]),
        "",
        f"## {labels['sections.hook']}",
        string_value(analysis.get("hook_breakdown"), default=labels["none_bullet"][2:]),
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
        *build_source_lines(analysis, labels, vault_path),
    ]
    return {
        "title": title,
        "raw_title": raw_title,
        "folder": folder,
        "file_name": file_name,
        "note_body": "\n".join(lines).strip() + "\n",
    }


def main() -> int:
    configure_console_output()
    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-json", required=True)
    parser.add_argument("--vault-path", default="")
    parser.add_argument("--vault-path-file", default="")
    parser.add_argument("--folder", default="")
    parser.add_argument("--folder-file", default="")
    parser.add_argument("--output-json")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    analysis = load_json(args.analysis_json)

    vault_path = string_value(args.vault_path)
    if not has_value(vault_path) and has_value(args.vault_path_file):
        vault_path = load_text(args.vault_path_file).strip()

    folder = string_value(args.folder)
    if not has_value(folder) and has_value(args.folder_file):
        folder = load_text(args.folder_file).strip()
    if not has_value(folder):
        raise SystemExit("--folder or --folder-file is required")

    note = build_note(analysis, folder, vault_path)
    result = {
        **note,
        "analysis_mode": string_value(analysis.get("analysis_mode"), default="analyze"),
        "analysis_status": string_value(analysis.get("analysis_status"), default="mock_generated"),
        "model": string_value(analysis.get("model"), default="mock-analyzer"),
        "provider": string_value(analysis.get("provider"), default="mock"),
        "provider_reported_model": string_value(analysis.get("provider_reported_model")),
        "source_url": string_value(analysis.get("source_url")),
        "normalized_url": string_value(analysis.get("normalized_url")),
        "prompt_template": string_value(analysis.get("prompt_template")),
        "output_contract_version": string_value(analysis.get("output_contract_version")),
        "output_language": string_value(analysis.get("output_language"), default="zh-CN"),
    }

    if not args.dry_run and has_value(vault_path):
        target_dir = Path(vault_path).joinpath(*[part for part in folder.replace("\\", "/").split("/") if part])
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
