import json
import re
from pathlib import Path
from typing import Any


DEFAULT_TAXONOMY_PATH = Path(__file__).resolve().parent.parent / "references" / "topic-taxonomy.json"


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


def normalize_text_for_matching(value: str) -> str:
    return re.sub(r"[\s_\-./\\]+", "", string_value(value).lower())


def clean_topic_candidate(value: str) -> str:
    text = string_value(value)
    if not has_value(text):
        return ""
    stem = Path(text).stem if "/" in text or "\\" in text or text.lower().endswith(".md") else text
    stem = re.sub(r"^[#\-\s]+", "", stem)
    stem = re.sub(r"[\s,.;:!?，。；：！？]+$", "", stem)
    return stem.strip()


def load_topic_taxonomy(path: str | Path | None = None) -> dict[str, Any]:
    taxonomy_path = Path(path) if path else DEFAULT_TAXONOMY_PATH
    return json.loads(taxonomy_path.read_text(encoding="utf-8"))


def canonical_topics(taxonomy: dict[str, Any]) -> list[dict[str, Any]]:
    topics = taxonomy.get("canonical_topics")
    return topics if isinstance(topics, list) else []


def default_topic_name(taxonomy: dict[str, Any], default: str = "阅读与学习") -> str:
    return string_value(taxonomy.get("default_topic"), default=default)


def topic_aliases(topic_name: str, taxonomy: dict[str, Any]) -> list[str]:
    target = normalize_text_for_matching(topic_name)
    for topic in canonical_topics(taxonomy):
        name = string_value(topic.get("name"))
        if normalize_text_for_matching(name) != target:
            continue
        aliases = [name]
        aliases.extend([string_value(item) for item in normalize_list(topic.get("aliases")) if has_value(item)])
        return dedupe_strings(aliases)
    return [string_value(topic_name)] if has_value(topic_name) else []


def exact_alias_map(taxonomy: dict[str, Any]) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for topic in canonical_topics(taxonomy):
        canonical = string_value(topic.get("name"))
        if not has_value(canonical):
            continue
        for alias in topic_aliases(canonical, taxonomy):
            normalized = normalize_text_for_matching(alias)
            if has_value(normalized):
                mapping[normalized] = canonical
    return mapping


def canonical_topic_name(value: str, taxonomy: dict[str, Any], default: str = "") -> str:
    candidate = clean_topic_candidate(value)
    normalized = normalize_text_for_matching(candidate)
    if not has_value(normalized):
        return string_value(default)

    alias_map = exact_alias_map(taxonomy)
    if normalized in alias_map:
        return alias_map[normalized]

    best_name = ""
    best_score = 0
    for topic in canonical_topics(taxonomy):
        canonical = string_value(topic.get("name"))
        if not has_value(canonical):
            continue

        score = 0
        for alias in topic_aliases(canonical, taxonomy):
            alias_normalized = normalize_text_for_matching(alias)
            if not has_value(alias_normalized):
                continue
            if alias_normalized in normalized or normalized in alias_normalized:
                score = max(score, len(alias_normalized) + 6)

        for keyword in normalize_list(topic.get("keywords")):
            keyword_text = normalize_text_for_matching(string_value(keyword))
            if not has_value(keyword_text):
                continue
            if keyword_text in normalized:
                score += len(keyword_text)

        if score > best_score:
            best_name = canonical
            best_score = score

    if best_score > 0:
        return best_name
    return string_value(default)


def canonicalize_topic_names(
    values: Any,
    taxonomy: dict[str, Any],
    default_topic: str = "",
    limit: int | None = None,
) -> list[str]:
    result: list[str] = []
    fallback = string_value(default_topic)
    for item in normalize_list(values):
        if isinstance(item, dict):
            text = string_value(item.get("name"), item.get("title"), item.get("topic"))
        else:
            text = string_value(item)
        canonical = canonical_topic_name(text, taxonomy, default=fallback)
        if has_value(canonical):
            result.append(canonical)
    deduped = dedupe_strings(result)
    return deduped if limit is None else deduped[:limit]


def topic_map_relative_paths(topic_names: list[str], folder: str, taxonomy: dict[str, Any]) -> list[str]:
    folder_normalized = "/".join([part for part in folder.replace("\\", "/").split("/") if part])
    canonical_names = canonicalize_topic_names(topic_names, taxonomy, default_topic="", limit=None)
    return [
        f"{folder_normalized}/{safe_file_name(topic_name)}.md"
        for topic_name in canonical_names
        if has_value(topic_name)
    ]


def canonicalize_topic_map_paths(paths: Any, folder: str, taxonomy: dict[str, Any]) -> list[str]:
    topic_names = [clean_topic_candidate(string_value(path)) for path in normalize_list(paths) if has_value(path)]
    canonical_names = canonicalize_topic_names(topic_names, taxonomy, default_topic="", limit=None)
    return topic_map_relative_paths(canonical_names, folder, taxonomy)


def safe_file_name(value: str) -> str:
    invalid = set('<>:"/\\|?*')
    sanitized = "".join("_" if ch in invalid else ch for ch in value)
    return sanitized.strip() or "untitled"
