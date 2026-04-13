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


def extract_intro_mentions(segments: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[str]]:
    mentions: list[dict[str, Any]] = []
    intro_names: list[str] = []
    for segment in intro_window_segments(segments):
        text = string_value(segment.get("text"), segment.get("raw_text"))
        if not has_value(text):
            continue
        segment_matches: list[tuple[int, int, str]] = []
        seen_spans: set[tuple[int, int, str]] = set()
        for pattern in SELF_INTRO_PATTERNS:
            for match in pattern.finditer(text):
                name = normalize_name_candidate(match.group("name"))
                key = (match.start("name"), match.end("name"), name)
                if not has_value(name) or key in seen_spans:
                    continue
                seen_spans.add(key)
                segment_matches.append(key)
                if name not in intro_names:
                    intro_names.append(name)
        if not segment_matches:
            continue

        segment_matches.sort(key=lambda item: item[0])
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
    return {
        "intro_names": intro_names,
        "intro_mentions": intro_mentions,
        "expected_speaker_count": infer_expected_speaker_count(segments, intro_names),
        "intro_segment_count": len(intro_window_segments(segments)),
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


def assign_speaker_ids(
    segments: list[dict[str, Any]],
    turns: list[dict[str, Any]],
    min_overlap_ratio: float,
) -> list[dict[str, Any]]:
    enriched: list[dict[str, Any]] = []
    for segment in segments:
        merged_segment = dict(segment)
        speaker_id = select_speaker_id(segment, turns, min_overlap_ratio)
        if has_value(speaker_id):
            merged_segment["speaker_id"] = speaker_id
        enriched.append(merged_segment)
    return enriched


def speaker_order_from_intro(segments: list[dict[str, Any]], turns: list[dict[str, Any]]) -> list[str]:
    speaker_ids: list[str] = []
    seen: set[str] = set()
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
        speaker_name_scores.setdefault(speaker_id, {})
        speaker_name_scores[speaker_id][name] = round(speaker_name_scores[speaker_id].get(name, 0.0) + confidence, 3)
        speaker_name_evidence.setdefault(speaker_id, []).append(
            {
                "name": name,
                "timestamp": string_value(mention.get("timestamp")),
                "text": string_value(mention.get("text")),
                "confidence": confidence,
            }
        )

    candidate_pairs: list[tuple[float, int, int, str, str]] = []
    detected_speaker_order = speaker_order_from_intro(segments, turns)
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

    remaining_speakers = [speaker_id for speaker_id in detected_speaker_order if speaker_id not in assignments]
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
) -> list[dict[str, Any]]:
    try:
        from pyannote.audio import Pipeline
        from pyannote.core import Annotation
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
    if has_value(device) and device.lower() not in {"", "auto", "cpu"}:
        try:
            import torch

            pipeline.to(torch.device(device))
        except Exception:
            pass

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
    return turns


def run_whisperx_provider(
    audio_path: str,
    token_env: str,
    device: str,
    expected_speaker_count: int,
) -> list[dict[str, Any]]:
    try:
        import whisperx
    except ImportError as exc:
        raise RuntimeError("whisperx is not installed.") from exc

    token = os.environ.get(token_env or "HF_TOKEN", "").strip()
    if not token:
        raise RuntimeError(f"Environment variable {token_env or 'HF_TOKEN'} is required for WhisperX diarization.")

    diarize_pipeline = whisperx.DiarizationPipeline(
        use_auth_token=token,
        device=(device or "cpu"),
    )
    diarize_kwargs: dict[str, Any] = {}
    if expected_speaker_count >= 2:
        diarize_kwargs["min_speakers"] = expected_speaker_count
        diarize_kwargs["max_speakers"] = expected_speaker_count
    diarization = diarize_pipeline(audio_path, **diarize_kwargs)
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
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--hf-token-env", default="HF_TOKEN")
    parser.add_argument("--mock-diarization-path", default="")
    parser.add_argument("--manual-speakers-path", default="")
    parser.add_argument("--min-overlap-ratio", type=float, default=0.35)
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

        manual_overrides: dict[str, dict[str, Any]] = {}
        if has_value(args.manual_speakers_path):
            manual_path = Path(args.manual_speakers_path).resolve()
            if manual_path.exists():
                manual_overrides = normalize_manual_speakers(load_json(manual_path))

        if provider == "mock":
            turns = run_mock_provider(args.mock_diarization_path)
            model_name = string_value(args.model, default="mock-turns")
        elif provider == "pyannote":
            turns = run_pyannote_provider(
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
                string_value(args.hf_token_env),
                string_value(args.device),
                expected_speaker_count,
            )
            model_name = string_value(args.model, default="whisperx-diarization")
        else:
            raise RuntimeError(f"Unsupported diarization provider: {provider}")

        segments_with_speaker_ids = assign_speaker_ids(
            segments=segments,
            turns=turns,
            min_overlap_ratio=float(args.min_overlap_ratio),
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
        }
        enriched_segments, speaker_map = apply_speaker_profiles(
            segments=segments_with_speaker_ids,
            auto_profiles=auto_profiles,
            manual_overrides=manual_overrides,
        )

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
