import argparse
import inspect
import json
import os
import re
import sys
import tempfile
from collections import OrderedDict
from pathlib import Path
from typing import Any


INTRO_WINDOW_SECONDS = 8 * 60
INTRO_WINDOW_SEGMENTS = 80
DEFAULT_SPEAKER_PREFIX = "Speaker"
SPLIT_SEGMENT_MIN_SECONDS = 3.2
SPLIT_FRAGMENT_MIN_SECONDS = 0.45
SPLIT_FRAGMENT_MIN_RATIO = 0.14
MERGE_GAP_SECONDS = 0.35
SPARSE_TURN_RESCUE_SHARE_THRESHOLD = 0.06
SPARSE_TURN_RESCUE_SECONDS_THRESHOLD = 120.0
SPARSE_TURN_RESCUE_MIN_OVERLAP_SECONDS = 0.28
SPARSE_TURN_RESCUE_MIN_WINDOW_SECONDS = 1.05
SPARSE_TURN_RESCUE_MERGE_GAP_SECONDS = 0.22
SPARSE_TURN_RESCUE_MAX_WINDOWS_PER_SEGMENT = 6
DEFAULT_REFINEMENT_STRATEGY = "embedding_agglomerative"
DEFAULT_REFINEMENT_TURN_MIN_SECONDS = 1.2
DEFAULT_REFINEMENT_WINDOW_SECONDS = 3.2
DEFAULT_REFINEMENT_BATCH_SIZE = 24
DEFAULT_REFINEMENT_MAX_TURNS = 600
INVALID_NAME_TOKENS = {
    "大家",
    "大家好",
    "我们",
    "你们",
    "自己",
    "今天",
    "本期",
    "这期",
    "节目",
    "播客",
    "这里",
    "这个",
    "那个",
    "什么",
    "一下",
    "内容",
    "方法",
    "问题",
    "老师",
    "朋友",
    "同学",
    "听友",
    "观众",
    "读者",
    "作者",
    "主持人",
    "主播",
    "嘉宾",
}
SELF_INTRO_PATTERNS = [
    re.compile(r"(?:^|[，。！？!?,\s])(?:大家好|哈喽|你好|欢迎来到[^，。！？!?,]{0,24}|欢迎收听[^，。！？!?,]{0,24}|这里是[^，。！？!?,]{0,24})?[，,、\s]*(?:我是|我叫|可以叫我|叫我)(?P<name>[\u4e00-\u9fffA-Za-z][\u4e00-\u9fffA-Za-z0-9·]{0,7})"),
    re.compile(r"(?:^|[，。！？!?,\s])(?:主持人|主播|嘉宾)?[：:\s]*(?:我是|我叫)(?P<name>[\u4e00-\u9fffA-Za-z][\u4e00-\u9fffA-Za-z0-9·]{0,7})"),
]
SPEAKER_COUNT_PATTERNS = [
    re.compile(r"我们(?P<count>[零一二两三四五六七八九十\d]+)个人"),
    re.compile(r"(?P<count>[零一二两三四五六七八九十\d]+)位(?:嘉宾|主播|主持人|朋友|人)"),
    re.compile(r"(?:请到|邀请到|来了)(?P<count>[零一二两三四五六七八九十\d]+)位"),
]
CHINESE_DIGITS = {
    "零": 0,
    "一": 1,
    "二": 2,
    "两": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
}


def configure_console_output() -> None:
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream is None:
            continue
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(encoding="utf-8", errors="backslashreplace")


def configure_runtime_environment() -> None:
    if not has_value(os.environ.get("MPLCONFIGDIR")):
        matplotlib_dir = Path(tempfile.gettempdir()) / "pyannote-matplotlib"
        matplotlib_dir.mkdir(parents=True, exist_ok=True)
        os.environ["MPLCONFIGDIR"] = str(matplotlib_dir)


def has_value(value: Any) -> bool:
    return value is not None and str(value).strip() != ""


def string_value(*values: Any, default: str = "") -> str:
    for value in values:
        if has_value(value):
            return str(value).strip()
    return default


def require_cuda_runtime(device: str, component_name: str) -> None:
    requested_device = string_value(device, default="").lower()
    if requested_device != "cuda":
        raise RuntimeError(f"{component_name} is locked to GPU-only. --device must be cuda.")

    try:
        import torch
    except ImportError as exc:
        raise RuntimeError(f"{component_name} is locked to GPU-only, but torch is not installed.") from exc

    if not torch.cuda.is_available():
        raise RuntimeError(
            f"{component_name} is locked to GPU-only, but torch.cuda.is_available() is False in the active Python environment."
        )


