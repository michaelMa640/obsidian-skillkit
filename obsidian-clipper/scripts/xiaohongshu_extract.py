import argparse
from datetime import datetime
import hashlib
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--normalized-url", default="")
    parser.add_argument("--cookies-file", default="")
    parser.add_argument("--storage-state-path", default="")
    parser.add_argument("--server-url", required=True)
    parser.add_argument("--timeout-ms", type=int, default=30000)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--backend-payload-path", default="")
    parser.add_argument("--proxy", default="")
    return parser.parse_args()


def has_value(value: Any) -> bool:
    return value is not None and str(value).strip() != ""


def string_value(*values: Any, default: str = "") -> str:
    for value in values:
        if has_value(value):
            return str(value).strip()
    return default


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_json(path: Path, payload: dict[str, Any]) -> None:
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
        candidate = string_value(url)
        if candidate and candidate not in candidates:
            candidates.append(candidate)

    add_candidate(source_url)
    add_candidate(normalized_url)

    if has_value(normalized_url):
        parsed = urllib.parse.urlparse(normalized_url)
        simplified = urllib.parse.urlunparse((parsed.scheme, parsed.netloc, parsed.path, "", "", ""))
        add_candidate(simplified)

    return candidates


def extract_note_id_from_url(*urls: str) -> str:
    for url in urls:
        value = string_value(url)
        if not value:
            continue
        for pattern in (r"/explore/([A-Za-z0-9]+)", r"/discovery/item/([A-Za-z0-9]+)"):
            match = re.search(pattern, value)
            if match:
                return match.group(1)
    return ""


def build_capture_identity(platform: str, source_item_id: str, normalized_url: str, source_url: str) -> tuple[str, str]:
    capture_key = f"{platform}:{source_item_id}" if has_value(source_item_id) else f"{platform}:{string_value(normalized_url, source_url)}"
    digest = hashlib.sha256(capture_key.encode("utf-8")).hexdigest()[:16]
    return capture_key, f"{platform}_{digest}"


def normalize_xiaohongshu_note_url(url: str, source_item_id: str) -> str:
    value = string_value(url)
    if has_value(source_item_id) and (not has_value(value) or "xhslink.com" in value):
        return f"https://www.xiaohongshu.com/discovery/item/{source_item_id}"
    return value


def post_json(server_url: str, payload: dict[str, Any], timeout_seconds: float) -> tuple[int, dict[str, Any]]:
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
        return status_code, json.loads(text) if text.strip() else {}


def build_page_request_candidates(source_url: str, normalized_url: str) -> list[str]:
    candidates = build_request_candidates(source_url, normalized_url)
    page_candidates: list[str] = []

    def add_candidate(url: str) -> None:
        candidate = string_value(url)
        if candidate and candidate not in page_candidates:
            page_candidates.append(candidate)

    for candidate in candidates:
        add_candidate(candidate)
        parsed = urllib.parse.urlparse(candidate)
        match = re.match(r"^/explore/([A-Za-z0-9]+)$", parsed.path or "")
        if match:
            discovery_url = urllib.parse.urlunparse(
                (parsed.scheme, parsed.netloc, f"/discovery/item/{match.group(1)}", "", parsed.query, "")
            )
            add_candidate(discovery_url)
    return page_candidates


def fetch_html(url: str, cookie_header: str, timeout_seconds: float) -> str:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/122.0.0.0 Safari/537.36"
        ),
        "Referer": "https://www.xiaohongshu.com/",
    }
    if has_value(cookie_header):
        headers["Cookie"] = cookie_header
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
        return response.read().decode("utf-8", errors="replace")


def extract_json_object(text: str, start_index: int) -> str:
    if start_index < 0 or start_index >= len(text) or text[start_index] != "{":
        return ""

    depth = 0
    in_string = False
    escape = False
    for index in range(start_index, len(text)):
        char = text[index]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start_index : index + 1]
    return ""


def extract_initial_state(html: str) -> dict[str, Any]:
    marker = "window.__INITIAL_STATE__="
    marker_index = html.find(marker)
    if marker_index < 0:
        return {}

    object_start = html.find("{", marker_index + len(marker))
    state_text = extract_json_object(html, object_start)
    if not state_text:
        return {}

    state_text = re.sub(r":undefined([,}])", r":null\1", state_text)
    return json.loads(state_text)


def find_note_payload(initial_state: dict[str, Any]) -> dict[str, Any]:
    note_store = ((initial_state.get("note") or {}).get("noteDetailMap") or {})
    for value in note_store.values():
        note = (value or {}).get("note") or {}
        if note:
            return note
    return {}


def first_stream_url(video: dict[str, Any]) -> str:
    stream = (((video.get("media") or {}).get("stream") or {}).get("h264") or [])
    for item in stream:
        if not isinstance(item, dict):
            continue
        master_url = string_value(item.get("masterUrl"))
        if has_value(master_url):
            return master_url
        backup_url = first_media_url(item.get("backupUrls"))
        if has_value(backup_url):
            return backup_url
    return ""


