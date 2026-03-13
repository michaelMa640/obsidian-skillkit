import argparse
import json
import re
from typing import Any

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


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


def collect_tags(text: str, platform: str) -> list[str]:
    tags = ["clipped", "social", platform]
    for match in re.findall(r"#([^#\s]{1,30})", text or "")[:10]:
        cleaned = match.strip()
        if cleaned and cleaned not in tags:
            tags.append(cleaned)
    return tags


def capture(url: str, platform: str, timeout_ms: int) -> dict[str, Any]:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1440, "height": 2200})
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
            page.wait_for_timeout(1500)
            try:
                page.wait_for_load_state("networkidle", timeout=5000)
            except PlaywrightTimeoutError:
                pass

            title = page.title().strip()
            description = first_non_empty(
                page.locator('meta[property="og:description"]').first.get_attribute("content"),
                page.locator('meta[name="description"]').first.get_attribute("content"),
            )
            og_title = first_non_empty(page.locator('meta[property="og:title"]').first.get_attribute("content"))
            og_image = first_non_empty(page.locator('meta[property="og:image"]').first.get_attribute("content"))
            author = first_non_empty(
                page.locator('meta[name="author"]').first.get_attribute("content"),
                page.locator('meta[property="article:author"]').first.get_attribute("content"),
            )
            visible_text = normalize_ws(page.locator("body").inner_text(timeout=5000))
            visible_preview = visible_text[:8000]

            image_urls: list[str] = []
            for src in page.locator("img").evaluate_all("els => els.map(e => e.currentSrc || e.src || '').filter(Boolean).slice(0, 12)"):
                if src and src not in image_urls:
                    image_urls.append(src)

            video_refs: list[str] = [url]
            for src in page.locator("video").evaluate_all("els => els.map(e => e.currentSrc || e.src || e.poster || '').filter(Boolean).slice(0, 6)"):
                if src and src not in video_refs:
                    video_refs.append(src)

            text_for_tags = first_non_empty(description, visible_preview)
            summary_parts = []
            if description:
                summary_parts.append(description)
            elif visible_preview:
                summary_parts.append(visible_preview[:180] + ("..." if len(visible_preview) > 180 else ""))
            else:
                summary_parts.append("Visible social page content captured via Playwright.")
            summary_parts.append(f"Captured with Playwright from {platform}.")

            result = {
                "title": first_non_empty(og_title, title, f"Social Clip - {platform}"),
                "author": first_non_empty(author, "unknown"),
                "published_at": "unknown",
                "summary": " ".join(summary_parts).strip(),
                "raw_text": visible_preview,
                "transcript": "",
                "tags": collect_tags(text_for_tags, platform),
                "images": image_urls,
                "videos": video_refs,
                "metadata": {
                    "capture_level": "standard" if visible_preview else "light",
                    "transcript_status": "missing",
                    "media_downloaded": False,
                    "analysis_ready": True,
                    "extractor": "playwright",
                    "final_url": page.url,
                    "image_count": len(image_urls),
                    "video_ref_count": len(video_refs),
                    "text_length": len(visible_preview),
                },
            }
            return result
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