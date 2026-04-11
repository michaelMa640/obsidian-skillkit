import argparse
import json
import os
import sys
import tempfile
from collections import OrderedDict
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
        normalized.append(
            {
                "start": start,
                "end": end,
                "speaker_id": speaker_id,
            }
        )
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
        }
    return result


def build_default_manual_map(segments: list[dict[str, Any]], overrides: dict[str, dict[str, Any]]) -> OrderedDict[str, dict[str, Any]]:
    raw_speakers: OrderedDict[str, None] = OrderedDict()
    for segment in segments:
        speaker_id = string_value(segment.get("speaker_id"))
        if has_value(speaker_id) and speaker_id not in raw_speakers:
            raw_speakers[speaker_id] = None

    manual_map: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for index, speaker_id in enumerate(raw_speakers.keys(), start=1):
        override = overrides.get(speaker_id, {})
        display_name = string_value(
            override.get("speaker"),
            override.get("display_name"),
            default=f"Speaker {index}",
        )
        manual_map[speaker_id] = {
            "speaker_id": speaker_id,
            "speaker": display_name,
            "display_name": display_name,
            "role": string_value(override.get("role")),
            "notes": string_value(override.get("notes")),
        }
    for speaker_id, override in overrides.items():
        if speaker_id not in manual_map:
            display_name = string_value(
                override.get("speaker"),
                override.get("display_name"),
                default=speaker_id,
            )
            manual_map[speaker_id] = {
                "speaker_id": speaker_id,
                "speaker": display_name,
                "display_name": display_name,
                "role": string_value(override.get("role")),
                "notes": string_value(override.get("notes")),
            }
    return manual_map


def segment_overlap(segment: dict[str, Any], turn: dict[str, Any]) -> float:
    start = max(float_value(segment.get("start")), float_value(turn.get("start")))
    end = min(float_value(segment.get("end")), float_value(turn.get("end")))
    return max(0.0, end - start)


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


def apply_speakers(
    segments: list[dict[str, Any]],
    turns: list[dict[str, Any]],
    manual_overrides: dict[str, dict[str, Any]],
    min_overlap_ratio: float,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    enriched: list[dict[str, Any]] = []
    speaker_stats: OrderedDict[str, dict[str, Any]] = OrderedDict()

    for segment in segments:
        speaker_id = select_speaker_id(segment, turns, min_overlap_ratio)
        merged_segment = dict(segment)
        if has_value(speaker_id):
            merged_segment["speaker_id"] = speaker_id
        enriched.append(merged_segment)

    manual_map = build_default_manual_map(enriched, manual_overrides)

    for segment in enriched:
        speaker_id = string_value(segment.get("speaker_id"))
        if not has_value(speaker_id):
            segment.pop("speaker", None)
            continue
        manual_entry = manual_map.get(speaker_id)
        display_name = string_value(
            manual_entry.get("speaker") if manual_entry else "",
            manual_entry.get("display_name") if manual_entry else "",
            default=speaker_id,
        )
        segment["speaker"] = display_name
        if manual_entry and has_value(manual_entry.get("role")):
            segment["speaker_role"] = string_value(manual_entry.get("role"))
        duration = max(0.0, float_value(segment.get("end")) - float_value(segment.get("start")))
        entry = speaker_stats.setdefault(
            speaker_id,
            {
                "speaker_id": speaker_id,
                "speaker": display_name,
                "display_name": display_name,
                "role": string_value(manual_entry.get("role") if manual_entry else ""),
                "notes": string_value(manual_entry.get("notes") if manual_entry else ""),
                "segment_count": 0,
                "total_seconds": 0.0,
                "first_timestamp": string_value(segment.get("timestamp")),
            },
        )
        entry["segment_count"] += 1
        entry["total_seconds"] = round(float_value(entry.get("total_seconds")) + duration, 3)
        if not has_value(entry.get("first_timestamp")):
            entry["first_timestamp"] = string_value(segment.get("timestamp"))

    speaker_map = list(speaker_stats.values())
    return enriched, speaker_map


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


def run_pyannote_provider(audio_path: str, model_name: str, token_env: str, device: str) -> list[dict[str, Any]]:
    try:
        from pyannote.audio import Pipeline
    except ImportError as exc:
        raise RuntimeError("pyannote.audio is not installed.") from exc

    token = os.environ.get(token_env or "HF_TOKEN", "").strip()
    if not token:
        raise RuntimeError(f"Environment variable {token_env or 'HF_TOKEN'} is required for pyannote diarization.")

    pipeline = Pipeline.from_pretrained(model_name or "pyannote/speaker-diarization-3.1", use_auth_token=token)
    if has_value(device) and device.lower() not in {"", "auto", "cpu"}:
        try:
            import torch

            pipeline.to(torch.device(device))
        except Exception:
            pass

    diarization = pipeline(load_audio_input(audio_path))
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


def run_whisperx_provider(audio_path: str, token_env: str, device: str) -> list[dict[str, Any]]:
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
    diarization = diarize_pipeline(audio_path)
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
            ),
        )
        return 1

    try:
        segments = normalize_segments(load_json(segments_path))
        manual_overrides: dict[str, dict[str, Any]] = {}
        if has_value(args.manual_speakers_path):
            manual_path = Path(args.manual_speakers_path).resolve()
            if manual_path.exists():
                manual_overrides = normalize_manual_speakers(load_json(manual_path))

        if provider == "mock":
            turns = run_mock_provider(args.mock_diarization_path)
            model_name = string_value(args.model, default="mock-turns")
        elif provider == "pyannote":
            turns = run_pyannote_provider(str(audio_path), string_value(args.model), string_value(args.hf_token_env), string_value(args.device))
            model_name = string_value(args.model, default="pyannote/speaker-diarization-3.1")
        elif provider == "whisperx":
            turns = run_whisperx_provider(str(audio_path), string_value(args.hf_token_env), string_value(args.device))
            model_name = string_value(args.model, default="whisperx-diarization")
        else:
            raise RuntimeError(f"Unsupported diarization provider: {provider}")

        enriched_segments, speaker_map = apply_speakers(
            segments=segments,
            turns=turns,
            manual_overrides=manual_overrides,
            min_overlap_ratio=float(args.min_overlap_ratio),
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
            ),
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
