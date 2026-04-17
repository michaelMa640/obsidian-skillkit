import argparse
import json
import os
import re
import site
import sys
import warnings
from pathlib import Path
from typing import Any


TIMESTAMP_RE = re.compile(r"^(?P<ts>(?:\d{2}:)?\d{2}:\d{2})\s+(?P<text>.+?)\s*$")
CUDA_DLL_HANDLES: list[Any] = []
CUDA_KEEPALIVE_REFERENCES: list[Any] = []

# requests may emit an environment-level dependency warning on import, which is
# noisy but not fatal for local GPU ASR execution.
warnings.filterwarnings(
    "ignore",
    message=r".*urllib3 .* doesn't match a supported version!.*",
)


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    return text in {"1", "true", "yes", "on"}


def write_json(path: str, payload: dict[str, Any]) -> None:
    Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def should_hard_exit(provider: str, device: str) -> bool:
    return sys.platform == "win32" and str(provider).strip().lower() == "faster-whisper" and str(device).strip().lower() == "cuda"


def hard_exit(code: int) -> int:
    try:
        sys.stdout.flush()
    except Exception:
        pass
    try:
        sys.stderr.flush()
    except Exception:
        pass
    os._exit(int(code))


def keep_cuda_objects_alive(*refs: Any) -> None:
    CUDA_KEEPALIVE_REFERENCES[:] = list(refs)


def read_text_if_exists(path: str | None) -> str:
    if not path:
        return ""
    candidate = Path(path)
    if not candidate.exists():
        return ""
    return candidate.read_text(encoding="utf-8").lstrip("\ufeff").strip()


def format_timestamp(seconds: float) -> str:
    total_seconds = max(int(seconds), 0)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"


def parse_timestamp_seconds(value: str) -> float:
    parts = [int(part) for part in value.split(":")]
    if len(parts) == 2:
        minutes, seconds = parts
        return float(minutes * 60 + seconds)
    if len(parts) == 3:
        hours, minutes, seconds = parts
        return float(hours * 3600 + minutes * 60 + seconds)
    raise ValueError(f"Unsupported timestamp format: {value}")


def configure_cuda_runtime(device: str) -> None:
    if str(device).strip().lower() != "cuda":
        return
    if sys.platform != "win32":
        return

    add_dll_directory = getattr(os, "add_dll_directory", None)
    dll_dirs: list[str] = []
    seen: set[str] = set()

    for site_path in site.getsitepackages():
        nvidia_root = Path(site_path) / "nvidia"
        if not nvidia_root.exists():
            continue
        for child in nvidia_root.iterdir():
            candidate = child / "bin"
            if not candidate.exists():
                continue
            resolved = str(candidate.resolve())
            if resolved in seen:
                continue
            seen.add(resolved)
            dll_dirs.append(resolved)
            if callable(add_dll_directory):
                try:
                    CUDA_DLL_HANDLES.append(add_dll_directory(resolved))
                except OSError:
                    pass

    if dll_dirs:
        existing_path = os.environ.get("PATH", "")
        os.environ["PATH"] = os.pathsep.join(dll_dirs + [existing_path])


def require_cuda_runtime(device: str) -> None:
    requested_device = str(device).strip().lower()
    if requested_device != "cuda":
        raise RuntimeError("Podcast ASR is locked to GPU-only. --device must be cuda.")

    configure_cuda_runtime(requested_device)

    try:
        import ctranslate2
        import torch
    except ImportError as exc:
        raise RuntimeError(
            "Podcast ASR is locked to GPU-only, but the active Python environment is missing torch or ctranslate2."
        ) from exc

    if not torch.cuda.is_available():
        raise RuntimeError(
            "Podcast ASR is locked to GPU-only, but torch.cuda.is_available() is False in the active Python environment."
        )

    getter = getattr(ctranslate2, "get_cuda_device_count", None)
    if not callable(getter):
        raise RuntimeError(
            "Podcast ASR is locked to GPU-only, but the active CTranslate2 build does not expose CUDA support."
        )

    try:
        cuda_device_count = int(getter())
    except Exception as exc:
        raise RuntimeError("Failed to query CTranslate2 CUDA device count.") from exc

    if cuda_device_count <= 0:
        raise RuntimeError(
            "Podcast ASR is locked to GPU-only, but the active CTranslate2 runtime reports no CUDA devices."
        )


