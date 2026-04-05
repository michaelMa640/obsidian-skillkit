import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


PLATFORM_RULES = {
    "xiaohongshu": {
        "ready_selectors": [
            'meta[property="og:title"]',
            'meta[property="og:description"]',
            '#detail-desc',
            '[class*="note-content"]',
            '[class*="desc"]',
        ],
        "title_selectors": [
            'meta[property="og:title"]',
            "h1",
            '[class*="title"]',
        ],
        "author_selectors": [
            'meta[name="author"]',
            '[class*="author"]',
            '[class*="user"] [class*="name"]',
        ],
        "text_selectors": [
            '#detail-desc',
            '[class*="note-content"]',
            '[class*="content"]',
            '[class*="desc"]',
            'article',
            'main',
        ],
        "metric_map": {
            "like_count": [
                '[class*="like"] [class*="count"]',
                '[class*="like"]',
            ],
            "collect_count": [
                '[class*="collect"] [class*="count"]',
                '[class*="collect"]',
            ],
            "comment_count": [
                '[class*="comment"] [class*="count"]',
                '[class*="comment"]',
            ],
        },
        "comment_selectors": [
            '[class*="comment"] [class*="content"]',
            '[class*="comment"] p',
        ],
    },
    "douyin": {
        "ready_selectors": [
            'meta[property="og:title"]',
            'meta[property="og:description"]',
            '[data-e2e="video-desc"]',
            '[data-e2e="browse-video-desc"]',
        ],
        "title_selectors": [
            '[data-e2e="video-desc"]',
            '[data-e2e="browse-video-desc"]',
            'meta[property="og:title"]',
            'h1',
        ],
        "author_selectors": [
            '[data-e2e="user-title"]',
            'meta[name="author"]',
            '[class*="author"]',
            '[class*="account"]',
        ],
        "text_selectors": [
            '[data-e2e="video-desc"]',
            '[data-e2e="browse-video-desc"]',
        ],
        "metric_map": {
            "like_count": [
                '[data-e2e="like-count"]',
                '[class*="like"] [class*="count"]',
            ],
            "comment_count": [
                '[data-e2e="comment-count"]',
                '[class*="comment"] [class*="count"]',
            ],
            "collect_count": [
                '[data-e2e="collect-count"]',
                '[class*="collect"] [class*="count"]',
            ],
            "share_count": [
                '[data-e2e="share-count"]',
                '[class*="share"] [class*="count"]',
            ],
        },
        "comment_selectors": [
            '[data-e2e="comment-item"] [data-e2e="comment-text"]',
            '[data-e2e="comment-item"] [class*="text"]',
            '[class*="comment"] [class*="content"]',
            '[class*="comment"] p',
        ],
    },
}


MAYBE_MOJIBAKE_MARKERS = ["婁", "闁", "闂", "锟", "鈥", "Ã", "æ"]
TRACKING_QUERY_KEYS = {
    "share_app_id",
    "share_from_user_hidden",
    "share_token",
    "share_sign",
    "sec_uid",
    "timestamp",
    "tt_from",
    "u_code",
    "user_id",
    "xsec_token",
    "xsec_source",
}
LOGIN_PROMPT_PATTERNS = (
    "立即登录",
    "登录查看更多评论",
    "登录查看全部评论",
    "登录查看评论",
    "请先登录",
    "绔嬪嵆鐧诲綍",
    "鐧诲綍鏌ョ湅鏇村璇勮",
    "鐧诲綍鏌ョ湅鍏ㄩ儴璇勮",
    "鐧诲綍鏌ョ湅璇勮",
    "璇峰厛鐧诲綍",
)
INTERSTITIAL_TEXT_PATTERNS = (
    "captcha",
    "verify",
    "验证码",
    "验证码中间页",
    "安全验证",
    "请完成安全验证",
)
AUTH_HOME_URLS = {
    "douyin": "https://www.douyin.com/",
}
AUTH_SESSION_COOKIE_NAMES = {
    "douyin": {
        "sessionid",
        "sessionid_ss",
        "sid_tt",
        "uid_tt",
        "passport_csrf_token",
        "passport_csrf_token_default",
        "ttwid",
    },
}
AUTH_INVALID_PATTERNS = {
    "douyin": (
        *LOGIN_PROMPT_PATTERNS,
        "登录查看更多精彩内容",
        "登录后查看更多精彩内容",
        "扫码登录",
    ),
}
XIAOHONGSHU_INTERSTITIAL_PATHS = {
    "/website-login/error",
}
XIAOHONGSHU_IP_RISK_ERROR_CODES = {
    "300012",
}
LIKELY_STATIC_IMAGE_MARKERS = (
    "douyinstatic.com/obj/douyin-pc-web",
    "byteimg.com/tos-cn-i-9r5gewecjs/emblem",
    "aweme-avatar",
)
HTTPONLY_COOKIE_PREFIX = "#HttpOnly_"


def first_non_empty(*values: Any) -> str:
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return ""


def repair_mojibake(text: str) -> str:
    text = text or ""
    if sum(1 for marker in MAYBE_MOJIBAKE_MARKERS if marker in text) < 2:
        return text
    try:
        fixed = text.encode("gb18030", errors="ignore").decode("utf-8", errors="ignore")
        if fixed and fixed != text:
            return fixed
    except Exception:
        return text
    return text


def normalize_ws(text: str) -> str:
    text = repair_mojibake(text or "")
    text = re.sub(r"\r\n?", "\n", text)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def extract_first_url(text: str) -> str:
    raw = (text or "").strip()
    if not raw:
        return ""
    match = re.search(r"https?://[^\s\"'<>]+", raw, re.IGNORECASE)
    return match.group(0).strip() if match else raw


def truncate(text: str, length: int) -> str:
    text = text or ""
    if len(text) <= length:
        return text
    return text[:length] + "..."


def is_zero_like(value: str) -> bool:
    normalized = normalize_ws(value)
    return normalized in {"0", "0.0", "0.00"}


