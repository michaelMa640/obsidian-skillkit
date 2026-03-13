# Obsidian Clipper

## English

### Overview

Obsidian Clipper is a first-stage OpenClaw skill for fast content capture.
It saves a link into an Obsidian vault as a reusable clipping note, without forcing a long AI analysis chain.

This skill is designed for the new two-stage workflow:
- Stage 1: `obsidian-clipper`
- Stage 2: `obsidian-analyzer`

### What This Skill Does

- accepts a source URL from OpenClaw
- detects the source platform and content type
- routes the request to the appropriate capture path
- saves a clipping note into `Clippings/`
- preserves enough structure for later analysis

### First Runnable Version

The current implementation includes a real PowerShell entrypoint:
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`

This first runnable version already supports:
- URL input
- platform detection
- route selection
- standardized clipping note generation
- direct write into an Obsidian vault in filesystem mode
- real `yt-dlp` integration for the `video_metadata` route, with fallback clipping when remote extraction fails
- built-in podcast page metadata capture, RSS hint extraction, transcript-link discovery, and show-notes-style text extraction for the `podcast` route

What is still placeholder-based in this version:
- browser-based social capture

### Current Capture Strategy

- article pages: built-in page fetch + main-text extraction, with fallback clipping when the page cannot be reached
- Xiaohongshu / Douyin: browser page capture planned, light placeholder capture for now
- Bilibili / YouTube: `yt-dlp` metadata + subtitles first, and fallback to minimal clipping if remote extraction fails
- Xiaoyuzhou / podcasts: page metadata + RSS/transcript hint discovery + show-notes-style text extraction, with graceful fallback when the page cannot be reached

Default principle:
- clip first
- keep it light
- avoid heavy media downloads unless explicitly needed

### Files In This Skill

- `SKILL.md`: agent-facing operating instructions
- `agents/openai.yaml`: UI metadata for the skill
- `references/local-config.example.json`: local machine config template
- `references/platform-routing.md`: routing reference for supported source types
- `scripts/run_clipper.ps1`: first runnable entrypoint
- `scripts/detect_platform.ps1`: platform routing helper

### Dependencies

Current first runnable version needs:
- OpenClaw
- PowerShell
- an accessible Obsidian vault path
- `yt-dlp` available on `PATH` for the `video_metadata` route
- web access for the built-in podcast metadata route

Future route-specific integrations may additionally need:
- Python
- Playwright
- article extraction tooling

This repository does not vendor those external tools.

## 涓枃

### 璇存槑

Obsidian Clipper 鏄竴涓潰鍚?OpenClaw 鐨勭涓€闃舵蹇€熷壀钘?skill銆?瀹冪殑鐩爣鏄妸閾炬帴灏藉揩淇濆瓨鍒?Obsidian 涓紝鑰屼笉鏄湪绗竴姝ュ氨璺戝畬鏁寸殑 AI 娣卞害鍒嗘瀽銆?
杩欎釜 skill 鏈嶅姟浜庢柊鐨勪袱闃舵宸ヤ綔娴侊細
- 绗竴闃舵锛歚obsidian-clipper`
- 绗簩闃舵锛歚obsidian-analyzer`

### 瀹冨仛浠€涔?
- 鎺ユ敹 OpenClaw 鎻愪氦鐨勯摼鎺?- 璇嗗埆骞冲彴鍜屽唴瀹圭被鍨?- 璺敱鍒板悎閫傜殑鎶撳彇璺緞
- 鎶婄粨鏋滃啓杩?`Clippings/`
- 淇濈暀鍚庣画鍒嗘瀽鎵€闇€鐨勭粨鏋?
### 褰撳墠绗竴鐗堝彲杩愯瀹炵幇

褰撳墠宸茬粡鏈夌湡瀹炲彲杩愯鐨?PowerShell 鍏ュ彛锛?- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`

杩欑涓€鐗堝凡缁忔敮鎸侊細
- URL 杈撳叆
- 骞冲彴璇嗗埆
- 璺敱閫夋嫨
- 鏍囧噯鍖?Clippings 绗旇鐢熸垚
- 鏂囦欢绯荤粺妯″紡涓嬬洿鎺ュ啓鍏?Obsidian vault
- `video_metadata` 璺敱鐪熷疄璋冪敤 `yt-dlp`
- `podcast` 璺敱鍐呭缓椤甸潰 metadata 鎶撳彇銆丷SS 绾跨储鎻愬彇銆乼ranscript 閾炬帴鍙戠幇銆乻how notes 椋庢牸鏂囨湰鎻愬彇

杩欎竴鐗堣繕娌℃湁鐪熸鎺ュソ鐨勯儴鍒嗭細
- 鏂囩珷姝ｆ枃瀹屾暣鎶撳彇
- 绀句氦骞冲彴娴忚鍣ㄦ姄鍙?
### 褰撳墠鎶撳彇绛栫暐

- 鏂囩珷缃戦〉锛氬凡鎺ュ叆椤甸潰鎶撳彇鍜屾鏂囨彁鍙栵紝椤甸潰涓嶅彲杈炬椂鑷姩闄嶇骇
- 灏忕孩涔?/ 鎶栭煶锛氬厛棰勭暀娴忚鍣ㄦ姄鍙栬矾寰勶紝褰撳墠鐢ㄨ交閲忓崰浣嶅壀钘?- Bilibili / YouTube锛氬凡鎺ュ叆 `yt-dlp`锛屼紭鍏堟姄鍏冩暟鎹拰瀛楀箷锛屽け璐ユ椂鑷姩闄嶇骇涓烘渶灏?clipping
- 灏忓畤瀹?/ 鎾锛氬凡鎺ュ叆椤甸潰 metadata銆丷SS/transcript 绾跨储銆乻how notes 椋庢牸鏂囨湰鎻愬彇锛岄〉闈笉鍙揪鏃惰嚜鍔ㄩ檷绾?
榛樿鍘熷垯锛?- 鍏堝壀钘?- 淇濇寔杞婚噺
- 闄ら潪鏄惧紡闇€瑕侊紝鍚﹀垯涓嶅仛閲嶅瀷濯掍綋涓嬭浇

### 杩欎釜 skill 鐩綍閲岀殑鏂囦欢

- `SKILL.md`锛氱粰浠ｇ悊鐪嬬殑璇存槑
- `agents/openai.yaml`锛歴kill 鐨勫厓鏁版嵁
- `references/local-config.example.json`锛氭湰鍦伴厤缃ā鏉?- `references/platform-routing.md`锛氬钩鍙拌矾鐢卞弬鑰?- `scripts/run_clipper.ps1`锛氱涓€鐗堝彲杩愯鍏ュ彛
- `scripts/detect_platform.ps1`锛氬钩鍙拌瘑鍒緟鍔╄剼鏈?
### 渚濊禆

褰撳墠杩欑増鏈€灏忓彲杩愯瀹炵幇闇€瑕侊細
- OpenClaw
- PowerShell
- 鍙闂殑 Obsidian vault
- `PATH` 涓彲鐢ㄧ殑 `yt-dlp`锛岀敤浜?`video_metadata` 璺敱
- 鍙闂洰鏍囨挱瀹㈤〉闈㈢殑缃戠粶鐜锛岀敤浜?`podcast` 璺敱

鍚庣画鎺ュ叆鐪熷疄璺嚎鏃讹紝鍙兘杩橀渶瑕侊細
- Python
- Playwright
- 姝ｆ枃鎻愬彇宸ュ叿
