import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from topic_taxonomy import canonicalize_topic_names, default_topic_name, load_topic_taxonomy


SOURCE_PREFIX_PATTERNS = [
    re.compile(r"^(本期节目|这期节目|本期播客|这期播客|节目里|节目中|播客里|播客中|主播提到|嘉宾提到|文章提到|作者提到)[，,:：\s]*"),
    re.compile(r"^(节目提出|节目认为|节目强调|节目分享|节目讨论|播客提出|播客强调)[，,:：\s]*"),
]
TOPIC_RULES = [
    ("阅读与学习", ("阅读", "读书", "学习", "笔记", "知识管理")),
    ("书籍与作品", ("书", "作品", "小说", "电影", "回忆录", "传记", "自传")),
    ("人物传记", ("人物", "名人", "传记", "自传", "演员", "作者")),
    ("决策与选择", ("决策", "选择", "转折", "机会", "绿灯", "红灯", "黄灯")),
    ("自我成长", ("成长", "改变", "勇气", "人生", "行动", "长期主义")),
    ("心理与情绪", ("心理", "情绪", "恐惧", "焦虑", "信心", "自我怀疑")),
    ("方法论", ("方法", "框架", "模型", "流程", "策略", "原则")),
    ("创作与表达", ("写作", "表达", "叙事", "讲故事", "创作")),
    ("电影与表演", ("电影", "表演", "演员", "奥斯卡", "好莱坞")),
    ("教育与养育", ("教育", "养育", "父母", "孩子")),
]
TAG_RULES = [
    ("阅读", ("阅读", "读书", "书单", "书")),
    ("书籍", ("书", "作品", "回忆录", "自传", "传记")),
    ("人物", ("人物", "名人", "作者", "演员")),
    ("人物传记", ("传记", "自传", "回忆录")),
    ("方法论", ("方法", "框架", "模型", "流程", "原则", "策略")),
    ("决策", ("决策", "选择", "转折", "机会", "判断")),
    ("自我成长", ("成长", "人生", "行动", "勇气", "改变")),
    ("心理成长", ("心理", "情绪", "恐惧", "焦虑", "信心")),
    ("创作", ("写作", "表达", "叙事", "创作")),
    ("教育", ("教育", "养育", "父母", "孩子")),
    ("电影与表演", ("电影", "表演", "演员", "奥斯卡")),
]
CATEGORY_FOLDERS = {
    "书籍作品": "书籍作品",
    "人物": "人物",
    "方法模型": "方法模型",
    "概念认知": "概念认知",
    "实践案例": "实践案例",
}
CATEGORY_TAGS = {
    "书籍作品": ["书籍", "阅读", "观点提炼"],
    "人物": ["人物", "人物传记", "自我成长"],
    "方法模型": ["方法论", "实践", "学习方法"],
    "概念认知": ["认知", "自我成长", "方法论"],
    "实践案例": ["实践", "案例", "方法论"],
}
WORK_PATTERN = re.compile(r"《([^》]{1,40})》")
TOPIC_TAXONOMY = load_topic_taxonomy()


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


def normalize_text_for_matching(value: str) -> str:
    return re.sub(r"\s+", "", string_value(value).lower())


def sanitize_text(value: str) -> str:
    text = string_value(value)
    if not has_value(text):
        return ""
    for pattern in SOURCE_PREFIX_PATTERNS:
        text = pattern.sub("", text)
    text = re.sub(r"\s+", " ", text).strip(" ，,。；;：:！!？?、")
    return text


def topic_matches(text: str) -> list[str]:
    return canonicalize_topic_names([text], taxonomy=TOPIC_TAXONOMY, default_topic="")


def normalize_topic_names(values: Any) -> list[str]:
    return canonicalize_topic_names(values, taxonomy=TOPIC_TAXONOMY, default_topic="")


def find_named_works(analysis: dict[str, Any]) -> list[str]:
    weighted_texts = [
        (string_value(analysis.get("title")), 1),
        (string_value(analysis.get("content_summary")), 3),
        (string_value(analysis.get("summary")), 2),
        (" ".join(string_value(item.get("text"), item.get("point"), item) if isinstance(item, dict) else string_value(item) for item in normalize_list(analysis.get("core_points"))), 3),
        (string_value(analysis.get("raw_text")), 2),
        (string_value(analysis.get("transcript")), 2),
    ]
    scores: dict[str, int] = {}
    for text, weight in weighted_texts:
        if not has_value(text):
            continue
        for match in WORK_PATTERN.finditer(text):
            work = string_value(match.group(1))
            if has_value(work):
                scores[work] = scores.get(work, 0) + weight
    ranked = sorted(scores.items(), key=lambda item: (-item[1], item[0]))
    return [work for work, score in ranked if score >= 2] or [work for work, _ in ranked]