def normalize_metric_value(value: Any) -> str:
    normalized = normalize_ws(str(value))
    if not normalized:
        return ""
    normalized = re.sub(r"^(点赞|获赞|赞|评论|收藏|分享)[\s:：]*", "", normalized)
    if not normalized:
        return ""
    if not re.search(r"\d", normalized):
        return ""
    return normalized


def looks_like_login_prompt(text: str) -> bool:
    normalized = normalize_ws(text)
    if not normalized:
        return False
    return any(pattern in normalized for pattern in LOGIN_PROMPT_PATTERNS)


def looks_like_interstitial_text(text: str) -> bool:
    normalized = normalize_ws(text)
    if not normalized:
        return False
    lowered = normalized.lower()
    return any(pattern in lowered for pattern in INTERSTITIAL_TEXT_PATTERNS)


def inspect_auth_session(context, platform: str, timeout_ms: int) -> dict[str, Any]:
    home_url = AUTH_HOME_URLS.get(platform, "")
    if not home_url:
        return {
            "auth_session_state": "unsupported_platform",
            "auth_session_likely_valid": False,
            "auth_session_reason": "no_preflight_for_platform",
            "auth_visible_login_prompt": False,
            "auth_context_cookie_count": 0,
            "auth_session_cookie_names": [],
        }

    page = context.new_page()
    try:
        page.goto(home_url, wait_until="domcontentloaded", timeout=min(timeout_ms, 15000))
        page.wait_for_timeout(1000)
        try:
            body_text = normalize_ws(page.locator("body").inner_text(timeout=min(timeout_ms, 2000)))
        except Exception:
            body_text = ""
        cookies = context.cookies([home_url])
        cookie_names = [normalize_ws(cookie.get("name", "")) for cookie in cookies if normalize_ws(cookie.get("name", ""))]
        session_cookie_names = sorted(
            {
                name
                for name in cookie_names
                if name in AUTH_SESSION_COOKIE_NAMES.get(platform, set())
            }
        )
        invalid_patterns = AUTH_INVALID_PATTERNS.get(platform, ())
        login_prompt_seen = any(pattern in body_text for pattern in invalid_patterns)

        if login_prompt_seen:
            session_state = "login_prompt_visible"
            likely_valid = False
            session_reason = "login_prompt_visible_on_home"
        elif session_cookie_names:
            session_state = "likely_valid"
            likely_valid = True
            session_reason = "session_cookies_present_without_login_prompt"
        elif cookie_names:
            session_state = "cookies_loaded_without_session_cookie"
            likely_valid = False
            session_reason = "context_has_cookies_but_no_session_cookie"
        else:
            session_state = "no_cookies_loaded"
            likely_valid = False
            session_reason = "context_has_no_cookies"

        return {
            "auth_session_state": session_state,
            "auth_session_likely_valid": likely_valid,
            "auth_session_reason": session_reason,
            "auth_visible_login_prompt": login_prompt_seen,
            "auth_context_cookie_count": len(cookie_names),
            "auth_session_cookie_names": session_cookie_names,
        }
    except Exception as exc:
        return {
            "auth_session_state": "unknown",
            "auth_session_likely_valid": False,
            "auth_session_reason": f"preflight_error: {exc}",
            "auth_visible_login_prompt": False,
            "auth_context_cookie_count": 0,
            "auth_session_cookie_names": [],
        }
    finally:
        page.close()


def normalize_identity_url(url: str) -> str:
    url = extract_first_url(url)
    try:
        parts = urlsplit(url)
    except Exception:
        return (url or "").strip()

    host = parts.netloc.lower()
    if host == "v.douyin.com":
        short_match = re.match(r"^/([A-Za-z0-9_-]+)/?", parts.path or "")
        if short_match:
            return f"{parts.scheme.lower()}://{host}/{short_match.group(1)}/"
    if host == "xhslink.com":
        short_match = re.match(r"^/o/([A-Za-z0-9_-]+)/?", parts.path or "")
        if short_match:
            return f"{parts.scheme.lower()}://{host}/o/{short_match.group(1)}"
        short_match = re.match(r"^/([A-Za-z0-9_-]+)/?", parts.path or "")
        if short_match:
            return f"{parts.scheme.lower()}://{host}/{short_match.group(1)}"

    filtered_query = []
    for key, value in parse_qsl(parts.query, keep_blank_values=True):
        lowered = key.lower()
        if lowered.startswith("utm_"):
            continue
        if lowered in TRACKING_QUERY_KEYS:
            continue
        filtered_query.append((key, value))
    filtered_query.sort()

    normalized_path = parts.path.rstrip("/") or "/"
    return urlunsplit(
        (
            parts.scheme.lower(),
            host,
            normalized_path,
            urlencode(filtered_query),
            "",
        )
    )


def detect_xiaohongshu_interstitial(page_url: str) -> dict[str, Any]:
    try:
        parts = urlsplit(page_url or "")
    except Exception:
        return {"is_interstitial": False}

    host = (parts.netloc or "").lower()
    path = parts.path or ""
    if not host.endswith("xiaohongshu.com") or path not in XIAOHONGSHU_INTERSTITIAL_PATHS:
        return {"is_interstitial": False}

    query = {key: value for key, value in parse_qsl(parts.query, keep_blank_values=True)}
    error_code = first_non_empty(query.get("error_code", ""))
    error_message = normalize_ws(query.get("error_msg", ""))
    redirect_path = first_non_empty(query.get("redirectPath", ""))
    redirect_path_normalized = normalize_identity_url(redirect_path) if redirect_path else ""
    block_type = "ip_risk" if (
        error_code in XIAOHONGSHU_IP_RISK_ERROR_CODES or "IP存在风险" in error_message
    ) else "website_error"

    return {
        "is_interstitial": True,
        "block_type": block_type,
        "error_code": error_code,
        "error_message": error_message,
        "redirect_path": redirect_path,
        "redirect_path_normalized": redirect_path_normalized,
        "page_url": page_url,
    }


