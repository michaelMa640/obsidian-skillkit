import json
import logging
import subprocess
import uuid
from pathlib import Path
from typing import Literal

from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, ValidationError


BASE_DIR = Path(__file__).resolve().parent
REFERENCES_DIR = BASE_DIR / "references"
DEFAULT_CONFIG_PATH = REFERENCES_DIR / "local-config.json"


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


def map_clipper_result(result: dict, vault_root: str, request_id: str) -> ShortVideoTaskResponse:
    final_status = str(result.get("final_run_status", "")).upper()
    auth_action = result.get("auth_action_required")
    if auth_action == "refresh_douyin_auth":
        return ShortVideoTaskResponse(
            success=False,
            status="AUTH_REQUIRED",
            action="clip",
            message_zh=str(result.get("auth_guidance_zh") or result.get("final_message_zh") or "抖音登录态已失效，请先刷新本机登录态。"),
            failed_step=str(result.get("failed_step") or ""),
            clipper_note=shorten_path(result.get("note_path"), vault_root),
            debug_hint="请到本机 debug 目录查看 support-bundle。",
            auth_action_required="refresh_douyin_auth",
            refresh_command=str(result.get("auth_refresh_command") or ""),
            request_id=request_id,
        )
    if final_status == "SUCCESS":
        return ShortVideoTaskResponse(
            success=True,
            status="SUCCESS",
            action="clip",
            message_zh=str(result.get("final_message_zh") or "剪藏成功。"),
            clipper_note=shorten_path(result.get("note_path"), vault_root),
            debug_hint="如需排查，请到本机 debug 目录获取 support-bundle。",
            request_id=request_id,
        )
    return ShortVideoTaskResponse(
        success=False,
        status="FAILED",
        action="clip",
        message_zh=str(result.get("final_message_zh") or "剪藏失败。"),
        failed_step=str(result.get("failed_step") or ""),
        clipper_note=shorten_path(result.get("note_path"), vault_root),
        debug_hint="请到本机 debug 目录获取 support-bundle。",
        request_id=request_id,
    )