def first_cover_url(note: dict[str, Any]) -> str:
    for item in note.get("imageList") or []:
        if not isinstance(item, dict):
            continue
        candidate = string_value(item.get("urlDefault"), item.get("urlPre"), item.get("url"))
        if has_value(candidate):
            return candidate
    return ""


def format_timestamp(value: Any) -> str:
    try:
        timestamp = float(value)
    except Exception:
        return "unknown"
    if timestamp > 10_000_000_000:
        timestamp = timestamp / 1000.0
    return datetime.fromtimestamp(timestamp).strftime("%Y-%m-%d_%H:%M:%S")


def build_ssr_success_payload(
    source_url: str,
    normalized_url: str,
    request_url_used: str,
    note: dict[str, Any],
    initial_state_path: str,
) -> dict[str, Any]:
    interact = note.get("interactInfo") or {}
    source_item_id = string_value(note.get("noteId"), default=extract_note_id_from_url(request_url_used, normalized_url, source_url))
    resolved_normalized_url = normalize_xiaohongshu_note_url(string_value(request_url_used, normalized_url, source_url), source_item_id)
    capture_key, capture_id = build_capture_identity("xiaohongshu", source_item_id, resolved_normalized_url, source_url)
    canonical_video_url = first_stream_url(note.get("video") or {})
    cover_url = first_cover_url(note)
    metrics = {
        "like_count": string_value(interact.get("likedCount")),
        "comment_count": string_value(interact.get("commentCount")),
        "collect_count": string_value(interact.get("collectedCount")),
        "share_count": string_value(interact.get("shareCount")),
    }
    media_candidates = [item for item in [canonical_video_url] if has_value(item)]
    return {
        "success": True,
        "extractor": "xiaohongshu_ssr",
        "backend": "xiaohongshu_html_ssr",
        "backend_status_code": 200,
        "backend_error_code": "",
        "backend_error_message": "",
        "backend_payload_path": initial_state_path,
        "request_url_used": request_url_used,
        "source_url": source_url,
        "normalized_url": resolved_normalized_url,
        "source_item_id": source_item_id,
        "capture_key": capture_key,
        "capture_id": capture_id,
        "title": string_value(note.get("title")),
        "author": string_value((note.get("user") or {}).get("nickname")),
        "description": string_value(note.get("desc")),
        "published_at": format_timestamp(note.get("time")),
        "metrics": metrics,
        "comments": [],
        "media_candidates": media_candidates,
        "canonical_video_url": canonical_video_url,
        "cover_url": cover_url,
        "access_blocked": False,
        "error_code": "",
        "error_message": "",
    }


def first_media_url(value: Any) -> str:
    if isinstance(value, list):
        for item in value:
            if has_value(item):
                return str(item).strip()
    if has_value(value):
        return str(value).strip()
    return ""


def normalize_metrics(data: dict[str, Any]) -> dict[str, str]:
    return {
        "like_count": string_value(data.get("鐐硅禐鏁伴噺")),
        "comment_count": string_value(data.get("璇勮鏁伴噺")),
        "collect_count": string_value(data.get("鏀惰棌鏁伴噺")),
        "share_count": string_value(data.get("鍒嗕韩鏁伴噺")),
    }


def build_success_payload(
    source_url: str,
    normalized_url: str,
    request_url_used: str,
    backend_status_code: int,
    backend_payload_path: str,
    backend_payload: dict[str, Any],
) -> dict[str, Any]:
    raw_backend_url = string_value(data.get("浣滃搧閾炬帴"), normalized_url, source_url)
    source_item_id = extract_note_id_from_url(raw_backend_url, request_url_used, source_url)
    resolved_normalized_url = normalize_xiaohongshu_note_url(raw_backend_url, source_item_id)
    capture_key, capture_id = build_capture_identity("xiaohongshu", source_item_id, resolved_normalized_url, source_url)
    metrics = normalize_metrics(data)
    canonical_video_url = first_media_url(data.get("涓嬭浇鍦板潃"))
    cover_url = first_media_url(data.get("灏侀潰鍦板潃"))
    media_candidates = [item for item in [canonical_video_url] if has_value(item)]
    return {
        "success": True,
        "extractor": "xiaohongshu_backend",
        "backend": "xhs_downloader_api",
        "backend_status_code": backend_status_code,
        "backend_error_code": "",
        "backend_error_message": "",
        "backend_payload_path": backend_payload_path,
        "request_url_used": request_url_used,
        "source_url": source_url,
        "source_item_id": source_item_id,
        "capture_key": capture_key,
        "capture_id": capture_id,
        "normalized_url": resolved_normalized_url,
        "title": string_value(data.get("title"), data.get("note_title")),
        "author": string_value(data.get("author"), data.get("nickname")),
        "description": string_value(data.get("description"), data.get("desc")),
        "published_at": string_value(data.get("published_at"), data.get("publish_time"), default="unknown"),
        "metrics": metrics,
        "comments": [],
        "media_candidates": media_candidates,
        "canonical_video_url": canonical_video_url,
        "cover_url": cover_url,
        "access_blocked": False,
        "error_code": "",
        "error_message": "",
    }


