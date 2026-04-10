import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


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


def list_value(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    if isinstance(value, str):
        return [value] if has_value(value) else []
    return [value]


def read_text(path: Path) -> str:
    encodings = ("utf-8", "utf-8-sig", "gb18030")
    last_error: Exception | None = None
    for encoding in encodings:
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError as exc:
            last_error = exc
    if last_error is not None:
        raise last_error
    return path.read_text(encoding="utf-8")


def load_text(path: str) -> str:
    return read_text(Path(path))


def load_json_file(path: Path, warnings: list[str], label: str) -> Any:
    if not path.exists():
        warnings.append(f"{label}_missing:{path}")
        return None
    text = read_text(path)
    if not text.strip():
        warnings.append(f"{label}_empty:{path}")
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        warnings.append(f"{label}_invalid_json:{path}:{exc.msg}")
        return None


def parse_frontmatter(note_text: str) -> tuple[dict[str, Any], str]:
    if not note_text.startswith("---"):
        return {}, note_text.strip()
    lines = note_text.splitlines()
    if len(lines) < 3:
        return {}, note_text.strip()

    frontmatter: dict[str, Any] = {}
    current_key: str | None = None
    in_frontmatter = False
    body_start = 0

    for index, line in enumerate(lines):
        if index == 0 and line.strip() == "---":
            in_frontmatter = True
            continue
        if in_frontmatter and line.strip() == "---":
            body_start = index + 1
            break

        if current_key and line.startswith("  - "):
            value = line[4:].strip().strip("'")
            frontmatter.setdefault(current_key, [])
            if isinstance(frontmatter[current_key], list):
                frontmatter[current_key].append(value)
            continue

        match = re.match(r"^(?P<key>[^:]+):\s*(?P<value>.*)$", line)
        if not match:
            current_key = None
            continue

        key = match.group("key").strip()
        value = match.group("value").strip()
        current_key = key
        if value == "":
            frontmatter[key] = []
            continue

        cleaned = value.strip().strip("'")
        lowered = cleaned.lower()
        if lowered == "true":
            frontmatter[key] = True
        elif lowered == "false":
            frontmatter[key] = False
        else:
            frontmatter[key] = cleaned

    body = "\n".join(lines[body_start:]).strip()
    return frontmatter, body


def parse_note_sections(note_body: str) -> dict[str, str]:
    sections: dict[str, str] = {}
    current_heading = "root"
    buffer: list[str] = []

    def flush() -> None:
        content = "\n".join(buffer).strip()
        if content:
            sections[current_heading] = content

    for line in note_body.splitlines():
        heading_match = re.match(r"^##\s+(.+?)\s*$", line)
        if heading_match:
            flush()
            current_heading = heading_match.group(1).strip()
            buffer = []
            continue
        buffer.append(line)
    flush()
    return sections


def title_from_note_path(note_path: str) -> str:
    if not has_value(note_path):
        return ""
    stem = Path(note_path).stem
    stem = re.sub(r"^[\u2713\u2714\u221A\u2705]\s*", "", stem)
    stem = re.sub(r"^\d{4}-\d{2}-\d{2}\s+", "", stem)
    return stem.strip()


def resolve_path(vault_path: str, path_value: str) -> str:
    if not has_value(path_value):
        return ""
    candidate = Path(path_value)
    if candidate.is_absolute():
        return str(candidate)
    if not has_value(vault_path):
        return str(candidate)
    return str(Path(vault_path).joinpath(*path_value.replace("\\", "/").split("/")))


def normalize_comment(item: Any) -> dict[str, str] | None:
    if isinstance(item, str):
        text = item.strip()
        if not text:
            return None
        return {
            "author": "",
            "text": text,
            "display_text": text,
            "like_count": "",
            "reply_count": "",
            "created_at": "",
            "cid": "",
        }
    if not isinstance(item, dict):
        return None
    author = string_value(item.get("author"), item.get("user_name"))
    text = string_value(item.get("text"), item.get("comment"), item.get("content"))
    display_text = string_value(item.get("display_text"), default=f"{author}: {text}" if has_value(author) else text)
    if not has_value(text) and not has_value(display_text):
        return None
    return {
        "author": author,
        "text": text,
        "display_text": display_text,
        "like_count": string_value(item.get("like_count"), item.get("digg_count")),
        "reply_count": string_value(item.get("reply_count")),
        "created_at": string_value(item.get("created_at")),
        "cid": string_value(item.get("cid")),
    }


def to_comment_list(value: Any) -> list[dict[str, str]]:
    comments: list[dict[str, str]] = []
    for item in list_value(value):
        normalized = normalize_comment(item)
        if normalized is not None:
            comments.append(normalized)
    return comments


def first_non_empty_section(sections: dict[str, str], names: list[str]) -> str:
    for name in names:
        value = sections.get(name, "")
        if has_value(value):
            return value
    return ""


def normalize_analysis_goal(raw_value: Any, analysis_mode: str) -> str:
    explicit = string_value(raw_value).lower()
    if explicit in {"analyze", "knowledge"}:
        return explicit
    mode = string_value(analysis_mode).lower()
    if mode == "analyze":
        return "analyze"
    return "knowledge"


def normalize_analysis_mode(raw_value: Any) -> str:
    mode = string_value(raw_value).lower()
    if mode == "learn":
        return "knowledge"
    if mode in {"analyze", "knowledge"}:
        return mode
    return mode or "knowledge"


def load_note(note_path: str, warnings: list[str]) -> tuple[dict[str, Any], str, dict[str, str]]:
    if not has_value(note_path):
        return {}, "", {}
    note = Path(note_path)
    if not note.exists():
        warnings.append(f"note_missing:{note}")
        return {}, "", {}
    text = read_text(note)
    frontmatter, body = parse_frontmatter(text)
    sections = parse_note_sections(body)
    return frontmatter, body, sections


def find_matching_note_path(vault_path: str, capture_json_path: str, capture: dict[str, Any]) -> str:
    if not has_value(vault_path) or not has_value(capture_json_path):
        return ""

    vault_root = Path(vault_path)
    clippings_root = vault_root / "Clippings"
    if not clippings_root.exists():
        return ""

    expected_capture_id = string_value(capture.get("capture_id"))
    expected_sidecar = ""
    try:
        expected_sidecar = Path(capture_json_path).resolve().as_posix().lower()
    except OSError:
        expected_sidecar = Path(capture_json_path).as_posix().lower()

    for note_file in clippings_root.rglob("*.md"):
        frontmatter, _, _ = load_note(str(note_file), [])
        candidate_capture_id = string_value(frontmatter.get("capture_id"))
        candidate_sidecar = string_value(frontmatter.get("sidecar_path"))
        candidate_sidecar_abs = resolve_path(vault_path, candidate_sidecar)
        try:
            candidate_sidecar_abs = Path(candidate_sidecar_abs).resolve().as_posix().lower() if has_value(candidate_sidecar_abs) else ""
        except OSError:
            candidate_sidecar_abs = Path(candidate_sidecar_abs).as_posix().lower() if has_value(candidate_sidecar_abs) else ""

        if has_value(expected_capture_id) and candidate_capture_id == expected_capture_id:
            return str(note_file)
        if has_value(expected_sidecar) and candidate_sidecar_abs == expected_sidecar:
            return str(note_file)

    return ""


def derive_capture_path(note_frontmatter: dict[str, Any], capture_json_path: str, vault_path: str) -> str:
    if has_value(capture_json_path):
        return capture_json_path
    return resolve_path(vault_path, string_value(note_frontmatter.get("sidecar_path")))


def build_payload(note_path: str, capture_json_path: str, vault_path: str, analysis_mode: str) -> dict[str, Any]:
    warnings: list[str] = []
    normalized_analysis_mode = normalize_analysis_mode(analysis_mode)
    frontmatter, note_body, note_sections = load_note(note_path, warnings)
    resolved_capture_path = derive_capture_path(frontmatter, capture_json_path, vault_path)
    capture = load_json_file(Path(resolved_capture_path), warnings, "capture_json") if has_value(resolved_capture_path) else None
    capture = capture or {}

    resolved_note_path = note_path
    if not has_value(resolved_note_path) and has_value(resolved_capture_path):
        resolved_note_path = find_matching_note_path(vault_path, resolved_capture_path, capture)
        if has_value(resolved_note_path):
            frontmatter, note_body, note_sections = load_note(resolved_note_path, warnings)
        else:
            warnings.append(f"source_note_not_found:{resolved_capture_path}")

    metadata_path = resolve_path(
        vault_path,
        string_value(
            capture.get("metadata_path"),
            frontmatter.get("metadata_path"),
        ),
    )
    comments_path = resolve_path(
        vault_path,
        string_value(
            capture.get("comments_path"),
            frontmatter.get("comments_path"),
        ),
    )
    metadata = load_json_file(Path(metadata_path), warnings, "metadata_json") if has_value(metadata_path) else None
    comments_raw = load_json_file(Path(comments_path), warnings, "comments_json") if has_value(comments_path) else None

    metadata = metadata or {}
    comments = to_comment_list(comments_raw if comments_raw is not None else capture.get("comments"))
    top_comments = [
        string_value(item.get("display_text"), item.get("text"))
        for item in comments[:5]
        if has_value(string_value(item.get("display_text"), item.get("text")))
    ]
    if not top_comments:
        top_comments = [string_value(value) for value in list_value(capture.get("top_comments")) if has_value(value)]

    summary = string_value(capture.get("summary"), metadata.get("summary"))
    description = string_value(capture.get("description"), capture.get("raw_text"))
    raw_text = string_value(
        capture.get("raw_text"),
        description,
        first_non_empty_section(note_sections, ["原始文案", "内容摘要"]),
        note_body,
    )
    transcript = string_value(
        capture.get("transcript"),
        metadata.get("transcript"),
        first_non_empty_section(note_sections, ["转录文本"]),
    )

    metrics_like = string_value(capture.get("metrics_like"), metadata.get("like_count"))
    metrics_comment = string_value(capture.get("metrics_comment"), metadata.get("comment_count"))
    metrics_share = string_value(capture.get("metrics_share"), metadata.get("share_count"))
    metrics_collect = string_value(capture.get("metrics_collect"), metadata.get("collect_count"))

    title = string_value(
        frontmatter.get("note_title"),
        title_from_note_path(resolved_note_path),
        frontmatter.get("title"),
        capture.get("title"),
        default="Untitled analysis source",
    )
    analysis_goal = normalize_analysis_goal(
        frontmatter.get("analysis_goal"),
        analysis_mode=normalized_analysis_mode,
    )
    if not has_value(frontmatter.get("analysis_goal")):
        analysis_goal = normalize_analysis_goal(capture.get("analysis_goal"), analysis_mode=normalized_analysis_mode)
    comments_count_value = capture.get("comments_count")
    if not has_value(comments_count_value):
        comments_count_value = metadata.get("comment_count_visible")
    if not has_value(comments_count_value):
        comments_count_value = len(comments)

    payload = {
        "analysis_mode": normalized_analysis_mode,
        "analysis_goal": analysis_goal,
        "source_note_path": resolved_note_path,
        "capture_json_path": resolved_capture_path,
        "source_url": string_value(frontmatter.get("source_url"), capture.get("source_url")),
        "normalized_url": string_value(frontmatter.get("normalized_url"), capture.get("normalized_url"), metadata.get("normalized_url")),
        "title": title,
        "platform": string_value(frontmatter.get("platform"), capture.get("platform"), metadata.get("platform")),
        "content_type": string_value(frontmatter.get("content_type"), capture.get("content_type"), metadata.get("content_type")),
        "route": string_value(frontmatter.get("route"), capture.get("route"), metadata.get("route")),
        "capture_id": string_value(frontmatter.get("capture_id"), capture.get("capture_id"), metadata.get("capture_id")),
        "capture_key": string_value(frontmatter.get("capture_key"), capture.get("capture_key"), metadata.get("capture_key")),
        "source_item_id": string_value(frontmatter.get("source_item_id"), capture.get("source_item_id"), metadata.get("source_item_id")),
        "author": string_value(frontmatter.get("author"), capture.get("author")),
        "published_at": string_value(frontmatter.get("published_at"), capture.get("published_at")),
        "summary": summary,
        "description": description,
        "raw_text": raw_text,
        "transcript": transcript,
        "note_body": note_body,
        "note_sections": note_sections,
        "tags": [str(item) for item in list_value(frontmatter.get("tags") or capture.get("tags")) if has_value(item)],
        "top_comments": top_comments,
        "comments": comments,
        "comments_count": comments_count_value,
        "comments_capture_status": string_value(capture.get("comments_capture_status"), metadata.get("comments_capture_status")),
        "comments_source": string_value(metadata.get("comments_source")),
        "metrics_like": metrics_like,
        "metrics_comment": metrics_comment,
        "metrics_share": metrics_share,
        "metrics_collect": metrics_collect,
        "metrics_source": string_value(metadata.get("metrics_source")),
        "engagement": {
            "like": metrics_like,
            "comment": metrics_comment,
            "share": metrics_share,
            "collect": metrics_collect,
        },
        "video_path": resolve_path(vault_path, string_value(frontmatter.get("video_path"), capture.get("video_path"), metadata.get("video_path"))),
        "audio_path": resolve_path(vault_path, string_value(frontmatter.get("audio_path"), capture.get("audio_path"), metadata.get("audio_path"))),
        "cover_path": resolve_path(vault_path, string_value(capture.get("cover_path"), metadata.get("cover_path"))),
        "sidecar_path": resolve_path(vault_path, string_value(frontmatter.get("sidecar_path"), capture.get("sidecar_path"), resolved_capture_path)),
        "comments_path": comments_path,
        "metadata_path": metadata_path,
        "transcript_status": string_value(frontmatter.get("transcript_status"), capture.get("transcript_status"), metadata.get("transcript_status")),
        "transcript_source": string_value(frontmatter.get("transcript_source"), capture.get("transcript_source"), metadata.get("transcript_source")),
        "transcript_raw_path": resolve_path(vault_path, string_value(frontmatter.get("transcript_raw_path"), capture.get("transcript_raw_path"), metadata.get("transcript_raw_path"))),
        "transcript_path": resolve_path(vault_path, string_value(frontmatter.get("transcript_path"), capture.get("transcript_path"), metadata.get("transcript_path"))),
        "transcript_segments_path": resolve_path(vault_path, string_value(frontmatter.get("transcript_segments_path"), capture.get("transcript_segments_path"), metadata.get("transcript_segments_path"))),
        "asr_status": string_value(frontmatter.get("asr_status"), capture.get("asr_status"), metadata.get("asr_status")),
        "asr_provider": string_value(frontmatter.get("asr_provider"), capture.get("asr_provider"), metadata.get("asr_provider")),
        "asr_model": string_value(frontmatter.get("asr_model"), capture.get("asr_model"), metadata.get("asr_model")),
        "asr_normalization": string_value(frontmatter.get("asr_normalization"), capture.get("asr_normalization"), metadata.get("asr_normalization")),
        "source_files": {
            "note_exists": has_value(note_path) and Path(note_path).exists(),
            "capture_exists": has_value(resolved_capture_path) and Path(resolved_capture_path).exists(),
            "comments_exists": has_value(comments_path) and Path(comments_path).exists(),
            "metadata_exists": has_value(metadata_path) and Path(metadata_path).exists(),
        },
        "payload_warnings": warnings,
    }
    return payload


def main() -> int:
    configure_console_output()
    parser = argparse.ArgumentParser()
    parser.add_argument("--note-path", default="")
    parser.add_argument("--note-path-file", default="")
    parser.add_argument("--capture-json-path", default="")
    parser.add_argument("--capture-json-path-file", default="")
    parser.add_argument("--vault-path", default="")
    parser.add_argument("--vault-path-file", default="")
    parser.add_argument("--mode", required=True)
    parser.add_argument("--output-json")
    args = parser.parse_args()

    note_path = args.note_path
    if not has_value(note_path) and has_value(args.note_path_file):
        note_path = load_text(args.note_path_file).strip()

    capture_json_path = args.capture_json_path
    if not has_value(capture_json_path) and has_value(args.capture_json_path_file):
        capture_json_path = load_text(args.capture_json_path_file).strip()

    vault_path = args.vault_path
    if not has_value(vault_path) and has_value(args.vault_path_file):
        vault_path = load_text(args.vault_path_file).strip()

    payload = build_payload(
        note_path=note_path,
        capture_json_path=capture_json_path,
        vault_path=vault_path,
        analysis_mode=args.mode,
    )
    output_text = json.dumps(payload, ensure_ascii=False, indent=2)
    if has_value(args.output_json):
        Path(args.output_json).write_text(output_text, encoding="utf-8")
    print(output_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
