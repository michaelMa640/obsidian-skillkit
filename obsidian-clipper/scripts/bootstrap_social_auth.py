import argparse
import json
from pathlib import Path
from typing import Any

from playwright.sync_api import sync_playwright


DEFAULT_LOGIN_URLS = {
    "douyin": "https://www.douyin.com/",
    "xiaohongshu": "https://www.xiaohongshu.com/",
}


def ensure_parent(path: str) -> None:
    Path(path).expanduser().resolve().parent.mkdir(parents=True, exist_ok=True)


def resolved_output_path(path: str | None, default_path: Path) -> Path:
    if path and str(path).strip():
        return Path(path).expanduser().resolve()
    return default_path.resolve()


def write_netscape_cookies(cookies: list[dict[str, Any]], output_path: Path) -> int:
    lines = ["# Netscape HTTP Cookie File"]
    count = 0
    for cookie in cookies:
        if not isinstance(cookie, dict):
            continue
        domain = str(cookie.get("domain") or "").strip()
        name = str(cookie.get("name") or "").strip()
        value = str(cookie.get("value") or "")
        if not domain or not name:
            continue
        include_subdomains = "TRUE" if domain.startswith(".") else "FALSE"
        path_value = str(cookie.get("path") or "/")
        is_secure = "TRUE" if cookie.get("secure") else "FALSE"
        expires = 0
        try:
            expires_value = float(cookie.get("expires") or 0)
            if expires_value > 0:
                expires = int(expires_value)
        except (TypeError, ValueError):
            expires = 0
        domain_value = f"#HttpOnly_{domain}" if cookie.get("httpOnly") else domain
        lines.append(f"{domain_value}\t{include_subdomains}\t{path_value}\t{is_secure}\t{expires}\t{name}\t{value}")
        count += 1
    output_path.write_text("\n".join(lines), encoding="utf-8")
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", default="douyin")
    parser.add_argument("--login-url", default="")
    parser.add_argument("--storage-state-output")
    parser.add_argument("--cookies-output")
    parser.add_argument("--output-json")
    args = parser.parse_args()

    platform = (args.platform or "douyin").strip().lower()
    login_url = (args.login_url or "").strip() or DEFAULT_LOGIN_URLS.get(platform, "https://www.douyin.com/")
    default_auth_dir = Path(__file__).resolve().parents[1] / ".local-auth"
    storage_state_output = resolved_output_path(args.storage_state_output, default_auth_dir / f"{platform}-storage-state.json")
    cookies_output = resolved_output_path(args.cookies_output, default_auth_dir / f"{platform}-cookies.txt")

    ensure_parent(str(storage_state_output))
    ensure_parent(str(cookies_output))

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=False)
        context = browser.new_context(viewport={"width": 1440, "height": 1400})
        page = context.new_page()
        page.goto(login_url, wait_until="domcontentloaded", timeout=60000)
        print(f"Opened {platform} login page: {login_url}")
        print("Complete the login in the browser window, then return here and press Enter to save auth files.")
        print("Type q and press Enter to cancel without saving.")
        response = input().strip().lower()
        if response in {"q", "quit", "exit"}:
            context.close()
            browser.close()
            print(json.dumps({"success": False, "cancelled": True, "platform": platform}, ensure_ascii=False))
            return 1

        context.storage_state(path=str(storage_state_output))
        cookies = context.cookies()
        cookie_count = write_netscape_cookies(cookies, cookies_output)
        origin_count = 0
        try:
            storage_state = json.loads(storage_state_output.read_text(encoding="utf-8"))
            origin_count = len(storage_state.get("origins") or []) if isinstance(storage_state, dict) else 0
        except Exception:
            origin_count = 0
        context.close()
        browser.close()

    payload = {
        "success": True,
        "platform": platform,
        "login_url": login_url,
        "storage_state_path": str(storage_state_output),
        "cookies_file": str(cookies_output),
        "cookie_count": cookie_count,
        "origin_count": origin_count,
    }
    encoded = json.dumps(payload, ensure_ascii=False)
    if args.output_json:
        Path(args.output_json).expanduser().resolve().write_text(encoded, encoding="utf-8")
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())