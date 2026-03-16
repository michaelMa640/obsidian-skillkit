import argparse
import hashlib
import json
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
            'h1',
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
            'meta[property="og:title"]',
            '[data-e2e="video-desc"]',
            '[data-e2e="browse-video-desc"]',
            'h1',
        ],
        "author_selectors": [
            'meta[name="author"]',
            '[data-e2e="user-title"]',
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


MAYBE_MOJIBAKE_MARKERS = ["娑", "閸", "閹", "閽", "闂", "閻", "閵"]
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
    "登录后查看更多评论",
    "请先登录",
)
LIKELY_STATIC_IMAGE_MARKERS = (
    "douyinstatic.com/obj/douyin-pc-web",
    "byteimg.com/tos-cn-i-9r5gewecjs/emblem",
    "aweme-avatar",
)


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


def truncate(text: str, length: int) -> str:
    text = text or ""
    if len(text) <= length:
        return text
    return text[:length] + "..."


def looks_like_login_prompt(text: str) -> bool:
    normalized = normalize_ws(text)
    if not normalized:
        return False
    return any(pattern in normalized for pattern in LOGIN_PROMPT_PATTERNS)


def normalize_identity_url(url: str) -> str:
    try:
        parts = urlsplit(url)
    except Exception:
        return (url or "").strip()

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
    normalized = urlunsplit(
        (
            parts.scheme.lower(),
            parts.netloc.lower(),
            normalized_path,
            urlencode(filtered_query),
            "",
        )
    )
    return normalized


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


def build_capture_identity(platform: str, normalized_url: str, source_item_id: str) -> tuple[str, str]:
    capture_key = f"{platform}:{source_item_id}" if source_item_id else f"{platform}:{normalized_url}"
    digest = hashlib.sha256(capture_key.encode("utf-8")).hexdigest()[:16]
    return capture_key, f"{platform}_{digest}"


def collect_tags(text: str, platform: str) -> list[str]:
    tags = ["clipped", "social", platform]
    for match in re.findall(r"#([^#\s]{1,30})", text or "")[:10]:
        cleaned = match.strip()
        if cleaned and cleaned not in tags:
            tags.append(cleaned)
    return tags


def safe_locator_text(page, selector: str, timeout_ms: int = 1500) -> str:
    try:
        locator = page.locator(selector).first
        if locator.count() == 0:
            return ""
        text = locator.inner_text(timeout=timeout_ms)
        return normalize_ws(text)
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
        for src in page.locator(css_selector).evaluate_all(script):
            candidate = first_non_empty(src)
            if candidate and candidate not in items:
                items.append(candidate)
    except Exception:
        return []
    return items[:limit]


def collect_metric_values(page, metric_map: dict[str, list[str]]) -> dict[str, str]:
    metrics: dict[str, str] = {}
    for key, selectors in metric_map.items():
        for selector in selectors:
            value = safe_locator_text(page, selector, timeout_ms=1200)
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
                "els => els.map(e => (e.innerText || e.textContent || '').trim()).filter(Boolean).slice(0, 24)"
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
    if not src:
        return False
    return src.startswith("http") or src.startswith("blob:")


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


def build_comment_objects(comments: list[str]) -> list[dict[str, str]]:
    return [{"text": comment} for comment in comments]


def build_engagement(metrics: dict[str, str]) -> dict[str, str]:
    return {
        "like": first_non_empty(metrics.get("like_count")),
        "comment": first_non_empty(metrics.get("comment_count")),
        "share": first_non_empty(metrics.get("share_count")),
        "collect": first_non_empty(metrics.get("collect_count")),
    }


def fill_metric_fallbacks(platform: str, metrics: dict[str, str], *texts: str) -> dict[str, str]:
    combined = "\n".join(normalize_ws(text) for text in texts if text).strip()
    if not combined:
        return metrics
    if platform == "douyin":
        if not metrics.get("like_count"):
            for pattern in (
                r"已经收获了\s*([0-9A-Za-z\.\u4e07wW]+)\s*个喜欢",
                r"获赞\s*([0-9A-Za-z\.\u4e07wW]+)",
                r"点赞\s*([0-9A-Za-z\.\u4e07wW]+)",
            ):
                match = re.search(pattern, combined)
                if match:
                    metrics["like_count"] = match.group(1)
                    break
        if not metrics.get("comment_count"):
            for pattern in (
                r"评论\s*([0-9A-Za-z\.\u4e07wW]+)",
                r"([0-9A-Za-z\.\u4e07wW]+)\s*条评论",
            ):
                match = re.search(pattern, combined)
                if match:
                    metrics["comment_count"] = match.group(1)
                    break
    return metrics


