import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


AUTO_START = "<!-- AUTO-GENERATED:STEP5:START -->"
AUTO_END = "<!-- AUTO-GENERATED:STEP5:END -->"


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


def normalize_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


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


def load_json(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def yaml_scalar(value: Any) -> str:
    if value is None:
        return "''"
    return "'" + str(value).replace("'", "''") + "'"


def safe_file_name(value: str) -> str:
    invalid = set('<>:"/\\|?*')
    sanitized = "".join("_" if ch in invalid else ch for ch in value)
    return sanitized.strip() or "untitled.md"


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


def obsidian_link(path_value: str, vault_path: str) -> str:
    relative = vault_path_or_original(path_value, vault_path)
    if not has_value(relative):
        return "n/a"
    target = relative[:-3] if relative.lower().endswith(".md") else relative
    return f"[[{target}]]"


def append_yaml_list(lines: list[str], key: str, values: list[str]) -> None:
    normalized = dedupe_strings(values)
    if not normalized:
        return
    lines.append(f"{key}:")
    lines.extend([f"  - {yaml_scalar(item)}" for item in normalized])


def parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    if not text.startswith("---"):
        return {}, text
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return {}, text

    data: dict[str, Any] = {}
    index = 1
    current_list_key = ""
    while index < len(lines):
        line = lines[index]
        if line == "---":
            body = "\n".join(lines[index + 1 :]).strip()
            return data, body
        if line.startswith("  - ") and has_value(current_list_key):
            data.setdefault(current_list_key, []).append(unquote_yaml_scalar(line[4:].strip()))
            index += 1
            continue
        if ":" in line:
            key, raw_value = line.split(":", 1)
            key = key.strip()
            raw_value = raw_value.strip()
            if raw_value == "":
                data[key] = []
                current_list_key = key
            else:
                data[key] = unquote_yaml_scalar(raw_value)
                current_list_key = ""
        else:
            current_list_key = ""
        index += 1
    return {}, text


def unquote_yaml_scalar(value: str) -> str:
    text = string_value(value)
    if len(text) >= 2 and text.startswith("'") and text.endswith("'"):
        return text[1:-1].replace("''", "'")
    return text


def extract_manual_body(body: str) -> str:
    text = body.strip()
    if not has_value(text):
        return ""
    if AUTO_START in text and AUTO_END in text:
        _, tail = text.split(AUTO_END, 1)
        return tail.strip()
    return text


def normalize_manual_body(body: str) -> str:
    text = body.strip()
    if not has_value(text):
        return "## 手动补充\n"
    if text.startswith("## ") or text.startswith("# "):
        return text + "\n"
    return "## 手动补充\n\n" + text + "\n"


def card_type_label(card_type: str) -> str:
    mapping = {
        "concept": "概念卡",
        "method": "方法卡",
        "tip": "技巧卡",
    }
    return mapping.get(string_value(card_type), "知识卡")


def build_target_path(vault_path: str, folder: str, file_name: str) -> Path:
    return Path(vault_path).joinpath(*[part for part in folder.replace("\\", "/").split("/") if part]) / file_name


def predicted_topic_map_relative_paths(topic_names: list[str], folder: str) -> list[str]:
    folder_normalized = "/".join([part for part in folder.replace("\\", "/").split("/") if part])
    return [
        f"{folder_normalized}/{safe_file_name(topic_name)}.md" if has_value(folder_normalized) else f"{safe_file_name(topic_name)}.md"
        for topic_name in topic_names
        if has_value(topic_name)
    ]


def merge_existing_list(existing_frontmatter: dict[str, Any], key: str, new_values: list[str]) -> list[str]:
    existing_values = normalize_list(existing_frontmatter.get(key))
    return dedupe_strings([string_value(item) for item in existing_values if has_value(item)] + new_values)


def build_card_note(
    card: dict[str, Any],
    bundle: dict[str, Any],
    vault_path: str,
    folder: str,
    topic_map_folder: str,
) -> dict[str, Any]:
    today = datetime.now().strftime("%Y-%m-%d")
    title = string_value(card.get("title"), default="未命名知识卡")
    file_name = safe_file_name(title) + ".md"
    target_path = build_target_path(vault_path, folder, file_name)

    existing_frontmatter: dict[str, Any] = {}
    manual_body = ""
    if target_path.exists():
        existing_frontmatter, existing_body = parse_frontmatter(target_path.read_text(encoding="utf-8"))
        manual_body = extract_manual_body(existing_body)

    source_note_path = string_value(bundle.get("source_note_path"))
    insight_note_path = string_value(bundle.get("insight_note_path"))

    source_note_paths = merge_existing_list(
        existing_frontmatter,
        "source_note_paths",
        [vault_path_or_original(source_note_path, vault_path)] if has_value(source_note_path) else [],
    )
    insight_note_paths = merge_existing_list(
        existing_frontmatter,
        "insight_note_paths",
        [vault_path_or_original(insight_note_path, vault_path)] if has_value(insight_note_path) else [],
    )
    topic_names = merge_existing_list(
        existing_frontmatter,
        "topic_names",
        [string_value(item) for item in normalize_list(card.get("topic_names")) if has_value(item)],
    )
    topic_map_paths = merge_existing_list(
        existing_frontmatter,
        "topic_map_paths",
        predicted_topic_map_relative_paths(topic_names, topic_map_folder),
    )

    source_note_links = [obsidian_link(path, vault_path) for path in source_note_paths]
    insight_note_links = [obsidian_link(path, vault_path) for path in insight_note_paths]
    topic_map_links = [obsidian_link(path, vault_path) for path in topic_map_paths]

    tags = merge_existing_list(
        existing_frontmatter,
        "tags",
        dedupe_strings(
            [
                "knowledge-card",
                string_value(card.get("card_type"), default="concept"),
                *[string_value(item) for item in normalize_list(card.get("tags")) if has_value(item)],
                *topic_names,
            ]
        ),
    )

    created_at = string_value(existing_frontmatter.get("created_at"), default=today)
    updated_at = today
    summary = string_value(card.get("summary"), default="暂无摘要。")
    evidence = string_value(card.get("evidence"), default="")

    lines = [
        "---",
        f"title: {yaml_scalar(title)}",
        "note_type: 'knowledge_card'",
        f"card_type: {yaml_scalar(string_value(card.get('card_type'), default='concept'))}",
        f"created_at: {yaml_scalar(created_at)}",
        f"updated_at: {yaml_scalar(updated_at)}",
        f"source_count: {len(source_note_paths)}",
        f"insight_count: {len(insight_note_paths)}",
        f"topic_count: {len(topic_names)}",
    ]
    append_yaml_list(lines, "source_note_paths", source_note_paths)
    append_yaml_list(lines, "insight_note_paths", insight_note_paths)
    append_yaml_list(lines, "topic_names", topic_names)
    append_yaml_list(lines, "topic_map_paths", topic_map_paths)
    append_yaml_list(lines, "tags", tags)
    lines.extend(
        [
            "---",
            "",
            f"# {title}",
            "",
            AUTO_START,
            "## 卡片摘要",
            summary,
            "",
            "## 卡片类型",
            f"- {card_type_label(string_value(card.get('card_type'), default='concept'))}",
            "",
            "## 关联主题地图",
            *([f"- {link}" for link in topic_map_links] or ["- 暂无"]),
            "",
            "## 关联知识解读",
            *([f"- {link}" for link in insight_note_links] or ["- 暂无"]),
            "",
            "## 来源剪藏",
            *([f"- {link}" for link in source_note_links] or ["- 暂无"]),
            "",
            "## 证据与线索",
            evidence if has_value(evidence) else "暂无。",
            AUTO_END,
            "",
            normalize_manual_body(manual_body).rstrip(),
            "",
        ]
    )

    relative_note_path = vault_path_or_original(str(target_path), vault_path)
    return {
        "title": title,
        "file_name": file_name,
        "note_path": str(target_path),
        "relative_note_path": relative_note_path,
        "note_body": "\n".join(lines),
        "card_type": string_value(card.get("card_type"), default="concept"),
        "summary": summary,
        "evidence": evidence,
        "topic_names": topic_names,
        "topic_map_paths": topic_map_paths,
        "topic_map_links": topic_map_links,
        "source_note_paths": source_note_paths,
        "source_note_links": source_note_links,
        "insight_note_paths": insight_note_paths,
        "insight_note_links": insight_note_links,
        "tags": tags,
    }


def main() -> int:
    configure_console_output()

    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-json", required=True)
    parser.add_argument("--vault-path", default="")
    parser.add_argument("--vault-path-file", default="")
    parser.add_argument("--folder", default="")
    parser.add_argument("--folder-file", default="")
    parser.add_argument("--topic-map-folder", default="")
    parser.add_argument("--topic-map-folder-file", default="")
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    bundle = load_json(args.bundle_json)

    vault_path = string_value(args.vault_path)
    if not has_value(vault_path) and has_value(args.vault_path_file):
        vault_path = load_text(args.vault_path_file).strip()

    folder = string_value(args.folder)
    if not has_value(folder) and has_value(args.folder_file):
        folder = load_text(args.folder_file).strip()

    topic_map_folder = string_value(args.topic_map_folder)
    if not has_value(topic_map_folder) and has_value(args.topic_map_folder_file):
        topic_map_folder = load_text(args.topic_map_folder_file).strip()

    if not has_value(folder):
        raise SystemExit("--folder or --folder-file is required")
    if not has_value(topic_map_folder):
        raise SystemExit("--topic-map-folder or --topic-map-folder-file is required")

    rendered_cards = [
        build_card_note(card, bundle, vault_path, folder, topic_map_folder)
        for card in normalize_list(bundle.get("selected_cards"))
        if isinstance(card, dict)
    ]

    if not args.dry_run and has_value(vault_path):
        target_dir = Path(vault_path).joinpath(*[part for part in folder.replace("\\", "/").split("/") if part])
        target_dir.mkdir(parents=True, exist_ok=True)
        for card in rendered_cards:
            Path(card["note_path"]).write_text(card["note_body"], encoding="utf-8")

    result = {
        "success": True,
        "source_note_path": string_value(bundle.get("source_note_path")),
        "insight_note_path": string_value(bundle.get("insight_note_path")),
        "source_url": string_value(bundle.get("source_url")),
        "normalized_url": string_value(bundle.get("normalized_url")),
        "output_folder": folder,
        "topic_map_folder": topic_map_folder,
        "rendered_card_count": len(rendered_cards),
        "topic_names": dedupe_strings(
            [topic for card in rendered_cards for topic in normalize_list(card.get("topic_names")) if has_value(topic)]
        ),
        "rendered_cards": rendered_cards,
    }

    output_text = json.dumps(result, ensure_ascii=False, indent=2)
    Path(args.output_json).write_text(output_text, encoding="utf-8")
    print(output_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