def extract_source_item_id(url: str, platform: str) -> str:
    patterns_by_platform = {
        "douyin": [
            r"/video/(\d+)",
            r"modal_id=(\d+)",
            r"item_ids?=(\d+)",
        ],
        "xiaohongshu": [
            r"/explore/([0-9a-zA-Z]+)",
            r"/discovery/item/([0-9a-zA-Z]+)",
            r"noteId=([0-9a-zA-Z]+)",
        ],
    }
    for pattern in patterns_by_platform.get(platform, []):
        match = re.search(pattern, url or "")
        if match:
            return match.group(1)
    return ""


def build_navigation_url(url: str, platform: str) -> str:
    normalized_input = normalize_identity_url(url)
    if platform == "douyin":
        source_item_id = extract_source_item_id(normalized_input, platform)
        if source_item_id:
            return f"https://www.douyin.com/video/{source_item_id}"
    return normalized_input


def build_capture_identity(platform: str, normalized_url: str, source_item_id: str) -> tuple[str, str]:
    capture_key = f"{platform}:{source_item_id}" if source_item_id else f"{platform}:{normalized_url}"
    digest = hashlib.sha256(capture_key.encode("utf-8")).hexdigest()[:16]
    return capture_key, f"{platform}_{digest}"


def collect_tags(text: str, platform: str) -> list[str]:
    tags = ["clipped", "social", platform]
    for match in re.findall(r"#([^#\s]{1,30})", text or "")[:10]:
        cleaned = normalize_ws(match)
        if cleaned and cleaned not in tags:
            tags.append(cleaned)
    return tags


def safe_locator_text(page, selector: str, timeout_ms: int = 1500) -> str:
    try:
        locator = page.locator(selector).first
        if locator.count() == 0:
            return ""
        return normalize_ws(locator.inner_text(timeout=timeout_ms))
    except Exception:
        return ""


def safe_meta_content(page, selector: str) -> str:
    try:
        locator = page.locator(selector).first
        if locator.count() == 0:
            return ""
        return first_non_empty(locator.get_attribute("content"))
    except Exception:
        return ""


def wait_for_platform(page, platform: str, timeout_ms: int) -> None:
    selectors = PLATFORM_RULES.get(platform, {}).get("ready_selectors", [])
    for selector in selectors:
        try:
            page.wait_for_selector(selector, timeout=min(timeout_ms, 8000))
            return
        except PlaywrightTimeoutError:
            continue
        except Exception:
            continue

    try:
        page.wait_for_load_state("networkidle", timeout=min(timeout_ms, 5000))
    except PlaywrightTimeoutError:
        pass


def pick_text_by_selectors(page, selectors: list[str], timeout_ms: int = 2000) -> str:
    for selector in selectors:
        text = safe_locator_text(page, selector, timeout_ms=timeout_ms)
        if text:
            return text
    return ""


def collect_media_refs(page, css_selector: str, script: str, limit: int) -> list[str]:
    items: list[str] = []
    try:
        values = page.locator(css_selector).evaluate_all(script)
    except Exception:
        return items
    for value in values:
        candidate = first_non_empty(value)
        if candidate and candidate not in items:
            items.append(candidate)
        if len(items) >= limit:
            break
    return items


def collect_metric_values(page, metric_map: dict[str, list[str]]) -> dict[str, str]:
    metrics: dict[str, str] = {}
    for key, selectors in metric_map.items():
        for selector in selectors:
            value = normalize_metric_value(safe_locator_text(page, selector, timeout_ms=1200))
            if value:
                metrics[key] = value
                break
    return metrics


def collect_visible_comments(page, selectors: list[str], limit: int = 8) -> tuple[list[str], bool]:
    comments: list[str] = []
    login_prompt_seen = False
    for selector in selectors:
        try:
            values = page.locator(selector).evaluate_all(
                "els => els.map(e => (e.innerText || e.textContent || '').trim()).filter(Boolean).slice(0, 40)"
            )
        except Exception:
            values = []
        for value in values:
            cleaned = normalize_ws(value)
            if not cleaned:
                continue
            if looks_like_login_prompt(cleaned):
                login_prompt_seen = True
                continue
            if len(cleaned) < 2:
                continue
            if cleaned in comments:
                continue
            comments.append(cleaned)
            if len(comments) >= limit:
                return comments, login_prompt_seen
    return comments, login_prompt_seen


def should_keep_video_ref(src: str) -> bool:
    src = (src or "").strip()
    return bool(src and (src.startswith("http") or src.startswith("blob:")))


def should_keep_image_ref(src: str, platform: str) -> bool:
    src = (src or "").strip()
    if not src or src.startswith("data:"):
        return False
    lowered = src.lower()
    if any(marker in lowered for marker in LIKELY_STATIC_IMAGE_MARKERS):
        return False
    if platform == "douyin":
        if "douyinpic.com" not in lowered and "douyinstatic.com" not in lowered:
            return False
        if "avatar" in lowered:
            return False
    return src.startswith("http")


def build_social_raw_text(description: str, visible_text: str) -> str:
    parts: list[str] = []
    if description:
        parts.append(description)
    if visible_text and visible_text != description:
        parts.append(visible_text)
    return "\n\n".join(part for part in parts if part).strip()


def stringify_count(value: Any) -> str:
    if value is None or value == "":
        return ""
    if isinstance(value, bool):
        return ""
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return str(int(value)) if value.is_integer() else str(value)
    return normalize_ws(str(value))


def format_unix_timestamp(value: Any) -> str:
    try:
        timestamp = int(value)
    except (TypeError, ValueError):
        return ""
    if timestamp <= 0:
        return ""
    try:
        return datetime.fromtimestamp(timestamp).isoformat(sep=" ", timespec="seconds")
    except Exception:
        return ""


def iter_url_candidates(value: Any) -> list[str]:
    urls: list[str] = []
    if value is None:
        return urls
    if isinstance(value, str):
        candidate = value.strip()
        if candidate:
            urls.append(candidate)
        return urls
    if isinstance(value, list):
        for item in value:
            for candidate in iter_url_candidates(item):
                if candidate not in urls:
                    urls.append(candidate)
        return urls
    if isinstance(value, dict):
        for key in ("url_list", "url", "play_addr", "download_addr", "play_addr_h264", "origin_cover", "cover", "dynamic_cover"):
            if key in value:
                for candidate in iter_url_candidates(value.get(key)):
                    if candidate not in urls:
                        urls.append(candidate)
        return urls
    return urls