def infer_card_type(title: str, summary: str) -> str:
    text = normalize_text_for_matching(" ".join([title, summary]))
    if any(token in text for token in ("如何", "怎么", "步骤", "流程", "方法", "框架", "模型", "策略", "原则")):
        return "method"
    if any(token in text for token in ("技巧", "建议", "提示", "经验", "窍门", "清单")):
        return "tip"
    return "concept"


def infer_card_category(title: str, summary: str, card_type: str, works: list[str]) -> str:
    normalized = normalize_text_for_matching(" ".join([title, summary]))
    if any(work and work in title for work in works):
        return "书籍作品"
    if any(token in normalized for token in ("作者", "演员", "人物", "名人", "马修")):
        return "人物"
    if card_type == "method" or any(token in normalized for token in ("方法", "框架", "模型", "流程", "原则")):
        return "方法模型"
    if any(token in normalized for token in ("案例", "例子", "经历", "故事", "实践")):
        return "实践案例"
    return "概念认知"


def normalize_candidate_tags(value: Any) -> list[str]:
    return dedupe_strings([sanitize_text(string_value(item)) for item in normalize_list(value) if has_value(item)])


def normalize_card_candidate(item: Any, works: list[str]) -> dict[str, Any] | None:
    if isinstance(item, str):
        title = sanitize_text(item)
        summary = ""
        evidence = ""
        tags: list[str] = []
    elif isinstance(item, dict):
        title = sanitize_text(string_value(item.get("title"), item.get("name")))
        summary = sanitize_text(string_value(item.get("summary"), item.get("detail"), item.get("description")))
        evidence = sanitize_text(string_value(item.get("evidence"), item.get("reason")))
        tags = normalize_candidate_tags(item.get("tags"))
    else:
        return None
    if not has_value(title):
        return None
    card_type = infer_card_type(title, summary)
    category = infer_card_category(title, summary, card_type, works)
    return {
        "title": title,
        "summary": summary,
        "evidence": evidence,
        "tags": tags,
        "card_type": card_type,
        "category": category,
    }


def fallback_candidates_from_analysis(analysis: dict[str, Any], works: list[str]) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    for item in normalize_list(analysis.get("methods")):
        if not isinstance(item, dict):
            continue
        name = sanitize_text(string_value(item.get("name"), item.get("title")))
        summary = sanitize_text(string_value(item.get("summary"), item.get("detail"), item.get("description")))
        steps = [sanitize_text(string_value(step)) for step in normalize_list(item.get("steps")) if has_value(step)]
        detail = summary
        if steps:
            detail = (detail + " 步骤：" + " -> ".join(steps)).strip()
        if has_value(name):
            candidates.append(
                {
                    "title": name,
                    "summary": detail,
                    "evidence": "",
                    "tags": ["方法论"],
                    "card_type": "method",
                    "category": infer_card_category(name, detail, "method", works),
                }
            )

    for item in normalize_list(analysis.get("concepts")):
        if isinstance(item, dict):
            title = sanitize_text(string_value(item.get("name"), item.get("title")))
            summary = sanitize_text(string_value(item.get("summary"), item.get("detail"), item.get("description")))
        else:
            title = sanitize_text(string_value(item))
            summary = ""
        if has_value(title):
            candidates.append(
                {
                    "title": title,
                    "summary": summary,
                    "evidence": "",
                    "tags": [],
                    "card_type": infer_card_type(title, summary),
                    "category": infer_card_category(title, summary, infer_card_type(title, summary), works),
                }
            )

    for item in normalize_list(analysis.get("tips_and_facts")):
        if isinstance(item, dict):
            title = sanitize_text(string_value(item.get("point"), item.get("name"), item.get("title")))
            summary = sanitize_text(string_value(item.get("detail"), item.get("summary"), item.get("description")))
        else:
            title = sanitize_text(string_value(item))
            summary = ""
        if has_value(title):
            candidates.append(
                {
                    "title": title,
                    "summary": summary,
                    "evidence": "",
                    "tags": ["方法论"] if "方法" in title else ["实践"],
                    "card_type": "tip",
                    "category": infer_card_category(title, summary, "tip", works),
                }
            )
    return candidates


def build_work_centric_candidates(analysis: dict[str, Any], works: list[str]) -> list[dict[str, Any]]:
    if not works:
        return []
    summary = sanitize_text(string_value(analysis.get("content_summary"), analysis.get("summary")))
    core_points: list[str] = []
    for item in normalize_list(analysis.get("core_points")):
        if isinstance(item, dict):
            text = sanitize_text(string_value(item.get("text"), item.get("point"), item.get("summary")))
        else:
            text = sanitize_text(string_value(item))
        if has_value(text):
            core_points.append(text)
    core_points = [item for item in core_points if has_value(item)]
    candidates: list[dict[str, Any]] = []
    for work in works[:2]:
        if has_value(summary):
            candidates.append(
                {
                    "title": f"《{work}》讲了什么",
                    "summary": summary,
                    "evidence": "",
                    "tags": ["书籍", "阅读"],
                    "card_type": "concept",
                    "category": "书籍作品",
                }
            )
        if core_points:
            candidates.append(
                {
                    "title": f"《{work}》的关键观点",
                    "summary": "；".join(core_points[:3]),
                    "evidence": "",
                    "tags": ["书籍", "观点提炼"],
                    "card_type": "concept",
                    "category": "书籍作品",
                }
            )
    return candidates


