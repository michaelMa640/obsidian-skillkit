import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


START_MARKER = "<!-- knowledge-summary:start -->"
END_MARKER = "<!-- knowledge-summary:end -->"


def configure_console_output() -> None:
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream is None:
            continue
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            reconfigure(encoding="utf-8", errors="backslashreplace")


def has_value(value: Any) -> bool:
    return value is not None and str(value).strip() != ""


def string_value(*values: Any, default: str = "") -> str:
    for value in values:
        if has_value(value):
            return str(value).strip()
    return default


def load_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def load_json(path: str) -> dict[str, Any]:
    return json.loads(load_text(path))


def yaml_scalar(value: Any) -> str:
    if value is None:
        return "''"
    return "'" + str(value).replace("'", "''") + "'"


def normalize_list(values: Any) -> list[Any]:
    if values is None:
        return []
    if isinstance(values, list):
        return values
    return [values]


def format_methods(values: Any) -> list[str]:
    lines: list[str] = []
    for item in normalize_list(values):
        if isinstance(item, dict):
            name = string_value(item.get("name"), item.get("title"), default="未命名方法")
            summary = string_value(item.get("summary"), item.get("detail"), item.get("description"))
            applicability = string_value(item.get("applicability"), item.get("scenario"))
            steps = [string_value(step) for step in normalize_list(item.get("steps")) if has_value(step)]
            parts = [name]
            if has_value(summary):
                parts.append(summary)
            if steps:
                parts.append("步骤: " + " -> ".join(steps))
            if has_value(applicability):
                parts.append("适用场景: " + applicability)
            lines.append("- " + " | ".join(parts))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or ["- 暂无"]


def format_tips(values: Any) -> list[str]:
    lines: list[str] = []
    for item in normalize_list(values):
        if isinstance(item, dict):
            point = string_value(item.get("point"), item.get("name"), item.get("title"), default="未命名要点")
            detail = string_value(item.get("detail"), item.get("summary"), item.get("description"))
            lines.append("- " + point + (f": {detail}" if has_value(detail) else ""))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or ["- 暂无"]


def format_topics(values: Any) -> list[str]:
    lines: list[str] = []
    for item in normalize_list(values):
        if isinstance(item, dict):
            name = string_value(item.get("name"), item.get("title"), item.get("topic"), default="未命名主题")
            reason = string_value(item.get("reason"), item.get("summary"), item.get("detail"))
            lines.append("- " + name + (f": {reason}" if has_value(reason) else ""))
            continue
        text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or ["- 暂无"]


def format_points(values: Any) -> list[str]:
    lines: list[str] = []
    for item in normalize_list(values):
        if isinstance(item, dict):
            text = string_value(item.get("text"), item.get("point"), item.get("summary"))
        else:
            text = string_value(item)
        if has_value(text):
            lines.append(f"- {text}")
    return lines or ["- 暂无"]


def relative_path(path_value: str, vault_path: str) -> str:
    if not has_value(path_value):
        return ""
    candidate = Path(path_value)
    if candidate.is_absolute():
        if not has_value(vault_path):
            return candidate.as_posix()
        try:
            return candidate.resolve().relative_to(Path(vault_path).resolve()).as_posix()
        except Exception:
            return candidate.as_posix()
    return path_value.replace("\\", "/")


def obsidian_note_link(path_value: str, vault_path: str) -> str:
    relative = relative_path(path_value, vault_path)
    if not has_value(relative):
        return "暂无"
    target = relative[:-3] if relative.lower().endswith(".md") else relative
    return f"[[{target}]]"


def build_knowledge_section(analysis: dict[str, Any], knowledge_note_path: str, vault_path: str) -> str:
    summary = string_value(analysis.get("content_summary"), default="暂无")
    core_points = format_points(analysis.get("core_points"))
    methods = format_methods(analysis.get("methods"))
    tips = format_tips(analysis.get("tips_and_facts"))
    topics = format_topics(analysis.get("topic_candidates"))
    note_link = obsidian_note_link(knowledge_note_path, vault_path)

    lines = [
        START_MARKER,
        "## 知识速览",
        "",
        "### 内容总结",
        summary,
        "",
        "### 核心观点",
        *core_points,
        "",
        "### 提到的方法论",
        *methods,
        "",
        "### 小技巧与小知识点",
        *tips,
        "",
        "### 关联主题",
        *topics,
        "",
        "### 完整知识解读",
        f"- {note_link}",
        END_MARKER,
    ]
    return "\n".join(lines).strip() + "\n"