def first_url_candidate(*values: Any) -> str:
    for value in values:
        for candidate in iter_url_candidates(value):
            if candidate:
                return candidate
    return ""


def build_comment_display(comment: dict[str, str]) -> str:
    author = normalize_ws(comment.get("author", ""))
    text = normalize_ws(comment.get("text", ""))
    if author and text:
        return f"{author}: {text}"
    return first_non_empty(text, author)


def build_comment_objects_from_text(comments: list[str]) -> list[dict[str, str]]:
    objects: list[dict[str, str]] = []
    for comment in comments:
        cleaned = normalize_ws(comment)
        if cleaned:
            objects.append({"text": cleaned, "display_text": cleaned})
    return objects


def load_json_file(path: str) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def load_playwright_cookies(cookies_file: str) -> list[dict[str, Any]]:
    raw_text = Path(cookies_file).read_text(encoding="utf-8-sig")
    stripped = raw_text.lstrip()
    if not stripped:
        return []

    if stripped.startswith("{") or stripped.startswith("["):
        data = load_json_file(cookies_file)
        cookie_items = data.get("cookies") if isinstance(data, dict) else data
        cookies: list[dict[str, Any]] = []
        for item in cookie_items or []:
            if not isinstance(item, dict):
                continue
            name = first_non_empty(item.get("name"))
            value = first_non_empty(item.get("value"))
            domain = first_non_empty(item.get("domain"))
            if not (name and value and domain):
                continue
            cookie: dict[str, Any] = {
                "name": name,
                "value": value,
                "domain": domain,
                "path": first_non_empty(item.get("path"), "/"),
                "secure": bool(item.get("secure")),
            }
            if item.get("httpOnly") is not None:
                cookie["httpOnly"] = bool(item.get("httpOnly"))
            expires = item.get("expires", item.get("expirationDate"))
            try:
                expires_value = float(expires)
            except (TypeError, ValueError):
                expires_value = 0
            if expires_value > 0:
                cookie["expires"] = expires_value
            same_site = first_non_empty(item.get("sameSite"))
            if same_site in {"Lax", "None", "Strict"}:
                cookie["sameSite"] = same_site
            cookies.append(cookie)
        return cookies

    cookies: list[dict[str, Any]] = []
    for raw_line in raw_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("#") and not line.startswith(HTTPONLY_COOKIE_PREFIX):
            continue
        fields = raw_line.split("\t")
        if len(fields) < 7:
            continue
        domain = fields[0].strip()
        http_only = False
        if domain.startswith(HTTPONLY_COOKIE_PREFIX):
            http_only = True
            domain = domain[len(HTTPONLY_COOKIE_PREFIX):]
        name = fields[5].strip()
        value = fields[6].strip()
        if not (domain and name):
            continue
        cookie: dict[str, Any] = {
            "name": name,
            "value": value,
            "domain": domain,
            "path": fields[2].strip() or "/",
            "secure": fields[3].strip().upper() == "TRUE",
        }
        if http_only:
            cookie["httpOnly"] = True
        try:
            expires_value = float(fields[4].strip())
        except (TypeError, ValueError):
            expires_value = 0
        if expires_value > 0:
            cookie["expires"] = expires_value
        cookies.append(cookie)
    return cookies


def fetch_json_via_page(page, path: str, timeout_ms: int = 4000) -> dict[str, Any]:
    try:
        result = page.evaluate(
            """
            async ({ path, timeoutMs }) => {
                const controller = new AbortController();
                const timer = setTimeout(() => controller.abort(), timeoutMs);
                try {
                    const response = await fetch(path, {
                        credentials: \"include\",
                        signal: controller.signal,
                    });
                    const text = await response.text();
                    try {
                        return {
                            ok: response.ok,
                            status: response.status,
                            data: JSON.parse(text),
                            text_preview: text.slice(0, 2000),
                        };
                    } catch (error) {
                        return {
                            ok: false,
                            status: response.status,
                            data: null,
                            text_preview: text.slice(0, 2000),
                            error: String(error),
                        };
                    }
                } catch (error) {
                    return {
                        ok: false,
                        status: 0,
                        data: null,
                        text_preview: \"\",
                        error: String(error),
                    };
                } finally {
                    clearTimeout(timer);
                }
            }
            """,
            {"path": path, "timeoutMs": max(timeout_ms, 1000)},
        )
    except Exception as exc:
        return {"ok": False, "status": 0, "data": None, "text_preview": "", "error": str(exc)}
    return result if isinstance(result, dict) else {"ok": False, "status": 0, "data": None, "text_preview": ""}


def collect_douyin_video_refs(video_data: dict[str, Any]) -> list[str]:
    refs: list[str] = []
    candidates: list[Any] = [
        video_data.get("play_addr"),
        video_data.get("download_addr"),
        video_data.get("play_addr_h264"),
    ]
    for bit_rate in video_data.get("bit_rate") or []:
        if isinstance(bit_rate, dict):
            candidates.append(bit_rate.get("play_addr"))
    for candidate_group in candidates:
        for candidate in iter_url_candidates(candidate_group):
            if should_keep_video_ref(candidate) and candidate not in refs:
                refs.append(candidate)
    return refs