def read_text(path: Path) -> str:
    encodings = ("utf-8-sig", "utf-8", "gb18030")
    last_error: Exception | None = None
    for encoding in encodings:
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError as exc:
            last_error = exc
    if last_error is not None:
        raise last_error
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> Any:
    return json.loads(read_text(path))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def float_value(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def int_value(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def bool_value(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    text = string_value(value).lower()
    if text in {"true", "1", "yes", "on"}:
        return True
    if text in {"false", "0", "no", "off"}:
        return False
    return default


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


def format_timestamp(seconds: float) -> str:
    total_seconds = max(0, int(float_value(seconds)))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def join_text_parts(left: str, right: str) -> str:
    left_text = string_value(left)
    right_text = string_value(right)
    if not has_value(left_text):
        return right_text
    if not has_value(right_text):
        return left_text
    separator = "" if left_text.endswith((" ", "\n")) or right_text.startswith((" ", "\n")) else " "
    return f"{left_text}{separator}{right_text}".strip()


def normalize_segments(raw: Any) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    if not isinstance(raw, list):
        return normalized
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            continue
        normalized.append(
            {
                **item,
                "index": int(item.get("index", index)),
                "start": round(float_value(item.get("start")), 3),
                "end": round(float_value(item.get("end")), 3),
                "timestamp": string_value(item.get("timestamp")),
                "raw_text": string_value(item.get("raw_text")),
                "text": string_value(item.get("text")),
                "speaker_id": string_value(item.get("speaker_id")),
                "speaker": string_value(item.get("speaker")),
            }
        )
    return normalized


def normalize_turns(raw: Any) -> list[dict[str, Any]]:
    entries = raw.get("turns") if isinstance(raw, dict) and isinstance(raw.get("turns"), list) else raw
    normalized: list[dict[str, Any]] = []
    if not isinstance(entries, list):
        return normalized
    for item in entries:
        if not isinstance(item, dict):
            continue
        start = round(float_value(item.get("start")), 3)
        end = round(float_value(item.get("end")), 3)
        speaker_id = string_value(
            item.get("speaker_id"),
            item.get("speaker"),
            item.get("label"),
            item.get("name"),
        )
        if end <= start or not has_value(speaker_id):
            continue
        normalized.append({"start": start, "end": end, "speaker_id": speaker_id})
    return normalized


def normalize_manual_speakers(raw: Any) -> dict[str, dict[str, Any]]:
    if isinstance(raw, dict):
        items = raw.get("speaker_map")
        if not isinstance(items, list):
            items = raw.get("speakers")
    elif isinstance(raw, list):
        items = raw
    else:
        items = []

    result: dict[str, dict[str, Any]] = {}
    for item in items:
        if isinstance(item, str):
            key = item.strip()
            if has_value(key):
                result[key] = {
                    "speaker_id": key,
                    "speaker": key,
                    "display_name": key,
                    "role": "",
                    "notes": "",
                    "name_source": "manual",
                }
            continue
        if not isinstance(item, dict):
            continue
        speaker_id = string_value(item.get("speaker_id"), item.get("id"), item.get("raw_speaker"))
        display_name = string_value(item.get("speaker"), item.get("display_name"), item.get("name"))
        if not has_value(speaker_id) and has_value(display_name):
            speaker_id = display_name
        if not has_value(speaker_id):
            continue
        if not has_value(display_name):
            display_name = speaker_id
        result[speaker_id] = {
            "speaker_id": speaker_id,
            "speaker": display_name,
            "display_name": display_name,
            "role": string_value(item.get("role")),
            "notes": string_value(item.get("notes")),
            "name_source": string_value(item.get("name_source"), default="manual"),
        }
    return result


def normalize_name_candidate(raw_name: str) -> str:
    text = string_value(raw_name)
    if not has_value(text):
        return ""
    text = re.sub(r"^[“”\"'‘’《》【】\[\]()（）<>\s:：,，、。.!！？-]+", "", text)
    text = re.sub(r"[“”\"'‘’《》【】\[\]()（）<>\s:：,，、。.!！？-]+$", "", text)
    text = re.sub(r"^(主持人|主播|嘉宾|作者|朋友|同学|老师)", "", text)
    text = re.sub(r"(主持人|主播|嘉宾|作者|朋友|同学|老师)$", "", text)
    text = text.strip()
    if not has_value(text) or len(text) > 8 or text.isdigit():
        return ""
    if text in INVALID_NAME_TOKENS:
        return ""
    if re.search(r"(节目|播客|评论|链接|内容|方法|问题|故事|作品|今天|本期|这期|这里)", text):
        return ""
    return text


def intro_window_segments(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        segment
        for segment in segments
        if int(segment.get("index", 0)) < INTRO_WINDOW_SEGMENTS and float_value(segment.get("start")) <= INTRO_WINDOW_SECONDS
    ]


def extract_self_intro_phrases(text: str) -> list[dict[str, Any]]:
    source_text = string_value(text)
    phrases: list[dict[str, Any]] = []
    seen_spans: set[tuple[int, int, str]] = set()
    if not has_value(source_text):
        return phrases
    for pattern in SELF_INTRO_PATTERNS:
        for match in pattern.finditer(source_text):
            name = normalize_name_candidate(match.group("name"))
            if not has_value(name):
                continue
            phrase_start = match.start()
            phrase_end = match.end()
            while phrase_start < phrase_end and source_text[phrase_start] in " \t\r\n，。！？!?,、:：;；":
                phrase_start += 1
            key = (match.start("name"), match.end("name"), name)
            if key in seen_spans:
                continue
            seen_spans.add(key)
            phrases.append(
                {
                    "phrase_start": phrase_start,
                    "phrase_end": phrase_end,
                    "name_start": match.start("name"),
                    "name_end": match.end("name"),
                    "name": name,
                    "phrase_text": source_text[phrase_start:phrase_end].strip(),
                }
            )
    phrases.sort(key=lambda item: int(item.get("name_start", 0)))
    return phrases


def extract_self_intro_matches(text: str) -> list[tuple[int, int, str]]:
    matches: list[tuple[int, int, str]] = []
    for phrase in extract_self_intro_phrases(text):
        matches.append(
            (
                int(phrase.get("name_start", 0)),
                int(phrase.get("name_end", 0)),
                string_value(phrase.get("name")),
            )
        )
    matches.sort(key=lambda item: item[0])
    return matches


def extract_intro_mentions(segments: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[str]]:
    mentions: list[dict[str, Any]] = []
    intro_names: list[str] = []
    for segment in intro_window_segments(segments):
        text = string_value(segment.get("text"), segment.get("raw_text"))
        if not has_value(text):
            continue
        segment_matches = extract_self_intro_matches(text)
        for _, _, name in segment_matches:
            if name not in intro_names:
                intro_names.append(name)
        if not segment_matches:
            continue

        seg_start = float_value(segment.get("start"))
        seg_end = max(seg_start, float_value(segment.get("end")))
        seg_duration = max(0.4, seg_end - seg_start)
        total_chars = max(len(text), 1)

        for order_index, (char_start, char_end, name) in enumerate(segment_matches):
            time_start = seg_start + seg_duration * (char_start / total_chars)
            time_end = seg_start + seg_duration * (char_end / total_chars)
            time_end = max(time_end, time_start + max(0.35, seg_duration / max(2, len(segment_matches) + 1)))
            mentions.append(
                {
                    "segment_index": int(segment.get("index", 0)),
                    "segment_start": seg_start,
                    "segment_end": seg_end,
                    "start": round(min(seg_end, time_start), 3),
                    "end": round(min(seg_end, time_end), 3),
                    "name": name,
                    "order": len(mentions),
                    "segment_local_order": order_index,
                    "timestamp": string_value(segment.get("timestamp")),
                    "text": text,
                }
            )
    return mentions, intro_names


def parse_chinese_number(token: str) -> int:
    text = re.sub(r"[^\d零一二两三四五六七八九十百]", "", string_value(token))
    if not has_value(text):
        return 0
    if text.isdigit():
        return int(text)
    if text in CHINESE_DIGITS:
        return CHINESE_DIGITS[text]
    if text == "十":
        return 10
    if "十" in text:
        left, _, right = text.partition("十")
        tens = CHINESE_DIGITS.get(left, 1 if not left else 0)
        ones = CHINESE_DIGITS.get(right, 0)
        return tens * 10 + ones
    return 0


def infer_expected_speaker_count(segments: list[dict[str, Any]], intro_names: list[str]) -> int:
    if len(intro_names) >= 2:
        return len(intro_names)
    intro_text = " ".join(string_value(segment.get("text"), segment.get("raw_text")) for segment in intro_window_segments(segments))
    for pattern in SPEAKER_COUNT_PATTERNS:
        for match in pattern.finditer(intro_text):
            count = parse_chinese_number(match.group("count"))
            if 2 <= count <= 8:
                return count
    return 0


def build_intro_context(segments: list[dict[str, Any]]) -> dict[str, Any]:
    intro_mentions, intro_names = extract_intro_mentions(segments)
    multi_name_segments: list[dict[str, Any]] = []
    for segment in intro_window_segments(segments):
        text = string_value(segment.get("text"), segment.get("raw_text"))
        if not has_value(text):
            continue
        segment_matches = extract_self_intro_matches(text)
        match_names = dedupe_strings([item[2] for item in segment_matches if has_value(item[2])])
        if len(match_names) < 2:
            continue
        multi_name_segments.append(
            {
                "segment_index": int(segment.get("index", 0)),
                "timestamp": string_value(segment.get("timestamp")),
                "text": text,
                "names": match_names,
                "match_count": len(segment_matches),
            }
        )
    return {
        "intro_names": intro_names,
        "intro_mentions": intro_mentions,
        "expected_speaker_count": infer_expected_speaker_count(segments, intro_names),
        "intro_segment_count": len(intro_window_segments(segments)),
        "multi_name_intro_segments": multi_name_segments,
    }


def segment_overlap(segment: dict[str, Any], turn: dict[str, Any]) -> float:
    start = max(float_value(segment.get("start")), float_value(turn.get("start")))
    end = min(float_value(segment.get("end")), float_value(turn.get("end")))
    return max(0.0, end - start)


def dominant_speaker_for_window(start: float, end: float, turns: list[dict[str, Any]]) -> str:
    best_speaker = ""
    best_overlap = 0.0
    for turn in turns:
        overlap = max(0.0, min(end, float_value(turn.get("end"))) - max(start, float_value(turn.get("start"))))
        if overlap > best_overlap:
            best_overlap = overlap
            best_speaker = string_value(turn.get("speaker_id"))
    return best_speaker if best_overlap > 0 else ""


def select_speaker_id(segment: dict[str, Any], turns: list[dict[str, Any]], min_overlap_ratio: float) -> str:
    duration = max(0.001, float_value(segment.get("end")) - float_value(segment.get("start")))
    best_speaker = string_value(segment.get("speaker_id"), segment.get("speaker"))
    best_overlap = 0.0
    for turn in turns:
        overlap = segment_overlap(segment, turn)
        if overlap <= 0:
            continue
        if overlap > best_overlap:
            best_overlap = overlap
            best_speaker = string_value(turn.get("speaker_id"))
    if best_overlap / duration >= min_overlap_ratio or best_overlap > 0.8:
        return best_speaker
    if has_value(string_value(segment.get("speaker_id"))):
        return string_value(segment.get("speaker_id"))
    return ""


def overlapping_turn_windows(segment: dict[str, Any], turns: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seg_start = float_value(segment.get("start"))
    seg_end = float_value(segment.get("end"))
    if seg_end <= seg_start:
        return []

    clipped: list[dict[str, Any]] = []
    for turn in turns:
        speaker_id = string_value(turn.get("speaker_id"))
        if not has_value(speaker_id):
            continue
        start = max(seg_start, float_value(turn.get("start")))
        end = min(seg_end, float_value(turn.get("end")))
        if end <= start:
            continue
        clipped.append(
            {
                "speaker_id": speaker_id,
                "start": round(start, 3),
                "end": round(end, 3),
                "duration": round(end - start, 3),
            }
        )

    if not clipped:
        return []

    clipped.sort(key=lambda item: (float_value(item.get("start")), float_value(item.get("end"))))
    merged: list[dict[str, Any]] = []
    for entry in clipped:
        if (
            merged
            and string_value(merged[-1].get("speaker_id")) == string_value(entry.get("speaker_id"))
            and float_value(entry.get("start")) <= float_value(merged[-1].get("end")) + 0.05
        ):
            merged[-1]["end"] = round(max(float_value(merged[-1].get("end")), float_value(entry.get("end"))), 3)
            merged[-1]["duration"] = round(
                float_value(merged[-1].get("duration")) + float_value(entry.get("duration")),
                3,
            )
            continue
        merged.append(dict(entry))
    return merged


def allocate_text_spans(text: str, fragment_durations: list[float]) -> list[str]:
    source_text = string_value(text)
    if not has_value(source_text):
        return ["" for _ in fragment_durations]
    if len(fragment_durations) <= 1:
        return [source_text]

    total_duration = sum(max(duration, 0.0) for duration in fragment_durations) or float(len(fragment_durations))
    target_length = len(source_text)
    raw_boundaries = [0]
    running = 0.0
    for duration in fragment_durations[:-1]:
        running += max(duration, 0.0)
        raw_boundaries.append(int(round(target_length * running / total_duration)))
    raw_boundaries.append(target_length)

    normalized_boundaries: list[int] = [0]
    max_index = target_length
    required_remaining = len(fragment_durations) - 1
    for boundary in raw_boundaries[1:-1]:
        lower = normalized_boundaries[-1] + 1
        upper = max(lower, max_index - required_remaining)
        normalized_boundaries.append(max(lower, min(boundary, upper)))
        required_remaining -= 1
    normalized_boundaries.append(target_length)

    parts: list[str] = []
    for index in range(len(fragment_durations)):
        start = normalized_boundaries[index]
        end = normalized_boundaries[index + 1]
        part = source_text[start:end].strip()
        if not has_value(part) and index == len(fragment_durations) - 1 and parts:
            parts[-1] = join_text_parts(parts[-1], source_text[start:end])
            part = ""
        parts.append(part)

    if any(has_value(part) for part in parts):
        return parts
    return [source_text] + ["" for _ in fragment_durations[1:]]


def split_text_by_char_boundaries(text: str, boundaries: list[int]) -> list[str]:
    source_text = string_value(text)
    if not has_value(source_text):
        return ["" for _ in range(max(0, len(boundaries) - 1))]
    if len(boundaries) < 2:
        return [source_text]

    normalized_boundaries: list[int] = [0]
    text_length = len(source_text)
    for boundary in boundaries[1:-1]:
        normalized_boundaries.append(max(normalized_boundaries[-1], min(int_value(boundary), text_length)))
    normalized_boundaries.append(text_length)

    parts: list[str] = []
    for index in range(len(normalized_boundaries) - 1):
        start = normalized_boundaries[index]
        end = normalized_boundaries[index + 1]
        part = source_text[start:end].strip()
        if not has_value(part) and index == len(normalized_boundaries) - 2 and parts:
            parts[-1] = join_text_parts(parts[-1], source_text[start:end])
            part = ""
        parts.append(part)
    return parts


def allocate_text_spans_with_separator_bias(text: str, fragment_durations: list[float]) -> list[str]:
    source_text = string_value(text)
    if not has_value(source_text):
        return ["" for _ in fragment_durations]
    if len(fragment_durations) <= 1:
        return [source_text]

    total_duration = sum(max(duration, 0.0) for duration in fragment_durations) or float(len(fragment_durations))
    target_length = len(source_text)
    raw_boundaries = [0]
    running = 0.0
    for duration in fragment_durations[:-1]:
        running += max(duration, 0.0)
        raw_boundaries.append(int(round(target_length * running / total_duration)))
    raw_boundaries.append(target_length)

    separator_chars = set(" \t\r\n，。！？!?,、:：;；")
    normalized_boundaries: list[int] = [0]
    required_remaining = len(fragment_durations) - 1
    max_index = target_length
    for boundary in raw_boundaries[1:-1]:
        lower = normalized_boundaries[-1] + 1
        upper = max(lower, max_index - required_remaining)
        snapped_boundary = max(lower, min(boundary, upper))
        best_boundary = snapped_boundary
        best_distance = target_length + 1
        search_start = max(lower, snapped_boundary - 8)
        search_end = min(upper, snapped_boundary + 8)
        for candidate in range(search_start, search_end + 1):
            left_char = source_text[candidate - 1] if candidate - 1 >= 0 and candidate - 1 < target_length else ""
            right_char = source_text[candidate] if candidate < target_length else ""
            if left_char not in separator_chars and right_char not in separator_chars:
                continue
            distance = abs(candidate - snapped_boundary)
            if distance < best_distance:
                best_distance = distance
                best_boundary = candidate
        normalized_boundaries.append(best_boundary)
        required_remaining -= 1
    normalized_boundaries.append(target_length)
    return split_text_by_char_boundaries(source_text, normalized_boundaries)


def summarize_turn_distribution(turns: list[dict[str, Any]]) -> list[dict[str, Any]]:
    total_seconds = round(sum(max(0.0, float_value(item.get("end")) - float_value(item.get("start"))) for item in turns), 3)
    stats: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for turn in sorted(turns, key=lambda item: (float_value(item.get("start")), float_value(item.get("end")))):
        speaker_id = string_value(turn.get("speaker_id"))
        if not has_value(speaker_id):
            continue
        duration = round(max(0.0, float_value(turn.get("end")) - float_value(turn.get("start"))), 3)
        if duration <= 0:
            continue
        entry = stats.setdefault(
            speaker_id,
            {
                "speaker_id": speaker_id,
                "turn_count": 0,
                "total_seconds": 0.0,
                "share": 0.0,
            },
        )
        entry["turn_count"] = int(entry.get("turn_count", 0)) + 1
        entry["total_seconds"] = round(float_value(entry.get("total_seconds")) + duration, 3)

    for entry in stats.values():
        seconds = round(float_value(entry.get("total_seconds")), 3)
        entry["share"] = round(seconds / total_seconds, 4) if total_seconds > 0 else 0.0
    return list(stats.values())


def split_segment_by_turns(
    segment: dict[str, Any],
    turns: list[dict[str, Any]],
    min_overlap_ratio: float,
) -> list[dict[str, Any]]:
    duration = max(0.001, float_value(segment.get("end")) - float_value(segment.get("start")))
    primary_speaker = select_speaker_id(segment, turns, min_overlap_ratio)
    windows = overlapping_turn_windows(segment, turns)
    unique_speakers = dedupe_strings([string_value(item.get("speaker_id")) for item in windows])

    if (
        len(unique_speakers) < 2
        or duration < SPLIT_SEGMENT_MIN_SECONDS
        or len(string_value(segment.get("text"), segment.get("raw_text"))) < 8
    ):
        merged_segment = dict(segment)
        if has_value(primary_speaker):
            merged_segment["speaker_id"] = primary_speaker
        return [merged_segment]

    viable_windows = [
        dict(item)
        for item in windows
        if float_value(item.get("duration")) >= max(SPLIT_FRAGMENT_MIN_SECONDS, duration * SPLIT_FRAGMENT_MIN_RATIO)
    ]
    if len(viable_windows) < 2:
        merged_segment = dict(segment)
        if has_value(primary_speaker):
            merged_segment["speaker_id"] = primary_speaker
        return [merged_segment]

    seg_start = float_value(segment.get("start"))
    seg_end = float_value(segment.get("end"))
    fragments: list[dict[str, Any]] = []
    for index, window in enumerate(viable_windows):
        previous_window = viable_windows[index - 1] if index > 0 else None
        next_window = viable_windows[index + 1] if index + 1 < len(viable_windows) else None
        start = seg_start if previous_window is None else (float_value(previous_window.get("end")) + float_value(window.get("start"))) / 2
        end = seg_end if next_window is None else (float_value(window.get("end")) + float_value(next_window.get("start"))) / 2
        start = max(seg_start, start)
        end = min(seg_end, end)
        if end - start < SPLIT_FRAGMENT_MIN_SECONDS:
            continue
        fragments.append(
            {
                "speaker_id": string_value(window.get("speaker_id")),
                "start": round(start, 3),
                "end": round(end, 3),
                "duration": round(end - start, 3),
            }
        )

    if len(fragments) < 2:
        merged_segment = dict(segment)
        if has_value(primary_speaker):
            merged_segment["speaker_id"] = primary_speaker
        return [merged_segment]

    text_parts = allocate_text_spans(string_value(segment.get("text")), [float_value(item.get("duration")) for item in fragments])
    raw_text_parts = allocate_text_spans(
        string_value(segment.get("raw_text"), segment.get("text")),
        [float_value(item.get("duration")) for item in fragments],
    )

    aligned: list[dict[str, Any]] = []
    for index, fragment in enumerate(fragments):
        text = string_value(text_parts[index] if index < len(text_parts) else "")
        raw_text = string_value(raw_text_parts[index] if index < len(raw_text_parts) else text)
        if not has_value(text) and not has_value(raw_text):
            continue
        aligned_segment = dict(segment)
        aligned_segment["start"] = round(float_value(fragment.get("start")), 3)
        aligned_segment["end"] = round(float_value(fragment.get("end")), 3)
        aligned_segment["timestamp"] = format_timestamp(float_value(fragment.get("start")))
        aligned_segment["speaker_id"] = string_value(fragment.get("speaker_id"), primary_speaker)
        aligned_segment["text"] = text
        aligned_segment["raw_text"] = raw_text
        aligned_segment["source_segment_index"] = int(segment.get("index", 0))
        aligned.append(aligned_segment)

    if len(aligned) < 2:
        merged_segment = dict(segment)
        if has_value(primary_speaker):
            merged_segment["speaker_id"] = primary_speaker
        return [merged_segment]
    return aligned


def merge_adjacent_segments(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    for segment in segments:
        current = dict(segment)
        current_speaker = string_value(current.get("speaker_id"))
        if not merged:
            merged.append(current)
            continue
        previous = merged[-1]
        previous_speaker = string_value(previous.get("speaker_id"))
        gap = float_value(current.get("start")) - float_value(previous.get("end"))
        same_source = int(previous.get("source_segment_index", previous.get("index", -1))) == int(
            current.get("source_segment_index", current.get("index", -2))
        )
        if (
            has_value(current_speaker)
            and current_speaker == previous_speaker
            and gap <= MERGE_GAP_SECONDS
            and (same_source or gap <= 0.05)
        ):
            previous["end"] = round(max(float_value(previous.get("end")), float_value(current.get("end"))), 3)
            previous["text"] = join_text_parts(string_value(previous.get("text")), string_value(current.get("text")))
            previous["raw_text"] = join_text_parts(
                string_value(previous.get("raw_text"), previous.get("text")),
                string_value(current.get("raw_text"), current.get("text")),
            )
            continue
        merged.append(current)

    for index, segment in enumerate(merged):
        segment["index"] = index
        segment["timestamp"] = string_value(segment.get("timestamp"), default=format_timestamp(float_value(segment.get("start"))))
    return merged


def assign_speaker_ids(
    segments: list[dict[str, Any]],
    turns: list[dict[str, Any]],
    min_overlap_ratio: float,
) -> list[dict[str, Any]]:
    enriched: list[dict[str, Any]] = []
    for segment in segments:
        enriched.extend(split_segment_by_turns(segment, turns, min_overlap_ratio))
    return merge_adjacent_segments(enriched)


def apply_sparse_speaker_turn_rescue(
    segments: list[dict[str, Any]],
    turns: list[dict[str, Any]],
    expected_speaker_count: int,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if expected_speaker_count < 3:
        return segments, {
            "status": "not_applicable",
            "sparse_speaker_ids": [],
            "applied_segment_count": 0,
            "applied_fragments": 0,
            "diagnostics": [],
        }

    turn_distribution = summarize_turn_distribution(turns)
    sparse_speaker_ids = [
        string_value(item.get("speaker_id"))
        for item in turn_distribution
        if (
            float_value(item.get("total_seconds")) < SPARSE_TURN_RESCUE_SECONDS_THRESHOLD
            or float_value(item.get("share")) < SPARSE_TURN_RESCUE_SHARE_THRESHOLD
        )
    ]
    sparse_speaker_ids = [speaker_id for speaker_id in sparse_speaker_ids if has_value(speaker_id)]
    if not sparse_speaker_ids:
        return segments, {
            "status": "no_sparse_speakers",
            "sparse_speaker_ids": [],
            "applied_segment_count": 0,
            "applied_fragments": 0,
            "diagnostics": [],
        }

    updated_segments: list[dict[str, Any]] = []
    diagnostics: list[dict[str, Any]] = []
    applied_segment_count = 0
    applied_fragments = 0

    for segment in segments:
        segment_speaker_id = string_value(segment.get("speaker_id"))
        if segment_speaker_id in sparse_speaker_ids:
            updated_segments.append(dict(segment))
            continue

        segment_start = float_value(segment.get("start"))
        segment_end = max(segment_start, float_value(segment.get("end")))
        text = string_value(segment.get("text"), segment.get("raw_text"))
        if not has_value(text) or segment_end - segment_start < 4.0:
            updated_segments.append(dict(segment))
            continue

        clipped_windows: list[dict[str, Any]] = []
        for turn in turns:
            speaker_id = string_value(turn.get("speaker_id"))
            if speaker_id not in sparse_speaker_ids:
                continue
            overlap_start = max(segment_start, float_value(turn.get("start")))
            overlap_end = min(segment_end, float_value(turn.get("end")))
            if overlap_end - overlap_start < 0.02:
                continue
            clipped_windows.append(
                {
                    "speaker_id": speaker_id,
                    "start": round(overlap_start, 3),
                    "end": round(overlap_end, 3),
                }
            )

        if not clipped_windows:
            updated_segments.append(dict(segment))
            continue

        clipped_windows.sort(key=lambda item: (float_value(item.get("start")), float_value(item.get("end"))))
        merged_windows: list[dict[str, Any]] = []
        for window in clipped_windows:
            if (
                merged_windows
                and string_value(merged_windows[-1].get("speaker_id")) == string_value(window.get("speaker_id"))
                and float_value(window.get("start")) <= float_value(merged_windows[-1].get("end")) + SPARSE_TURN_RESCUE_MERGE_GAP_SECONDS
            ):
                merged_windows[-1]["end"] = round(max(float_value(merged_windows[-1].get("end")), float_value(window.get("end"))), 3)
                continue
            merged_windows.append(dict(window))

        merged_windows = [
            {
                **window,
                "duration": round(float_value(window.get("end")) - float_value(window.get("start")), 3),
            }
            for window in merged_windows
            if float_value(window.get("end")) - float_value(window.get("start")) >= SPARSE_TURN_RESCUE_MIN_OVERLAP_SECONDS
        ]

        if not merged_windows:
            updated_segments.append(dict(segment))
            continue

        if len(merged_windows) > SPARSE_TURN_RESCUE_MAX_WINDOWS_PER_SEGMENT:
            diagnostics.append(
                {
                    "segment_index": int(segment.get("index", -1)),
                    "timestamp": string_value(segment.get("timestamp")),
                    "text": text,
                    "status": "skipped_too_many_sparse_windows",
                    "window_count": len(merged_windows),
                }
            )
            updated_segments.append(dict(segment))
            continue

        expanded_windows: list[dict[str, Any]] = []
        for index, window in enumerate(merged_windows):
            previous_end = segment_start if index == 0 else float_value(expanded_windows[-1].get("end"))
            next_start = segment_end if index == len(merged_windows) - 1 else float_value(merged_windows[index + 1].get("start"))
            current_start = float_value(window.get("start"))
            current_end = float_value(window.get("end"))
            current_duration = max(0.0, current_end - current_start)
            target_duration = max(current_duration, SPARSE_TURN_RESCUE_MIN_WINDOW_SECONDS)
            extra = max(0.0, target_duration - current_duration)
            available_before = max(0.0, current_start - previous_end)
            available_after = max(0.0, next_start - current_end)
            expand_before = min(available_before, extra / 2)
            expand_after = min(available_after, extra - expand_before)
            if expand_before + expand_after < extra:
                remaining = extra - expand_before - expand_after
                extra_before = min(max(0.0, available_before - expand_before), remaining)
                expand_before += extra_before
                remaining -= extra_before
                if remaining > 0:
                    expand_after += min(max(0.0, available_after - expand_after), remaining)
            expanded_windows.append(
                {
                    "speaker_id": string_value(window.get("speaker_id")),
                    "start": round(max(previous_end, current_start - expand_before), 3),
                    "end": round(min(next_start, current_end + expand_after), 3),
                }
            )

        fragments: list[dict[str, Any]] = []
        cursor = segment_start
        for window in expanded_windows:
            window_start = float_value(window.get("start"))
            window_end = float_value(window.get("end"))
            if window_start - cursor >= 0.05:
                fragments.append(
                    {
                        "speaker_id": segment_speaker_id,
                        "start": round(cursor, 3),
                        "end": round(window_start, 3),
                    }
                )
            fragments.append(
                {
                    "speaker_id": string_value(window.get("speaker_id")),
                    "start": round(window_start, 3),
                    "end": round(window_end, 3),
                }
            )
            cursor = window_end
        if segment_end - cursor >= 0.05:
            fragments.append(
                {
                    "speaker_id": segment_speaker_id,
                    "start": round(cursor, 3),
                    "end": round(segment_end, 3),
                }
            )

        fragments = [
            {
                **fragment,
                "duration": round(float_value(fragment.get("end")) - float_value(fragment.get("start")), 3),
            }
            for fragment in fragments
            if float_value(fragment.get("end")) - float_value(fragment.get("start")) >= 0.05
        ]
        if len(fragments) < 2:
            updated_segments.append(dict(segment))
            continue

        fragment_durations = [float_value(item.get("duration")) for item in fragments]
        text_parts = allocate_text_spans_with_separator_bias(text, fragment_durations)
        raw_text_parts = allocate_text_spans_with_separator_bias(string_value(segment.get("raw_text"), text), fragment_durations)

        created_fragments: list[dict[str, Any]] = []
        for index, fragment in enumerate(fragments):
            fragment_text = string_value(text_parts[index] if index < len(text_parts) else "")
            fragment_raw_text = string_value(raw_text_parts[index] if index < len(raw_text_parts) else fragment_text)
            if not has_value(fragment_text) and not has_value(fragment_raw_text):
                continue
            created_fragment = dict(segment)
            created_fragment["start"] = round(float_value(fragment.get("start")), 3)
            created_fragment["end"] = round(float_value(fragment.get("end")), 3)
            created_fragment["timestamp"] = format_timestamp(float_value(fragment.get("start")))
            created_fragment["speaker_id"] = string_value(fragment.get("speaker_id"))
            created_fragment["text"] = fragment_text
            created_fragment["raw_text"] = fragment_raw_text
            created_fragment["source_segment_index"] = int(
                segment.get("source_segment_index", segment.get("index", 0))
                if segment.get("source_segment_index", segment.get("index", 0)) is not None
                else 0
            )
            created_fragment["split_strategy"] = "sparse_speaker_turn_rescue"
            created_fragments.append(created_fragment)

        if len(created_fragments) < 2:
            updated_segments.append(dict(segment))
            continue

        applied_segment_count += 1
        applied_fragments += len(created_fragments)
        diagnostics.append(
            {
                "segment_index": int(segment.get("index", -1)),
                "timestamp": string_value(segment.get("timestamp")),
                "speaker_id": segment_speaker_id,
                "text": text,
                "windows": [
                    {
                        "speaker_id": string_value(item.get("speaker_id")),
                        "start": float_value(item.get("start")),
                        "end": float_value(item.get("end")),
                    }
                    for item in expanded_windows
                ],
                "status": "applied",
            }
        )
        updated_segments.extend(created_fragments)

    return merge_adjacent_segments(updated_segments), {
        "status": "applied" if applied_segment_count else "no_action",
        "sparse_speaker_ids": sparse_speaker_ids,
        "applied_segment_count": applied_segment_count,
        "applied_fragments": applied_fragments,
        "turn_distribution": turn_distribution,
        "diagnostics": diagnostics,
    }


def apply_intro_text_guided_split(
    segments: list[dict[str, Any]],
    speaker_inference: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    auto_assignments = (
        speaker_inference.get("auto_assignments")
        if isinstance(speaker_inference.get("auto_assignments"), list)
        else []
    )
    name_to_speaker_id: dict[str, str] = {}
    for item in auto_assignments:
        if not isinstance(item, dict):
            continue
        speaker_id = string_value(item.get("speaker_id"))
        name = string_value(item.get("speaker"))
        if has_value(speaker_id) and has_value(name) and name not in name_to_speaker_id:
            name_to_speaker_id[name] = speaker_id

    if len(name_to_speaker_id) < 2:
        return segments, {
            "status": "not_applicable",
            "applied_segment_count": 0,
            "applied_fragments": 0,
            "diagnostics": [],
        }

    updated_segments: list[dict[str, Any]] = []
    diagnostics: list[dict[str, Any]] = []
    applied_segment_count = 0
    applied_fragments = 0

    for segment in segments:
        text = string_value(segment.get("text"), segment.get("raw_text"))
        phrases = extract_self_intro_phrases(text)
        phrase_names = [string_value(item.get("name")) for item in phrases if has_value(item.get("name"))]

        if (
            float_value(segment.get("start")) > INTRO_WINDOW_SECONDS
            or len(phrases) < 2
            or len(dedupe_strings(phrase_names)) < 2
        ):
            updated_segments.append(dict(segment))
            continue

        mapped_speaker_ids = [string_value(name_to_speaker_id.get(name)) for name in phrase_names]
        if any(not has_value(speaker_id) for speaker_id in mapped_speaker_ids):
            diagnostics.append(
                {
                    "segment_index": int(segment.get("index", -1)),
                    "timestamp": string_value(segment.get("timestamp")),
                    "text": text,
                    "names": phrase_names,
                    "status": "skipped_missing_name_mapping",
                }
            )
            updated_segments.append(dict(segment))
            continue
        if len(dedupe_strings(mapped_speaker_ids)) < len(mapped_speaker_ids):
            diagnostics.append(
                {
                    "segment_index": int(segment.get("index", -1)),
                    "timestamp": string_value(segment.get("timestamp")),
                    "text": text,
                    "names": phrase_names,
                    "speaker_ids": mapped_speaker_ids,
                    "status": "skipped_non_unique_speaker_mapping",
                }
            )
            updated_segments.append(dict(segment))
            continue

        segment_start = float_value(segment.get("start"))
        segment_end = max(segment_start, float_value(segment.get("end")))
        segment_duration = max(0.001, segment_end - segment_start)
        text_length = max(len(text), 1)
        boundaries = [0] + [int(phrase.get("phrase_start", 0)) for phrase in phrases[1:]] + [text_length]
        normalized_boundaries = [0]
        for boundary in boundaries[1:-1]:
            normalized_boundaries.append(max(normalized_boundaries[-1] + 1, min(boundary, text_length - 1)))
        normalized_boundaries.append(text_length)

        fragment_durations: list[float] = []
        fragments: list[dict[str, Any]] = []
        for index, phrase in enumerate(phrases):
            char_start = normalized_boundaries[index]
            char_end = normalized_boundaries[index + 1]
            start = segment_start + segment_duration * (char_start / text_length)
            end = segment_start + segment_duration * (char_end / text_length)
            if index == len(phrases) - 1:
                end = segment_end
            if end - start < max(0.28, SPLIT_FRAGMENT_MIN_SECONDS * 0.6):
                fragments = []
                break
            fragment_durations.append(round(end - start, 3))
            fragments.append(
                {
                    "start": round(start, 3),
                    "end": round(end, 3),
                    "speaker_id": mapped_speaker_ids[index],
                    "name": string_value(phrase.get("name")),
                }
            )

        if len(fragments) < 2:
            diagnostics.append(
                {
                    "segment_index": int(segment.get("index", -1)),
                    "timestamp": string_value(segment.get("timestamp")),
                    "text": text,
                    "names": phrase_names,
                    "status": "skipped_fragment_too_short",
                }
            )
            updated_segments.append(dict(segment))
            continue

        text_parts = split_text_by_char_boundaries(text, normalized_boundaries)
        raw_text_parts = allocate_text_spans(
            string_value(segment.get("raw_text"), text),
            fragment_durations,
        )

        created_fragments: list[dict[str, Any]] = []
        for index, fragment in enumerate(fragments):
            fragment_text = string_value(text_parts[index] if index < len(text_parts) else "")
            fragment_raw_text = string_value(raw_text_parts[index] if index < len(raw_text_parts) else fragment_text)
            if not has_value(fragment_text) and not has_value(fragment_raw_text):
                continue
            created_fragment = dict(segment)
            created_fragment["start"] = round(float_value(fragment.get("start")), 3)
            created_fragment["end"] = round(float_value(fragment.get("end")), 3)
            created_fragment["timestamp"] = format_timestamp(float_value(fragment.get("start")))
            created_fragment["speaker_id"] = string_value(fragment.get("speaker_id"))
            created_fragment["text"] = fragment_text
            created_fragment["raw_text"] = fragment_raw_text
            created_fragment["source_segment_index"] = int(
                segment.get("source_segment_index", segment.get("index", 0))
                if segment.get("source_segment_index", segment.get("index", 0)) is not None
                else 0
            )
            created_fragment["split_strategy"] = "intro_text_guided_self_intro"
            created_fragments.append(created_fragment)

        if len(created_fragments) < 2:
            updated_segments.append(dict(segment))
            continue

        applied_segment_count += 1
        applied_fragments += len(created_fragments)
        diagnostics.append(
            {
                "segment_index": int(segment.get("index", -1)),
                "timestamp": string_value(segment.get("timestamp")),
                "text": text,
                "names": phrase_names,
                "speaker_ids": mapped_speaker_ids,
                "fragments": [
                    {
                        "start": float_value(item.get("start")),
                        "end": float_value(item.get("end")),
                        "speaker_id": string_value(item.get("speaker_id")),
                        "text": string_value(item.get("text")),
                    }
                    for item in created_fragments
                ],
                "status": "applied",
            }
        )
        updated_segments.extend(created_fragments)

    return merge_adjacent_segments(updated_segments), {
        "status": "applied" if applied_segment_count else "no_action",
        "applied_segment_count": applied_segment_count,
        "applied_fragments": applied_fragments,
        "diagnostics": diagnostics,
    }


def speaker_order_from_intro(
    segments: list[dict[str, Any]],
    turns: list[dict[str, Any]],
    intro_mentions: list[dict[str, Any]] | None = None,
) -> list[str]:
    speaker_ids: list[str] = []
    seen: set[str] = set()
    if isinstance(intro_mentions, list):
        for mention in intro_mentions:
            speaker_id = dominant_speaker_for_window(
                float_value(mention.get("start")),
                float_value(mention.get("end")),
                turns,
            )
            if has_value(speaker_id) and speaker_id not in seen:
                seen.add(speaker_id)
                speaker_ids.append(speaker_id)
    if speaker_ids:
        return speaker_ids
    for turn in sorted(turns, key=lambda item: (float_value(item.get("start")), float_value(item.get("end")))):
        if float_value(turn.get("start")) > INTRO_WINDOW_SECONDS:
            break
        speaker_id = string_value(turn.get("speaker_id"))
        if has_value(speaker_id) and speaker_id not in seen:
            seen.add(speaker_id)
            speaker_ids.append(speaker_id)
    if speaker_ids:
        return speaker_ids
    for segment in intro_window_segments(segments):
        speaker_id = string_value(segment.get("speaker_id"))
        if has_value(speaker_id) and speaker_id not in seen:
            seen.add(speaker_id)
            speaker_ids.append(speaker_id)
    return speaker_ids


def infer_auto_speaker_profiles(
    segments: list[dict[str, Any]],
    turns: list[dict[str, Any]],
    intro_context: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    intro_mentions = intro_context.get("intro_mentions") if isinstance(intro_context.get("intro_mentions"), list) else []
    intro_names = intro_context.get("intro_names") if isinstance(intro_context.get("intro_names"), list) else []
    if not intro_mentions and not intro_names:
        return {}, {
            "intro_names": [],
            "expected_speaker_count": int(intro_context.get("expected_speaker_count", 0) or 0),
            "detected_speaker_order": [],
            "auto_assignments": [],
            "status": "no_intro_detected",
        }

    segments_by_index = {int(segment.get("index", 0)): segment for segment in segments}
    speaker_name_scores: dict[str, dict[str, float]] = {}
    speaker_name_evidence: dict[str, list[dict[str, Any]]] = {}
    intro_name_order = {name: index for index, name in enumerate(intro_names)}
    detected_speaker_order = speaker_order_from_intro(segments, turns, intro_mentions)
    all_detected_speakers = dedupe_strings([string_value(segment.get("speaker_id")) for segment in segments if has_value(segment.get("speaker_id"))])

    def add_evidence(speaker_id: str, name: str, confidence: float, timestamp: str, text: str) -> None:
        if not has_value(speaker_id) or not has_value(name):
            return
        speaker_name_scores.setdefault(speaker_id, {})
        speaker_name_scores[speaker_id][name] = round(speaker_name_scores[speaker_id].get(name, 0.0) + confidence, 3)
        speaker_name_evidence.setdefault(speaker_id, []).append(
            {
                "name": name,
                "timestamp": string_value(timestamp),
                "text": string_value(text),
                "confidence": confidence,
            }
        )

    for segment in intro_window_segments(segments):
        speaker_id = string_value(segment.get("speaker_id"))
        if not has_value(speaker_id):
            continue
        text = string_value(segment.get("text"), segment.get("raw_text"))
        segment_matches = extract_self_intro_matches(text)
        if not segment_matches:
            continue
        anchored_names = [segment_matches[-1][2]] if len(segment_matches) == 1 else []
        confidence = 2.6 if len(segment_matches) == 1 else 0.0
        for name in anchored_names:
            add_evidence(
                speaker_id=speaker_id,
                name=name,
                confidence=confidence,
                timestamp=string_value(segment.get("timestamp")),
                text=text,
            )

    for mention in intro_mentions:
        name = string_value(mention.get("name"))
        if not has_value(name):
            continue
        speaker_id = dominant_speaker_for_window(
            float_value(mention.get("start")),
            float_value(mention.get("end")),
            turns,
        )
        confidence = 2.0
        if not has_value(speaker_id):
            segment = segments_by_index.get(int(mention.get("segment_index", -1)))
            speaker_id = string_value(segment.get("speaker_id") if segment else "")
            confidence = 1.0
        if not has_value(speaker_id):
            continue
        add_evidence(
            speaker_id=speaker_id,
            name=name,
            confidence=confidence,
            timestamp=string_value(mention.get("timestamp")),
            text=string_value(mention.get("text")),
        )

    candidate_pairs: list[tuple[float, int, int, str, str]] = []
    speaker_order_index = {speaker_id: index for index, speaker_id in enumerate(detected_speaker_order)}
    for speaker_id, score_map in speaker_name_scores.items():
        for name, score in score_map.items():
            candidate_pairs.append(
                (
                    -score,
                    intro_name_order.get(name, 999),
                    speaker_order_index.get(speaker_id, 999),
                    speaker_id,
                    name,
                )
            )
    candidate_pairs.sort()

    assignments: OrderedDict[str, str] = OrderedDict()
    assigned_names: set[str] = set()
    for _, _, _, speaker_id, name in candidate_pairs:
        if speaker_id in assignments or name in assigned_names:
            continue
        assignments[speaker_id] = name
        assigned_names.add(name)

    remaining_speakers = [speaker_id for speaker_id in all_detected_speakers if speaker_id not in assignments]
    remaining_names = [name for name in intro_names if name not in assigned_names]
    if remaining_speakers and remaining_names and len(remaining_speakers) == len(remaining_names):
        for speaker_id, name in zip(remaining_speakers, remaining_names):
            assignments[speaker_id] = name
            assigned_names.add(name)

    profiles: dict[str, dict[str, Any]] = {}
    for speaker_id, display_name in assignments.items():
        evidence_lines = [
            f"{string_value(item.get('timestamp'))} {string_value(item.get('text'))}".strip()
            for item in speaker_name_evidence.get(speaker_id, [])
            if has_value(string_value(item.get("text")))
        ]
        profiles[speaker_id] = {
            "speaker_id": speaker_id,
            "speaker": display_name,
            "display_name": display_name,
            "role": "",
            "notes": "开场自我介绍自动映射" + (f" | {' || '.join(dedupe_strings(evidence_lines)[:2])}" if evidence_lines else ""),
            "name_source": "auto_intro",
        }

    inference = {
        "intro_names": intro_names,
        "expected_speaker_count": int(intro_context.get("expected_speaker_count", 0) or 0),
        "detected_speaker_order": detected_speaker_order,
        "auto_assignments": [
            {
                "speaker_id": speaker_id,
                "speaker": name,
                "score": speaker_name_scores.get(speaker_id, {}).get(name, 0.0),
            }
            for speaker_id, name in assignments.items()
        ],
        "unmapped_intro_names": [name for name in intro_names if name not in assigned_names],
        "status": "mapped" if assignments else "intro_detected_but_unmapped",
    }
    return profiles, inference


def diagnose_intro_speaker_collisions(
    segments: list[dict[str, Any]],
    intro_context: dict[str, Any],
) -> dict[str, Any]:
    diagnostics: list[dict[str, Any]] = []
    multi_name_segments = (
        intro_context.get("multi_name_intro_segments")
        if isinstance(intro_context.get("multi_name_intro_segments"), list)
        else []
    )
    if not multi_name_segments:
        return {
            "status": "not_applicable",
            "collapsed_segment_count": 0,
            "diagnostics": [],
        }

    for item in multi_name_segments:
        raw_segment_index = item.get("segment_index", -1)
        segment_index = int(raw_segment_index if raw_segment_index is not None else -1)
        intro_names = dedupe_strings(item.get("names") if isinstance(item.get("names"), list) else [])
        related_segments = [
            segment
            for segment in segments
            if int(
                segment.get("source_segment_index", segment.get("index", -1))
                if segment.get("source_segment_index", segment.get("index", -1)) is not None
                else -1
            ) == segment_index
            or int(segment.get("index", -1) if segment.get("index", -1) is not None else -1) == segment_index
        ]
        detected_speaker_ids = dedupe_strings(
            [string_value(segment.get("speaker_id")) for segment in related_segments if has_value(segment.get("speaker_id"))]
        )
        detected_speakers = dedupe_strings(
            [string_value(segment.get("speaker")) for segment in related_segments if has_value(segment.get("speaker"))]
        )
        collapsed = len(detected_speaker_ids) < len(intro_names)
        diagnostics.append(
            {
                "segment_index": segment_index,
                "timestamp": string_value(item.get("timestamp")),
                "text": string_value(item.get("text")),
                "intro_names": intro_names,
                "intro_name_count": len(intro_names),
                "detected_speaker_ids": detected_speaker_ids,
                "detected_speakers": detected_speakers,
                "detected_speaker_count": len(detected_speaker_ids),
                "related_segment_count": len(related_segments),
                "status": "collapsed_to_fewer_speakers" if collapsed else "separated",
            }
        )

    collapsed_diagnostics = [item for item in diagnostics if item.get("status") == "collapsed_to_fewer_speakers"]
    return {
        "status": "intro_multi_self_intro_collapsed" if collapsed_diagnostics else "ok",
        "collapsed_segment_count": len(collapsed_diagnostics),
        "diagnostics": diagnostics,
    }


def build_speaker_quality_gate(
    distribution_summary: dict[str, Any],
    intro_diagnostics: dict[str, Any],
) -> dict[str, Any]:
    reasons: list[str] = []
    distribution_status = string_value(distribution_summary.get("status"))
    if has_value(distribution_status) and distribution_status != "balanced":
        reasons.append(distribution_status)

    intro_status = string_value(intro_diagnostics.get("status"))
    if has_value(intro_status) and intro_status not in {"ok", "not_applicable"}:
        reasons.append(intro_status)

    status = "blocked" if reasons else "passed"
    status_detail = "speaker_context_blocked" if status == "blocked" else "speaker_context_allowed"
    return {
        "status": status,
        "status_detail": status_detail,
        "allow_downstream_speaker_context": status == "passed",
        "reasons": reasons,
        "distribution_status": distribution_status,
        "intro_diagnostics_status": intro_status,
        "reason_summary": (
            "Speaker labels were downgraded for downstream analysis because diarization quality is not reliable enough."
            if status == "blocked"
            else "Speaker labels passed the quality gate and can be used downstream."
        ),
    }


def build_speaker_identity_map(
    segments: list[dict[str, Any]],
    auto_profiles: dict[str, dict[str, Any]],
    manual_overrides: dict[str, dict[str, Any]],
) -> OrderedDict[str, dict[str, Any]]:
    raw_speakers: OrderedDict[str, None] = OrderedDict()
    for segment in segments:
        speaker_id = string_value(segment.get("speaker_id"))
        if has_value(speaker_id) and speaker_id not in raw_speakers:
            raw_speakers[speaker_id] = None

    identity_map: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for index, speaker_id in enumerate(raw_speakers.keys(), start=1):
        auto_profile = auto_profiles.get(speaker_id, {})
        manual_profile = manual_overrides.get(speaker_id, {})
        display_name = string_value(
            manual_profile.get("speaker"),
            manual_profile.get("display_name"),
            auto_profile.get("speaker"),
            auto_profile.get("display_name"),
            default=f"{DEFAULT_SPEAKER_PREFIX} {index}",
        )
        identity_map[speaker_id] = {
            "speaker_id": speaker_id,
            "speaker": display_name,
            "display_name": display_name,
            "role": string_value(manual_profile.get("role"), auto_profile.get("role")),
            "notes": string_value(manual_profile.get("notes"), auto_profile.get("notes")),
            "name_source": string_value(
                manual_profile.get("name_source"),
                "manual" if speaker_id in manual_overrides else "",
                auto_profile.get("name_source"),
                "default",
            ),
        }

    for speaker_id, manual_profile in manual_overrides.items():
        if speaker_id in identity_map:
            continue
        display_name = string_value(manual_profile.get("speaker"), manual_profile.get("display_name"), default=speaker_id)
        identity_map[speaker_id] = {
            "speaker_id": speaker_id,
            "speaker": display_name,
            "display_name": display_name,
            "role": string_value(manual_profile.get("role")),
            "notes": string_value(manual_profile.get("notes")),
            "name_source": string_value(manual_profile.get("name_source"), default="manual"),
        }
    return identity_map


def apply_speaker_profiles(
    segments: list[dict[str, Any]],
    auto_profiles: dict[str, dict[str, Any]],
    manual_overrides: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    enriched = [dict(segment) for segment in segments]
    speaker_stats: OrderedDict[str, dict[str, Any]] = OrderedDict()
    identity_map = build_speaker_identity_map(enriched, auto_profiles, manual_overrides)

    for segment in enriched:
        speaker_id = string_value(segment.get("speaker_id"))
        if not has_value(speaker_id):
            segment.pop("speaker", None)
            continue
        identity = identity_map.get(speaker_id, {})
        display_name = string_value(
            identity.get("speaker"),
            identity.get("display_name"),
            default=speaker_id,
        )
        segment["speaker"] = display_name
        if has_value(identity.get("role")):
            segment["speaker_role"] = string_value(identity.get("role"))

        duration = max(0.0, float_value(segment.get("end")) - float_value(segment.get("start")))
        entry = speaker_stats.setdefault(
            speaker_id,
            {
                "speaker_id": speaker_id,
                "speaker": display_name,
                "display_name": display_name,
                "role": string_value(identity.get("role")),
                "notes": string_value(identity.get("notes")),
                "name_source": string_value(identity.get("name_source"), default="default"),
                "segment_count": 0,
                "total_seconds": 0.0,
                "first_timestamp": string_value(segment.get("timestamp")),
            },
        )
        entry["segment_count"] += 1
        entry["total_seconds"] = round(float_value(entry.get("total_seconds")) + duration, 3)
        if not has_value(entry.get("first_timestamp")):
            entry["first_timestamp"] = string_value(segment.get("timestamp"))

    return enriched, list(speaker_stats.values())


def summarize_speaker_distribution(
    speaker_map: list[dict[str, Any]],
    expected_speaker_count: int,
) -> dict[str, Any]:
    total_seconds = round(sum(float_value(item.get("total_seconds")) for item in speaker_map), 3)
    sparse_speakers: list[dict[str, Any]] = []
    summary: list[dict[str, Any]] = []
    for item in speaker_map:
        seconds = round(float_value(item.get("total_seconds")), 3)
        share = round(seconds / total_seconds, 4) if total_seconds > 0 else 0.0
        entry = {
            "speaker_id": string_value(item.get("speaker_id")),
            "speaker": string_value(item.get("speaker")),
            "segment_count": int(item.get("segment_count", 0) or 0),
            "total_seconds": seconds,
            "share": share,
        }
        summary.append(entry)
        if seconds < 90 or share < 0.04:
            sparse_speakers.append(entry)
    return {
        "detected_speaker_count": len(speaker_map),
        "expected_speaker_count": expected_speaker_count,
        "total_speaker_seconds": total_seconds,
        "sparse_speakers": sparse_speakers,
        "distribution": summary,
        "status": (
            "speaker_count_mismatch"
            if expected_speaker_count >= 2 and len(speaker_map) != expected_speaker_count
            else "sparse_speaker_detected"
            if sparse_speakers
            else "balanced"
        ),
    }


def stable_original_speaker_order(turns: list[dict[str, Any]]) -> list[str]:
    ordered: OrderedDict[str, None] = OrderedDict()
    for turn in sorted(turns, key=lambda item: (float_value(item.get("start")), float_value(item.get("end")))):
        speaker_id = string_value(turn.get("speaker_id"))
        if has_value(speaker_id) and speaker_id not in ordered:
            ordered[speaker_id] = None
    return list(ordered.keys())


def build_refinement_turn_windows(
    turns: list[dict[str, Any]],
    window_seconds: float,
    min_turn_seconds: float,
    max_turns: int,
) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    clip_duration = max(0.8, float_value(window_seconds, default=DEFAULT_REFINEMENT_WINDOW_SECONDS))
    minimum_duration = max(0.4, float_value(min_turn_seconds, default=DEFAULT_REFINEMENT_TURN_MIN_SECONDS))
    for index, turn in enumerate(turns):
        start = float_value(turn.get("start"))
        end = float_value(turn.get("end"))
        duration = max(0.0, end - start)
        if duration < minimum_duration or not has_value(turn.get("speaker_id")):
            continue
        center = start + duration / 2
        clip_start = max(0.0, center - clip_duration / 2)
        candidates.append(
            {
                "index": index,
                "turn": turn,
                "duration": duration,
                "speaker_id": string_value(turn.get("speaker_id")),
                "clip_start": round(clip_start, 3),
                "clip_end": round(clip_start + clip_duration, 3),
            }
        )
    candidates.sort(key=lambda item: (-float_value(item.get("duration")), int(item.get("index", 0))))
    if max_turns > 0:
        candidates = candidates[:max_turns]
    candidates.sort(key=lambda item: int(item.get("index", 0)))
    return candidates


def extract_refinement_embeddings(
    pipeline: Any,
    audio_input: dict[str, Any],
    candidates: list[dict[str, Any]],
    *,
    batch_size: int,
) -> list[dict[str, Any]]:
    import torch
    import torch.nn.functional as F
    from pyannote.core import Segment

    if not candidates:
        return []

    results: list[dict[str, Any]] = []
    effective_batch_size = max(1, int(batch_size or DEFAULT_REFINEMENT_BATCH_SIZE))
    for batch_start in range(0, len(candidates), effective_batch_size):
        batch = candidates[batch_start : batch_start + effective_batch_size]
        waveforms: list[torch.Tensor] = []
        for candidate in batch:
            waveform, _ = pipeline._audio.crop(
                audio_input,
                Segment(float_value(candidate.get("clip_start")), float_value(candidate.get("clip_end"))),
                mode="pad",
            )
            waveforms.append(waveform)

        max_samples = max(int(waveform.shape[-1]) for waveform in waveforms)
        padded = [
            waveform if int(waveform.shape[-1]) == max_samples else F.pad(waveform, (0, max_samples - int(waveform.shape[-1])))
            for waveform in waveforms
        ]
        waveform_batch = torch.stack(padded, dim=0)
        embedding_batch = pipeline._embedding(waveform_batch)

        for candidate, embedding in zip(batch, embedding_batch):
            results.append(
                {
                    **candidate,
                    "embedding": embedding.tolist() if hasattr(embedding, "tolist") else list(embedding),
                }
            )
    return results


def cluster_embedding_vectors(vectors: list[list[float]], cluster_count: int) -> list[int]:
    from sklearn.cluster import AgglomerativeClustering

    if cluster_count < 2:
        return [0 for _ in vectors]

    try:
        model = AgglomerativeClustering(n_clusters=cluster_count, metric="cosine", linkage="average")
    except TypeError:
        model = AgglomerativeClustering(n_clusters=cluster_count, affinity="cosine", linkage="average")
    return [int(label) for label in model.fit_predict(vectors)]


def build_cluster_centroids(assignments: list[dict[str, Any]]) -> dict[int, list[float]]:
    centroids: dict[int, list[float]] = {}
    if not assignments:
        return centroids
    import numpy as np

    grouped: dict[int, list[tuple[np.ndarray, float]]] = {}
    for item in assignments:
        label = int(item.get("cluster_label", 0))
        vector = np.array(item.get("embedding") or [], dtype="float32")
        if vector.size == 0:
            continue
        grouped.setdefault(label, []).append((vector, max(0.3, float_value(item.get("duration"), default=1.0))))

    for label, values in grouped.items():
        weighted = sum(vector * weight for vector, weight in values)
        norm = float(np.linalg.norm(weighted))
        centroids[label] = ((weighted / norm) if norm > 0 else weighted).astype("float32").tolist()
    return centroids


def cosine_similarity(left: list[float], right: list[float]) -> float:
    import numpy as np

    left_array = np.array(left, dtype="float32")
    right_array = np.array(right, dtype="float32")
    left_norm = float(np.linalg.norm(left_array))
    right_norm = float(np.linalg.norm(right_array))
    if left_norm <= 0 or right_norm <= 0:
        return -1.0
    return float(np.dot(left_array / left_norm, right_array / right_norm))


def map_clusters_to_speaker_ids(assignments: list[dict[str, Any]], turns: list[dict[str, Any]]) -> dict[int, str]:
    cluster_scores: list[tuple[float, int, str]] = []
    for item in assignments:
        cluster_scores.append(
            (
                float_value(item.get("duration"), default=0.0),
                int(item.get("cluster_label", 0)),
                string_value(item.get("speaker_id")),
            )
        )

    by_cluster: dict[int, dict[str, float]] = {}
    for duration, cluster_label, speaker_id in cluster_scores:
        by_cluster.setdefault(cluster_label, {})
        by_cluster[cluster_label][speaker_id] = round(by_cluster[cluster_label].get(speaker_id, 0.0) + duration, 3)

    ordered_original_ids = stable_original_speaker_order(turns)
    mapping: dict[int, str] = {}
    used_ids: set[str] = set()
    scored_pairs: list[tuple[float, int, str]] = []
    for cluster_label, scores in by_cluster.items():
        for speaker_id, duration in scores.items():
            scored_pairs.append((duration, cluster_label, speaker_id))
    scored_pairs.sort(reverse=True)

    for _, cluster_label, speaker_id in scored_pairs:
        if cluster_label in mapping or speaker_id in used_ids:
            continue
        mapping[cluster_label] = speaker_id
        used_ids.add(speaker_id)

    remaining_original_ids = [speaker_id for speaker_id in ordered_original_ids if speaker_id not in used_ids]
    for cluster_label in sorted(by_cluster.keys()):
        if cluster_label in mapping:
            continue
        if remaining_original_ids:
            mapping[cluster_label] = remaining_original_ids.pop(0)
            continue
        mapping[cluster_label] = f"SPEAKER_{len(mapping):02d}"
    return mapping


def refine_turns_with_embeddings(
    *,
    turns: list[dict[str, Any]],
    pipeline: Any,
    audio_input: dict[str, Any],
    expected_speaker_count: int,
    refinement_strategy: str,
    refinement_turn_min_seconds: float,
    refinement_window_seconds: float,
    refinement_batch_size: int,
    refinement_max_turns: int,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    strategy = string_value(refinement_strategy, default=DEFAULT_REFINEMENT_STRATEGY).lower()
    if strategy not in {"embedding_agglomerative", "embedding_refine"}:
        return turns, {"enabled": False, "status": "unsupported_strategy", "strategy": strategy}
    if expected_speaker_count < 2:
        return turns, {"enabled": False, "status": "skipped_no_expected_speaker_count", "strategy": strategy}

    original_speaker_ids = dedupe_strings([string_value(turn.get("speaker_id")) for turn in turns if has_value(turn.get("speaker_id"))])
    if len(original_speaker_ids) < 2:
        return turns, {"enabled": False, "status": "skipped_not_enough_original_speakers", "strategy": strategy}

    candidates = build_refinement_turn_windows(
        turns=turns,
        window_seconds=refinement_window_seconds,
        min_turn_seconds=refinement_turn_min_seconds,
        max_turns=refinement_max_turns,
    )
    if len(candidates) < expected_speaker_count:
        return turns, {
            "enabled": False,
            "status": "skipped_not_enough_candidate_turns",
            "strategy": strategy,
            "candidate_turn_count": len(candidates),
        }

    embedded_candidates = extract_refinement_embeddings(
        pipeline=pipeline,
        audio_input=audio_input,
        candidates=candidates,
        batch_size=refinement_batch_size,
    )
    vectors = [item.get("embedding") or [] for item in embedded_candidates if item.get("embedding")]
    if len(vectors) < expected_speaker_count:
        return turns, {
            "enabled": False,
            "status": "skipped_embedding_extraction_too_small",
            "strategy": strategy,
            "embedded_turn_count": len(vectors),
        }

    cluster_labels = cluster_embedding_vectors(vectors, expected_speaker_count)
    labeled_candidates: list[dict[str, Any]] = []
    for item, label in zip(embedded_candidates, cluster_labels):
        labeled_candidates.append({**item, "cluster_label": int(label)})

    cluster_to_speaker_id = map_clusters_to_speaker_ids(labeled_candidates, turns)
    cluster_centroids = build_cluster_centroids(labeled_candidates)
    assigned_turn_indices = {int(item.get("index", -1)): int(item.get("cluster_label", 0)) for item in labeled_candidates}

    refined_turns: list[dict[str, Any]] = []
    fallback_reassigned_count = 0
    for index, turn in enumerate(turns):
        refined_turn = dict(turn)
        if index in assigned_turn_indices:
            cluster_label = assigned_turn_indices[index]
            refined_turn["speaker_id"] = cluster_to_speaker_id.get(cluster_label, string_value(turn.get("speaker_id")))
            refined_turns.append(refined_turn)
            continue

        refined_turns.append(refined_turn)

    cluster_distribution: dict[int, dict[str, Any]] = {}
    for item in labeled_candidates:
        label = int(item.get("cluster_label", 0))
        entry = cluster_distribution.setdefault(
            label,
            {
                "cluster_label": label,
                "turn_count": 0,
                "total_seconds": 0.0,
                "mapped_speaker_id": cluster_to_speaker_id.get(label, ""),
            },
        )
        entry["turn_count"] += 1
        entry["total_seconds"] = round(float_value(entry.get("total_seconds")) + float_value(item.get("duration")), 3)

    return refined_turns, {
        "enabled": True,
        "status": "applied",
        "strategy": strategy,
        "candidate_turn_count": len(candidates),
        "embedded_turn_count": len(labeled_candidates),
        "expected_speaker_count": expected_speaker_count,
        "original_speaker_count": len(original_speaker_ids),
        "fallback_reassigned_count": fallback_reassigned_count,
        "cluster_mapping": [
            {
                "cluster_label": int(label),
                "speaker_id": speaker_id,
            }
            for label, speaker_id in sorted(cluster_to_speaker_id.items(), key=lambda item: item[0])
        ],
        "cluster_distribution": [cluster_distribution[label] for label in sorted(cluster_distribution.keys())],
        "centroid_count": len(cluster_centroids),
    }


def render_speaker_transcript(segments: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for segment in segments:
        text = string_value(segment.get("text"))
        if not has_value(text):
            continue
        timestamp = string_value(segment.get("timestamp"))
        speaker = string_value(segment.get("speaker"))
        prefix_parts = [part for part in [f"[{timestamp}]" if has_value(timestamp) else "", speaker] if has_value(part)]
        prefix = " ".join(prefix_parts).strip()
        lines.append(f"{prefix}: {text}" if has_value(prefix) else text)
    return "\n".join(lines).strip()


def run_mock_provider(mock_path: str) -> list[dict[str, Any]]:
    if not has_value(mock_path):
        raise RuntimeError("Mock diarization requires --mock-diarization-path.")
    path = Path(mock_path)
    if not path.exists():
        raise RuntimeError(f"Mock diarization file does not exist: {mock_path}")
    return normalize_turns(load_json(path))


def load_pyannote_pipeline(model_name: str, token_env: str, device: str):
    require_cuda_runtime(device, "Pyannote diarization")

    try:
        from pyannote.audio import Pipeline
        import torch
    except ImportError as exc:
        raise RuntimeError("pyannote.audio is not installed.") from exc

    token = os.environ.get(token_env or "HF_TOKEN", "").strip()
    if not token:
        raise RuntimeError(f"Environment variable {token_env or 'HF_TOKEN'} is required for pyannote diarization.")

    pipeline_kwargs: dict[str, Any] = {}
    from_pretrained_signature = inspect.signature(Pipeline.from_pretrained)
    if "token" in from_pretrained_signature.parameters:
        pipeline_kwargs["token"] = token
    else:
        pipeline_kwargs["use_auth_token"] = token

    pipeline = Pipeline.from_pretrained(model_name or "pyannote/speaker-diarization-3.1", **pipeline_kwargs)
    pipeline.to(torch.device("cuda"))
    return pipeline


def load_audio_input(audio_path: str) -> dict[str, Any]:
    try:
        import av
        import numpy as np
        import torch
    except ImportError as exc:
        raise RuntimeError("PyAV, numpy, and torch are required to preload audio for pyannote diarization.") from exc

    decoded_chunks: list[Any] = []
    sample_rate = 0
    try:
        with av.open(audio_path) as container:
            for frame in container.decode(audio=0):
                array = frame.to_ndarray()
                if getattr(array, "ndim", 0) == 1:
                    array = array.reshape(1, -1)
                decoded_chunks.append(array)
                sample_rate = int(getattr(frame, "sample_rate", 0) or sample_rate)
    except Exception as exc:
        raise RuntimeError(f"Failed to decode audio for diarization: {exc}") from exc

    if not decoded_chunks or sample_rate <= 0:
        raise RuntimeError(f"No decodable audio frames were found in: {audio_path}")

    waveform = np.concatenate(decoded_chunks, axis=1)
    if waveform.shape[0] > 1:
        waveform = waveform.mean(axis=0, keepdims=True)
    if np.issubdtype(waveform.dtype, np.integer):
        info = np.iinfo(waveform.dtype)
        max_abs = float(max(abs(info.min), info.max)) or 1.0
        waveform = waveform.astype("float32") / max_abs
    else:
        waveform = waveform.astype("float32")

    return {
        "waveform": torch.from_numpy(waveform),
        "sample_rate": sample_rate,
    }


def run_pyannote_provider(
    audio_path: str,
    model_name: str,
    token_env: str,
    device: str,
    expected_speaker_count: int,
) -> tuple[list[dict[str, Any]], Any, dict[str, Any]]:
    try:
        from pyannote.core import Annotation
    except ImportError as exc:
        raise RuntimeError("pyannote.audio is not installed.") from exc

    pipeline = load_pyannote_pipeline(model_name, token_env, device)
    audio_input = load_audio_input(audio_path)
    if expected_speaker_count >= 2:
        try:
            diarization_output = pipeline(audio_input, num_speakers=expected_speaker_count)
        except TypeError:
            diarization_output = pipeline(
                audio_input,
                min_speakers=expected_speaker_count,
                max_speakers=expected_speaker_count,
            )
    else:
        diarization_output = pipeline(audio_input)

    if isinstance(diarization_output, Annotation):
        diarization = diarization_output
    elif hasattr(diarization_output, "speaker_diarization"):
        diarization = diarization_output.speaker_diarization
    else:
        raise RuntimeError(f"Unsupported pyannote diarization output type: {type(diarization_output)!r}")

    turns: list[dict[str, Any]] = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        turns.append(
            {
                "start": round(float(turn.start), 3),
                "end": round(float(turn.end), 3),
                "speaker_id": string_value(speaker),
            }
        )
    return turns, pipeline, audio_input


def run_whisperx_provider(
    audio_path: str,
    model_name: str,
    token_env: str,
    device: str,
    expected_speaker_count: int,
) -> list[dict[str, Any]]:
    try:
        import whisperx
    except ImportError as exc:
        raise RuntimeError("whisperx is not installed.") from exc

    require_cuda_runtime(device, "WhisperX diarization")

    diarization_pipeline_type = getattr(whisperx, "DiarizationPipeline", None)
    if diarization_pipeline_type is None:
        try:
            from whisperx.diarize import DiarizationPipeline as whisperx_diarization_pipeline
        except ImportError as exc:
            raise RuntimeError("WhisperX diarization pipeline is not available in the installed package.") from exc
        diarization_pipeline_type = whisperx_diarization_pipeline

    requested_device = string_value(device, default="cuda").lower()

    token = os.environ.get(token_env or "HF_TOKEN", "").strip()
    if not token:
        raise RuntimeError(f"Environment variable {token_env or 'HF_TOKEN'} is required for WhisperX diarization.")

    pipeline_kwargs: dict[str, Any] = {
        "device": requested_device or "cuda",
    }
    if has_value(model_name):
        pipeline_signature = inspect.signature(diarization_pipeline_type.__init__)
        if "model_name" in pipeline_signature.parameters:
            pipeline_kwargs["model_name"] = model_name
    init_signature = inspect.signature(diarization_pipeline_type.__init__)
    if "token" in init_signature.parameters:
        pipeline_kwargs["token"] = token
    elif "use_auth_token" in init_signature.parameters:
        pipeline_kwargs["use_auth_token"] = token
    else:
        raise RuntimeError("Installed WhisperX diarization pipeline does not expose a supported token argument.")

    diarize_pipeline = diarization_pipeline_type(**pipeline_kwargs)
    audio_input = load_audio_input(audio_path)
    waveform = audio_input.get("waveform")
    if waveform is None:
        raise RuntimeError("Failed to preload audio for WhisperX diarization.")
    if hasattr(waveform, "detach"):
        waveform = waveform.detach().cpu().numpy()
    if getattr(waveform, "ndim", 0) > 1:
        waveform = waveform[0]

    diarize_kwargs: dict[str, Any] = {}
    if expected_speaker_count >= 2:
        diarize_kwargs["min_speakers"] = expected_speaker_count
        diarize_kwargs["max_speakers"] = expected_speaker_count
    diarization = diarize_pipeline(waveform, **diarize_kwargs)
    if hasattr(diarization, "to_dict"):
        return normalize_turns(diarization.to_dict("records"))
    return normalize_turns(diarization)


def build_result(
    *,
    success: bool,
    status: str,
    provider: str,
    model: str,
    segments: list[dict[str, Any]],
    speaker_map: list[dict[str, Any]],
    raw_turns: list[dict[str, Any]],
    error: str,
    speaker_inference: dict[str, Any],
) -> dict[str, Any]:
    return {
        "success": success,
        "status": status,
        "provider": provider,
        "model": model,
        "segment_count": len(segments),
        "speaker_count": len(speaker_map),
        "segments": segments,
        "speaker_map": speaker_map,
        "speakers": [string_value(item.get("speaker")) for item in speaker_map if has_value(item.get("speaker"))],
        "speaker_transcript": render_speaker_transcript(segments),
        "turn_count": len(raw_turns),
        "turns": raw_turns,
        "speaker_inference": speaker_inference,
        "error": error,
    }


def main() -> int:
    configure_console_output()
    configure_runtime_environment()

    parser = argparse.ArgumentParser(description="Enhance podcast transcript segments with diarization speakers.")
    parser.add_argument("--audio-path", required=True)
    parser.add_argument("--segments-json", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--provider", default="pyannote")
    parser.add_argument("--model", default="")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--hf-token-env", default="HF_TOKEN")
    parser.add_argument("--mock-diarization-path", default="")
    parser.add_argument("--manual-speakers-path", default="")
    parser.add_argument("--min-overlap-ratio", type=float, default=0.35)
    parser.add_argument("--refinement-enabled", default="false")
    parser.add_argument("--refinement-strategy", default=DEFAULT_REFINEMENT_STRATEGY)
    parser.add_argument("--refinement-turn-min-seconds", type=float, default=DEFAULT_REFINEMENT_TURN_MIN_SECONDS)
    parser.add_argument("--refinement-window-seconds", type=float, default=DEFAULT_REFINEMENT_WINDOW_SECONDS)
    parser.add_argument("--refinement-batch-size", type=int, default=DEFAULT_REFINEMENT_BATCH_SIZE)
    parser.add_argument("--refinement-max-turns", type=int, default=DEFAULT_REFINEMENT_MAX_TURNS)
    args = parser.parse_args()

    audio_path = Path(args.audio_path).resolve()
    segments_path = Path(args.segments_json).resolve()
    output_path = Path(args.output_json).resolve()
    provider = string_value(args.provider, default="pyannote").lower()

    if not audio_path.exists():
        write_json(
            output_path,
            build_result(
                success=False,
                status="missing_audio",
                provider=provider,
                model=string_value(args.model),
                segments=[],
                speaker_map=[],
                raw_turns=[],
                error=f"Audio file does not exist: {audio_path}",
                speaker_inference={},
            ),
        )
        return 1

    if not segments_path.exists():
        write_json(
            output_path,
            build_result(
                success=False,
                status="missing_segments",
                provider=provider,
                model=string_value(args.model),
                segments=[],
                speaker_map=[],
                raw_turns=[],
                error=f"Transcript segments file does not exist: {segments_path}",
                speaker_inference={},
            ),
        )
        return 1

    try:
        segments = normalize_segments(load_json(segments_path))
        intro_context = build_intro_context(segments)
        expected_speaker_count = int(intro_context.get("expected_speaker_count", 0) or 0)
        refinement_enabled = bool_value(args.refinement_enabled, default=False)

        manual_overrides: dict[str, dict[str, Any]] = {}
        if has_value(args.manual_speakers_path):
            manual_path = Path(args.manual_speakers_path).resolve()
            if manual_path.exists():
                manual_overrides = normalize_manual_speakers(load_json(manual_path))

        pipeline = None
        audio_input = None
        if provider == "mock":
            turns = run_mock_provider(args.mock_diarization_path)
            model_name = string_value(args.model, default="mock-turns")
        elif provider == "pyannote":
            turns, pipeline, audio_input = run_pyannote_provider(
                str(audio_path),
                string_value(args.model),
                string_value(args.hf_token_env),
                string_value(args.device),
                expected_speaker_count,
            )
            model_name = string_value(args.model, default="pyannote/speaker-diarization-3.1")
        elif provider == "whisperx":
            turns = run_whisperx_provider(
                str(audio_path),
                string_value(args.model),
                string_value(args.hf_token_env),
                string_value(args.device),
                expected_speaker_count,
            )
            model_name = string_value(args.model, default="whisperx-diarization")
        else:
            raise RuntimeError(f"Unsupported diarization provider: {provider}")

        refinement_summary: dict[str, Any] = {
            "enabled": refinement_enabled,
            "status": "disabled",
        }
        if refinement_enabled and provider == "pyannote" and pipeline is not None and audio_input is not None:
            turns, refinement_summary = refine_turns_with_embeddings(
                turns=turns,
                pipeline=pipeline,
                audio_input=audio_input,
                expected_speaker_count=expected_speaker_count,
                refinement_strategy=string_value(args.refinement_strategy, default=DEFAULT_REFINEMENT_STRATEGY),
                refinement_turn_min_seconds=float_value(args.refinement_turn_min_seconds, default=DEFAULT_REFINEMENT_TURN_MIN_SECONDS),
                refinement_window_seconds=float_value(args.refinement_window_seconds, default=DEFAULT_REFINEMENT_WINDOW_SECONDS),
                refinement_batch_size=int_value(args.refinement_batch_size, default=DEFAULT_REFINEMENT_BATCH_SIZE),
                refinement_max_turns=int_value(args.refinement_max_turns, default=DEFAULT_REFINEMENT_MAX_TURNS),
            )
        elif refinement_enabled:
            refinement_summary = {
                "enabled": True,
                "status": "skipped_provider_not_supported",
                "provider": provider,
            }

        segments_with_speaker_ids = assign_speaker_ids(
            segments=segments,
            turns=turns,
            min_overlap_ratio=float(args.min_overlap_ratio),
        )
        _, pre_split_speaker_inference = infer_auto_speaker_profiles(
            segments=segments_with_speaker_ids,
            turns=turns,
            intro_context=intro_context,
        )
        segments_with_speaker_ids, intro_text_guided_split = apply_intro_text_guided_split(
            segments=segments_with_speaker_ids,
            speaker_inference=pre_split_speaker_inference,
        )
        segments_with_speaker_ids, sparse_speaker_turn_rescue = apply_sparse_speaker_turn_rescue(
            segments=segments_with_speaker_ids,
            turns=turns,
            expected_speaker_count=expected_speaker_count,
        )
        auto_profiles, speaker_inference = infer_auto_speaker_profiles(
            segments=segments_with_speaker_ids,
            turns=turns,
            intro_context=intro_context,
        )
        speaker_inference = {
            **speaker_inference,
            "expected_speaker_count": expected_speaker_count,
            "provider": provider,
            "refinement": refinement_summary,
            "pre_text_guided_auto_assignments": (
                pre_split_speaker_inference.get("auto_assignments")
                if isinstance(pre_split_speaker_inference.get("auto_assignments"), list)
                else []
            ),
            "intro_text_guided_split": intro_text_guided_split,
            "sparse_speaker_turn_rescue": sparse_speaker_turn_rescue,
        }
        enriched_segments, speaker_map = apply_speaker_profiles(
            segments=segments_with_speaker_ids,
            auto_profiles=auto_profiles,
            manual_overrides=manual_overrides,
        )
        intro_diagnostics = diagnose_intro_speaker_collisions(
            segments=enriched_segments,
            intro_context=intro_context,
        )
        distribution_summary = summarize_speaker_distribution(
            speaker_map=speaker_map,
            expected_speaker_count=expected_speaker_count,
        )
        speaker_quality_gate = build_speaker_quality_gate(
            distribution_summary=distribution_summary,
            intro_diagnostics=intro_diagnostics,
        )
        speaker_inference = {
            **speaker_inference,
            "alignment_strategy": "turn_aligned_split",
            "intro_diagnostics": intro_diagnostics,
            "distribution_summary": distribution_summary,
            "speaker_quality_gate": speaker_quality_gate,
        }

        success = len(speaker_map) > 0
        status = "success" if success else "no_speakers"
        result = build_result(
            success=success,
            status=status,
            provider=provider,
            model=model_name,
            segments=enriched_segments,
            speaker_map=speaker_map,
            raw_turns=turns,
            error="",
            speaker_inference=speaker_inference,
        )
        write_json(output_path, result)
        return 0 if success else 1
    except Exception as exc:
        write_json(
            output_path,
            build_result(
                success=False,
                status="failed",
                provider=provider,
                model=string_value(args.model),
                segments=[],
                speaker_map=[],
                raw_turns=[],
                error=str(exc),
                speaker_inference={},
            ),
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
