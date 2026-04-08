import argparse
import json
from pathlib import Path
from typing import Any


def parse_bool(value: str | bool) -> bool:
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    return text in {"1", "true", "yes", "on"}


def write_json(path: str, payload: dict[str, Any]) -> None:
    Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


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


def build_mock_result(audio_path: str, mock_transcript_path: str | None) -> dict[str, Any]:
    transcript = read_text_if_exists(mock_transcript_path)
    if not transcript:
        transcript = f"00:00 Mock ASR transcript for {Path(audio_path).stem}."
    return {
        "success": True,
        "provider": "mock",
        "model": "mock",
        "language": "zh",
        "transcript": transcript,
        "segment_count": max(len([line for line in transcript.splitlines() if line.strip()]), 1),
        "error": "",
    }


def build_faster_whisper_result(
    audio_path: str,
    model_name: str,
    language: str,
    device: str,
    compute_type: str,
    beam_size: int,
    vad_filter: bool,
) -> dict[str, Any]:
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

    segments, info = model.transcribe(audio_path, **transcribe_kwargs)
    transcript_lines: list[str] = []
    segment_count = 0
    for segment in segments:
        text = str(segment.text).strip()
        if not text:
            continue
        transcript_lines.append(f"{format_timestamp(float(segment.start))} {text}")
        segment_count += 1

    transcript = "\n".join(transcript_lines).strip()
    if not transcript:
        raise RuntimeError("ASR finished without returning any transcript text.")

    detected_language = getattr(info, "language", "") or language
    return {
        "success": True,
        "provider": "faster-whisper",
        "model": model_name,
        "language": detected_language,
        "transcript": transcript,
        "segment_count": segment_count,
        "error": "",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Podcast ASR fallback runner.")
    parser.add_argument("--audio-path", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--provider", default="faster-whisper")
    parser.add_argument("--model", default="base")
    parser.add_argument("--language", default="zh")
    parser.add_argument("--device", default="auto")
    parser.add_argument("--compute-type", default="auto")
    parser.add_argument("--beam-size", type=int, default=5)
    parser.add_argument("--vad-filter", default="true")
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
            "transcript": "",
            "segment_count": 0,
            "error": f"Audio file does not exist: {audio_path}",
        }
        write_json(output_json, payload)
        return 1

    try:
        if provider == "mock":
            payload = build_mock_result(audio_path, args.mock_transcript_path)
        elif provider == "faster-whisper":
            payload = build_faster_whisper_result(
                audio_path=audio_path,
                model_name=str(args.model),
                language=str(args.language),
                device=str(args.device),
                compute_type=str(args.compute_type),
                beam_size=int(args.beam_size),
                vad_filter=parse_bool(args.vad_filter),
            )
        else:
            raise RuntimeError(f"Unsupported ASR provider: {provider}")
    except Exception as exc:
        payload = {
            "success": False,
            "provider": provider,
            "model": str(args.model),
            "language": str(args.language),
            "transcript": "",
            "segment_count": 0,
            "error": str(exc),
        }
        write_json(output_json, payload)
        return 1

    write_json(output_json, payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
