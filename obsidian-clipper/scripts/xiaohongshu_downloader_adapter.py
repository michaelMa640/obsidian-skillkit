import argparse
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


VIDEO_KEY_HINTS = (
    "video",
    "media",
    "stream",
    "master",
    "play",
    "download",
    "origin",
    "h264",
    "mp4",
)

COVER_KEY_HINTS = (
    "cover",
    "image",
    "thumbnail",
    "poster",
    "pic",
)

VIDEO_EXTENSIONS = (".mp4", ".mov", ".m4v", ".webm")
IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".gif")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--normalized-url", default="")
    parser.add_argument("--capture-id", required=True)
    parser.add_argument("--attachment-dir", required=True)
    parser.add_argument("--cookies-file", default="")
    parser.add_argument("--storage-state-path", default="")
    parser.add_argument("--server-url", required=True)
    parser.add_argument("--timeout-ms", type=int, default=30000)
    parser.add_argument("--backend-payload-path", default="")
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--proxy", default="")
    return parser.parse_args()


def has_value(value: str) -> bool:
    return bool(value and str(value).strip())


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def parse_cookie_file(cookies_file: Path) -> str:
    if not cookies_file.exists():
        return ""

    cookie_pairs: list[str] = []
    for raw_line in read_text(cookies_file).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 7:
            name = parts[-2].strip()
            value = parts[-1].strip()
            if has_value(name):
                cookie_pairs.append(f"{name}={value}")
    return "; ".join(cookie_pairs)


def build_request_candidates(source_url: str, normalized_url: str) -> list[str]:
    candidates: list[str] = []

    def add_candidate(url: str) -> None:
        if not has_value(url):
            return
        candidate = str(url).strip()
        if candidate and candidate not in candidates:
            candidates.append(candidate)

    add_candidate(source_url)
    add_candidate(normalized_url)

    if has_value(normalized_url):
        parsed = urllib.parse.urlparse(normalized_url)
        simplified = urllib.parse.urlunparse(
            (parsed.scheme, parsed.netloc, parsed.path, "", "", "")
        )
        add_candidate(simplified)

    return candidates


