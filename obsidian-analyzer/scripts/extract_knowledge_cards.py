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


def normalize_topic_names(values: Any) -> list[str]:
    names: list[str] = []
    for item in normalize_list(values):
        if isinstance(item, dict):
            name = string_value(item.get("name"), item.get("title"), item.get("topic"))
        else:
            name = string_value(item)
        if has_value(name):
            names.append(name)
    return dedupe_strings(names)


def normalize_text_for_matching(value: str) -> str:
    return re.sub(r"\s+", "", string_value(value).lower())


def topic_aliases(topic_name: str) -> list[str]:
    text = string_value(topic_name)
    aliases = [text]
    aliases.extend(re.findall(r"[A-Za-z0-9][A-Za-z0-9 _-]*", text))
    aliases.extend(re.split(r"[()（）/|、，,]", text))
    normalized = [normalize_text_for_matching(alias) for alias in aliases if has_value(alias)]
    return dedupe_strings([alias for alias in normalized if has_value(alias)])


def infer_card_type(title: str, summary: str, tags: list[str]) -> str:
    text = " ".join([title, summary, *tags]).lower()
    if any(
        token in text
        for token in (
            "如何",
            "怎么",
            "怎样",
            "步骤",
            "流程",
            "方法",
            "框架",
            "清单",
            "workflow",
            "how ",
            "process",
            "playbook",
        )
    ):
        return "method"
    if any(
        token in text
        for token in (
            "技巧",
            "经验",
            "建议",
            "提示",
            "窍门",
            "heuristic",
            "tip",
            "best practice",
        )
    ):
        return "tip"
    return "concept"


def score_card(title: str, summary: str, tags: list[str], card_type: str) -> int:
    score = 0
    title_length = len(title)
    summary_length = len(summary)
    if 4 <= title_length <= 40:
        score += 2
    elif has_value(title):
        score += 1
    if summary_length >= 40:
        score += 4
    elif summary_length >= 20:
        score += 2
    elif summary_length >= 8:
        score += 1
    if tags:
        score += 1
    if card_type == "method":
        score += 2
    elif card_type == "tip":
        score += 1
    if re.search(r"(什么是|如何|为什么|何时|怎样|怎么|[?？])", title):
        score += 1
    return score


def normalize_candidate_tags(value: Any) -> list[str]:
    return dedupe_strings([string_value(item) for item in normalize_list(value) if has_value(item)])


def normalize_card_candidate(item: Any) -> dict[str, Any] | None:
    if isinstance(item, str):
        title = string_value(item)
        if not has_value(title):
            return None
        summary = ""
        evidence = ""
        tags: list[str] = []
    elif isinstance(item, dict):
        title = string_value(item.get("title"), item.get("name"))
        summary = string_value(item.get("summary"), item.get("detail"), item.get("description"))
        evidence = string_value(item.get("evidence"), item.get("reason"))
        tags = normalize_candidate_tags(item.get("tags"))
    else:
        return None
    if not has_value(title):
        return None
    card_type = infer_card_type(title, summary, tags)
    return {
        "title": title,
        "summary": summary,
        "evidence": evidence,
        "tags": tags,
        "card_type": card_type,
        "score": score_card(title, summary, tags, card_type),
    }


def fallback_candidates_from_analysis(analysis: dict[str, Any]) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []

    for item in normalize_list(analysis.get("methods")):
        if not isinstance(item, dict):
            continue
        name = string_value(item.get("name"), item.get("title"))
        summary = string_value(item.get("summary"), item.get("detail"), item.get("description"))
        steps = [string_value(step) for step in normalize_list(item.get("steps")) if has_value(step)]
        if not has_value(name):
            continue
        detail = summary
        if steps:
            steps_text = " -> ".join(steps)
            detail = string_value(detail, default="")
            detail = f"{detail} 步骤: {steps_text}".strip()
        tags = ["method"]
        candidates.append(
            {
                "title": name,
                "summary": detail,
                "evidence": "",
                "tags": tags,
                "card_type": "method",
                "score": score_card(name, detail, tags, "method"),
            }
        )

    for item in normalize_list(analysis.get("concepts")):
        if isinstance(item, dict):
            name = string_value(item.get("name"), item.get("title"))
            summary = string_value(item.get("summary"), item.get("detail"), item.get("description"))
        else:
            name = string_value(item)
            summary = ""
        if not has_value(name):
            continue
        tags = ["concept"]
        candidates.append(
            {
                "title": name,
                "summary": summary,
                "evidence": "",
                "tags": tags,
                "card_type": "concept",
                "score": score_card(name, summary, tags, "concept"),
            }
        )

    for item in normalize_list(analysis.get("tips_and_facts")):
        if isinstance(item, dict):
            title = string_value(item.get("point"), item.get("name"), item.get("title"))
            summary = string_value(item.get("detail"), item.get("summary"), item.get("description"))
        else:
            title = string_value(item)
            summary = ""
        if not has_value(title):
            continue
        tags = ["tip"]
        candidates.append(
            {
                "title": title,
                "summary": summary,
                "evidence": "",
                "tags": tags,
                "card_type": "tip",
                "score": score_card(title, summary, tags, "tip"),
            }
        )

    return candidates


