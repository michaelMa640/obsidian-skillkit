import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from topic_taxonomy import canonicalize_topic_names, load_topic_taxonomy


TOPIC_TAXONOMY = load_topic_taxonomy()


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


def yaml_frontmatter_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(value)
    return yaml_scalar(value)


def safe_file_name(value: str) -> str:
    invalid = set('<>:"/\\|?*')
    sanitized = "".join("_" if ch in invalid else ch for ch in value)
    return sanitized.strip() or "untitled.md"


def normalize_inline_spaces(value: str) -> str:
    return re.sub(r"\s+", " ", string_value(value)).strip()


def clean_note_title(raw_title: str) -> str:
    text = normalize_inline_spaces(raw_title)
    if not has_value(text):
        return "未命名知识解读"
    text = re.sub(r"https?://\S+", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"@\S+", " ", text)
    text = re.sub(r"#\S+", " ", text)
    text = normalize_inline_spaces(text)
    text = re.sub(r"^[\s,.;:!?，。！？\-_/]+", "", text)
    text = re.sub(r"[\s,.;:!?，。！？\-_/]+$", "", text)
    text = normalize_inline_spaces(text)
    return text or "未命名知识解读"


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


def vault_path_or_original(path_value: str, vault_path: str) -> str:
    relative = relative_vault_path(path_value, vault_path)
    if has_value(relative):
        return relative
    return string_value(path_value)


def obsidian_link(path_value: str, vault_path: str, embed: bool = False) -> str:
    relative = vault_path_or_original(path_value, vault_path)
    if not has_value(relative):
        return string_value(path_value, default="n/a")
    target = relative[:-3] if relative.lower().endswith(".md") else relative
    if embed:
        return f"![[{target}]]"
    return f"[[{target}]]"


def normalize_list(values: Any) -> list[Any]:
    if values is None:
        return []
    if isinstance(values, list):
        return values
    return [values]


def lines_from_string_list(values: Any, empty_text: str) -> list[str]:
    lines = [f"- {string_value(item)}" for item in normalize_list(values) if has_value(item)]
    return lines or [empty_text]


def lines_from_methods(values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values)
    lines: list[str] = []
    for item in items:
        if isinstance(item, dict):
            name = string_value(item.get("name"), default="未命名方法")
            summary = string_value(item.get("summary"))
            applicability = string_value(item.get("applicability"))
            steps = [string_value(step) for step in normalize_list(item.get("steps")) if has_value(step)]
            parts = [name]
            if has_value(summary):
                parts.append(summary)
            if steps:
                parts.append("步骤: " + " -> ".join(steps))
            if has_value(applicability):
                parts.append("适用场景: " + applicability)
            lines.append("- " + " | ".join(parts))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or [empty_text]


def lines_from_tips(values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values)
    lines: list[str] = []
    for item in items:
        if isinstance(item, dict):
            point = string_value(item.get("point"), item.get("name"), default="未命名要点")
            detail = string_value(item.get("detail"), item.get("summary"))
            lines.append("- " + point + (f": {detail}" if has_value(detail) else ""))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or [empty_text]


def lines_from_concepts(values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values)
    lines: list[str] = []
    for item in items:
        if isinstance(item, dict):
            name = string_value(item.get("name"), default="未命名概念")
            summary = string_value(item.get("summary"))
            lines.append("- " + name + (f": {summary}" if has_value(summary) else ""))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or [empty_text]


def lines_from_cards(values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values)
    lines: list[str] = []
    for item in items:
        if isinstance(item, dict):
            title = string_value(item.get("title"), item.get("name"), default="未命名知识卡")
            summary = string_value(item.get("summary"))
            evidence = string_value(item.get("evidence"))
            tags = [string_value(tag) for tag in normalize_list(item.get("tags")) if has_value(tag)]
            parts = [title]
            if has_value(summary):
                parts.append(summary)
            if has_value(evidence):
                parts.append("证据: " + evidence)
            if tags:
                parts.append("标签: " + ", ".join(tags))
            lines.append("- " + " | ".join(parts))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or [empty_text]