def extract_douyin_api_payload(page, aweme_id: str, timeout_ms: int, comment_limit: int = 8) -> dict[str, Any]:
    if not aweme_id:
        return {}

    detail_result = fetch_json_via_page(page, f"/aweme/v1/web/aweme/detail/?aweme_id={aweme_id}", timeout_ms=timeout_ms)
    comments_result = fetch_json_via_page(
        page,
        f"/aweme/v1/web/comment/list/?aweme_id={aweme_id}&cursor=0&count={max(comment_limit, 10)}",
        timeout_ms=timeout_ms,
    )

    detail_data = detail_result.get("data") or {}
    aweme = detail_data.get("aweme_detail") or {}
    stats = aweme.get("statistics") or {}
    author = aweme.get("author") or {}
    video_data = aweme.get("video") or {}
    comments_data = comments_result.get("data") or {}

    comment_items: list[dict[str, str]] = []
    for item in comments_data.get("comments") or []:
        if not isinstance(item, dict):
            continue
        text = normalize_ws(item.get("text", ""))
        if not text or looks_like_login_prompt(text):
            continue
        comment = {
            "cid": first_non_empty(item.get("cid")),
            "author": normalize_ws((item.get("user") or {}).get("nickname", "")),
            "text": text,
            "like_count": stringify_count(item.get("digg_count")),
            "reply_count": stringify_count(item.get("reply_comment_total")),
            "created_at": format_unix_timestamp(item.get("create_time")),
        }
        comment["display_text"] = build_comment_display(comment)
        if comment["display_text"]:
            comment_items.append(comment)
        if len(comment_items) >= comment_limit:
            break

    metrics = {
        "like_count": stringify_count(stats.get("digg_count")),
        "comment_count": stringify_count(stats.get("comment_count")),
        "collect_count": stringify_count(stats.get("collect_count")),
        "share_count": stringify_count(stats.get("share_count")),
    }
    cover_url = first_url_candidate(
        video_data.get("origin_cover"),
        video_data.get("cover"),
        video_data.get("dynamic_cover"),
        aweme.get("images"),
    )

    return {
        "title": normalize_ws(first_non_empty(aweme.get("desc"))),
        "description": normalize_ws(first_non_empty(aweme.get("desc"))),
        "author": normalize_ws(first_non_empty(author.get("nickname"), author.get("unique_id"))),
        "published_at": format_unix_timestamp(aweme.get("create_time")),
        "metrics": metrics,
        "candidate_video_refs": collect_douyin_video_refs(video_data),
        "cover_url": cover_url,
        "image_urls": [cover_url] if cover_url else [],
        "comments": comment_items,
        "top_comments": [item["display_text"] for item in comment_items if item.get("display_text")],
        "comments_total": stringify_count(first_non_empty(comments_data.get("total"), stats.get("comment_count"))),
        "detail_status": detail_result.get("status", 0),
        "comments_status": comments_result.get("status", 0),
        "detail_ok": bool(detail_result.get("ok") and aweme),
        "comments_ok": bool(comments_result.get("ok")),
    }


def build_engagement(metrics: dict[str, str]) -> dict[str, str]:
    return {
        "like": first_non_empty(metrics.get("like_count")),
        "comment": first_non_empty(metrics.get("comment_count")),
        "share": first_non_empty(metrics.get("share_count")),
        "collect": first_non_empty(metrics.get("collect_count")),
    }


def fill_metric_fallbacks(platform: str, metrics: dict[str, str], *texts: str) -> dict[str, str]:
    if platform == "douyin":
        return metrics
    combined = "\n".join(normalize_ws(text) for text in texts if text).strip()
    if not combined:
        return metrics
    patterns_by_key = {
        "like_count": (r"点赞\s*([0-9A-Za-z\.\u4e07wW]+)", r"获赞\s*([0-9A-Za-z\.\u4e07wW]+)"),
        "comment_count": (r"评论\s*([0-9A-Za-z\.\u4e07wW]+)",),
        "collect_count": (r"收藏\s*([0-9A-Za-z\.\u4e07wW]+)",),
    }
    for key, patterns in patterns_by_key.items():
        if metrics.get(key):
            continue
        for pattern in patterns:
            match = re.search(pattern, combined)
            if match:
                metrics[key] = match.group(1)
                break
    return metrics