def build_failure_payload(
    source_url: str,
    normalized_url: str,
    request_url_used: str,
    error_code: str,
    message: str,
    backend_status_code: int = 0,
    backend_payload_path: str = "",
) -> dict[str, Any]:
    source_item_id = extract_note_id_from_url(request_url_used, normalized_url, source_url)
    capture_key, capture_id = build_capture_identity("xiaohongshu", source_item_id, normalized_url, source_url)
    return {
        "success": False,
        "extractor": "xiaohongshu_backend",
        "backend": "xhs_downloader_api",
        "backend_status_code": backend_status_code,
        "backend_error_code": error_code,
        "backend_error_message": message,
        "backend_payload_path": backend_payload_path,
        "request_url_used": request_url_used,
        "source_url": source_url,
        "normalized_url": normalized_url,
        "source_item_id": source_item_id,
        "capture_key": capture_key,
        "capture_id": capture_id,
        "title": "",
        "author": "",
        "description": "",
        "published_at": "unknown",
        "metrics": {},
        "comments": [],
        "media_candidates": [],
        "canonical_video_url": "",
        "cover_url": "",
        "access_blocked": False,
        "error_code": error_code,
        "error_message": message,
    }


def main() -> int:
    args = parse_args()
    output_json = Path(args.output_json)
    backend_payload_path = Path(args.backend_payload_path) if has_value(args.backend_payload_path) else None
    cookie_header = parse_cookie_file(Path(args.cookies_file)) if has_value(args.cookies_file) else ""
    request_candidates = build_request_candidates(args.source_url, args.normalized_url)
    timeout_seconds = max(float(args.timeout_ms) / 1000.0, 5.0)
    request_url_used = request_candidates[0] if request_candidates else args.source_url
    last_status_code = 0
    last_backend_payload: dict[str, Any] = {}
    last_message = ""

    page_candidates = build_page_request_candidates(args.source_url, args.normalized_url)
    initial_state_path = ""
    if backend_payload_path is not None:
        initial_state_path = str(backend_payload_path.with_name("xiaohongshu-initial-state.json"))

    for candidate_url in page_candidates:
        try:
            html = fetch_html(candidate_url, cookie_header, timeout_seconds)
            initial_state = extract_initial_state(html)
            note = find_note_payload(initial_state)
            if note:
                if has_value(initial_state_path):
                    write_json(Path(initial_state_path), initial_state)
                write_json(
                    output_json,
                    build_ssr_success_payload(
                        args.source_url,
                        args.normalized_url,
                        candidate_url,
                        note,
                        initial_state_path,
                    ),
                )
                return 0
            if "page not found" in html.lower():
                last_message = "XHS SSR page request returned a page-not-found shell."
        except Exception as exc:
            last_message = f"XHS SSR request failed: {exc}"

    for candidate_url in request_candidates:
        request_url_used = candidate_url
        payload: dict[str, Any] = {"url": candidate_url, "download": False, "cookie": cookie_header}
        if has_value(args.proxy):
            payload["proxy"] = args.proxy
        try:
            status_code, backend_payload = post_json(args.server_url, payload, timeout_seconds)
        except urllib.error.URLError as exc:
            write_json(
                output_json,
                build_failure_payload(
                    args.source_url,
                    args.normalized_url,
                    candidate_url,
                    "backend_unavailable",
                    f"XHS-Downloader API is unavailable: {exc.reason}",
                ),
            )
            return 0
        except Exception as exc:
            write_json(
                output_json,
                build_failure_payload(
                    args.source_url,
                    args.normalized_url,
                    candidate_url,
                    "backend_request_failed",
                    f"XHS-Downloader request failed: {exc}",
                ),
            )
            return 0

        last_status_code = status_code
        last_backend_payload = backend_payload
        if backend_payload_path is not None:
            write_json(backend_payload_path, backend_payload)

        data = backend_payload.get("data") or {}
        if isinstance(data, dict) and (has_value(data.get("浣滃搧鏍囬")) or has_value(first_media_url(data.get("涓嬭浇鍦板潃")))):
            write_json(
                output_json,
                build_success_payload(
                    args.source_url,
                    args.normalized_url,
                    candidate_url,
                    status_code,
                    str(backend_payload_path) if backend_payload_path is not None else "",
                    backend_payload,
                ),
            )
            return 0

        last_message = string_value(backend_payload.get("message"), default="XHS extractor did not return structured item data.")

    write_json(
        output_json,
        build_failure_payload(
            args.source_url,
            args.normalized_url,
            request_url_used,
            "extract_failed",
            last_message or "XHS extractor did not return structured item data.",
            backend_status_code=last_status_code,
            backend_payload_path=str(backend_payload_path) if backend_payload_path is not None else "",
        ),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
