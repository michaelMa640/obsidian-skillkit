import json
import subprocess
import urllib.request
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class FeishuConfig(BaseModel):
    enabled: bool = False
    mode: Literal["openclaw_cli", "webhook"] = "openclaw_cli"
    target: str = ""
    openclaw_command: str = "openclaw"
    webhook_url: str = ""
    timeout_seconds: int = 10
    message_prefix: str = "Gateway 任务结果"


class FeishuCallbackPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: str
    action: str
    status: str
    message_zh: str
    source_url: str | None = None
    normalized_url: str | None = None
    original_source_text: str | None = None
    clipper_note: str | None = None
    analyzer_note: str | None = None
    failed_step: str | None = None
    auth_action_required: str | None = None
    refresh_command: str | None = None
    debug_hint: str | None = None


TERMINAL_STATUSES = {"SUCCESS", "PARTIAL", "FAILED", "AUTH_REQUIRED"}


def render_feishu_text(config: FeishuConfig, payload: FeishuCallbackPayload) -> str:
    lines = [
        config.message_prefix,
        f"request_id: {payload.request_id}",
        f"action: {payload.action}",
        f"status: {payload.status}",
        f"message: {payload.message_zh}",
    ]
    if payload.source_url:
        lines.append(f"source_url: {payload.source_url}")
    if payload.normalized_url:
        lines.append(f"normalized_url: {payload.normalized_url}")
    if payload.original_source_text:
        lines.append(f"original_source_text: {payload.original_source_text}")
    if payload.clipper_note:
        lines.append(f"clipper_note: {payload.clipper_note}")
    if payload.analyzer_note:
        lines.append(f"analyzer_note: {payload.analyzer_note}")
    if payload.failed_step:
        lines.append(f"failed_step: {payload.failed_step}")
    if payload.auth_action_required:
        lines.append(f"auth_action_required: {payload.auth_action_required}")
    if payload.refresh_command:
        lines.append(f"refresh_command: {payload.refresh_command}")
    if payload.debug_hint:
        lines.append(f"debug_hint: {payload.debug_hint}")
    return "\n".join(lines)


def build_feishu_request_body(text: str) -> dict[str, Any]:
    return {
        "msg_type": "text",
        "content": {
            "text": text,
        },
    }


def send_via_webhook(config: FeishuConfig, text: str) -> dict[str, Any]:
    if not config.webhook_url.strip():
        raise ValueError("Feishu notifier mode=webhook but webhook_url is empty.")

    body = build_feishu_request_body(text)
    body_bytes = json.dumps(body, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url=config.webhook_url,
        data=body_bytes,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=config.timeout_seconds) as response:
        response_body = response.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(response_body)
        except json.JSONDecodeError:
            parsed = {"raw_response": response_body}
        return {"sent": True, "mode": "webhook", "response": parsed}


def send_via_openclaw_cli(config: FeishuConfig, text: str) -> dict[str, Any]:
    if not config.target.strip():
        raise ValueError("Feishu notifier mode=openclaw_cli but target is empty.")

    command = [
        config.openclaw_command,
        "message",
        "send",
        "--channel",
        "feishu",
        "--target",
        config.target,
        "--message",
        text,
    ]
    run = subprocess.run(
        command,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        timeout=config.timeout_seconds,
    )
    if run.returncode != 0:
        raise RuntimeError(run.stderr.strip() or run.stdout.strip() or "openclaw message send failed.")
    return {
        "sent": True,
        "mode": "openclaw_cli",
        "stdout": run.stdout.strip(),
        "stderr": run.stderr.strip(),
    }


def send_feishu_callback(config_dict: dict[str, Any], payload_dict: dict[str, Any]) -> dict[str, Any]:
    config = FeishuConfig.model_validate(config_dict)
    payload = FeishuCallbackPayload.model_validate(payload_dict)

    if payload.status not in TERMINAL_STATUSES:
        raise ValueError(f"Feishu callback only supports terminal statuses: {payload.status}")

    if not config.enabled:
        return {"sent": False, "reason": "disabled"}

    text = render_feishu_text(config, payload)
    if config.mode == "openclaw_cli":
        return send_via_openclaw_cli(config, text)
    return send_via_webhook(config, text)