def build_converter(normalize_script: str) -> tuple[Any | None, str]:
    normalized = normalize_script.strip().lower()
    if normalized in {"", "none", "original", "raw"}:
        return None, "none"
    if normalized not in {"simplified", "zh-cn", "zh-hans", "hans"}:
        raise RuntimeError(f"Unsupported normalize-script value: {normalize_script}")
    try:
        from opencc import OpenCC
    except ImportError as exc:
        raise RuntimeError(
            "Simplified transcript normalization requires the 'opencc-python-reimplemented' or 'opencc' package."
        ) from exc
    return OpenCC("t2s"), "opencc:t2s"


def normalize_text(text: str, converter: Any | None) -> str:
    if converter is None or not text:
        return text
    return str(converter.convert(text)).strip()


def build_segment(index: int, start: float, end: float, raw_text: str, text: str) -> dict[str, Any]:
    return {
        "index": index,
        "start": round(float(start), 3),
        "end": round(float(end), 3),
        "timestamp": format_timestamp(float(start)),
        "raw_text": raw_text,
        "text": text,
    }


def segments_to_transcript(segments: list[dict[str, Any]], field: str) -> str:
    lines: list[str] = []
    for segment in segments:
        text = str(segment.get(field, "")).strip()
        if not text:
            continue
        lines.append(f"{segment['timestamp']} {text}")
    return "\n".join(lines).strip()


def parse_mock_segments(transcript_raw: str, converter: Any | None) -> list[dict[str, Any]]:
    segments: list[dict[str, Any]] = []
    for index, line in enumerate(transcript_raw.splitlines()):
        stripped = line.strip()
        if not stripped:
            continue
        timestamp_match = TIMESTAMP_RE.match(stripped)
        if timestamp_match:
            timestamp = timestamp_match.group("ts")
            raw_text = timestamp_match.group("text").strip()
            start = parse_timestamp_seconds(timestamp)
        else:
            raw_text = stripped
            start = float(index)
        segments.append(
            build_segment(
                index=len(segments),
                start=start,
                end=start,
                raw_text=raw_text,
                text=normalize_text(raw_text, converter),
            )
        )
    return segments


def build_result_payload(
    provider: str,
    model: str,
    language: str,
    transcript_raw: str,
    segments: list[dict[str, Any]],
    normalization: str,
) -> dict[str, Any]:
    transcript = segments_to_transcript(segments, "text")
    if not transcript:
        raise RuntimeError("ASR finished without returning any transcript text.")
    transcript_raw_rendered = segments_to_transcript(segments, "raw_text")
    return {
        "success": True,
        "provider": provider,
        "model": model,
        "language": language,
        "transcript_raw": transcript_raw_rendered if transcript_raw_rendered else transcript_raw,
        "transcript": transcript,
        "segments": segments,
        "segment_count": len(segments),
        "normalization": normalization,
        "normalization_applied": transcript != (transcript_raw_rendered if transcript_raw_rendered else transcript_raw),
        "error": "",
    }


def build_mock_result(audio_path: str, mock_transcript_path: str | None, normalize_script: str) -> dict[str, Any]:
    transcript_raw = read_text_if_exists(mock_transcript_path)
    if not transcript_raw:
        transcript_raw = f"00:00 Mock ASR transcript for {Path(audio_path).stem}."
    converter, normalization = build_converter(normalize_script)
    segments = parse_mock_segments(transcript_raw, converter)
    return build_result_payload(
        provider="mock",
        model="mock",
        language="zh",
        transcript_raw=transcript_raw,
        segments=segments,
        normalization=normalization,
    )