def extract_social_payload(page, source_url: str, platform: str, timeout_ms: int, auth_debug: dict[str, Any] | None = None) -> dict[str, Any]:
    rules = PLATFORM_RULES.get(platform, {})
    requested_url = build_navigation_url(source_url, platform)
    page_url = normalize_identity_url(page.url)
    interstitial = detect_xiaohongshu_interstitial(page.url) if platform == "xiaohongshu" else {"is_interstitial": False}
    identity_url = first_non_empty(
        interstitial.get("redirect_path_normalized", ""),
        page_url,
        requested_url,
        normalize_identity_url(source_url),
    )
    source_item_id = first_non_empty(
        extract_source_item_id(identity_url, platform),
        extract_source_item_id(page_url, platform),
        extract_source_item_id(requested_url, platform),
        extract_source_item_id(source_url, platform),
    )
    final_url = requested_url if (platform == "douyin" and source_item_id) else first_non_empty(
        identity_url,
        requested_url,
        normalize_identity_url(source_url),
    )
    capture_key, capture_id = build_capture_identity(platform, final_url, source_item_id)

    structured_payload: dict[str, Any] = {}
    if platform == "douyin" and source_item_id:
        structured_payload = extract_douyin_api_payload(page, source_item_id, timeout_ms=min(timeout_ms, 5000))

    page_title = normalize_ws(page.title().strip())
    if looks_like_interstitial_text(page_title):
        page_title = ""
    try:
        body_text = normalize_ws(page.locator("body").inner_text(timeout=timeout_ms))
    except Exception:
        body_text = ""

    if interstitial.get("is_interstitial"):
        auth_debug = auth_debug or {}
        block_type = first_non_empty(interstitial.get("block_type"), "website_error")
        error_code = first_non_empty(interstitial.get("error_code"))
        error_message = first_non_empty(interstitial.get("error_message"))
        guidance_en = (
            "Xiaohongshu blocked this request with an IP risk page. Switch to a trusted network environment and retry."
            if block_type == "ip_risk"
            else "Xiaohongshu redirected this request to a website error page before the real note loaded."
        )
        guidance_zh = (
            "小红书将这次请求拦截为 IP 风险，请切换到可信网络环境后重试。"
            if block_type == "ip_risk"
            else "小红书在真实笔记页加载前跳转到了站点错误页，请稍后重试。"
        )
        title = "小红书 IP 风险拦截" if block_type == "ip_risk" else "小红书访问受限"
        raw_lines = [
            title,
            f"错误码: {error_code}" if error_code else "",
            f"错误信息: {error_message}" if error_message else "",
            f"原始目标: {interstitial.get('redirect_path_normalized')}" if interstitial.get("redirect_path_normalized") else "",
            f"拦截页面: {page.url}",
        ]
        raw_text = "\n".join(line for line in raw_lines if line)
        metadata: dict[str, Any] = {
            "capture_level": "blocked",
            "transcript_status": "missing",
            "media_downloaded": False,
            "analysis_ready": False,
            "extractor": "playwright",
            "route": "social",
            "platform": platform,
            "content_type": "short_video",
            "source_url": source_url,
            "normalized_url": final_url,
            "source_item_id": source_item_id,
            "capture_key": capture_key,
            "capture_id": capture_id,
            "final_url": page.url,
            "download_status": "blocked",
            "download_method": "none",
            "image_count": 0,
            "candidate_video_ref_count": 0,
            "text_length": len(raw_text),
            "comment_count_visible": 0,
            "platform_comment_count": "",
            "comments_capture_status": "none",
            "comments_login_required": False,
            "metrics_source": "none",
            "comments_source": "none",
            "detail_api_status": 0,
            "comments_api_status": 0,
            "detail_api_ok": False,
            "comments_api_ok": False,
            "auth_applied": bool(auth_debug.get("auth_applied")),
            "auth_mode": first_non_empty(auth_debug.get("auth_mode"), "none"),
            "auth_cookie_count": int(auth_debug.get("auth_cookie_count", 0)),
            "auth_session_state": first_non_empty(auth_debug.get("auth_session_state"), "unknown"),
            "auth_session_likely_valid": bool(auth_debug.get("auth_session_likely_valid")),
            "auth_visible_login_prompt": bool(auth_debug.get("auth_visible_login_prompt")),
            "auth_context_cookie_count": int(auth_debug.get("auth_context_cookie_count", 0)),
            "auth_storage_state_configured": bool(auth_debug.get("auth_storage_state_configured")),
            "auth_cookies_file_configured": bool(auth_debug.get("auth_cookies_file_configured")),
            "access_blocked": True,
            "access_block_type": block_type,
            "access_block_error_code": error_code,
            "access_block_error_message": error_message,
            "access_block_page_url": page.url,
            "access_block_target_url": first_non_empty(interstitial.get("redirect_path_normalized")),
            "auth_action_required": "switch_xiaohongshu_network",
            "auth_failure_reason": "xiaohongshu_ip_risk_blocked" if block_type == "ip_risk" else "xiaohongshu_website_error",
            "auth_guidance_en": guidance_en,
            "auth_guidance_zh": guidance_zh,
        }
        if auth_debug.get("auth_error"):
            metadata["auth_error"] = first_non_empty(auth_debug.get("auth_error"))
        if auth_debug.get("auth_session_reason"):
            metadata["auth_session_reason"] = first_non_empty(auth_debug.get("auth_session_reason"))
        if auth_debug.get("auth_session_cookie_names"):
            metadata["auth_session_cookie_names"] = auth_debug.get("auth_session_cookie_names")
        return {
            "capture_version": "phase3-social-v2",
            "capture_id": capture_id,
            "capture_key": capture_key,
            "source_url": source_url,
            "normalized_url": final_url,
            "platform": platform,
            "content_type": "short_video",
            "route": "social",
            "source_item_id": source_item_id,
            "title": title,
            "author": "unknown",
            "published_at": "unknown",
            "summary": guidance_zh,
            "description": guidance_zh,
            "raw_text": raw_text,
            "transcript": "",
            "tags": ["clipped", "social", platform, "access_blocked"],
            "images": [],
            "videos": [],
            "candidate_video_refs": [],
            "cover_url": "",
            "top_comments": [],
            "comments": [],
            "comments_count": 0,
            "comments_capture_status": "none",
            "comments_login_required": False,
            "auth_applied": bool(auth_debug.get("auth_applied")),
            "auth_mode": first_non_empty(auth_debug.get("auth_mode"), "none"),
            "auth_cookie_count": int(auth_debug.get("auth_cookie_count", 0)),
            "auth_session_state": first_non_empty(auth_debug.get("auth_session_state"), "unknown"),
            "auth_session_likely_valid": bool(auth_debug.get("auth_session_likely_valid")),
            "engagement": {"like": "", "comment": "", "share": "", "collect": ""},
            "metrics_like": "",
            "metrics_comment": "",
            "metrics_share": "",
            "metrics_collect": "",
            "status": "blocked",
            "download_status": "blocked",
            "download_method": "none",
            "media_downloaded": False,
            "analysis_ready": False,
            "analyzer_status": "pending",
            "bitable_sync_status": "pending",
            "access_blocked": True,
            "access_block_type": block_type,
            "access_block_error_code": error_code,
            "access_block_error_message": error_message,
            "access_block_page_url": page.url,
            "access_block_target_url": first_non_empty(interstitial.get("redirect_path_normalized")),
            "auth_action_required": "switch_xiaohongshu_network",
            "auth_failure_reason": "xiaohongshu_ip_risk_blocked" if block_type == "ip_risk" else "xiaohongshu_website_error",
            "auth_guidance_en": guidance_en,
            "auth_guidance_zh": guidance_zh,
            "errors": [guidance_zh],
            "metadata": metadata,
        }

    title = first_non_empty(
        structured_payload.get("title", ""),
        safe_meta_content(page, 'meta[property="og:title"]'),
        pick_text_by_selectors(page, rules.get("title_selectors", [])),
        page_title,
        f"Social Clip - {platform}",
    )
    if looks_like_interstitial_text(title):
        title = f"Social Clip - {platform}"
    description = normalize_ws(
        first_non_empty(
            structured_payload.get("description", ""),
            safe_meta_content(page, 'meta[property="og:description"]'),
            safe_meta_content(page, 'meta[name="description"]'),
        )
    )
    if looks_like_interstitial_text(description):
        description = ""
    author = first_non_empty(
        structured_payload.get("author", ""),
        safe_meta_content(page, 'meta[name="author"]'),
        safe_meta_content(page, 'meta[property="article:author"]'),
        pick_text_by_selectors(page, rules.get("author_selectors", [])),
        "unknown",
    )
    published_at = first_non_empty(
        structured_payload.get("published_at", ""),
        safe_meta_content(page, 'meta[property="article:published_time"]'),
        safe_meta_content(page, 'meta[name="publish-date"]'),
        "unknown",
    )

    if platform == "douyin":
        visible_text = first_non_empty(
            structured_payload.get("description", ""),
            pick_text_by_selectors(page, rules.get("text_selectors", []), timeout_ms=timeout_ms),
            description,
            title,
        )
    else:
        visible_text = first_non_empty(
            pick_text_by_selectors(page, rules.get("text_selectors", []), timeout_ms=timeout_ms),
            body_text,
        )
    visible_text = normalize_ws(visible_text)
    if looks_like_interstitial_text(visible_text):
        visible_text = ""

    api_comments = structured_payload.get("comments") or []
    api_top_comments = structured_payload.get("top_comments") or []
    if api_comments:
        comment_objects = api_comments
        top_comments = api_top_comments
        login_prompt_seen = False
    else:
        visible_comments, login_prompt_seen = collect_visible_comments(page, rules.get("comment_selectors", []), limit=8)
        comment_objects = build_comment_objects_from_text(visible_comments)
        top_comments = [item["display_text"] for item in comment_objects if item.get("display_text")]

    raw_text = build_social_raw_text(description, visible_text)
    visible_preview = truncate(raw_text, 8000)

    image_urls: list[str] = []
    structured_images = structured_payload.get("image_urls") or []
    og_image = safe_meta_content(page, 'meta[property="og:image"]')
    if platform == "douyin" and structured_images:
        image_urls.extend([image for image in structured_images if image and image not in image_urls])
    else:
        collected_images = collect_media_refs(
            page,
            "img",
            "els => els.map(e => e.currentSrc || e.src || '').filter(Boolean).slice(0, 16)",
            16,
        )
        for candidate in [og_image, *collected_images]:
            normalized_candidate = first_non_empty(candidate)
            if (
                normalized_candidate
                and normalized_candidate not in image_urls
                and should_keep_image_ref(normalized_candidate, platform)
            ):
                image_urls.append(normalized_candidate)

    candidate_video_refs: list[str] = []
    for candidate in structured_payload.get("candidate_video_refs") or []:
        if should_keep_video_ref(candidate) and candidate not in candidate_video_refs:
            candidate_video_refs.append(candidate)
    for candidate in collect_media_refs(
        page,
        "video",
        "els => els.map(e => e.currentSrc || e.src || e.poster || '').filter(Boolean).slice(0, 6)",
        6,
    ):
        if should_keep_video_ref(candidate) and candidate not in candidate_video_refs:
            candidate_video_refs.append(candidate)

    metrics = collect_metric_values(page, rules.get("metric_map", {}))
    for key, value in (structured_payload.get("metrics") or {}).items():
        normalized_value = normalize_metric_value(value)
        if not normalized_value:
            continue
        existing_value = normalize_ws(metrics.get(key, ""))
        if is_zero_like(normalized_value) and existing_value and not is_zero_like(existing_value):
            continue
        metrics[key] = normalized_value
    metrics = fill_metric_fallbacks(platform, metrics, description, visible_text, title)
    engagement = build_engagement(metrics)

    comments_login_required = bool(login_prompt_seen and not comment_objects)
    summary_parts = []
    if description:
        summary_parts.append(description)
    elif visible_preview:
        summary_parts.append(truncate(visible_preview, 180))
    else:
        summary_parts.append("Visible social page content captured via Playwright.")
    metric_text = ", ".join(f"{key}: {value}" for key, value in metrics.items() if value)
    if metric_text:
        summary_parts.append("Metrics: " + metric_text)
    if comment_objects:
        summary_parts.append(f"Visible comments captured: {len(comment_objects)}.")
    elif comments_login_required:
        summary_parts.append("Comments may require login.")
    summary_parts.append(f"Captured with Playwright from {platform}.")

    comments_capture_status = "login_required" if comments_login_required else ("captured" if comment_objects else "none")
    auth_debug = auth_debug or {}
    metadata: dict[str, Any] = {
        "capture_level": "standard" if visible_preview else "light",
        "transcript_status": "missing",
        "media_downloaded": False,
        "analysis_ready": True,
        "extractor": "playwright",
        "route": "social",
        "platform": platform,
        "content_type": "short_video",
        "source_url": source_url,
        "normalized_url": final_url,
        "source_item_id": source_item_id,
        "capture_key": capture_key,
        "capture_id": capture_id,
        "final_url": page.url,
        "download_status": "skipped",
        "download_method": "none",
        "image_count": len(image_urls),
        "candidate_video_ref_count": len(candidate_video_refs),
        "text_length": len(visible_preview),
        "comment_count_visible": len(comment_objects),
        "platform_comment_count": first_non_empty(structured_payload.get("comments_total", ""), metrics.get("comment_count", "")),
        "comments_capture_status": comments_capture_status,
        "comments_login_required": comments_login_required,
        "metrics_source": "douyin_api" if structured_payload.get("metrics") else "dom",
        "comments_source": "douyin_api" if api_comments else ("dom" if comment_objects else "none"),
        "detail_api_status": structured_payload.get("detail_status", 0),
        "comments_api_status": structured_payload.get("comments_status", 0),
        "detail_api_ok": bool(structured_payload.get("detail_ok")),
        "comments_api_ok": bool(structured_payload.get("comments_ok")),
        "auth_applied": bool(auth_debug.get("auth_applied")),
        "auth_mode": first_non_empty(auth_debug.get("auth_mode"), "none"),
        "auth_cookie_count": int(auth_debug.get("auth_cookie_count", 0)),
        "auth_session_state": first_non_empty(auth_debug.get("auth_session_state"), "unknown"),
        "auth_session_likely_valid": bool(auth_debug.get("auth_session_likely_valid")),
        "auth_visible_login_prompt": bool(auth_debug.get("auth_visible_login_prompt")),
        "auth_context_cookie_count": int(auth_debug.get("auth_context_cookie_count", 0)),
        "auth_storage_state_configured": bool(auth_debug.get("auth_storage_state_configured")),
        "auth_cookies_file_configured": bool(auth_debug.get("auth_cookies_file_configured")),
    }
    if auth_debug.get("auth_error"):
        metadata["auth_error"] = first_non_empty(auth_debug.get("auth_error"))
    if auth_debug.get("auth_session_reason"):
        metadata["auth_session_reason"] = first_non_empty(auth_debug.get("auth_session_reason"))
    if auth_debug.get("auth_session_cookie_names"):
        metadata["auth_session_cookie_names"] = auth_debug.get("auth_session_cookie_names")
    metadata.update(metrics)
    if top_comments:
        metadata["comments_preview"] = top_comments
    if structured_payload.get("cover_url"):
        metadata["cover_url"] = structured_payload["cover_url"]

    return {
        "capture_version": "phase3-social-v2",
        "capture_id": capture_id,
        "capture_key": capture_key,
        "source_url": source_url,
        "normalized_url": final_url,
        "platform": platform,
        "content_type": "short_video",
        "route": "social",
        "source_item_id": source_item_id,
        "title": normalize_ws(title),
        "author": normalize_ws(author),
        "published_at": published_at,
        "summary": " ".join(summary_parts).strip(),
        "description": description,
        "raw_text": visible_preview,
        "transcript": "",
        "tags": collect_tags(first_non_empty(description, visible_text), platform),
        "images": image_urls,
        "videos": candidate_video_refs,
        "candidate_video_refs": candidate_video_refs,
        "cover_url": first_non_empty(
            structured_payload.get("cover_url", ""),
            og_image if should_keep_image_ref(og_image, platform) else "",
            image_urls[0] if image_urls else "",
        ),
        "top_comments": top_comments,
        "comments": comment_objects,
        "comments_count": len(comment_objects),
        "comments_capture_status": comments_capture_status,
        "comments_login_required": comments_login_required,
        "auth_applied": bool(auth_debug.get("auth_applied")),
        "auth_mode": first_non_empty(auth_debug.get("auth_mode"), "none"),
        "auth_cookie_count": int(auth_debug.get("auth_cookie_count", 0)),
        "auth_session_state": first_non_empty(auth_debug.get("auth_session_state"), "unknown"),
        "auth_session_likely_valid": bool(auth_debug.get("auth_session_likely_valid")),
        "engagement": engagement,
        "metrics_like": first_non_empty(engagement.get("like")),
        "metrics_comment": first_non_empty(engagement.get("comment")),
        "metrics_share": first_non_empty(engagement.get("share")),
        "metrics_collect": first_non_empty(engagement.get("collect")),
        "status": "clipped",
        "download_status": "skipped",
        "download_method": "none",
        "media_downloaded": False,
        "analyzer_status": "pending",
        "bitable_sync_status": "pending",
        "metadata": metadata,
    }


