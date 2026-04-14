import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from topic_taxonomy import (
    canonicalize_topic_map_paths,
    canonicalize_topic_names,
    default_topic_name,
    load_topic_taxonomy,
    topic_map_relative_paths,
)


AUTO_START = "<!-- AUTO-GENERATED:STEP5:START -->"
AUTO_END = "<!-- AUTO-GENERATED:STEP5:END -->"
TOPIC_TAXONOMY = load_topic_taxonomy()
CATEGORY_LABELS = {
    "书籍作品": "书籍作品",
    "人物": "人物",
    "方法模型": "方法模型",
    "概念认知": "概念认知",
    "实践案例": "实践案例",
}


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
        if not has_value(normalized) or normalized in seen:
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
    return sanitized.strip() or "untitled"


def relative_vault_path(path_value: str, vault_path: str) -> str:
    if not has_value(path_value) or not has_value(vault_path):
        return ""
    try:
        candidate = Path(path_value).resolve()
        root = Path(vault_path).resolve()
        return candidate.relative_to(root).as_posix()
    except Exception:
        return ""


def vault_path_or_original(path_value: str, vault_path: str) -> str:
    relative = relative_vault_path(path_value, vault_path)
    return relative if has_value(relative) else string_value(path_value)


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
    data: dict[str, Any] = {}
    index = 1
    current_key = ""
    while index < len(lines):
        line = lines[index]
        if line == "---":
            return data, "\n".join(lines[index + 1 :]).strip()
        if line.startswith("  - ") and has_value(current_key):
            data.setdefault(current_key, []).append(line[4:].strip().strip("'"))
            index += 1
            continue
        if ":" in line:
            key, raw_value = line.split(":", 1)
            key = key.strip()
            raw_value = raw_value.strip()
            if raw_value == "":
                data[key] = []
                current_key = key
            else:
                data[key] = raw_value.strip("'")
                current_key = ""
        else:
            current_key = ""
        index += 1
    return {}, text


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


def build_target_path(vault_path: str, folder: str, category: str, file_name: str) -> Path:
    parts = [part for part in folder.replace("\\", "/").split("/") if part]
    parts.extend([part for part in category.replace("\\", "/").split("/") if part])
    return Path(vault_path).joinpath(*parts) / file_name


def predicted_topic_map_relative_paths(topic_names: list[str], folder: str) -> list[str]:
    return topic_map_relative_paths(topic_names, folder, TOPIC_TAXONOMY)


def merge_existing_list(existing_frontmatter: dict[str, Any], key: str, new_values: list[str], limit: int | None = None) -> list[str]:
    merged = dedupe_strings(
        [string_value(item) for item in normalize_list(existing_frontmatter.get(key)) if has_value(item)] + new_values
    )
    return merged if limit is None else merged[:limit]


def card_type_label(card_type: str) -> str:
    mapping = {"concept": "概念卡", "method": "方法卡", "tip": "技巧卡"}
    return mapping.get(string_value(card_type), "知识卡")


def build_card_note(
    card: dict[str, Any],
    bundle: dict[str, Any],
    vault_path: str,
    folder: str,
    topic_map_folder: str,
) -> dict[str, Any]:
    today = datetime.now().strftime("%Y-%m-%d")
    title = string_value(card.get("title"), default="未命名知识卡")
    category = string_value(card.get("folder_category"), card.get("category"), default="概念认知")
    category_label = CATEGORY_LABELS.get(category, category)
    file_name = safe_file_name(title) + ".md"
    target_path = build_target_path(vault_path, folder, category, file_name)

    existing_frontmatter: dict[str, Any] = {}
    manual_body = ""
    if target_path.exists():
        existing_frontmatter, existing_body = parse_frontmatter(target_path.read_text(encoding="utf-8"))
        manual_body = extract_manual_body(existing_body)

    source_note_path = string_value(bundle.get("source_note_path"))
    insight_note_path = string_value(bundle.get("insight_note_path"))
    topic_names = canonicalize_topic_names(
        [
            *normalize_list(existing_frontmatter.get("topic_names")),
            *[string_value(item) for item in normalize_list(card.get("topic_names")) if has_value(item)],
        ],
        taxonomy=TOPIC_TAXONOMY,
        default_topic="",
    )
    if not topic_names:
        topic_names = canonicalize_topic_names(
            normalize_list(card.get("topic_names")),
            taxonomy=TOPIC_TAXONOMY,
            default_topic=default_topic_name(TOPIC_TAXONOMY),
        )
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
    topic_map_paths = dedupe_strings(
        canonicalize_topic_map_paths(existing_frontmatter.get("topic_map_paths"), topic_map_folder, TOPIC_TAXONOMY)
        + predicted_topic_map_relative_paths(topic_names, topic_map_folder)
    )
    tags = merge_existing_list(
        existing_frontmatter,
        "tags",
        [string_value(item) for item in normalize_list(card.get("tags")) if has_value(item)],
        limit=5,
    )

    source_note_links = [obsidian_link(path, vault_path) for path in source_note_paths]
    insight_note_links = [obsidian_link(path, vault_path) for path in insight_note_paths]
    topic_map_links = [obsidian_link(path, vault_path) for path in topic_map_paths]

    created_at = string_value(existing_frontmatter.get("created_at"), default=today)
    summary = string_value(card.get("summary"), default="暂无")
    evidence = string_value(card.get("evidence"), default="")

    lines = [
        "---",
        f"title: {yaml_scalar(title)}",
        "note_type: 'knowledge_card'",
        f"card_type: {yaml_scalar(string_value(card.get('card_type'), default='concept'))}",
        f"card_category: {yaml_scalar(category_label)}",
        f"created_at: {yaml_scalar(created_at)}",
        f"updated_at: {yaml_scalar(today)}",
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
            "## 核心结论",
            summary,
            "",
            "## 分类信息",
            f"- 卡片类型: {card_type_label(string_value(card.get('card_type'), default='concept'))}",
            f"- 粗粒度分类: {category_label}",
            f"- 标签: {', '.join(tags) if tags else '暂无'}",
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
            evidence if has_value(evidence) else "暂无",
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
        "category": category_label,
        "folder_category": category,
        "summary": summary,
        "evidence": evidence,
        "topic_names": topic_names,
        "topic_map_paths": topic_map_paths,
        "source_note_paths": source_note_paths,
        "insight_note_paths": insight_note_paths,
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
        for card in rendered_cards:
            target_path = Path(card["note_path"])
            target_path.parent.mkdir(parents=True, exist_ok=True)
            target_path.write_text(card["note_body"], encoding="utf-8")

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