def lines_from_topics(values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values)
    lines: list[str] = []
    for item in items:
        if isinstance(item, dict):
            name = string_value(item.get("name"), default="未命名主题")
            reason = string_value(item.get("reason"), item.get("summary"))
            lines.append("- " + name + (f": {reason}" if has_value(reason) else ""))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or [empty_text]


def lines_from_quotes(values: Any, fallback_values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values) or normalize_list(fallback_values)
    lines: list[str] = []
    for item in items:
        if isinstance(item, dict):
            quote = string_value(item.get("quote"), item.get("text"))
            timestamp = string_value(item.get("timestamp"))
            speaker = string_value(item.get("speaker"))
            reason = string_value(item.get("reason"))
            if not has_value(quote):
                continue
            extras = []
            if has_value(timestamp):
                extras.append(timestamp)
            if has_value(speaker):
                extras.append(speaker)
            if has_value(reason):
                extras.append(reason)
            suffix = f" | {' | '.join(extras)}" if extras else ""
            lines.append(f"- {quote}{suffix}")
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or [empty_text]


def lines_from_timestamp_index(values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values)
    lines: list[str] = []
    for item in items:
        if isinstance(item, dict):
            timestamp = string_value(item.get("timestamp"), item.get("time"), item.get("start"))
            topic = string_value(item.get("topic"), item.get("text"), item.get("title"), default="未命名片段")
            note = string_value(item.get("note"), item.get("detail"), item.get("summary"))
            if has_value(timestamp):
                lines.append("- " + timestamp + " | " + topic + (f": {note}" if has_value(note) else ""))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or [empty_text]


def lines_from_speaker_map(values: Any, empty_text: str) -> list[str]:
    items = normalize_list(values)
    lines: list[str] = []
    for item in items:
        if isinstance(item, dict):
            speaker = string_value(item.get("speaker"), default="未命名说话人")
            role = string_value(item.get("role"))
            notes = string_value(item.get("notes"))
            extras = []
            if has_value(role):
                extras.append(role)
            if has_value(notes):
                extras.append(notes)
            lines.append("- " + speaker + (f": {' | '.join(extras)}" if extras else ""))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or [empty_text]


