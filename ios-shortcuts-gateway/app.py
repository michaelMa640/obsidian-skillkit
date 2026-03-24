import json
import logging
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from feishu_notifier import TERMINAL_STATUSES as FEISHU_TERMINAL_STATUSES
from feishu_notifier import FeishuConfig as NotifierFeishuConfig
from feishu_notifier import send_feishu_callback


BASE_DIR = Path(__file__).resolve().parent
REFERENCES_DIR = BASE_DIR / "references"
DEFAULT_CONFIG_PATH = REFERENCES_DIR / "local-config.json"
TERMINAL_STATUSES = {"SUCCESS", "PARTIAL", "FAILED", "AUTH_REQUIRED"}


class ServerConfig(BaseModel):
    host: str
    port: int
    bind_mode: Literal["tailscale_only", "localhost_only"]
    allowed_tailscale_cidr: str | None = None


class AuthConfig(BaseModel):
    bearer_token: str = Field(min_length=1)


class RoutingConfig(BaseModel):
    clipper_script: str
    analyzer_script: str


class ObsidianConfig(BaseModel):
    vault_path: str


class RuntimeConfig(BaseModel):
    python_command: str = "python"
    powershell_command: str = "powershell"


class LoggingConfig(BaseModel):
    level: str = "info"
    directory: str = ".tmp/gateway"
    redact_source_text: bool = True


class GatewayConfig(BaseModel):
    server: ServerConfig
    auth: AuthConfig
    routing: RoutingConfig
    obsidian: ObsidianConfig
    runtime: RuntimeConfig = Field(default_factory=RuntimeConfig)
    feishu: NotifierFeishuConfig = Field(default_factory=NotifierFeishuConfig)
    logging: LoggingConfig = Field(default_factory=LoggingConfig)


class ShortVideoTaskRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: Literal["clip", "analyze"]
    source_text: str = Field(min_length=1, max_length=5000)
    client: str = "ios_shortcuts"
    request_id: str | None = Field(default=None, min_length=1, max_length=128)
    wait_for_completion: bool = False


class ShortVideoTaskResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    success: bool
    status: Literal["SUCCESS", "FAILED", "PARTIAL", "AUTH_REQUIRED", "CONFIG_REQUIRED", "ACCEPTED", "RUNNING"]
    action: Literal["clip", "analyze"]
    message_zh: str
    failed_step: str | None = None
    clipper_note: str | None = None
    analyzer_note: str | None = None
    debug_hint: str | None = None
    auth_action_required: Literal["refresh_douyin_auth"] | None = None
    refresh_command: str | None = None
    request_id: str | None = None
    display_text: str | None = None


class TaskStatusRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: str
    action: Literal["clip", "analyze"]
    status: Literal["ACCEPTED", "RUNNING", "SUCCESS", "PARTIAL", "FAILED", "AUTH_REQUIRED"]
    message_zh: str
    created_at: str
    updated_at: str
    failed_step: str | None = None
    source_url: str | None = None
    normalized_url: str | None = None
    original_source_text: str | None = None
    clipper_note: str | None = None
    analyzer_note: str | None = None
    auth_action_required: Literal["refresh_douyin_auth"] | None = None
    refresh_command: str | None = None
    debug_hint: str | None = None
    callback_attempted_at: str | None = None
    callback_sent: bool | None = None
    callback_error: str | None = None


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_directory(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def make_request_directory(log_dir: Path, request_id: str) -> Path:
    return ensure_directory(log_dir / "runs" / request_id)


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def shorten_path(full_path: str | None, vault_root: str) -> str | None:
    if not full_path:
        return None
    try:
        path_obj = Path(full_path).resolve()
        vault_obj = Path(vault_root).resolve()
        return str(path_obj.relative_to(vault_obj)).replace("\\", "/")
    except Exception:
        return full_path


def default_debug_hint(request_dir: Path) -> str:
    return f"本机目录：{request_dir}"


def load_config(config_path: Path) -> GatewayConfig:
    if not config_path.exists():
        raise FileNotFoundError(
            f"Gateway config not found: {config_path}. Copy references/local-config.example.json to references/local-config.json."
        )
    raw = json.loads(config_path.read_text(encoding="utf-8"))
    try:
        return GatewayConfig.model_validate(raw)
    except ValidationError as exc:
        raise ValueError(f"Invalid gateway config: {exc}") from exc


def load_status(path: Path) -> TaskStatusRecord | None:
    if not path.exists():
        return None
    return TaskStatusRecord.model_validate(read_json(path))


def save_status(path: Path, record: TaskStatusRecord) -> None:
    existing = load_status(path)
    if existing is not None and existing.status in TERMINAL_STATUSES and record.status != existing.status:
        write_json(path, existing.model_dump())
        return
    write_json(path, record.model_dump())


def status_to_response(record: TaskStatusRecord) -> ShortVideoTaskResponse:
    display_text = f"{record.message_zh}\nrequest_id: {record.request_id}"
    return ShortVideoTaskResponse(
        success=record.status in {"SUCCESS", "PARTIAL", "ACCEPTED", "RUNNING"},
        status=record.status,
        action=record.action,
        message_zh=record.message_zh,
        failed_step=record.failed_step,
        clipper_note=record.clipper_note,
        analyzer_note=record.analyzer_note,
        debug_hint=record.debug_hint,
        auth_action_required=record.auth_action_required,
        refresh_command=record.refresh_command,
        request_id=record.request_id,
        display_text=display_text,
    )


def build_status_record(
    *,
    request_id: str,
    action: Literal["clip", "analyze"],
    status_value: Literal["ACCEPTED", "RUNNING", "SUCCESS", "PARTIAL", "FAILED", "AUTH_REQUIRED"],
    message_zh: str,
    created_at: str,
    source_url: str | None,
    normalized_url: str | None,
    original_source_text: str | None,
    failed_step: str | None = None,
    clipper_note: str | None = None,
    analyzer_note: str | None = None,
    auth_action_required: Literal["refresh_douyin_auth"] | None = None,
    refresh_command: str | None = None,
    debug_hint: str | None = None,
    callback_attempted_at: str | None = None,
    callback_sent: bool | None = None,
    callback_error: str | None = None,
) -> TaskStatusRecord:
    return TaskStatusRecord(
        request_id=request_id,
        action=action,
        status=status_value,
        message_zh=message_zh,
        created_at=created_at,
        updated_at=utc_now_iso(),
        failed_step=failed_step,
        source_url=source_url,
        normalized_url=normalized_url,
        original_source_text=original_source_text,
        clipper_note=clipper_note,
        analyzer_note=analyzer_note,
        auth_action_required=auth_action_required,
        refresh_command=refresh_command,
        debug_hint=debug_hint,
        callback_attempted_at=callback_attempted_at,
        callback_sent=callback_sent,
        callback_error=callback_error,
    )


def run_powershell_script(
    powershell_command: str,
    script_path: str,
    args: list[str],
    cwd: Path,
) -> subprocess.CompletedProcess[str]:
    command = [
        powershell_command,
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        script_path,
        *args,
    ]
    return subprocess.run(
        command,
        cwd=str(cwd),
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def extract_link_fields(result: dict, original_source_text: str) -> tuple[str | None, str | None, str]:
    source_url = result.get("source_url")
    normalized_url = result.get("normalized_url")
    return source_url, normalized_url, original_source_text


def record_from_clipper_result(
    result: dict,
    *,
    vault_root: str,
    request_id: str,
    action: Literal["clip", "analyze"],
    created_at: str,
    original_source_text: str,
    debug_hint: str,
) -> TaskStatusRecord:
    final_status = str(result.get("final_run_status", "")).upper()
    source_url, normalized_url, original_text = extract_link_fields(result, original_source_text)
    common = {
        "request_id": request_id,
        "action": action,
        "created_at": created_at,
        "source_url": source_url,
        "normalized_url": normalized_url,
        "original_source_text": original_text,
        "clipper_note": shorten_path(result.get("note_path"), vault_root),
        "debug_hint": debug_hint,
    }
    if result.get("auth_action_required") == "refresh_douyin_auth":
        return build_status_record(
            status_value="AUTH_REQUIRED",
            message_zh=str(result.get("auth_guidance_zh") or result.get("final_message_zh") or "抖音登录态已失效，请先刷新本机登录态。"),
            failed_step=str(result.get("failed_step") or ""),
            auth_action_required="refresh_douyin_auth",
            refresh_command=str(result.get("auth_refresh_command") or ""),
            **common,
        )
    if final_status == "SUCCESS":
        return build_status_record(
            status_value="SUCCESS",
            message_zh=str(result.get("final_message_zh") or "剪藏成功。"),
            **common,
        )
    return build_status_record(
        status_value="FAILED",
        message_zh=str(result.get("final_message_zh") or "剪藏失败。"),
        failed_step=str(result.get("failed_step") or ""),
        **common,
    )


def record_from_analyzer_result(
    clipper_result: dict,
    analyzer_result: dict,
    *,
    vault_root: str,
    request_id: str,
    created_at: str,
    original_source_text: str,
    debug_hint: str,
) -> TaskStatusRecord:
    source_url = clipper_result.get("source_url") or analyzer_result.get("source_url")
    normalized_url = clipper_result.get("normalized_url") or analyzer_result.get("normalized_url")
    analysis_status = str(analyzer_result.get("analysis_status", "")).lower()
    final_status = str(analyzer_result.get("final_run_status", "")).upper()
    common = {
        "request_id": request_id,
        "action": "analyze",
        "created_at": created_at,
        "source_url": source_url,
        "normalized_url": normalized_url,
        "original_source_text": original_source_text,
        "clipper_note": shorten_path(clipper_result.get("note_path"), vault_root),
        "analyzer_note": shorten_path(analyzer_result.get("note_path"), vault_root),
        "debug_hint": debug_hint,
    }
    if final_status == "SUCCESS" and analysis_status == "partial":
        return build_status_record(
            status_value="PARTIAL",
            message_zh=str(analyzer_result.get("final_message_zh") or "任务已完成，但结果不完整。"),
            failed_step=str(analyzer_result.get("failed_step") or ""),
            **common,
        )
    if final_status == "SUCCESS":
        return build_status_record(
            status_value="SUCCESS",
            message_zh=str(analyzer_result.get("final_message_zh") or "已完成剪藏并生成爆款拆解。"),
            **common,
        )
    return build_status_record(
        status_value="FAILED",
        message_zh=str(analyzer_result.get("final_message_zh") or "拆解失败。"),
        failed_step=str(analyzer_result.get("failed_step") or "analyze"),
        **common,
    )


def build_callback_payload(record: TaskStatusRecord) -> dict:
    return {
        "request_id": record.request_id,
        "action": record.action,
        "status": record.status,
        "message_zh": record.message_zh,
        "source_url": record.source_url,
        "normalized_url": record.normalized_url,
        "original_source_text": record.original_source_text,
        "clipper_note": record.clipper_note,
        "analyzer_note": record.analyzer_note,
        "failed_step": record.failed_step,
        "auth_action_required": record.auth_action_required,
        "refresh_command": record.refresh_command,
        "debug_hint": record.debug_hint,
    }


def finalize_terminal_record(config: GatewayConfig, request_dir: Path, record: TaskStatusRecord) -> TaskStatusRecord:
    if record.status not in FEISHU_TERMINAL_STATUSES:
        return record

    callback_result_path = request_dir / "feishu-callback.json"
    attempted_at = utc_now_iso()
    updated_record = record.model_copy(
        update={
            "updated_at": attempted_at,
            "callback_attempted_at": attempted_at,
        }
    )

    try:
        callback_result = send_feishu_callback(config.feishu.model_dump(), build_callback_payload(record))
        updated_record = updated_record.model_copy(
            update={
                "callback_sent": bool(callback_result.get("sent")),
                "callback_error": None,
            }
        )
        write_json(callback_result_path, callback_result)
    except Exception as exc:
        callback_result = {"sent": False, "error": str(exc)}
        updated_record = updated_record.model_copy(
            update={
                "callback_sent": False,
                "callback_error": str(exc),
            }
        )
        write_json(callback_result_path, callback_result)

    return updated_record


def execute_task(config: GatewayConfig, request_dir: Path, payload: ShortVideoTaskRequest, logger: logging.Logger) -> TaskStatusRecord:
    request_id = request_dir.name
    status_json = request_dir / "status.json"
    clipper_json = request_dir / "clipper-result.json"
    analyzer_json = request_dir / "analyzer-result.json"
    debug_hint = default_debug_hint(request_dir)
    running_record = load_status(status_json)
    created_at = running_record.created_at if running_record else utc_now_iso()
    powershell_command = config.runtime.powershell_command

    clipper_args = [
        "-SourceUrl",
        payload.source_text,
        "-VaultPath",
        config.obsidian.vault_path,
        "-OutputJsonPath",
        str(clipper_json),
        "-DebugDirectory",
        str(request_dir / "clipper-debug"),
    ]
    clipper_run = run_powershell_script(
        powershell_command=powershell_command,
        script_path=config.routing.clipper_script,
        args=clipper_args,
        cwd=BASE_DIR.parent,
    )
    (request_dir / "clipper-stdout.log").write_text(clipper_run.stdout or "", encoding="utf-8")
    (request_dir / "clipper-stderr.log").write_text(clipper_run.stderr or "", encoding="utf-8")

    if not clipper_json.exists():
        return build_status_record(
            request_id=request_id,
            action=payload.action,
            status_value="FAILED",
            message_zh="剪藏阶段未生成结果文件。",
            failed_step="clip",
            created_at=created_at,
            source_url=None,
            normalized_url=None,
            original_source_text=payload.source_text,
            debug_hint=debug_hint,
        )

    clipper_result = read_json(clipper_json)

    if payload.action == "clip":
        return record_from_clipper_result(
            clipper_result,
            vault_root=config.obsidian.vault_path,
            request_id=request_id,
            action="clip",
            created_at=created_at,
            original_source_text=payload.source_text,
            debug_hint=debug_hint,
        )

    clipper_record = record_from_clipper_result(
        clipper_result,
        vault_root=config.obsidian.vault_path,
        request_id=request_id,
        action="analyze",
        created_at=created_at,
        original_source_text=payload.source_text,
        debug_hint=debug_hint,
    )
    if clipper_record.status in {"FAILED", "AUTH_REQUIRED"}:
        return clipper_record

    capture_json_path = clipper_result.get("sidecar_path")
    if not capture_json_path:
        return build_status_record(
            request_id=request_id,
            action="analyze",
            status_value="FAILED",
            message_zh="剪藏成功，但未返回 sidecar_path，无法继续拆解。",
            failed_step="handoff",
            created_at=created_at,
            source_url=clipper_record.source_url,
            normalized_url=clipper_record.normalized_url,
            original_source_text=payload.source_text,
            clipper_note=clipper_record.clipper_note,
            debug_hint=debug_hint,
        )

    absolute_capture_json = str((Path(config.obsidian.vault_path) / Path(capture_json_path)).resolve())
    analyzer_args = [
        "-CaptureJsonPath",
        absolute_capture_json,
        "-VaultPath",
        config.obsidian.vault_path,
        "-OutputJsonPath",
        str(analyzer_json),
        "-DebugDirectory",
        str(request_dir / "analyzer-debug"),
    ]
    analyzer_run = run_powershell_script(
        powershell_command=powershell_command,
        script_path=config.routing.analyzer_script,
        args=analyzer_args,
        cwd=BASE_DIR.parent,
    )
    (request_dir / "analyzer-stdout.log").write_text(analyzer_run.stdout or "", encoding="utf-8")
    (request_dir / "analyzer-stderr.log").write_text(analyzer_run.stderr or "", encoding="utf-8")

    if not analyzer_json.exists():
        return build_status_record(
            request_id=request_id,
            action="analyze",
            status_value="FAILED",
            message_zh="拆解阶段未生成结果文件。",
            failed_step="analyze",
            created_at=created_at,
            source_url=clipper_record.source_url,
            normalized_url=clipper_record.normalized_url,
            original_source_text=payload.source_text,
            clipper_note=clipper_record.clipper_note,
            debug_hint=debug_hint,
        )

    analyzer_result = read_json(analyzer_json)
    return record_from_analyzer_result(
        clipper_result,
        analyzer_result,
        vault_root=config.obsidian.vault_path,
        request_id=request_id,
        created_at=created_at,
        original_source_text=payload.source_text,
        debug_hint=debug_hint,
    )


def run_task_background(config: GatewayConfig, request_dir: Path, payload_dict: dict, logger: logging.Logger) -> None:
    payload = ShortVideoTaskRequest.model_validate(payload_dict)
    status_json = request_dir / "status.json"
    accepted_record = load_status(status_json)
    created_at = accepted_record.created_at if accepted_record else utc_now_iso()

    running = build_status_record(
        request_id=request_dir.name,
        action=payload.action,
        status_value="RUNNING",
        message_zh="任务已接收，正在后台执行。",
        created_at=created_at,
        source_url=None,
        normalized_url=None,
        original_source_text=payload.source_text,
        debug_hint=default_debug_hint(request_dir),
    )
    save_status(status_json, running)

    try:
        final_record = execute_task(config, request_dir, payload, logger)
    except Exception as exc:  # pragma: no cover
        logger.exception("task_failed request_id=%s action=%s", request_dir.name, payload.action)
        final_record = build_status_record(
            request_id=request_dir.name,
            action=payload.action,
            status_value="FAILED",
            message_zh=f"后台任务执行失败：{exc}",
            failed_step="gateway",
            created_at=created_at,
            source_url=None,
            normalized_url=None,
            original_source_text=payload.source_text,
            debug_hint=default_debug_hint(request_dir),
        )

    final_record = finalize_terminal_record(config, request_dir, final_record)
    save_status(status_json, final_record)
    logger.info(
        "task_finished request_id=%s action=%s status=%s callback_sent=%s",
        request_dir.name,
        payload.action,
        final_record.status,
        final_record.callback_sent,
    )


def build_app(config_path: Path = DEFAULT_CONFIG_PATH) -> FastAPI:
    app = FastAPI(title="iOS Shortcuts Gateway", version="0.4.0")

    config_error: str | None = None
    try:
        config = load_config(config_path)
    except Exception as exc:  # pragma: no cover
        config = None
        config_error = str(exc)

    if config is not None:
        log_dir = (BASE_DIR / config.logging.directory).resolve()
    else:
        log_dir = (BASE_DIR / ".tmp" / "gateway").resolve()
    log_dir.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        handlers=[
            logging.FileHandler(log_dir / "gateway.log", encoding="utf-8"),
            logging.StreamHandler(),
        ],
    )
    logger = logging.getLogger("ios-shortcuts-gateway")
    if config is not None:
        logger.setLevel(getattr(logging, config.logging.level.upper(), logging.INFO))

    app.state.gateway_config = config
    app.state.gateway_config_error = config_error
    app.state.gateway_log_dir = log_dir

    def require_bearer_token(authorization: str | None = Header(default=None)) -> str:
        current = app.state.gateway_config
        if current is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Gateway config unavailable: {app.state.gateway_config_error}",
            )
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid bearer token.")
        token = authorization.removeprefix("Bearer ").strip()
        if token != current.auth.bearer_token:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing or invalid bearer token.")
        return token

    @app.get("/health")
    def health() -> dict[str, str]:
        if app.state.gateway_config is None:
            return {
                "status": "config_required",
                "service": "ios-shortcuts-gateway",
                "detail": app.state.gateway_config_error or "Gateway config unavailable.",
            }
        return {"status": "ok", "service": "ios-shortcuts-gateway"}

    @app.get("/config/summary")
    def config_summary(_: str = Depends(require_bearer_token)) -> dict[str, str | bool]:
        current = app.state.gateway_config
        return {
            "bind_mode": current.server.bind_mode,
            "host": current.server.host,
            "vault_path": current.obsidian.vault_path,
            "clipper_script": current.routing.clipper_script,
            "analyzer_script": current.routing.analyzer_script,
            "feishu_enabled": current.feishu.enabled,
        }

    @app.get("/short-video/task/{request_id}", response_model=ShortVideoTaskResponse)
    def get_task_status(request_id: str, _: str = Depends(require_bearer_token)) -> ShortVideoTaskResponse:
        request_dir = make_request_directory(log_dir, request_id)
        status_json = request_dir / "status.json"
        record = load_status(status_json)
        if record is None:
            raise HTTPException(status_code=404, detail="Request ID not found.")
        return status_to_response(record)

    @app.post("/short-video/task", response_model=ShortVideoTaskResponse)
    def short_video_task(
        payload: ShortVideoTaskRequest,
        background_tasks: BackgroundTasks,
        _: str = Depends(require_bearer_token),
    ) -> ShortVideoTaskResponse:
        current = app.state.gateway_config
        request_id = payload.request_id or uuid.uuid4().hex
        payload = payload.model_copy(update={"request_id": request_id})

        safe_preview = "[redacted]" if current.logging.redact_source_text else payload.source_text
        logger.info("task_received request_id=%s action=%s source=%s", request_id, payload.action, safe_preview)

        request_dir = make_request_directory(log_dir, request_id)
        request_json = request_dir / "request.json"
        status_json = request_dir / "status.json"
        write_json(request_json, payload.model_dump())

        accepted = build_status_record(
            request_id=request_id,
            action=payload.action,
            status_value="ACCEPTED",
            message_zh="任务已提交，正在后台执行。结果将稍后通过飞书返回。",
            created_at=utc_now_iso(),
            source_url=None,
            normalized_url=None,
            original_source_text=payload.source_text,
            debug_hint=default_debug_hint(request_dir),
        )
        save_status(status_json, accepted)

        if payload.wait_for_completion:
            running = build_status_record(
                request_id=request_id,
                action=payload.action,
                status_value="RUNNING",
                message_zh="任务已接收，正在后台执行。",
                created_at=accepted.created_at,
                source_url=None,
                normalized_url=None,
                original_source_text=payload.source_text,
                debug_hint=default_debug_hint(request_dir),
            )
            save_status(status_json, running)
            final_record = execute_task(current, request_dir, payload, logger)
            final_record = finalize_terminal_record(current, request_dir, final_record)
            save_status(status_json, final_record)
            return status_to_response(final_record)

        background_tasks.add_task(run_task_background, current, request_dir, payload.model_dump(), logger)
        return status_to_response(accepted)

    return app


app = build_app()
