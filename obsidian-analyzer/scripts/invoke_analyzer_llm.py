import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any


def has_value(value: Any) -> bool:
    return value is not None and str(value).strip() != ""


def string_value(*values: Any, default: str = "") -> str:
    for value in values:
        if has_value(value):
            return str(value).strip()
    return default


def load_json(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def configure_console_output() -> None:
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream is None:
            continue
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(encoding="utf-8", errors="backslashreplace")


def read_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def normalize_base_url(base_url: str) -> str:
    return base_url.rstrip("/")


def load_schema_brief(schema_path: str) -> dict[str, Any]:
    schema = load_json(schema_path)
    properties = schema.get("properties", {})
    required = schema.get("required", [])
    return {
        "required": required,
        "properties": sorted(properties.keys()),
    }


def build_text_instruction(prompt_text: str, payload: dict[str, Any], schema_brief: dict[str, Any]) -> str:
    compact_payload = json.dumps(payload, ensure_ascii=False, indent=2)
    compact_schema = json.dumps(schema_brief, ensure_ascii=False, indent=2)
    return (
        f"{prompt_text}\n\n"
        "You must return valid JSON only.\n"
        "The word JSON is intentional because the transport requests JSON mode.\n\n"
        "Required output schema summary:\n"
        f"{compact_schema}\n\n"
        "Analyzer payload JSON:\n"
        f"{compact_payload}\n"
    )


def language_instruction(language: str) -> str:
    normalized = (language or "").strip().lower()
    if normalized in {"zh", "zh-cn", "zh-hans", "chinese", "cn"}:
        return (
            "Write every natural-language analysis field in Simplified Chinese. "
            "Keep field names in JSON as defined by the schema, but all narrative content must be Chinese."
        )
    if normalized in {"en", "en-us", "english"}:
        return "Write every natural-language analysis field in English."
    return f"Write every natural-language analysis field in the target language `{language}`."


def default_analysis_title(payload: dict[str, Any], language: str, mode: str = "analyze") -> str:
    base_title = string_value(payload.get("title"), default="Untitled")
    normalized = (language or "").strip().lower()
    if mode == "analyze":
        suffix = "Breakdown" if normalized in {"en", "en-us", "english"} else "爆款拆解"
        return f"{base_title} - {suffix}"
    suffix = "Knowledge Note" if normalized in {"en", "en-us", "english"} else "知识解读"
    return f"{base_title} - {suffix}"


def normalize_analysis_mode(value: Any) -> str:
    mode = string_value(value).lower()
    if mode == "learn":
        return "knowledge"
    if mode in {"analyze", "knowledge"}:
        return mode
    return mode or "knowledge"


def normalize_analysis_goal(value: Any, analysis_mode: str) -> str:
    goal = string_value(value).lower()
    if goal in {"analyze", "knowledge"}:
        return goal
    if normalize_analysis_mode(analysis_mode) == "analyze":
        return "analyze"
    return "knowledge"


def should_inline_video(video_path: str, max_inline_mb: float) -> bool:
    path = Path(video_path)
    if not path.exists() or not path.is_file():
        return False
    max_bytes = int(max_inline_mb * 1024 * 1024)
    return path.stat().st_size <= max_bytes


def encode_video_data_uri(video_path: str) -> str:
    suffix = Path(video_path).suffix.lower().lstrip(".") or "mp4"
    raw = Path(video_path).read_bytes()
    encoded = base64.b64encode(raw).decode("utf-8")
    return f"data:video/{suffix};base64,{encoded}"


def build_messages(
    payload: dict[str, Any],
    prompt_text: str,
    schema_brief: dict[str, Any],
    include_video: bool,
    max_inline_video_mb: float,
    video_fps: int,
    output_language: str,
) -> tuple[list[dict[str, Any]], list[str]]:
    warnings: list[str] = []
    user_content: list[dict[str, Any]] = []
    video_path = string_value(payload.get("video_path"))

    if include_video and has_value(video_path):
        if video_path.startswith(("http://", "https://", "data:video/")):
            user_content.append(
                {
                    "type": "video_url",
                    "video_url": {"url": video_path},
                    "fps": video_fps,
                }
            )
        elif should_inline_video(video_path, max_inline_video_mb):
            user_content.append(
                {
                    "type": "video_url",
                    "video_url": {"url": encode_video_data_uri(video_path)},
                    "fps": video_fps,
                }
            )
        else:
            warnings.append(f"video_not_included:local_video_exceeds_inline_limit_or_missing:{video_path}")
    elif include_video:
        warnings.append("video_not_included:no_video_path")

    user_content.append(
        {
            "type": "text",
            "text": f"{language_instruction(output_language)}\n\n{build_text_instruction(prompt_text, payload, schema_brief)}",
        }
    )
    return [{"role": "user", "content": user_content}], warnings


def post_chat_completion(
    *,
    api_key: str,
    base_url: str,
    model: str,
    messages: list[dict[str, Any]],
    timeout_seconds: int,
    enable_thinking: bool,
    temperature: float,
) -> dict[str, Any]:
    endpoint = f"{normalize_base_url(base_url)}/chat/completions"
    request_body = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "response_format": {"type": "json_object"},
        "enable_thinking": enable_thinking,
    }
    data = json.dumps(request_body, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        return json.loads(response.read().decode("utf-8"))


def extract_content(response_json: dict[str, Any]) -> str:
    choices = response_json.get("choices") or []
    if not choices:
        raise ValueError("Model response does not contain choices.")
    message = (choices[0] or {}).get("message") or {}
    content = message.get("content")
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and has_value(item.get("text")):
                parts.append(str(item["text"]))
        content = "\n".join(parts)
    if not has_value(content):
        raise ValueError("Model response does not contain message.content.")
    return str(content)


def resolve_api_key(llm: dict[str, Any]) -> tuple[str, str]:
    configured_key = string_value(llm.get("api_key"))
    if has_value(configured_key):
        return configured_key, "config"
    api_key_env = string_value(llm.get("api_key_env"), default="DASHSCOPE_API_KEY")
    env_value = os.getenv(api_key_env)
    if has_value(env_value):
        return str(env_value).strip(), f"env:{api_key_env}"
    return "", f"env:{api_key_env}"


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def normalize_text_list(values: Any, *field_names: str) -> list[str]:
    normalized: list[str] = []
    for item in as_list(values):
        if isinstance(item, dict):
            candidates = [item.get(field_name) for field_name in field_names]
            text = string_value(*candidates)
        else:
            text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_methods(values: Any) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            name = string_value(item.get("name"), item.get("title"), item.get("method"))
            summary = string_value(item.get("summary"), item.get("detail"), item.get("description"))
            applicability = string_value(item.get("applicability"), item.get("applicable_to"), item.get("scenario"))
            steps = normalize_text_list(item.get("steps"), "text", "step")
            entry: dict[str, Any] = {}
            if has_value(name):
                entry["name"] = name
            if has_value(summary):
                entry["summary"] = summary
            if steps:
                entry["steps"] = steps
            if has_value(applicability):
                entry["applicability"] = applicability
            if entry:
                normalized.append(entry if "name" in entry else " | ".join([value for value in [summary, applicability] if has_value(value)]))
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_named_points(values: Any, *, primary_keys: tuple[str, ...], detail_keys: tuple[str, ...]) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            primary = string_value(*[item.get(key) for key in primary_keys])
            detail = string_value(*[item.get(key) for key in detail_keys])
            if has_value(primary) and has_value(detail):
                normalized.append({"point": primary, "detail": detail})
            elif has_value(primary):
                normalized.append(primary)
            elif has_value(detail):
                normalized.append(detail)
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_concepts(values: Any) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            name = string_value(item.get("name"), item.get("title"), item.get("concept"))
            summary = string_value(item.get("summary"), item.get("detail"), item.get("description"))
            if has_value(name) and has_value(summary):
                normalized.append({"name": name, "summary": summary})
            elif has_value(name):
                normalized.append(name)
            elif has_value(summary):
                normalized.append(summary)
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_knowledge_cards(values: Any) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            title = string_value(item.get("title"), item.get("name"), item.get("question"))
            summary = string_value(item.get("summary"), item.get("detail"), item.get("answer"), item.get("description"))
            evidence = string_value(item.get("evidence"), item.get("reason"))
            tags = normalize_text_list(item.get("tags"))
            entry: dict[str, Any] = {}
            if has_value(title):
                entry["title"] = title
            if has_value(summary):
                entry["summary"] = summary
            if has_value(evidence):
                entry["evidence"] = evidence
            if tags:
                entry["tags"] = tags
            if entry:
                normalized.append(entry if "title" in entry else summary)
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_topic_candidates(values: Any) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            name = string_value(item.get("name"), item.get("title"), item.get("topic"))
            reason = string_value(item.get("reason"), item.get("summary"), item.get("detail"))
            if has_value(name) and has_value(reason):
                normalized.append({"name": name, "reason": reason})
            elif has_value(name):
                normalized.append(name)
            elif has_value(reason):
                normalized.append(reason)
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_quotes(values: Any) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            quote = string_value(item.get("quote"), item.get("text"), item.get("content"))
            timestamp = string_value(item.get("timestamp"), item.get("time"))
            speaker = string_value(item.get("speaker"), item.get("name"))
            reason = string_value(item.get("reason"), item.get("note"))
            entry: dict[str, Any] = {}
            if has_value(quote):
                entry["quote"] = quote
            if has_value(timestamp):
                entry["timestamp"] = timestamp
            if has_value(speaker):
                entry["speaker"] = speaker
            if has_value(reason):
                entry["reason"] = reason
            if entry:
                normalized.append(entry if "quote" in entry else reason)
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_timestamp_index(values: Any) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            timestamp = string_value(item.get("timestamp"), item.get("time"), item.get("start"))
            topic = string_value(item.get("topic"), item.get("text"), item.get("title"))
            note = string_value(item.get("note"), item.get("detail"), item.get("summary"))
            if has_value(timestamp) and has_value(topic):
                entry: dict[str, Any] = {"timestamp": timestamp, "topic": topic}
                if has_value(note):
                    entry["note"] = note
                normalized.append(entry)
            elif has_value(timestamp):
                normalized.append(timestamp)
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_speaker_map(values: Any) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            speaker = string_value(item.get("speaker"), item.get("name"), item.get("label"))
            role = string_value(item.get("role"), item.get("identity"))
            notes = string_value(item.get("notes"), item.get("detail"), item.get("description"))
            if has_value(speaker):
                entry: dict[str, Any] = {"speaker": speaker}
                if has_value(role):
                    entry["role"] = role
                if has_value(notes):
                    entry["notes"] = notes
                normalized.append(entry)
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def normalize_source_highlights(values: Any) -> list[Any]:
    normalized: list[Any] = []
    for item in as_list(values):
        if isinstance(item, dict):
            quote = string_value(item.get("quote"), item.get("text"), item.get("content"))
            reason = string_value(item.get("reason"), item.get("note"))
            if has_value(quote) and has_value(reason):
                normalized.append({"quote": quote, "reason": reason})
            elif has_value(quote):
                normalized.append({"quote": quote})
            elif has_value(reason):
                normalized.append(reason)
            continue
        text = string_value(item)
        if has_value(text):
            normalized.append(text)
    return normalized


def ensure_defaults_analyze(result: dict[str, Any], payload: dict[str, Any], model: str, output_language: str) -> dict[str, Any]:
    analysis_run_date = datetime.now().strftime("%Y-%m-%d")
    return {
        "title": string_value(payload.get("title"), result.get("title"), default=default_analysis_title(payload, output_language, "analyze")),
        "analysis_mode": "analyze",
        "analysis_goal": "analyze",
        "source_note_path": string_value(payload.get("source_note_path"), result.get("source_note_path")),
        "capture_json_path": string_value(payload.get("capture_json_path"), result.get("capture_json_path")),
        "source_url": string_value(payload.get("source_url"), result.get("source_url")),
        "normalized_url": string_value(payload.get("normalized_url"), result.get("normalized_url")),
        "platform": string_value(payload.get("platform"), result.get("platform")),
        "content_type": string_value(payload.get("content_type"), result.get("content_type")),
        "capture_id": string_value(payload.get("capture_id"), result.get("capture_id")),
        "analyzed_at": analysis_run_date,
        "model": string_value(model),
        "provider_reported_model": string_value(result.get("model")),
        "analysis_status": string_value(result.get("analysis_status"), default="success"),
        "prompt_template": string_value(result.get("prompt_template"), default="references/prompts/analyze.md"),
        "output_contract_version": string_value(result.get("output_contract_version"), default="analyze-v1"),
        "core_conclusion": string_value(result.get("core_conclusion")),
        "hook_breakdown": string_value(result.get("hook_breakdown")),
        "structure_breakdown": result.get("structure_breakdown") or [],
        "emotion_trust_signals": result.get("emotion_trust_signals") or [],
        "comment_feedback": result.get("comment_feedback") or [],
        "engagement_insights": result.get("engagement_insights") or [],
        "reusable_formula": result.get("reusable_formula") or [],
        "risk_flags": result.get("risk_flags") or [],
        "source_highlights": result.get("source_highlights") or [],
        "metrics_like": string_value(result.get("metrics_like"), payload.get("metrics_like")),
        "metrics_comment": string_value(result.get("metrics_comment"), payload.get("metrics_comment")),
        "metrics_share": string_value(result.get("metrics_share"), payload.get("metrics_share")),
        "metrics_collect": string_value(result.get("metrics_collect"), payload.get("metrics_collect")),
        "comments_count": result.get("comments_count", payload.get("comments_count")),
        "video_path": string_value(payload.get("video_path"), result.get("video_path")),
        "audio_path": string_value(payload.get("audio_path"), result.get("audio_path")),
        "transcript_path": string_value(payload.get("transcript_path"), result.get("transcript_path")),
        "transcript_raw_path": string_value(payload.get("transcript_raw_path"), result.get("transcript_raw_path")),
        "transcript_segments_path": string_value(payload.get("transcript_segments_path"), result.get("transcript_segments_path")),
        "asr_normalization": string_value(payload.get("asr_normalization"), result.get("asr_normalization")),
        "output_language": output_language,
    }


def ensure_defaults_knowledge(result: dict[str, Any], payload: dict[str, Any], model: str, output_language: str) -> dict[str, Any]:
    analysis_run_date = datetime.now().strftime("%Y-%m-%d")
    return {
        "title": string_value(payload.get("title"), result.get("title"), default=default_analysis_title(payload, output_language, "knowledge")),
        "analysis_mode": "knowledge",
        "analysis_goal": "knowledge",
        "source_note_path": string_value(payload.get("source_note_path"), result.get("source_note_path")),
        "capture_json_path": string_value(payload.get("capture_json_path"), result.get("capture_json_path")),
        "source_url": string_value(payload.get("source_url"), result.get("source_url")),
        "normalized_url": string_value(payload.get("normalized_url"), result.get("normalized_url")),
        "platform": string_value(payload.get("platform"), result.get("platform")),
        "content_type": string_value(payload.get("content_type"), result.get("content_type")),
        "route": string_value(payload.get("route"), result.get("route")),
        "capture_id": string_value(payload.get("capture_id"), result.get("capture_id")),
        "author": string_value(payload.get("author"), result.get("author")),
        "published_at": string_value(payload.get("published_at"), result.get("published_at")),
        "podcast_title": string_value(payload.get("podcast_title"), result.get("podcast_title")),
        "podcast_author": string_value(payload.get("podcast_author"), result.get("podcast_author")),
        "episode_url": string_value(payload.get("episode_url"), result.get("episode_url")),
        "episode_id": string_value(payload.get("episode_id"), result.get("episode_id")),
        "duration_seconds": string_value(payload.get("duration_seconds"), result.get("duration_seconds")),
        "tags": normalize_text_list(payload.get("tags"), "text", "name", "title") or normalize_text_list(result.get("tags"), "text", "name", "title"),
        "analyzed_at": analysis_run_date,
        "model": string_value(model),
        "provider_reported_model": string_value(result.get("model")),
        "analysis_status": string_value(result.get("analysis_status"), default="success"),
        "prompt_template": string_value(result.get("prompt_template"), default="references/prompts/knowledge.md"),
        "output_contract_version": string_value(result.get("output_contract_version"), default="knowledge-v1"),
        "content_summary": string_value(
            result.get("content_summary"),
            result.get("summary"),
            payload.get("summary"),
            payload.get("description"),
        ),
        "core_points": normalize_text_list(result.get("core_points"), "text", "point", "summary"),
        "methods": normalize_methods(result.get("methods")),
        "tips_and_facts": normalize_named_points(
            result.get("tips_and_facts"),
            primary_keys=("point", "name", "title"),
            detail_keys=("detail", "summary", "description"),
        ),
        "concepts": normalize_concepts(result.get("concepts")),
        "knowledge_cards": normalize_knowledge_cards(result.get("knowledge_cards")),
        "topic_candidates": normalize_topic_candidates(result.get("topic_candidates")),
        "action_items": normalize_text_list(result.get("action_items"), "text", "action", "step"),
        "open_questions": normalize_text_list(result.get("open_questions"), "text", "question", "issue"),
        "quotes": normalize_quotes(result.get("quotes")),
        "timestamp_index": normalize_timestamp_index(result.get("timestamp_index")),
        "speaker_map": normalize_speaker_map(result.get("speaker_map")),
        "source_highlights": normalize_source_highlights(result.get("source_highlights")),
        "video_path": string_value(payload.get("video_path"), result.get("video_path")),
        "audio_path": string_value(payload.get("audio_path"), result.get("audio_path")),
        "transcript_path": string_value(payload.get("transcript_path"), result.get("transcript_path")),
        "transcript_raw_path": string_value(payload.get("transcript_raw_path"), result.get("transcript_raw_path")),
        "transcript_segments_path": string_value(payload.get("transcript_segments_path"), result.get("transcript_segments_path")),
        "asr_normalization": string_value(payload.get("asr_normalization"), result.get("asr_normalization")),
        "output_language": output_language,
    }


def main() -> int:
    configure_console_output()
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload-json", required=True)
    parser.add_argument("--config-json", required=True)
    parser.add_argument("--prompt-path", required=True)
    parser.add_argument("--schema-path", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--request-json")
    parser.add_argument("--response-json")
    args = parser.parse_args()

    payload = load_json(args.payload_json)
    normalized_mode = normalize_analysis_mode(payload.get("analysis_mode"))
    payload["analysis_mode"] = normalized_mode
    payload["analysis_goal"] = normalize_analysis_goal(payload.get("analysis_goal"), normalized_mode)
    config = load_json(args.config_json)
    llm = config.get("llm") or {}

    provider = string_value(llm.get("provider"))
    if provider != "dashscope_openai_compatible":
        raise ValueError(f"Unsupported llm.provider: {provider}")

    model = string_value(llm.get("model"))
    if not has_value(model):
        raise ValueError("llm.model is required.")

    api_key, api_key_source = resolve_api_key(llm)
    if not has_value(api_key):
        raise ValueError(
            "LLM API key is not configured. Set llm.api_key in local-config.json or provide llm.api_key_env as an environment variable."
        )

    base_url = string_value(llm.get("base_url"), default="https://dashscope.aliyuncs.com/compatible-mode/v1")
    timeout_seconds = int(llm.get("timeout_seconds") or 120)
    enable_thinking = bool(llm.get("enable_thinking")) if llm.get("enable_thinking") is not None else False
    temperature = float(llm.get("temperature") or 0.2)
    include_video = bool(llm.get("include_video")) if llm.get("include_video") is not None else True
    max_inline_video_mb = float(llm.get("max_inline_video_mb") or 7)
    video_fps = int(llm.get("video_fps") or 2)
    output_language = string_value((config.get("analyzer") or {}).get("output_language"), default="zh-CN")

    prompt_text = read_text(args.prompt_path)
    schema_brief = load_schema_brief(args.schema_path)
    messages, input_warnings = build_messages(
        payload=payload,
        prompt_text=prompt_text,
        schema_brief=schema_brief,
        include_video=include_video,
        max_inline_video_mb=max_inline_video_mb,
        video_fps=video_fps,
        output_language=output_language,
    )

    request_payload = {
        "provider": provider,
        "model": model,
        "base_url": base_url,
        "timeout_seconds": timeout_seconds,
        "enable_thinking": enable_thinking,
        "temperature": temperature,
        "response_format": {"type": "json_object"},
        "messages": messages,
        "input_warnings": input_warnings,
        "api_key_source": api_key_source,
    }
    if has_value(args.request_json):
        Path(args.request_json).write_text(json.dumps(request_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    try:
        response_json = post_chat_completion(
            api_key=api_key,
            base_url=base_url,
            model=model,
            messages=messages,
            timeout_seconds=timeout_seconds,
            enable_thinking=enable_thinking,
            temperature=temperature,
        )
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"DashScope HTTP {exc.code}: {error_body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"DashScope request failed: {exc}") from exc

    if has_value(args.response_json):
        Path(args.response_json).write_text(json.dumps(response_json, ensure_ascii=False, indent=2), encoding="utf-8")

    content = extract_content(response_json)
    result_json = json.loads(content)
    if normalized_mode == "analyze":
        final_result = ensure_defaults_analyze(result_json, payload=payload, model=model, output_language=output_language)
    else:
        final_result = ensure_defaults_knowledge(result_json, payload=payload, model=model, output_language=output_language)
    final_result["provider"] = provider
    final_result["input_warnings"] = input_warnings
    final_result["usage"] = response_json.get("usage") or {}

    Path(args.output_json).write_text(json.dumps(final_result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(final_result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