def dedupe_strings(values: list[str]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        normalized = string_value(value)
        if not has_value(normalized):
            continue
        if normalized in seen:
            continue
        seen.add(normalized)
        result.append(normalized)
    return result


def extract_named_values(values: Any, *keys: str) -> list[str]:
    items = normalize_list(values)
    names: list[str] = []
    for item in items:
        if isinstance(item, dict):
            candidates = [item.get(key) for key in keys]
            text = string_value(*candidates)
        else:
            text = string_value(item)
        if has_value(text):
            names.append(text)
    return dedupe_strings(names)


def append_yaml_list(lines: list[str], key: str, values: list[str]) -> None:
    normalized = dedupe_strings(values)
    if not normalized:
        return
    lines.append(f"{key}:")
    lines.extend([f"  - {yaml_scalar(item)}" for item in normalized])


def build_navigation_lines(analysis: dict[str, Any], vault_path: str) -> list[str]:
    source_note_path = string_value(analysis.get("source_note_path"))
    capture_json_path = string_value(analysis.get("capture_json_path"))
    audio_path = string_value(analysis.get("audio_path"))
    transcript_path = string_value(analysis.get("transcript_path"))
    source_url = string_value(analysis.get("source_url"))
    normalized_url = string_value(analysis.get("normalized_url"))

    lines = [f"- 来源剪藏: {obsidian_link(source_note_path, vault_path)}"]
    if has_value(source_url):
        lines.append(f"- 原始链接: {source_url}")
    if has_value(normalized_url) and normalized_url != source_url:
        lines.append(f"- 规范化链接: {normalized_url}")
    if has_value(capture_json_path):
        lines.append(f"- Capture JSON: {obsidian_link(capture_json_path, vault_path)}")
    if has_value(transcript_path):
        lines.append(f"- 转录文本: {obsidian_link(transcript_path, vault_path)}")
    if has_value(audio_path):
        lines.append(f"- 音频文件: {obsidian_link(audio_path, vault_path)}")
    return lines


def build_source_lines(analysis: dict[str, Any], vault_path: str) -> list[str]:
    source_note_path = string_value(analysis.get("source_note_path"))
    capture_json_path = string_value(analysis.get("capture_json_path"))
    audio_path = string_value(analysis.get("audio_path"))
    transcript_path = string_value(analysis.get("transcript_path"))
    transcript_raw_path = string_value(analysis.get("transcript_raw_path"))
    transcript_segments_path = string_value(analysis.get("transcript_segments_path"))
    speaker_annotated_transcript_path = string_value(analysis.get("speaker_annotated_transcript_path"))
    speakers_path = string_value(analysis.get("speakers_path"))
    video_path = string_value(analysis.get("video_path"))
    asr_normalization = string_value(analysis.get("asr_normalization"))
    source_url = string_value(analysis.get("source_url"))
    normalized_url = string_value(analysis.get("normalized_url"))

    lines = [
        f"- 来源笔记: {obsidian_link(source_note_path, vault_path)}",
        f"- 原始链接: {source_url if has_value(source_url) else 'n/a'}",
        f"- 规范化链接: {normalized_url if has_value(normalized_url) else 'n/a'}",
        f"- Capture JSON: {obsidian_link(capture_json_path, vault_path)}",
        f"- 音频文件: {obsidian_link(audio_path, vault_path)}",
        f"- 文本稿: {obsidian_link(transcript_path, vault_path)}",
        f"- 原始文本稿: {obsidian_link(transcript_raw_path, vault_path)}",
        f"- 说话人文本稿: {obsidian_link(speaker_annotated_transcript_path, vault_path)}",
        f"- 分段文本 JSON: {obsidian_link(transcript_segments_path, vault_path)}",
        f"- 说话人映射 JSON: {obsidian_link(speakers_path, vault_path)}",
        f"- 本地视频: {obsidian_link(video_path, vault_path)}",
    ]
    if has_value(asr_normalization):
        lines.append(f"- ASR 规范化: {asr_normalization}")
    if has_value(relative_vault_path(audio_path, vault_path)):
        lines.extend(["", "### 音频嵌入", obsidian_link(audio_path, vault_path, embed=True)])
    return lines


def build_note(analysis: dict[str, Any], folder: str, vault_path: str) -> dict[str, Any]:
    output_language = string_value(analysis.get("output_language"), default="zh-CN")
    source_note_path = string_value(analysis.get("source_note_path"))
    raw_title = string_value(
        title_from_source_note_path(source_note_path),
        analysis.get("title"),
        default="未命名知识解读",
    )
    title = clean_note_title(raw_title)
    analyzed_at = datetime.now().strftime("%Y-%m-%d")
    mode = string_value(analysis.get("analysis_mode"), default="knowledge")
    goal = string_value(analysis.get("analysis_goal"), default="knowledge")
    model = string_value(analysis.get("model"), default="mock-knowledge")
    provider = string_value(analysis.get("provider"), default="mock")
    provider_reported_model = string_value(analysis.get("provider_reported_model"))
    analysis_status = string_value(analysis.get("analysis_status"), default="mock_generated")
    route = string_value(analysis.get("route"))
    author = string_value(analysis.get("author"))
    published_at = string_value(analysis.get("published_at"))
    podcast_title = string_value(analysis.get("podcast_title"))
    podcast_author = string_value(analysis.get("podcast_author"))
    episode_url = string_value(analysis.get("episode_url"))
    episode_id = string_value(analysis.get("episode_id"))
    duration_seconds = string_value(analysis.get("duration_seconds"))
    capture_json_path = string_value(analysis.get("capture_json_path"))
    audio_path = string_value(analysis.get("audio_path"))
    transcript_path = string_value(analysis.get("transcript_path"))
    transcript_raw_path = string_value(analysis.get("transcript_raw_path"))
    transcript_segments_path = string_value(analysis.get("transcript_segments_path"))
    speaker_annotated_transcript_path = string_value(analysis.get("speaker_annotated_transcript_path"))
    speakers_path = string_value(analysis.get("speakers_path"))
    video_path = string_value(analysis.get("video_path"))
    file_name = safe_file_name(f"{analyzed_at} {title}.md")
    source_note_link = obsidian_link(source_note_path, vault_path)
    source_note_path_value = vault_path_or_original(source_note_path, vault_path)
    capture_json_path_value = vault_path_or_original(capture_json_path, vault_path)
    audio_path_value = vault_path_or_original(audio_path, vault_path)
    transcript_path_value = vault_path_or_original(transcript_path, vault_path)
    transcript_raw_path_value = vault_path_or_original(transcript_raw_path, vault_path)
    transcript_segments_path_value = vault_path_or_original(transcript_segments_path, vault_path)
    speaker_annotated_transcript_path_value = vault_path_or_original(speaker_annotated_transcript_path, vault_path)
    speakers_path_value = vault_path_or_original(speakers_path, vault_path)
    video_path_value = vault_path_or_original(video_path, vault_path)
    topic_names = canonicalize_topic_names(
        extract_named_values(analysis.get("topic_candidates"), "name", "title", "topic"),
        taxonomy=TOPIC_TAXONOMY,
        default_topic="",
    )
    knowledge_card_titles = extract_named_values(analysis.get("knowledge_cards"), "title", "name")
    speaker_names = extract_named_values(analysis.get("speaker_map"), "speaker", "name", "title")
    insight_tags = dedupe_strings(
        ["insight", "knowledge", *[string_value(item) for item in normalize_list(analysis.get("tags"))]]
    )
    has_audio = has_value(audio_path_value)
    has_transcript = has_value(transcript_path_value)
    has_timestamps = len(normalize_list(analysis.get("timestamp_index"))) > 0
    has_speakers = len(speaker_names) > 0

    lines = [
        "---",
        f"title: {yaml_scalar(title)}",
        "note_type: 'knowledge_insight'",
        f"source_url: {yaml_scalar(string_value(analysis.get('source_url')))}",
        f"normalized_url: {yaml_scalar(string_value(analysis.get('normalized_url')))}",
        f"source_note_path: {yaml_scalar(source_note_path_value)}",
        f"source_note_link: {yaml_scalar(source_note_link)}",
        f"capture_json_path: {yaml_scalar(capture_json_path_value)}",
        f"audio_path: {yaml_scalar(audio_path_value)}",
        f"transcript_path: {yaml_scalar(transcript_path_value)}",
        f"transcript_raw_path: {yaml_scalar(transcript_raw_path_value)}",
        f"transcript_segments_path: {yaml_scalar(transcript_segments_path_value)}",
        f"speaker_annotated_transcript_path: {yaml_scalar(speaker_annotated_transcript_path_value)}",
        f"speakers_path: {yaml_scalar(speakers_path_value)}",
        f"video_path: {yaml_scalar(video_path_value)}",
        f"analysis_mode: {yaml_scalar(mode)}",
        f"analysis_goal: {yaml_scalar(goal)}",
        f"platform: {yaml_scalar(string_value(analysis.get('platform')))}",
        f"content_type: {yaml_scalar(string_value(analysis.get('content_type')))}",
        f"route: {yaml_scalar(route)}",
        f"capture_id: {yaml_scalar(string_value(analysis.get('capture_id')))}",
        f"author: {yaml_scalar(author)}",
        f"published_at: {yaml_scalar(published_at)}",
        f"podcast_title: {yaml_scalar(podcast_title)}",
        f"podcast_author: {yaml_scalar(podcast_author)}",
        f"episode_url: {yaml_scalar(episode_url)}",
        f"episode_id: {yaml_scalar(episode_id)}",
        f"duration_seconds: {yaml_scalar(duration_seconds)}",
        f"analyzed_at: {yaml_scalar(analyzed_at)}",
        f"provider: {yaml_scalar(provider)}",
        f"provider_reported_model: {yaml_scalar(provider_reported_model)}",
        f"model: {yaml_scalar(model)}",
        f"analysis_status: {yaml_scalar(analysis_status)}",
        f"prompt_template: {yaml_scalar(string_value(analysis.get('prompt_template')))}",
        f"output_contract_version: {yaml_scalar(string_value(analysis.get('output_contract_version')))}",
        f"output_language: {yaml_scalar(output_language)}",
        f"knowledge_card_candidate_count: {yaml_frontmatter_value(len(knowledge_card_titles))}",
        f"topic_candidate_count: {yaml_frontmatter_value(len(topic_names))}",
        f"speaker_count: {yaml_frontmatter_value(len(speaker_names))}",
        f"timestamp_count: {yaml_frontmatter_value(len(normalize_list(analysis.get('timestamp_index'))))}",
        f"has_audio: {yaml_frontmatter_value(has_audio)}",
        f"has_transcript: {yaml_frontmatter_value(has_transcript)}",
        f"has_timestamps: {yaml_frontmatter_value(has_timestamps)}",
        f"has_speakers: {yaml_frontmatter_value(has_speakers)}",
    ]
    append_yaml_list(lines, "topic_names", topic_names)
    append_yaml_list(lines, "knowledge_card_titles", knowledge_card_titles)
    append_yaml_list(lines, "speaker_names", speaker_names)
    append_yaml_list(lines, "tags", insight_tags)
    lines.extend([
        "---",
        "",
        f"# {markdown_title(title, '未命名知识解读')}",
        "",
        "## 回链入口",
        *build_navigation_lines(analysis, vault_path),
        "",
        "## 分析元数据",
        f"- 平台: {string_value(analysis.get('platform'), default='n/a')}",
        f"- 路由: {route if has_value(route) else 'n/a'}",
        f"- 内容类型: {string_value(analysis.get('content_type'), default='n/a')}",
        f"- 模式: {mode}",
        f"- 目标: {goal}",
        f"- 作者: {author if has_value(author) else 'n/a'}",
        f"- 发布时间: {published_at if has_value(published_at) else 'n/a'}",
        f"- 提供方: {provider}",
        f"- 模型: {model}",
        f"- 状态: {analysis_status}",
        f"- Capture ID: {string_value(analysis.get('capture_id'), default='n/a')}",
    ])
    if has_value(podcast_title):
        lines.append(f"- 播客名称: {podcast_title}")
    if has_value(podcast_author):
        lines.append(f"- 播客作者: {podcast_author}")
    if has_value(episode_id):
        lines.append(f"- 单集 ID: {episode_id}")
    if has_value(duration_seconds):
        lines.append(f"- 时长（秒）: {duration_seconds}")
    lines.extend([
        "",
        "## 内容总结",
        string_value(analysis.get("content_summary"), default="暂无"),
        "",
        "## 核心观点",
        *lines_from_string_list(analysis.get("core_points"), empty_text="- 暂无"),
        "",
        "## 关键概念",
        *lines_from_concepts(analysis.get("concepts"), empty_text="- 暂无"),
        "",
        "## 方法论",
        *lines_from_methods(analysis.get("methods"), empty_text="- 暂无"),
        "",
        "## 小技巧或知识点",
        *lines_from_tips(analysis.get("tips_and_facts"), empty_text="- 暂无"),
        "",
        "## 可沉淀知识卡候选",
        *lines_from_cards(analysis.get("knowledge_cards"), empty_text="- 暂无"),
        "",
        "## 关联主题",
        *([f"- {topic}" for topic in topic_names] or ["- 暂无"]),
        "",
        "## 可行动建议",
        *lines_from_string_list(analysis.get("action_items"), empty_text="- 暂无"),
        "",
        "## 待确认问题",
        *lines_from_string_list(analysis.get("open_questions"), empty_text="- 暂无"),
        "",
        "## 精华引用",
        *lines_from_quotes(analysis.get("quotes"), analysis.get("source_highlights"), empty_text="- 暂无"),
        "",
        "## 时间戳索引",
        *lines_from_timestamp_index(analysis.get("timestamp_index"), empty_text="- 暂无"),
        "",
        "## 人物与说话人",
        *lines_from_speaker_map(analysis.get("speaker_map"), empty_text="- 暂无"),
        "",
        "## 来源",
        *build_source_lines(analysis, vault_path),
    ])
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
        "analysis_mode": string_value(analysis.get("analysis_mode"), default="knowledge"),
        "analysis_goal": string_value(analysis.get("analysis_goal"), default="knowledge"),
        "analysis_status": string_value(analysis.get("analysis_status"), default="mock_generated"),
        "model": string_value(analysis.get("model"), default="mock-knowledge"),
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
