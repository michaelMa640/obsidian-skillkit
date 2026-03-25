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
    if mode == "learn":
        suffix = "Learn Note" if normalized in {"en", "en-us", "english"} else "学习笔记"
    else:
        suffix = "Breakdown" if normalized in {"en", "en-us", "english"} else "爆款拆解"
    return f"{base_title} - {suffix}"


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


def ensure_defaults(result: dict[str, Any], payload: dict[str, Any], model: str, output_language: str) -> dict[str, Any]:
    analysis_run_date = datetime.now().strftime("%Y-%m-%d")
    return {
        "title": string_value(payload.get("title"), result.get("title"), default=default_analysis_title(payload, output_language, "analyze")),
        "analysis_mode": "analyze",
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
    final_result = ensure_defaults(result_json, payload=payload, model=model, output_language=output_language)
    final_result["provider"] = provider
    final_result["input_warnings"] = input_warnings
    final_result["usage"] = response_json.get("usage") or {}

    Path(args.output_json).write_text(json.dumps(final_result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(final_result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
