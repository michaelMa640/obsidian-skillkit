import argparse
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any


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


def load_json(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def has_value(value: Any) -> bool:
    return value is not None and str(value).strip() != ""


def string_value(*values: Any, default: str = "") -> str:
    for value in values:
        if has_value(value):
            return str(value).strip()
    return default


def bool_value(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    text = str(value).strip().lower()
    if text in {"true", "1", "yes"}:
        return True
    if text in {"false", "0", "no"}:
        return False
    return default


def use_category_hint_folder(config: dict[str, Any]) -> bool:
    clipper_config = config.get("clipper") or {}
    return bool_value(clipper_config.get("allow_category_hint_folder_override"), False)


def yaml_scalar(value: Any) -> str:
    if value is None:
        return "''"
    return "'" + str(value).replace("'", "''") + "'"


def frontmatter_text(value: Any) -> str:
    return normalize_inline_spaces(value)


def markdown_title(title: str) -> str:
    if not has_value(title):
        return "未命名剪藏"
    return "\\" + title if title.startswith("#") else title


def safe_file_name(value: str) -> str:
    invalid = set('<>:"/\\|?*')
    sanitized = "".join("_" if ch in invalid else ch for ch in value)
    return sanitized.strip() or "untitled.md"


def normalize_inline_spaces(value: str) -> str:
    return re.sub(r"\s+", " ", string_value(value)).strip()


def metric_value(*values: Any, default: str = "") -> str:
    for value in values:
        text = normalize_inline_spaces(value)
        if not has_value(text):
            continue
        text = re.sub(r"^(点赞|获赞|赞|评论|收藏|分享)[\s:：]*", "", text)
        if not has_value(text):
            continue
        if re.search(r"\d", text):
            return text
    return default


def clean_note_title(raw_title: str) -> str:
    text = normalize_inline_spaces(raw_title)
    if not has_value(text):
        return "未命名剪藏"

    text = re.sub(r"https?://\S+", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"@\S+", " ", text)
    text = re.sub(r"#\S+", " ", text)

    removable_phrases = (
        "视频很长，建议大家收藏",
        "视频很长,建议大家收藏",
        "建议大家收藏",
        "建议收藏",
        "记得收藏",
        "先收藏",
        "值得收藏",
    )
    for phrase in removable_phrases:
        text = text.replace(phrase, " ")

    text = normalize_inline_spaces(text)
    text = re.sub(r"^[\s,.;:!?，。！？、#@\-_/]+", "", text)
    text = re.sub(r"[\s,.;:!?，。！？、#@\-_/]+$", "", text)
    text = normalize_inline_spaces(text)
    return text or "未命名剪藏"


def nested_value(data: Any, *keys: str) -> Any:
    current = data
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def looks_like_login_prompt(text: str) -> bool:
    normalized = string_value(text)
    return any(pattern in normalized for pattern in LOGIN_PROMPT_PATTERNS)


def is_social_short_video(detection: dict[str, Any]) -> bool:
    return detection.get("route") == "social" and detection.get("content_type") == "short_video"


def should_embed_local_video(detection: dict[str, Any], capture: dict[str, Any]) -> bool:
    video_path = string_value(capture.get("video_path"), nested_value(capture, "metadata", "video_path"))
    return has_value(video_path) and detection.get("route") == "social"


def should_embed_local_audio(detection: dict[str, Any], capture: dict[str, Any]) -> bool:
    audio_path = string_value(capture.get("audio_path"), nested_value(capture, "metadata", "audio_path"))
    return has_value(audio_path) and detection.get("route") == "podcast"


def collect_top_comments(capture: dict[str, Any]) -> list[str]:
    top_comments = [string_value(item) for item in capture.get("top_comments") or [] if has_value(item)]
    if not top_comments:
        for item in capture.get("comments") or []:
            if not isinstance(item, dict):
                continue
            display = string_value(item.get("display_text"))
            if not has_value(display):
                author = string_value(item.get("author"))
                text = string_value(item.get("text"))
                if has_value(author) and has_value(text):
                    display = f"{author}: {text}"
                else:
                    display = string_value(text, author)
            if has_value(display):
                top_comments.append(display)
    return [item for item in top_comments if not looks_like_login_prompt(item)]


def build_summary(capture: dict[str, Any], detection: dict[str, Any], top_comments: list[str]) -> str:
    parts: list[str] = []
    description = string_value(capture.get("description"), capture.get("title"))
    if has_value(description):
        parts.append(description)
    else:
        fallback_summary = string_value(capture.get("summary"))
        if has_value(fallback_summary):
            parts.append(fallback_summary)

    metrics_like = metric_value(capture.get("metrics_like"), nested_value(capture, "metadata", "like_count"))
    metrics_comment = metric_value(capture.get("metrics_comment"), nested_value(capture, "metadata", "comment_count"))
    metrics_collect = metric_value(capture.get("metrics_collect"), nested_value(capture, "metadata", "collect_count"))
    metrics_share = metric_value(capture.get("metrics_share"), nested_value(capture, "metadata", "share_count"))

    metric_parts = []
    if has_value(metrics_like):
        metric_parts.append(f"点赞 {metrics_like}")
    if has_value(metrics_comment):
        metric_parts.append(f"评论 {metrics_comment}")
    if has_value(metrics_collect):
        metric_parts.append(f"收藏 {metrics_collect}")
    if has_value(metrics_share):
        metric_parts.append(f"分享 {metrics_share}")
    if metric_parts:
        parts.append("互动数据: " + "，".join(metric_parts) + "。")

    comments_login_required = bool_value(capture.get("comments_login_required"), bool_value(nested_value(capture, "metadata", "comments_login_required")))
    if top_comments:
        parts.append(f"可见评论抓取 {len(top_comments)} 条。")
    elif comments_login_required:
        parts.append("评论区可能需要登录态。")

    extractor = string_value(nested_value(capture, "metadata", "extractor"))
    if has_value(extractor):
        parts.append(f"采集方式: {extractor} / {detection.get('platform', '')}。")

    return " ".join(part for part in parts if has_value(part)) or "(none)"


def attachment_lines(capture: dict[str, Any]) -> list[str]:
    mapping = (
        ("audio_path", "本地音频"),
        ("video_path", "本地视频"),
        ("cover_path", "封面图"),
        ("transcript_path", "转录文本"),
        ("sidecar_path", "Capture JSON"),
        ("comments_path", "Comments JSON"),
        ("metadata_path", "Metadata JSON"),
    )
    lines = []
    for key, label in mapping:
        value = string_value(capture.get(key), nested_value(capture, "metadata", key))
        if has_value(value):
            lines.append(f"- {label}: {value}")
    return lines or ["- none"]


def podcast_info_lines(capture: dict[str, Any]) -> list[str]:
    metadata = capture.get("metadata") or {}
    podcast_title = string_value(capture.get("podcast_title"), metadata.get("podcast_title"), default="unknown")
    podcast_author = string_value(capture.get("podcast_author"), metadata.get("podcast_author"), capture.get("author"), default="unknown")
    episode_id = string_value(capture.get("episode_id"), capture.get("source_item_id"), metadata.get("source_item_id"), default="n/a")
    duration_seconds = string_value(capture.get("duration_seconds"), metadata.get("duration_seconds"), default="0")
    return [
        f"- 播客名称: {podcast_title}",
        f"- 播客作者: {podcast_author}",
        f"- 单集 ID: {episode_id}",
        f"- 时长（秒）: {duration_seconds}",
    ]


def podcast_resource_lines(capture: dict[str, Any]) -> list[str]:
    metadata = capture.get("metadata") or {}
    rss_url = string_value(capture.get("rss_url"), metadata.get("rss_url"), default="n/a")
    transcript_url = string_value(capture.get("transcript_url"), metadata.get("transcript_url"), default="n/a")
    enclosure_url = string_value(capture.get("enclosure_url"), metadata.get("enclosure_url"), default="n/a")
    source_strategy = string_value(capture.get("source_strategy"), metadata.get("source_strategy"), default="page_only")
    rss_match_strategy = string_value(metadata.get("rss_match_strategy"), default="n/a")
    audio_download_status = string_value(capture.get("audio_download_status"), default="skipped")
    transcript_source = string_value(capture.get("transcript_source"), metadata.get("transcript_source"), default="missing")
    return [
        f"- Source Strategy: {source_strategy}",
        f"- RSS URL: {rss_url}",
        f"- Transcript URL: {transcript_url}",
        f"- Enclosure URL: {enclosure_url}",
        f"- RSS Match Strategy: {rss_match_strategy}",
        f"- Audio Download Status: {audio_download_status}",
        f"- Transcript Source: {transcript_source}",
    ]


def status_lines(capture: dict[str, Any]) -> list[str]:
    metadata = capture.get("metadata") or {}
    download_status = string_value(capture.get("download_status"), metadata.get("download_status"), default="unknown")
    download_method = string_value(capture.get("download_method"), metadata.get("download_method"), default="unknown")
    audio_download_status = string_value(capture.get("audio_download_status"), default="skipped")
    media_downloaded = bool_value(capture.get("media_downloaded"), bool_value(metadata.get("media_downloaded")))
    transcript_status = string_value(metadata.get("transcript_status"), default="missing")
    asr_status = string_value(capture.get("asr_status"), metadata.get("asr_status"), default="not_attempted")
    asr_provider = string_value(capture.get("asr_provider"), metadata.get("asr_provider"))
    asr_model = string_value(capture.get("asr_model"), metadata.get("asr_model"))
    asr_error = string_value(capture.get("asr_error"), metadata.get("asr_error"))
    analyzer_status = string_value(capture.get("analyzer_status"), default="pending")
    bitable_sync_status = string_value(capture.get("bitable_sync_status"), default="pending")
    analysis_ready = bool_value(capture.get("analysis_ready"), bool_value(metadata.get("analysis_ready"), True))
    access_blocked = bool_value(capture.get("access_blocked"), bool_value(metadata.get("access_blocked")))
    access_block_type = string_value(capture.get("access_block_type"), metadata.get("access_block_type"))
    access_block_error_code = string_value(capture.get("access_block_error_code"), metadata.get("access_block_error_code"))
    auth_guidance_zh = string_value(capture.get("auth_guidance_zh"), metadata.get("auth_guidance_zh"))
    lines = [
        f"- 下载状态: {download_status}",
        f"- 下载方式: {download_method}",
        f"- 音频下载状态: {audio_download_status}",
        f"- 视频已落盘: {'是' if media_downloaded else '否'}",
        f"- 转录状态: {transcript_status}",
        f"- ASR 状态: {asr_status}",
        f"- Analyzer 状态: {analyzer_status}",
        f"- 多维表格同步: {bitable_sync_status}",
        f"- 分析就绪: {'是' if analysis_ready else '否'}",
    ]
    if has_value(asr_provider):
        lines.append(f"- ASR Provider: {asr_provider}")
    if has_value(asr_model):
        lines.append(f"- ASR Model: {asr_model}")
    if has_value(asr_error):
        lines.append(f"- ASR 错误: {asr_error}")
    if access_blocked:
        block_label = "IP 风险拦截" if access_block_type == "ip_risk" else "站点访问受限"
        lines.insert(0, f"- 访问状态: {block_label}")
        if has_value(access_block_error_code):
            lines.insert(1, f"- 拦截错误码: {access_block_error_code}")
        if has_value(auth_guidance_zh):
            lines.append(f"- 处理建议: {auth_guidance_zh}")
    return lines


def engagement_lines(capture: dict[str, Any], top_comments: list[str]) -> list[str]:
    metadata = capture.get("metadata") or {}
    metrics_like = metric_value(capture.get("metrics_like"), metadata.get("like_count"), default="未获取")
    metrics_comment = metric_value(capture.get("metrics_comment"), metadata.get("comment_count"), default="未获取")
    metrics_collect = metric_value(capture.get("metrics_collect"), metadata.get("collect_count"), default="未获取")
    metrics_share = metric_value(capture.get("metrics_share"), metadata.get("share_count"), default="未获取")
    comments_count = string_value(capture.get("comments_count"), metadata.get("comment_count_visible"), default=str(len(top_comments)))
    comments_capture_status = string_value(capture.get("comments_capture_status"), metadata.get("comments_capture_status"), default="none")
    return [
        f"- 点赞数: {metrics_like}",
        f"- 平台评论总数: {metrics_comment}",
        f"- 已抓取评论条数: {comments_count}",
        f"- 分享数: {metrics_share}",
        f"- 收藏数: {metrics_collect}",
        f"- 评论抓取状态: {comments_capture_status}",
    ]


def images_text(capture: dict[str, Any]) -> list[str]:
    images = [string_value(item) for item in capture.get("images") or [] if has_value(item)]
    return [f"- {item}" for item in images] if images else ["- none"]


def videos_text(capture: dict[str, Any]) -> list[str]:
    videos = [string_value(item) for item in capture.get("videos") or [] if has_value(item)]
    return [f"- {item}" for item in videos] if videos else ["- none"]


def join_vault_path(vault_path: str, folder: str) -> Path:
    parts = [part for part in re.split(r"[\\/]+", folder) if part]
    return Path(vault_path).joinpath(*parts)


def render_note(config: dict[str, Any], detection: dict[str, Any], capture: dict[str, Any], source_url: str, category_hint: str | None) -> dict[str, Any]:
    clipper_config = config.get("clipper") or {}
    captured_at = datetime.now().strftime("%Y-%m-%d")
    folder = string_value(
        category_hint if use_category_hint_folder(config) else "",
        clipper_config.get("default_folder"),
        default="Clippings",
    )
    title = string_value(capture.get("title"), default="未命名剪藏")
    note_title = clean_note_title(title)
    file_prefix = f"{captured_at} " if bool_value(clipper_config.get("prefix_date"), True) else ""
    file_name = safe_file_name(f"{file_prefix}{note_title}.md")
    display_title = markdown_title(note_title)
    tags = [string_value(tag) for tag in capture.get("tags") or [] if has_value(tag)] or ["clipped"]

    normalized_url = string_value(capture.get("normalized_url"), nested_value(capture, "metadata", "normalized_url"))
    capture_id = string_value(capture.get("capture_id"), nested_value(capture, "metadata", "capture_id"))
    capture_key = string_value(capture.get("capture_key"), nested_value(capture, "metadata", "capture_key"))
    source_item_id = string_value(capture.get("source_item_id"), nested_value(capture, "metadata", "source_item_id"))
    capture_level = string_value(nested_value(capture, "metadata", "capture_level"), default="light")
    transcript_status = string_value(nested_value(capture, "metadata", "transcript_status"), default="missing")
    transcript_source = string_value(capture.get("transcript_source"), nested_value(capture, "metadata", "transcript_source"), default="missing")
    asr_status = string_value(capture.get("asr_status"), nested_value(capture, "metadata", "asr_status"), default="not_attempted")
    asr_provider = string_value(capture.get("asr_provider"), nested_value(capture, "metadata", "asr_provider"))
    media_downloaded = bool_value(capture.get("media_downloaded"), bool_value(nested_value(capture, "metadata", "media_downloaded")))
    analysis_ready = bool_value(capture.get("analysis_ready"), bool_value(nested_value(capture, "metadata", "analysis_ready"), True))
    download_status = string_value(capture.get("download_status"), nested_value(capture, "metadata", "download_status"))
    download_method = string_value(capture.get("download_method"), nested_value(capture, "metadata", "download_method"))
    video_path = string_value(capture.get("video_path"), nested_value(capture, "metadata", "video_path"))
    audio_path = string_value(capture.get("audio_path"), nested_value(capture, "metadata", "audio_path"))
    sidecar_path = string_value(capture.get("sidecar_path"), nested_value(capture, "metadata", "sidecar_path"))
    author = string_value(capture.get("author"), default="unknown")
    published_at = string_value(capture.get("published_at"), default="unknown")
    raw_text = string_value(capture.get("raw_text"), default="(none)")
    transcript = string_value(capture.get("transcript"), default="(none)")
    podcast_title = string_value(capture.get("podcast_title"), nested_value(capture, "metadata", "podcast_title"))
    podcast_author = string_value(capture.get("podcast_author"), nested_value(capture, "metadata", "podcast_author"), author)
    episode_url = string_value(capture.get("episode_url"), default=source_url)
    episode_id = string_value(capture.get("episode_id"), source_item_id)
    rss_url = string_value(capture.get("rss_url"), nested_value(capture, "metadata", "rss_url"))
    transcript_url = string_value(capture.get("transcript_url"), nested_value(capture, "metadata", "transcript_url"))
    enclosure_url = string_value(capture.get("enclosure_url"), nested_value(capture, "metadata", "enclosure_url"))
    source_strategy = string_value(capture.get("source_strategy"), nested_value(capture, "metadata", "source_strategy"))
    duration_seconds = string_value(capture.get("duration_seconds"), nested_value(capture, "metadata", "duration_seconds"), default="0")
    audio_path = string_value(capture.get("audio_path"))

    top_comments = collect_top_comments(capture)
    lines = [
        "---",
        f"title: {yaml_scalar(frontmatter_text(title))}",
        f"note_title: {yaml_scalar(frontmatter_text(note_title))}",
        f"source_url: {yaml_scalar(frontmatter_text(source_url))}",
        f"normalized_url: {yaml_scalar(frontmatter_text(normalized_url))}",
        f"platform: {yaml_scalar(frontmatter_text(detection.get('platform', '')))}",
        f"content_type: {yaml_scalar(frontmatter_text(detection.get('content_type', '')))}",
        f"author: {yaml_scalar(frontmatter_text(author))}",
        f"published_at: {yaml_scalar(frontmatter_text(published_at))}",
        f"captured_at: {yaml_scalar(frontmatter_text(captured_at))}",
        f"route: {yaml_scalar(frontmatter_text(detection.get('route', '')))}",
        f"capture_id: {yaml_scalar(frontmatter_text(capture_id))}",
        f"capture_key: {yaml_scalar(frontmatter_text(capture_key))}",
        f"source_item_id: {yaml_scalar(frontmatter_text(source_item_id))}",
        f"episode_url: {yaml_scalar(frontmatter_text(episode_url))}",
        f"episode_id: {yaml_scalar(frontmatter_text(episode_id))}",
        f"podcast_title: {yaml_scalar(frontmatter_text(podcast_title))}",
        f"podcast_author: {yaml_scalar(frontmatter_text(podcast_author))}",
        f"rss_url: {yaml_scalar(frontmatter_text(rss_url))}",
        f"transcript_url: {yaml_scalar(frontmatter_text(transcript_url))}",
        f"enclosure_url: {yaml_scalar(frontmatter_text(enclosure_url))}",
        f"source_strategy: {yaml_scalar(frontmatter_text(source_strategy))}",
        f"duration_seconds: {yaml_scalar(frontmatter_text(duration_seconds))}",
        f"audio_path: {yaml_scalar(frontmatter_text(audio_path))}",
        f"capture_level: {yaml_scalar(frontmatter_text(capture_level))}",
        f"transcript_status: {yaml_scalar(frontmatter_text(transcript_status))}",
        f"transcript_source: {yaml_scalar(frontmatter_text(transcript_source))}",
        f"asr_status: {yaml_scalar(frontmatter_text(asr_status))}",
        f"asr_provider: {yaml_scalar(frontmatter_text(asr_provider))}",
        f"media_downloaded: {str(media_downloaded).lower()}",
        f"analysis_ready: {str(analysis_ready).lower()}",
        f"download_status: {yaml_scalar(frontmatter_text(download_status))}",
        f"download_method: {yaml_scalar(frontmatter_text(download_method))}",
        f"video_path: {yaml_scalar(frontmatter_text(video_path))}",
        f"sidecar_path: {yaml_scalar(frontmatter_text(sidecar_path))}",
        "tags:",
    ]
    lines.extend([f"  - {yaml_scalar(tag)}" for tag in tags])
    lines.extend([
        f"status: {string_value(capture.get('status'), default='clipped')}",
        "---",
        "",
        f"# {display_title}",
        "",
        "## 来源信息",
        f"- 链接: {source_url}",
        f"- 规范化链接: {normalized_url if has_value(normalized_url) else 'n/a'}",
        f"- 平台: {detection.get('platform', '')}",
        f"- 内容类型: {detection.get('content_type', '')}",
        f"- 路由: {detection.get('route', '')}",
        f"- Capture ID: {capture_id if has_value(capture_id) else 'n/a'}",
        f"- Source Item ID: {source_item_id if has_value(source_item_id) else 'n/a'}",
        "",
    ])

    if detection.get("route") == "podcast":
        lines.extend([
            "## 播客信息",
            *podcast_info_lines(capture),
            "",
            "## 资源线索",
            *podcast_resource_lines(capture),
            "",
        ])

    lines.extend([
        "## 内容摘要",
        build_summary(capture, detection, top_comments),
        "",
        "## 原始文案",
        raw_text,
        "",
    ])

    if should_embed_local_video(detection, capture):
        lines.extend(["## 视频内容", f"![[{video_path}]]" if has_value(video_path) else "- 当前未落到本地 mp4 文件。"])
        if has_value(video_path):
            lines.extend([
                "",
                f"- 本地视频: {video_path}",
                f"- 下载状态: {download_status if has_value(download_status) else 'unknown'}",
                f"- 下载方式: {download_method if has_value(download_method) else 'unknown'}",
            ])
        lines.append("")

    if detection.get("route") == "podcast":
        lines.extend(["## 音频附件"])
        if should_embed_local_audio(detection, capture):
            lines.extend([
                f"![[{audio_path}]]",
                "",
                f"- 本地音频: {audio_path}",
            ])
        else:
            lines.append("- 当前未落到本地音频文件。")
        lines.append("")

    lines.extend([
        "## 转录文本",
        f"- 来源: {transcript_source}",
        f"- ASR 状态: {asr_status}",
        *([f"- ASR Provider: {asr_provider}"] if has_value(asr_provider) else []),
        "",
        transcript,
        "",
        "## 互动数据",
        *engagement_lines(capture, top_comments),
        "",
        "## 可见评论",
    ])
    lines.extend([f"- {item}" for item in top_comments] if top_comments else ["- 未抓取到可展示评论。"])
    lines.extend(["", "## 附件索引", *attachment_lines(capture)])

    if not should_embed_local_video(detection, capture):
        lines.extend(["", "## 图片链接", *images_text(capture), "", "## 视频链接", *videos_text(capture)])

    lines.extend(["", "## 采集状态", *status_lines(capture)])
    return {
        "title": title,
        "note_title": note_title,
        "folder": folder,
        "file_name": file_name,
        "tags": tags,
        "note_body": "\n".join(lines),
    }


def write_note(vault_path: str, note: dict[str, Any]) -> str:
    target_folder = join_vault_path(vault_path, note["folder"])
    target_folder.mkdir(parents=True, exist_ok=True)
    target_path = target_folder / note["file_name"]
    target_path.write_text(note["note_body"], encoding="utf-8")
    return str(target_path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-json", required=True)
    parser.add_argument("--detection-json", required=True)
    parser.add_argument("--capture-json", required=True)
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--vault-path")
    parser.add_argument("--vault-path-file")
    parser.add_argument("--category-hint")
    parser.add_argument("--write-note", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--output-json")
    args = parser.parse_args()

    vault_path = args.vault_path
    if not has_value(vault_path) and has_value(args.vault_path_file):
        vault_path = load_text(args.vault_path_file).strip()

    note = render_note(
        load_json(args.config_json),
        load_json(args.detection_json),
        load_json(args.capture_json),
        args.source_url,
        args.category_hint,
    )
    if args.write_note and not args.dry_run:
        if not has_value(vault_path):
            raise SystemExit("vault path required when --write-note is set")
        note["note_path"] = write_note(vault_path, note)

    payload = json.dumps(note, ensure_ascii=False)
    if args.output_json:
        Path(args.output_json).write_text(payload, encoding="utf-8")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