def flatten_urls(value, path: str = "") -> list[tuple[str, str]]:
    urls: list[tuple[str, str]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else str(key)
            urls.extend(flatten_urls(child, child_path))
        return urls
    if isinstance(value, list):
        for index, child in enumerate(value):
            child_path = f"{path}[{index}]" if path else f"[{index}]"
            urls.extend(flatten_urls(child, child_path))
        return urls
    if isinstance(value, str) and value.startswith(("http://", "https://")):
        urls.append((path.lower(), value))
    return urls


def looks_like_video_url(path_hint: str, url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    lowered_path = parsed.path.lower()
    lowered_hint = path_hint.lower()
    if lowered_path.endswith(VIDEO_EXTENSIONS):
        return True
    if any(token in lowered_hint for token in VIDEO_KEY_HINTS) and not lowered_path.endswith(IMAGE_EXTENSIONS):
        return True
    if "mp4" in lowered_path or "video" in lowered_path:
        return True
    return False


def looks_like_cover_url(path_hint: str, url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    lowered_path = parsed.path.lower()
    lowered_hint = path_hint.lower()
    if lowered_path.endswith(IMAGE_EXTENSIONS):
        return True
    if any(token in lowered_hint for token in COVER_KEY_HINTS):
        return True
    return False


def choose_best_video_url(flattened_urls: list[tuple[str, str]]) -> str:
    candidates: list[str] = []
    for path_hint, url in flattened_urls:
        if not looks_like_video_url(path_hint, url):
            continue
        parsed = urllib.parse.urlparse(url)
        lowered_path = parsed.path.lower()
        if lowered_path.endswith(".m3u8"):
            continue
        if url not in candidates:
            candidates.append(url)
    return candidates[0] if candidates else ""


def choose_best_cover_url(flattened_urls: list[tuple[str, str]]) -> str:
    candidates: list[str] = []
    for path_hint, url in flattened_urls:
        if looks_like_cover_url(path_hint, url) and url not in candidates:
            candidates.append(url)
    return candidates[0] if candidates else ""


def infer_extension(url: str, content_type: str = "") -> str:
    parsed = urllib.parse.urlparse(url)
    ext = Path(parsed.path).suffix.lower()
    if ext in VIDEO_EXTENSIONS + IMAGE_EXTENSIONS:
        return ext
    if has_value(content_type):
        guessed = mimetypes.guess_extension(content_type.split(";")[0].strip()) or ""
        if guessed:
            return guessed
    return ".mp4"


def download_file(
    url: str,
    destination: Path,
    referer: str,
    origin: str,
    cookie_header: str,
    timeout_seconds: float,
) -> tuple[bool, str]:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/122.0.0.0 Safari/537.36"
        ),
        "Referer": referer,
    }
    if has_value(origin):
        headers["Origin"] = origin
    if has_value(cookie_header):
        headers["Cookie"] = cookie_header

    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        content_type = response.headers.get("Content-Type", "")
        if "mpegurl" in content_type.lower():
            return False, "Adapter received an m3u8 playlist instead of a direct video file."
        data = response.read()
        if not data:
            return False, "Adapter downloaded an empty file."
        if not destination.suffix:
            destination = destination.with_suffix(infer_extension(url, content_type))
        destination.write_bytes(data)
        return True, str(destination)


def post_json(server_url: str, payload: dict, timeout_seconds: float) -> tuple[int, dict]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        server_url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        status_code = getattr(response, "status", 200)
        text = response.read().decode("utf-8", errors="replace")
        if not text.strip():
            return status_code, {}
        return status_code, json.loads(text)


def build_success_payload(
    args: argparse.Namespace,
    video_path: str,
    cover_url: str,
    backend_payload_path: str,
    backend_status_code: int,
    media_url: str,
    request_url_used: str,
) -> dict:
    return {
        "success": True,
        "download_status": "success",
        "download_method": "xhs-downloader",
        "video_path": video_path,
        "cover_url": cover_url,
        "backend_status_code": backend_status_code,
        "backend_error_code": "",
        "backend_error_message": "",
        "backend_payload_path": backend_payload_path,
        "media_url": media_url,
        "errors": [],
        "fallbacks": [],
        "backend": "xhs_downloader_api",
        "capture_id": args.capture_id,
        "request_url_used": request_url_used,
    }


def build_failure_payload(
    args: argparse.Namespace,
    error_code: str,
    message: str,
    backend_payload_path: str = "",
    backend_status_code: int = 0,
    extra_errors: list[str] | None = None,
    extra_fallbacks: list[str] | None = None,
    request_url_used: str = "",
) -> dict:
    return {
        "success": False,
        "download_status": "failed",
        "download_method": "none",
        "video_path": "",
        "cover_url": "",
        "backend_status_code": backend_status_code,
        "backend_error_code": error_code,
        "backend_error_message": message,
        "backend_payload_path": backend_payload_path,
        "media_url": "",
        "errors": extra_errors or [message],
        "fallbacks": extra_fallbacks or [error_code],
        "backend": "xhs_downloader_api",
        "capture_id": args.capture_id,
        "request_url_used": request_url_used,
    }


def main() -> int:
    args = parse_args()
    attachment_dir = Path(args.attachment_dir)
    attachment_dir.mkdir(parents=True, exist_ok=True)
    output_json = Path(args.output_json)
    backend_payload_path = Path(args.backend_payload_path) if has_value(args.backend_payload_path) else None

    cookie_header = ""
    if has_value(args.cookies_file):
        cookie_header = parse_cookie_file(Path(args.cookies_file))

    request_candidates = build_request_candidates(args.source_url, args.normalized_url)
    request_url = request_candidates[0] if request_candidates else args.source_url
    referer = request_url or args.source_url
    origin = ""
    if has_value(referer):
        parsed_referer = urllib.parse.urlparse(referer)
        if has_value(parsed_referer.scheme) and has_value(parsed_referer.netloc):
            origin = f"{parsed_referer.scheme}://{parsed_referer.netloc}"

    timeout_seconds = max(float(args.timeout_ms) / 1000.0, 5.0)
    last_status_code = 0
    backend_payload = {}
    request_url_used = request_url
    last_error_message = ""

    for candidate_url in request_candidates:
        request_url_used = candidate_url
        referer = candidate_url or args.source_url
        origin = ""
        if has_value(referer):
            parsed_referer = urllib.parse.urlparse(referer)
            if has_value(parsed_referer.scheme) and has_value(parsed_referer.netloc):
                origin = f"{parsed_referer.scheme}://{parsed_referer.netloc}"

        api_payload = {
            "url": candidate_url,
            "download": False,
            "cookie": cookie_header,
        }
        if has_value(args.proxy):
            api_payload["proxy"] = args.proxy

        try:
            status_code, backend_payload = post_json(args.server_url, api_payload, timeout_seconds)
            last_status_code = status_code
        except urllib.error.URLError as exc:
            write_json(
                output_json,
                build_failure_payload(
                    args,
                    error_code="backend_unavailable",
                    message=f"XHS-Downloader API is unavailable: {exc.reason}",
                    request_url_used=candidate_url,
                ),
            )
            return 0
        except Exception as exc:
            write_json(
                output_json,
                build_failure_payload(
                    args,
                    error_code="backend_request_failed",
                    message=f"XHS-Downloader request failed: {exc}",
                    request_url_used=candidate_url,
                ),
            )
            return 0

        flattened_urls = flatten_urls(backend_payload)
        media_url = choose_best_video_url(flattened_urls)
        if has_value(media_url):
            break

        backend_message = ""
        if isinstance(backend_payload, dict):
            backend_message = str(backend_payload.get("message", "")).strip()
        last_error_message = backend_message or "XHS-Downloader did not return a direct downloadable video URL."
    else:
        write_json(
            output_json,
            build_failure_payload(
                args,
                error_code="backend_no_media_url",
                message=last_error_message or "XHS-Downloader did not return a direct downloadable video URL.",
                backend_status_code=last_status_code,
                request_url_used=request_url_used,
            ),
        )
        return 0

    backend_payload_path_text = ""
    if backend_payload_path is not None:
        write_json(backend_payload_path, backend_payload if isinstance(backend_payload, dict) else {"payload": backend_payload})
        backend_payload_path_text = str(backend_payload_path)

    flattened_urls = flatten_urls(backend_payload)
    media_url = choose_best_video_url(flattened_urls)
    cover_url = choose_best_cover_url(flattened_urls)

    if not has_value(media_url):
        write_json(
            output_json,
            build_failure_payload(
                args,
                error_code="backend_no_media_url",
                message="XHS-Downloader did not return a direct downloadable video URL.",
                backend_payload_path=backend_payload_path_text,
                backend_status_code=last_status_code,
                request_url_used=request_url_used,
            ),
        )
        return 0

    destination = attachment_dir / "video-xhs-downloader"
    try:
        ok, result_text = download_file(
            url=media_url,
            destination=destination,
            referer=referer,
            origin=origin,
            cookie_header=cookie_header,
            timeout_seconds=timeout_seconds,
        )
    except urllib.error.HTTPError as exc:
        write_json(
            output_json,
            build_failure_payload(
                args,
                error_code="backend_download_failed",
                message=f"Adapter download failed with HTTP {exc.code}.",
                backend_payload_path=backend_payload_path_text,
                backend_status_code=last_status_code,
                request_url_used=request_url_used,
            ),
        )
        return 0
    except Exception as exc:
        write_json(
            output_json,
            build_failure_payload(
                args,
                error_code="backend_download_failed",
                message=f"Adapter download failed: {exc}",
                backend_payload_path=backend_payload_path_text,
                backend_status_code=last_status_code,
                request_url_used=request_url_used,
            ),
        )
        return 0

    if not ok:
        write_json(
            output_json,
            build_failure_payload(
                args,
                error_code="backend_download_failed",
                message=result_text,
                backend_payload_path=backend_payload_path_text,
                backend_status_code=last_status_code,
                request_url_used=request_url_used,
            ),
        )
        return 0

    write_json(
        output_json,
        build_success_payload(
            args=args,
            video_path=result_text,
            cover_url=cover_url,
            backend_payload_path=backend_payload_path_text,
            backend_status_code=last_status_code,
            media_url=media_url,
            request_url_used=request_url_used,
        ),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