def score_card(card: dict[str, Any], works: list[str]) -> int:
    title = string_value(card.get("title"))
    summary = string_value(card.get("summary"))
    score = 0
    if 4 <= len(title) <= 30:
        score += 2
    if len(summary) >= 18:
        score += 3
    if len(summary) >= 40:
        score += 2
    if string_value(card.get("card_type")) == "method":
        score += 2
    if any(work and work in title for work in works):
        score += 3
    if string_value(card.get("category")) == "书籍作品":
        score += 1
    return score


def derive_topics(card: dict[str, Any], analysis_topics: list[str]) -> list[str]:
    matches = topic_matches(" ".join([string_value(card.get("title")), string_value(card.get("summary")), string_value(card.get("evidence"))]))
    topics = dedupe_strings([*matches, *analysis_topics])
    if topics:
        return topics[:3]
    return [default_topic_name(TOPIC_TAXONOMY)]


def derive_tags(card: dict[str, Any], topic_names: list[str]) -> list[str]:
    text = " ".join([string_value(card.get("title")), string_value(card.get("summary")), *topic_names])
    tags: list[str] = []
    for tag_name, keywords in TAG_RULES:
        if any(keyword in text for keyword in keywords):
            tags.append(tag_name)
    tags.extend(normalize_candidate_tags(card.get("tags")))
    tags.extend(topic_names[:2])
    tags.extend(CATEGORY_TAGS.get(string_value(card.get("category")), []))
    normalized = dedupe_strings([sanitize_text(tag) for tag in tags if has_value(tag)])
    if len(normalized) < 3:
        normalized = dedupe_strings(normalized + CATEGORY_TAGS.get(string_value(card.get("category")), []))
    return normalized[:5]


def select_cards(analysis: dict[str, Any], max_cards: int) -> tuple[list[dict[str, Any]], list[str], list[str]]:
    works = find_named_works(analysis)
    analysis_topics = normalize_topic_names(analysis.get("topic_candidates"))
    explicit = [normalize_card_candidate(item, works) for item in normalize_list(analysis.get("knowledge_cards"))]
    candidates = [item for item in explicit if item is not None]
    candidates.extend(build_work_centric_candidates(analysis, works))
    candidates.extend(fallback_candidates_from_analysis(analysis, works))

    unique: dict[str, dict[str, Any]] = {}
    for card in candidates:
        key = normalize_text_for_matching(string_value(card.get("title")))
        if not has_value(key):
            continue
        candidate_score = score_card(card, works)
        existing = unique.get(key)
        if existing is None or candidate_score > int(existing.get("_score", 0)):
            unique[key] = {**card, "_score": candidate_score}

    selected: list[dict[str, Any]] = []
    for card in sorted(unique.values(), key=lambda item: (-int(item.get("_score", 0)), string_value(item.get("title")))):
        topic_names = derive_topics(card, analysis_topics)
        tags = derive_tags(card, topic_names)
        selected.append(
            {
                "title": string_value(card.get("title")),
                "summary": string_value(card.get("summary")),
                "evidence": string_value(card.get("evidence")),
                "card_type": string_value(card.get("card_type"), default="concept"),
                "category": string_value(card.get("category"), default="概念认知"),
                "folder_category": CATEGORY_FOLDERS.get(string_value(card.get("category")), "概念认知"),
                "topic_names": topic_names,
                "tags": tags[:5],
            }
        )
        if len(selected) >= max(1, max_cards):
            break
    return selected, analysis_topics, works


def main() -> int:
    configure_console_output()

    parser = argparse.ArgumentParser()
    parser.add_argument("--analysis-json", required=True)
    parser.add_argument("--insight-note-path", required=True)
    parser.add_argument("--max-cards", type=int, default=5)
    parser.add_argument("--output-json", required=True)
    args = parser.parse_args()

    analysis = load_json(args.analysis_json)
    selected_cards, analysis_topics, works = select_cards(analysis, args.max_cards)
    distinct_topics = dedupe_strings([topic for card in selected_cards for topic in normalize_list(card.get("topic_names")) if has_value(topic)])

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
        "named_works": works,
        "analysis_topic_names": analysis_topics,
        "selected_card_count": len(selected_cards),
        "selected_cards": selected_cards,
        "topic_names": distinct_topics,
        "topic_map_count": len(distinct_topics),
    }

    output_text = json.dumps(result, ensure_ascii=False, indent=2)
    Path(args.output_json).write_text(output_text, encoding="utf-8")
    print(output_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