def capture(url: str, platform: str, timeout_ms: int, storage_state: str = "", cookies_file: str = "") -> dict[str, Any]:
    auth_debug: dict[str, Any] = {
        "auth_applied": False,
        "auth_mode": "none",
        "auth_cookie_count": 0,
        "auth_storage_state_configured": bool(storage_state),
        "auth_cookies_file_configured": bool(cookies_file),
        "auth_session_state": "not_configured",
        "auth_session_likely_valid": False,
        "auth_session_reason": "",
        "auth_visible_login_prompt": False,
        "auth_context_cookie_count": 0,
        "auth_session_cookie_names": [],
    }
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context_kwargs: dict[str, Any] = {"viewport": {"width": 1440, "height": 2200}}
        storage_state_path = storage_state.strip()
        cookies_file_path = cookies_file.strip()

        if storage_state_path:
            if Path(storage_state_path).exists():
                context_kwargs["storage_state"] = storage_state_path
                auth_debug["auth_applied"] = True
                auth_debug["auth_mode"] = "storage_state"
            else:
                auth_debug["auth_error"] = f"storage_state_missing: {storage_state_path}"

        context = browser.new_context(**context_kwargs)
        try:
            if cookies_file_path and Path(cookies_file_path).exists():
                cookies = load_playwright_cookies(cookies_file_path)
                if cookies:
                    context.add_cookies(cookies)
                    auth_debug["auth_applied"] = True
                    auth_debug["auth_cookie_count"] = len(cookies)
                    auth_debug["auth_mode"] = (
                        "storage_state+cookies_file" if auth_debug.get("auth_mode") == "storage_state" else "cookies_file"
                    )
            elif cookies_file_path and "auth_error" not in auth_debug:
                auth_debug["auth_error"] = f"cookies_file_missing: {cookies_file_path}"

            page = context.new_page()
            if auth_debug.get("auth_applied"):
                auth_debug.update(inspect_auth_session(context, platform, timeout_ms=min(timeout_ms, 15000)))
            elif auth_debug.get("auth_error"):
                auth_debug["auth_session_state"] = "missing_files"
                auth_debug["auth_session_reason"] = first_non_empty(auth_debug.get("auth_error"))
            navigation_url = build_navigation_url(url, platform)
            page.goto(navigation_url, wait_until="domcontentloaded", timeout=timeout_ms)
            page.wait_for_timeout(1200)
            wait_for_platform(page, platform, timeout_ms)
            page.mouse.wheel(0, 1800)
            page.wait_for_timeout(1200)
            return extract_social_payload(page, url, platform, timeout_ms=min(timeout_ms, 5000), auth_debug=auth_debug)
        finally:
            context.close()
            browser.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--timeout-ms", type=int, default=25000)
    parser.add_argument("--storage-state", default="")
    parser.add_argument("--cookies-file", default="")
    parser.add_argument("--output-json")
    args = parser.parse_args()

    result = capture(args.url, args.platform, args.timeout_ms, storage_state=args.storage_state, cookies_file=args.cookies_file)
    payload = json.dumps(result, ensure_ascii=False)
    if args.output_json:
        with open(args.output_json, "w", encoding="utf-8") as handle:
            handle.write(payload)
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