def map_analyzer_result(clipper: dict, analyzer: dict, vault_root: str, request_id: str) -> ShortVideoTaskResponse:
    clipper_auth_action = clipper.get("auth_action_required")
    if clipper_auth_action == "refresh_douyin_auth":
        return ShortVideoTaskResponse(
            success=False,
            status="AUTH_REQUIRED",
            action="analyze",
            message_zh=str(clipper.get("auth_guidance_zh") or clipper.get("final_message_zh") or "抖音登录态已失效，请先刷新本机登录态。"),
            failed_step=str(clipper.get("failed_step") or ""),
            clipper_note=shorten_path(clipper.get("note_path"), vault_root),
            debug_hint="请到本机 debug 目录查看 support-bundle。",
            auth_action_required="refresh_douyin_auth",
            refresh_command=str(clipper.get("auth_refresh_command") or ""),
            request_id=request_id,
        )

    clipper_status = str(clipper.get("final_run_status", "")).upper()
    if clipper_status != "SUCCESS":
        return ShortVideoTaskResponse(
            success=False,
            status="FAILED",
            action="analyze",
            message_zh=str(clipper.get("final_message_zh") or "剪藏阶段失败。"),
            failed_step=str(clipper.get("failed_step") or "clip"),
            clipper_note=shorten_path(clipper.get("note_path"), vault_root),
            debug_hint="请到本机 debug 目录获取 support-bundle。",
            request_id=request_id,
        )

    analyzer_status = str(analyzer.get("final_run_status", "")).upper()
    analysis_status = str(analyzer.get("analysis_status", "")).lower()
    if analyzer_status == "SUCCESS" and analysis_status == "partial":
        return ShortVideoTaskResponse(
            success=True,
            status="PARTIAL",
            action="analyze",
            message_zh=str(analyzer.get("final_message_zh") or "任务已完成，但结果不完整。"),
            failed_step=str(analyzer.get("failed_step") or ""),
            clipper_note=shorten_path(clipper.get("note_path"), vault_root),
            analyzer_note=shorten_path(analyzer.get("note_path"), vault_root),
            debug_hint="如需排查，请到本机 debug 目录获取 support-bundle。",
            request_id=request_id,
        )
    if analyzer_status == "SUCCESS":
        return ShortVideoTaskResponse(
            success=True,
            status="SUCCESS",
            action="analyze",
            message_zh=str(analyzer.get("final_message_zh") or "已完成剪藏并生成爆款拆解。"),
            clipper_note=shorten_path(clipper.get("note_path"), vault_root),
            analyzer_note=shorten_path(analyzer.get("note_path"), vault_root),
            debug_hint="如需排查，请到本机 debug 目录获取 support-bundle。",
            request_id=request_id,
        )
    return ShortVideoTaskResponse(
        success=False,
        status="FAILED",
        action="analyze",
        message_zh=str(analyzer.get("final_message_zh") or "拆解失败。"),
        failed_step=str(analyzer.get("failed_step") or "analyze"),
        clipper_note=shorten_path(clipper.get("note_path"), vault_root),
        analyzer_note=shorten_path(analyzer.get("note_path"), vault_root),
        debug_hint="请到本机 debug 目录获取 support-bundle。",
        request_id=request_id,
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


def save_status(path: Path, response: ShortVideoTaskResponse) -> None:
    write_json(path, response.model_dump())


def load_status(path: Path) -> ShortVideoTaskResponse | None:
    if not path.exists():
        return None
    return ShortVideoTaskResponse.model_validate(read_json(path))


def execute_task(config: GatewayConfig, request_dir: Path, payload: ShortVideoTaskRequest, logger: logging.Logger) -> ShortVideoTaskResponse:
    request_id = request_dir.name
    clipper_json = request_dir / "clipper-result.json"
    analyzer_json = request_dir / "analyzer-result.json"
    status_json = request_dir / "status.json"
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
        return ShortVideoTaskResponse(
            success=False,
            status="FAILED",
            action=payload.action,
            message_zh="剪藏阶段未生成结果文件。",
            failed_step="clip",
            debug_hint=default_debug_hint(request_dir),
            request_id=request_id,
        )

    clipper_result = read_json(clipper_json)

    if payload.action == "clip":
        response = map_clipper_result(clipper_result, config.obsidian.vault_path, request_id)
        response.debug_hint = default_debug_hint(request_dir)
        return response

    clipper_status = str(clipper_result.get("final_run_status", "")).upper()
    if clipper_result.get("auth_action_required") == "refresh_douyin_auth" or clipper_status != "SUCCESS":
        response = map_analyzer_result(clipper_result, {}, config.obsidian.vault_path, request_id)
        response.debug_hint = default_debug_hint(request_dir)
        return response

    capture_json_path = clipper_result.get("sidecar_path")
    if not capture_json_path:
        return ShortVideoTaskResponse(
            success=False,
            status="FAILED",
            action="analyze",
            message_zh="剪藏成功，但未返回 sidecar_path，无法继续拆解。",
            failed_step="handoff",
            clipper_note=shorten_path(clipper_result.get("note_path"), config.obsidian.vault_path),
            debug_hint=default_debug_hint(request_dir),
            request_id=request_id,
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
        return ShortVideoTaskResponse(
            success=False,
            status="FAILED",
            action="analyze",
            message_zh="拆解阶段未生成结果文件。",
            failed_step="analyze",
            clipper_note=shorten_path(clipper_result.get("note_path"), config.obsidian.vault_path),
            debug_hint=default_debug_hint(request_dir),
            request_id=request_id,
        )

    analyzer_result = read_json(analyzer_json)
    response = map_analyzer_result(clipper_result, analyzer_result, config.obsidian.vault_path, request_id)
    response.debug_hint = default_debug_hint(request_dir)
    save_status(status_json, response)
    logger.info("task_finished request_id=%s action=%s status=%s", request_id, payload.action, response.status)
    return response


def run_task_background(config: GatewayConfig, request_dir: Path, payload_dict: dict, logger: logging.Logger) -> None:
    payload = ShortVideoTaskRequest.model_validate(payload_dict)
    status_json = request_dir / "status.json"
    running = ShortVideoTaskResponse(
        success=True,
        status="RUNNING",
        action=payload.action,
        message_zh="任务已接收，正在后台执行。",
        debug_hint=default_debug_hint(request_dir),
        request_id=request_dir.name,
    )
    save_status(status_json, running)
    try:
        response = execute_task(config, request_dir, payload, logger)
    except Exception as exc:  # pragma: no cover
        logger.exception("task_failed request_id=%s action=%s", request_dir.name, payload.action)
        response = ShortVideoTaskResponse(
            success=False,
            status="FAILED",
            action=payload.action,
            message_zh=f"后台任务执行失败：{exc}",
            failed_step="gateway",
            debug_hint=default_debug_hint(request_dir),
            request_id=request_dir.name,
        )
    save_status(status_json, response)


def build_app(config_path: Path = DEFAULT_CONFIG_PATH) -> FastAPI:
    app = FastAPI(title="iOS Shortcuts Gateway", version="0.2.0")

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
        level_name = config.logging.level.upper()
        logger.setLevel(getattr(logging, level_name, logging.INFO))

    app.state.gateway_config = config
    app.state.gateway_config_error = config_error
    app.state.gateway_logger = logger
    app.state.gateway_log_dir = log_dir

    def require_bearer_token(authorization: str | None = Header(default=None)) -> str:
        if app.state.gateway_config is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Gateway config unavailable: {app.state.gateway_config_error}",
            )
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing or invalid bearer token.",
            )
        token = authorization.removeprefix("Bearer ").strip()
        if token != app.state.gateway_config.auth.bearer_token:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing or invalid bearer token.",
            )
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
    def config_summary(_: str = Depends(require_bearer_token)) -> dict[str, str]:
        current = app.state.gateway_config
        return {
            "bind_mode": current.server.bind_mode,
            "host": current.server.host,
            "vault_path": current.obsidian.vault_path,
            "clipper_script": current.routing.clipper_script,
            "analyzer_script": current.routing.analyzer_script,
        }

    @app.get("/short-video/task/{request_id}", response_model=ShortVideoTaskResponse)
    def get_task_status(request_id: str, _: str = Depends(require_bearer_token)) -> ShortVideoTaskResponse:
        request_dir = make_request_directory(log_dir, request_id)
        status_json = request_dir / "status.json"
        response = load_status(status_json)
        if response is None:
            raise HTTPException(status_code=404, detail="Request ID not found.")
        return response

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

        accepted = ShortVideoTaskResponse(
            success=True,
            status="ACCEPTED",
            action=payload.action,
            message_zh="任务已接收，正在后台执行。请稍后按 request_id 查询结果。",
            debug_hint=default_debug_hint(request_dir),
            request_id=request_id,
        )
        save_status(status_json, accepted)

        if payload.wait_for_completion:
            response = execute_task(current, request_dir, payload, logger)
            save_status(status_json, response)
            return response

        background_tasks.add_task(run_task_background, current, request_dir, payload.model_dump(), logger)
        return accepted

    return app


app = build_app()