def assign_topics(card: dict[str, Any], topic_names: list[str]) -> list[str]:
    if not topic_names:
        return ["未分类主题"]

    title = normalize_text_for_matching(string_value(card.get("title")))
    summary = normalize_text_for_matching(string_value(card.get("summary")))
    tags = [normalize_text_for_matching(tag) for tag in normalize_list(card.get("tags")) if has_value(tag)]

    matched: list[str] = []
    for topic in topic_names:
        aliases = topic_aliases(topic)
        if any(alias and (alias in title or alias in summary or alias in tags) for alias in aliases):
            matched.append(topic)

    if matched:
        return dedupe_strings(matched)[:3]
    if len(topic_names) >= 2:
        return topic_names[:2]
    return topic_names[:1]


def select_cards(analysis: dict[str, Any], max_cards: int) -> list[dict[str, Any]]:
    raw_candidates = [normalize_card_candidate(item) for item in normalize_list(analysis.get("knowledge_cards"))]
    candidates = [candidate for candidate in raw_candidates if candidate is not None]
    if not candidates:
        candidates = fallback_candidates_from_analysis(analysis)

    unique: dict[str, dict[str, Any]] = {}
    for candidate in candidates:
        title = string_value(candidate.get("title"))
        if not has_value(title):
            continue
        key = title.lower()
        existing = unique.get(key)
        if existing is None or int(candidate.get("score", 0)) > int(existing.get("score", 0)):
            unique[key] = candidate

    sorted_candidates = sorted(
        unique.values(),
        key=lambda item: (-int(item.get("score", 0)), string_value(item.get("title"))),
    )
    return sorted_candidates[: max(1, max_cards)]


def main() -> int:
    configure_console_output()

    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-json", required=True)
    parser.add_argument("--insight-note-path", required=True)
    parser.add_argument("--max-cards", type=int, default=5)
    parser.add_argument("--output-json", required=True)
    args = parser.parse_args()

    analysis = load_json(args.analysis_json)
    topic_names = normalize_topic_names(analysis.get("topic_candidates"))
    selected_cards: list[dict[str, Any]] = []

    for candidate in select_cards(analysis, args.max_cards):
        card_topics = assign_topics(candidate, topic_names)
        tags = dedupe_strings(
            [
                *normalize_candidate_tags(candidate.get("tags")),
                "knowledge-card",
                string_value(candidate.get("card_type"), default="concept"),
                *card_topics,
            ]
        )
        selected_cards.append(
            {
                "title": string_value(candidate.get("title")),
                "summary": string_value(candidate.get("summary")),
                "evidence": string_value(candidate.get("evidence")),
                "card_type": string_value(candidate.get("card_type"), default="concept"),
                "topic_names": card_topics,
                "tags": tags,
            }
        )

    distinct_topic_names = dedupe_strings(
        [topic for card in selected_cards for topic in normalize_list(card.get("topic_names")) if has_value(topic)]
    )

    result = {
        "success": True,
        "analysis_mode": string_value(analysis.get("analysis_mode"), default="knowledge"),
        "analysis_goal": string_value(analysis.get("analysis_goal"), default="knowledge"),
        "title": string_value(analysis.get("title")),
        "source_note_path": string_value(analysis.get("source_note_path")),
        "insight_note_path": string_value(args.insight_note_path),
        "capture_json_path": string_value(analysis.get("capture_json_path")),
        "source_url": string_value(analysis.get("source_url")),
        "normalized_url": string_value(analysis.get("normalized_url")),
        "platform": string_value(analysis.get("platform")),
        "content_type": string_value(analysis.get("content_type")),
        "route": string_value(analysis.get("route")),
        "capture_id": string_value(analysis.get("capture_id")),
        "author": string_value(analysis.get("author")),
        "published_at": string_value(analysis.get("published_at")),
        "selected_card_count": len(selected_cards),
        "selected_cards": selected_cards,
        "topic_names": distinct_topic_names,
        "topic_map_count": len(distinct_topic_names),
    }

    output_text = json.dumps(result, ensure_ascii=False, indent=2)
    Path(args.output_json).write_text(output_text, encoding="utf-8")
    print(output_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