def build_faster_whisper_result(
    audio_path: str,
    model_name: str,
    language: str,
    device: str,
    compute_type: str,
    beam_size: int,
    vad_filter: bool,
    normalize_script: str,
) -> dict[str, Any]:
    require_cuda_runtime(device)
    try:
        from faster_whisper import WhisperModel
    except ImportError as exc:
        raise RuntimeError(
            "faster-whisper is not installed. Install it in the active Python environment before enabling podcast ASR fallback."
        ) from exc

    model_kwargs: dict[str, Any] = {}
    if device != "auto":
        model_kwargs["device"] = device
    if compute_type != "auto":
        model_kwargs["compute_type"] = compute_type

    model = WhisperModel(model_name, **model_kwargs)
    transcribe_kwargs: dict[str, Any] = {
        "beam_size": beam_size,
        "vad_filter": vad_filter,
    }
    if language and language.lower() != "auto":
        transcribe_kwargs["language"] = language

    converter, normalization = build_converter(normalize_script)
    raw_lines: list[str] = []
    segments_payload: list[dict[str, Any]] = []
    segments, info = model.transcribe(audio_path, **transcribe_kwargs)
    for segment in segments:
        raw_text = str(segment.text).strip()
        if not raw_text:
            continue
        normalized_text = normalize_text(raw_text, converter)
        start = float(segment.start)
        end = float(getattr(segment, "end", segment.start))
        segments_payload.append(
            build_segment(
                index=len(segments_payload),
                start=start,
                end=end,
                raw_text=raw_text,
                text=normalized_text,
            )
        )
        raw_lines.append(f"{format_timestamp(start)} {raw_text}")

    detected_language = getattr(info, "language", "") or language
    transcript_raw = "\n".join(raw_lines).strip()
    payload = build_result_payload(
        provider="faster-whisper",
        model=model_name,
        language=detected_language,
        transcript_raw=transcript_raw,
        segments=segments_payload,
        normalization=normalization,
    )
    if should_hard_exit("faster-whisper", device):
        # Keep the CUDA-backed objects alive until the caller writes JSON and
        # terminates the process. Releasing them during function return can
        # abort the interpreter on Windows.
        keep_cuda_objects_alive(model, info, segments, converter)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Podcast ASR fallback runner.")
    parser.add_argument("--audio-path", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--provider", default="faster-whisper")
    parser.add_argument("--model", default="large-v3")
    parser.add_argument("--language", default="zh")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--compute-type", default="float16")
    parser.add_argument("--beam-size", type=int, default=5)
    parser.add_argument("--vad-filter", default="true")
    parser.add_argument("--normalize-script", default="simplified")
    parser.add_argument("--mock-transcript-path", default="")
    args = parser.parse_args()

    audio_path = str(Path(args.audio_path).resolve())
    output_json = str(Path(args.output_json).resolve())
    provider = str(args.provider).strip().lower()

    if not Path(audio_path).exists():
        payload = {
            "success": False,
            "provider": provider,
            "model": str(args.model),
            "language": str(args.language),
            "transcript_raw": "",
            "transcript": "",
            "segments": [],
            "segment_count": 0,
            "normalization": "none",
            "normalization_applied": False,
            "error": f"Audio file does not exist: {audio_path}",
        }
        write_json(output_json, payload)
        if should_hard_exit(provider, args.device):
            hard_exit(1)
        return 1

    try:
        if provider == "mock":
            payload = build_mock_result(audio_path, args.mock_transcript_path, str(args.normalize_script))
        elif provider == "faster-whisper":
            payload = build_faster_whisper_result(
                audio_path=audio_path,
                model_name=str(args.model),
                language=str(args.language),
                device=str(args.device),
                compute_type=str(args.compute_type),
                beam_size=int(args.beam_size),
                vad_filter=parse_bool(args.vad_filter),
                normalize_script=str(args.normalize_script),
            )
        else:
            raise RuntimeError(f"Unsupported ASR provider: {provider}")
    except Exception as exc:
        payload = {
            "success": False,
            "provider": provider,
            "model": str(args.model),
            "language": str(args.language),
            "transcript_raw": "",
            "transcript": "",
            "segments": [],
            "segment_count": 0,
            "normalization": "none",
            "normalization_applied": False,
            "error": str(exc),
        }
        write_json(output_json, payload)
        if should_hard_exit(provider, args.device):
            hard_exit(1)
        return 1

    write_json(output_json, payload)
    if should_hard_exit(provider, args.device):
        hard_exit(0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
