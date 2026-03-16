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
    },
    "douyin": {
        "ready_selectors": [
            'meta[property="og:title"]',
            'meta[property="og:description"]',
            '[data-e2e="video-desc"]',
            '[class*="title"]',
            '[class*="desc"]',
        ],
        "title_selectors": [
            'meta[property="og:title"]',
            'h1',
            '[data-e2e="video-desc"]',
            '[class*="title"]',
        ],
        "author_selectors": [
            'meta[name="author"]',
            '[data-e2e="user-title"]',
            '[class*="author"]',
            '[class*="account"]',
        ],
        "text_selectors": [
            '[data-e2e="video-desc"]',
            '[class*="desc"]',
            '[class*="content"]',
            'article',
            'main',
        ],
        "metric_selectors": [
            '[data-e2e="like-count"]',
            '[data-e2e="comment-count"]',
            '[data-e2e="share-count"]',
            '[class*="count"]',
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


def normalize_ws(text: str) -> str:
    text = re.sub(r"\r\n?", "\n", text or "")
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


def collect_metric_text(page, selectors: list[str]) -> list[str]:
    metrics: list[str] = []
    for selector in selectors:
        try:
            values = page.locator(selector).evaluate_all(
                "els => els.map(e => (e.innerText || e.textContent || '').trim()).filter(Boolean).slice(0, 8)"
            )
        except Exception:
            values = []
        for value in values:
            if value and value not in metrics:
                metrics.append(normalize_ws(value))
    return metrics[:8]


def collect_media_refs(page, css_selector: str, script: str, limit: int) -> list[str]:
    items: list[str] = []
    try:
        for src in page.locator(css_selector).evaluate_all(script):
            if src and src not in items:
                items.append(src)
    except Exception:
        return []
    return items[:limit]


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
    visible_text = first_non_empty(
        pick_text_by_selectors(page, rules.get("text_selectors", []), timeout_ms=timeout_ms),
        normalize_ws(page.locator("body").inner_text(timeout=timeout_ms)),
    )
    visible_preview = truncate(visible_text, 8000)
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
        if src not in video_refs:
            video_refs.append(src)

    metrics = collect_metric_text(page, rules.get("metric_selectors", []))

    summary_parts = []
    if description:
        summary_parts.append(description)
    elif visible_preview:
        summary_parts.append(truncate(visible_preview, 180))
    else:
        summary_parts.append("Visible social page content captured via Playwright.")
    if metrics:
        summary_parts.append("Metrics: " + ", ".join(metrics[:4]))
    summary_parts.append(f"Captured with Playwright from {platform}.")

    metadata = {
        "capture_level": "standard" if visible_preview else "light",
        "transcript_status": "missing",
        "media_downloaded": False,
        "analysis_ready": True,
        "extractor": "playwright",
        "final_url": page.url,
        "image_count": len(image_urls),
        "video_ref_count": len(video_refs),
        "text_length": len(visible_preview),
    }
    if metrics:
        metadata["metrics_preview"] = metrics

    return {
        "title": title,
        "author": author,
        "published_at": "unknown",
        "summary": " ".join(summary_parts).strip(),
        "raw_text": visible_preview,
        "transcript": "",
        "tags": collect_tags(first_non_empty(description, visible_preview), platform),
        "images": image_urls,
        "videos": video_refs,
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
            page.wait_for_timeout(800)
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
    print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())