def extract_social_payload(page, source_url: str, platform: str, timeout_ms: int) -> dict[str, Any]:
    rules = PLATFORM_RULES.get(platform, {})
    final_url = normalize_identity_url(page.url)
    source_item_id = first_non_empty(
        extract_source_item_id(final_url, platform),
        extract_source_item_id(source_url, platform),
    )
    capture_key, capture_id = build_capture_identity(platform, final_url, source_item_id)

    title = first_non_empty(
        safe_meta_content(page, 'meta[property="og:title"]'),
        pick_text_by_selectors(page, rules.get("title_selectors", [])),
        page.title().strip(),
        f"Social Clip - {platform}",
    )
    description = normalize_ws(
        first_non_empty(
            safe_meta_content(page, 'meta[property="og:description"]'),
            safe_meta_content(page, 'meta[name="description"]'),
        )
    )
    author = first_non_empty(
        safe_meta_content(page, 'meta[name="author"]'),
        safe_meta_content(page, 'meta[property="article:author"]'),
        pick_text_by_selectors(page, rules.get("author_selectors", [])),
        "unknown",
    )
    published_at = first_non_empty(
        safe_meta_content(page, 'meta[property="article:published_time"]'),
        safe_meta_content(page, 'meta[name="publish-date"]'),
        "unknown",
    )

    if platform == "douyin":
        visible_text = first_non_empty(
            pick_text_by_selectors(page, rules.get("text_selectors", []), timeout_ms=timeout_ms),
            description,
            title,
        )
    else:
        visible_text = first_non_empty(
            pick_text_by_selectors(page, rules.get("text_selectors", []), timeout_ms=timeout_ms),
            normalize_ws(page.locator("body").inner_text(timeout=timeout_ms)),
        )
    visible_text = normalize_ws(visible_text)

    comments, login_prompt_seen = collect_visible_comments(page, rules.get("comment_selectors", []), limit=8)
    comment_objects = build_comment_objects(comments)
    raw_text = build_social_raw_text(description, visible_text)
    visible_preview = truncate(raw_text, 8000)

    image_urls: list[str] = []
    og_image = safe_meta_content(page, 'meta[property="og:image"]')
    collected_images = collect_media_refs(
        page,
        "img",
        "els => els.map(e => e.currentSrc || e.src || '').filter(Boolean).slice(0, 12)",
        12,
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
    for src in collect_media_refs(
        page,
        "video",
        "els => els.map(e => e.currentSrc || e.src || e.poster || '').filter(Boolean).slice(0, 6)",
        6,
    ):
        if should_keep_video_ref(src) and src not in candidate_video_refs:
            candidate_video_refs.append(src)

    metrics = collect_metric_values(page, rules.get("metric_map", {}))
    metrics = fill_metric_fallbacks(platform, metrics, description, visible_text, title)
    engagement = build_engagement(metrics)

    summary_parts = []
    if description:
        summary_parts.append(description)
    elif visible_preview:
        summary_parts.append(truncate(visible_preview, 180))
    else:
        summary_parts.append("已通过 Playwright 抓取页面可见内容。")
    metric_text = ", ".join(f"{key}: {value}" for key, value in metrics.items() if value)
    if metric_text:
        summary_parts.append("互动数据: " + metric_text)
    if comments:
        summary_parts.append(f"可见评论抓取 {len(comments)} 条。")
    elif login_prompt_seen:
        summary_parts.append("评论区需要登录态才能稳定抓取。")
    summary_parts.append(f"采集方式: Playwright / {platform}。")

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
        "comment_count_visible": len(comments),
        "comments_capture_status": "login_required" if login_prompt_seen and not comments else ("captured" if comments else "none"),
    }
    metadata.update(metrics)
    if comments:
        metadata["comments_preview"] = comments

    return {
        "capture_version": "phase2-social-v1",
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
        "cover_url": first_non_empty(og_image if should_keep_image_ref(og_image, platform) else "", image_urls[0] if image_urls else ""),
        "top_comments": comments,
        "comments": comment_objects,
        "comments_count": len(comments),
        "comments_capture_status": "login_required" if login_prompt_seen and not comments else ("captured" if comments else "none"),
        "comments_login_required": bool(login_prompt_seen and not comments),
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


def capture(url: str, platform: str, timeout_ms: int) -> dict[str, Any]:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1440, "height": 2200})
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
            page.wait_for_timeout(1200)
            wait_for_platform(page, platform, timeout_ms)
            page.mouse.wheel(0, 1800)
            page.wait_for_timeout(1000)
            return extract_social_payload(page, url, platform, timeout_ms=min(timeout_ms, 5000))
        finally:
            browser.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--timeout-ms", type=int, default=25000)
    parser.add_argument("--output-json")
    args = parser.parse_args()

    result = capture(args.url, args.platform, args.timeout_ms)
    payload = json.dumps(result, ensure_ascii=False)
    if args.output_json:
        with open(args.output_json, "w", encoding="utf-8") as f:
            f.write(payload)
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())