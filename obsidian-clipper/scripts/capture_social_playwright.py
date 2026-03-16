import argparse
import json
import re
from typing import Any

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
        "metric_selectors": [
            '[class*="like"]',
            '[class*="collect"]',
            '[class*="comment"]',
        ],
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


def first_non_empty(*values: Any) -> str:
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return ""


MAYBE_MOJIBAKE_MARKERS = [
    "涓",
    "鍙",
    "鎶",
    "钂",
    "闂",
    "鍣",
    "鍐",
    "鐗",
    "銆",
]


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
            if src and src not in items:
                items.append(src)
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


def collect_visible_comments(page, selectors: list[str], limit: int = 8) -> list[str]:
    comments: list[str] = []
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
            if len(cleaned) < 2:
                continue
            if cleaned in comments:
                continue
            comments.append(cleaned)
            if len(comments) >= limit:
                return comments
    return comments


def should_keep_video_ref(src: str) -> bool:
    src = (src or "").strip()
    if not src:
        return False
    return src.startswith("http") or src.startswith("blob:")


def build_social_raw_text(platform: str, description: str, visible_text: str, comments: list[str]) -> str:
    parts: list[str] = []
    if description:
        parts.append(description)
    if visible_text and visible_text != description:
        parts.append(visible_text)
    if comments:
        parts.append("Top Comments:\n" + "\n".join(f"- {comment}" for comment in comments))
    if not parts and platform == "douyin":
        return ""
    return "\n\n".join(parts).strip()


def extract_social_payload(page, url: str, platform: str, timeout_ms: int) -> dict[str, Any]:
    rules = PLATFORM_RULES.get(platform, {})
    title = first_non_empty(
        safe_meta_content(page, 'meta[property="og:title"]'),
        pick_text_by_selectors(page, rules.get("title_selectors", [])),
        page.title().strip(),
        f"Social Clip - {platform}",
    )
    description = first_non_empty(
        safe_meta_content(page, 'meta[property="og:description"]'),
        safe_meta_content(page, 'meta[name="description"]'),
    )
    author = first_non_empty(
        safe_meta_content(page, 'meta[name="author"]'),
        safe_meta_content(page, 'meta[property="article:author"]'),
        pick_text_by_selectors(page, rules.get("author_selectors", [])),
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

    comments = collect_visible_comments(page, rules.get("comment_selectors", []), limit=8)
    raw_text = build_social_raw_text(platform, normalize_ws(description), normalize_ws(visible_text), comments)
    visible_preview = truncate(raw_text, 8000)

    image_urls: list[str]
    if platform == "douyin":
        image_urls = []
    else:
        og_image = safe_meta_content(page, 'meta[property="og:image"]')
        image_urls = collect_media_refs(
            page,
            "img",
            "els => els.map(e => e.currentSrc || e.src || '').filter(Boolean).slice(0, 12)",
            12,
        )
        if og_image and og_image not in image_urls:
            image_urls.insert(0, og_image)

    video_refs = [url]
    for src in collect_media_refs(
        page,
        "video",
        "els => els.map(e => e.currentSrc || e.src || e.poster || '').filter(Boolean).slice(0, 6)",
        6,
    ):
        if should_keep_video_ref(src) and src not in video_refs:
            video_refs.append(src)

    metrics = collect_metric_values(page, rules.get("metric_map", {}))

    summary_parts = []
    if description:
        summary_parts.append(normalize_ws(description))
    elif visible_preview:
        summary_parts.append(truncate(visible_preview, 180))
    else:
        summary_parts.append("Visible social page content captured via Playwright.")
    if metrics:
        metric_text = ", ".join(f"{key}: {value}" for key, value in metrics.items() if value)
        if metric_text:
            summary_parts.append("Metrics: " + metric_text)
    if comments:
        summary_parts.append(f"Visible comments captured: {len(comments)}.")
    summary_parts.append(f"Captured with Playwright from {platform}.")

    metadata: dict[str, Any] = {
        "capture_level": "standard" if visible_preview else "light",
        "transcript_status": "missing",
        "media_downloaded": False,
        "analysis_ready": True,
        "extractor": "playwright",
        "final_url": page.url,
        "image_count": len(image_urls),
        "video_ref_count": len(video_refs),
        "text_length": len(visible_preview),
        "comment_count_visible": len(comments),
    }
    metadata.update(metrics)
    if comments:
        metadata["comments_preview"] = comments

    return {
        "title": normalize_ws(title),
        "author": normalize_ws(author),
        "published_at": "unknown",
        "summary": " ".join(summary_parts).strip(),
        "raw_text": visible_preview,
        "transcript": "",
        "tags": collect_tags(first_non_empty(description, visible_text), platform),
        "images": image_urls,
        "videos": video_refs,
        "metadata": metadata,
        "comments": comments,
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