def upsert_frontmatter_scalar(lines: list[str], key: str, value: str) -> list[str]:
    if not lines or lines[0] != "---":
        return lines
    end_index = -1
    for index in range(1, len(lines)):
        if lines[index] == "---":
            end_index = index
            break
    if end_index < 0:
        return lines

    replacement = f"{key}: {yaml_scalar(value)}"
    for index in range(1, end_index):
        if re.match(rf"^{re.escape(key)}\s*:", lines[index]):
            lines[index] = replacement
            return lines
    lines.insert(end_index, replacement)
    return lines


def update_analyzer_status_line(lines: list[str], analyzer_status: str) -> list[str]:
    updated = False
    for index, line in enumerate(lines):
        if line.startswith("- Analyzer 状态: "):
            lines[index] = f"- Analyzer 状态: {analyzer_status}"
            updated = True
            break
    if not updated:
        for index, line in enumerate(lines):
            if line.strip() == "## 采集状态":
                lines.insert(index + 1, f"- Analyzer 状态: {analyzer_status}")
                break
    return lines


def replace_or_insert_knowledge_section(body_text: str, knowledge_section: str, clear_only: bool) -> tuple[str, bool]:
    marker_pattern = re.compile(
        rf"{re.escape(START_MARKER)}.*?{re.escape(END_MARKER)}\s*",
        flags=re.DOTALL,
    )
    changed = False
    if marker_pattern.search(body_text):
        body_text = marker_pattern.sub("" if clear_only else knowledge_section + "\n", body_text)
        changed = True
    elif not clear_only:
        insert_before = re.search(r"(?m)^## 原始文案\s*$", body_text)
        if insert_before:
            body_text = body_text[: insert_before.start()] + knowledge_section + "\n" + body_text[insert_before.start() :]
        else:
            body_text = body_text.rstrip() + "\n\n" + knowledge_section
        changed = True
    return body_text.strip() + "\n", changed


def split_frontmatter(text: str) -> tuple[list[str], str]:
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return lines, ""
    for index in range(1, len(lines)):
        if lines[index] == "---":
            return lines[: index + 1], "\n".join(lines[index + 1 :]).lstrip("\n")
    return lines, ""


def main() -> int:
    configure_console_output()
    parser = argparse.ArgumentParser()
    parser.add_argument("--note-path", required=True)
    parser.add_argument("--analysis-json", default="")
    parser.add_argument("--knowledge-note-path", default="")
    parser.add_argument("--vault-path", default="")
    parser.add_argument("--analyzer-status", default="done")
    parser.add_argument("--output-json")
    args = parser.parse_args()

    note_path = Path(args.note_path)
    note_text = note_path.read_text(encoding="utf-8")
    frontmatter_lines, body_text = split_frontmatter(note_text)
    if not body_text:
        body_text = "\n".join(frontmatter_lines)
        frontmatter_lines = []

    frontmatter_lines = upsert_frontmatter_scalar(frontmatter_lines, "analysis_goal", "knowledge")
    frontmatter_lines = upsert_frontmatter_scalar(frontmatter_lines, "analyzer_status", args.analyzer_status)
    frontmatter_lines = upsert_frontmatter_scalar(frontmatter_lines, "knowledge_note_path", relative_path(args.knowledge_note_path, args.vault_path))
    frontmatter_lines = upsert_frontmatter_scalar(frontmatter_lines, "knowledge_summary_updated_at", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

    body_lines = body_text.splitlines()
    body_lines = update_analyzer_status_line(body_lines, args.analyzer_status)
    body_text = "\n".join(body_lines).strip() + "\n"

    knowledge_section_written = False
    if has_value(args.analysis_json):
        analysis = load_json(args.analysis_json)
        knowledge_section = build_knowledge_section(analysis, args.knowledge_note_path, args.vault_path)
        body_text, knowledge_section_written = replace_or_insert_knowledge_section(body_text, knowledge_section, clear_only=False)
    else:
        body_text, _ = replace_or_insert_knowledge_section(body_text, "", clear_only=True)

    final_lines: list[str] = []
    if frontmatter_lines and frontmatter_lines[0] == "---":
        final_lines.extend(frontmatter_lines)
        final_lines.append("")
    final_lines.append(body_text.rstrip("\n"))
    final_text = "\n".join(final_lines).rstrip() + "\n"
    note_path.write_text(final_text, encoding="utf-8")

    result = {
        "success": True,
        "note_path": str(note_path),
        "analyzer_status": args.analyzer_status,
        "knowledge_section_written": knowledge_section_written,
        "knowledge_note_path": relative_path(args.knowledge_note_path, args.vault_path),
    }
    output = json.dumps(result, ensure_ascii=False, indent=2)
    if has_value(args.output_json):
        Path(args.output_json).write_text(output, encoding="utf-8")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
