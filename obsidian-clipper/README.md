# Obsidian Clipper

## English

### Overview

Obsidian Clipper is the first-stage OpenClaw skill for fast content capture.
It saves a source into an Obsidian vault as a reusable raw-content note without forcing a long AI analysis chain.

This skill is designed for the new two-stage workflow:
- Stage 1: `obsidian-clipper`
- Stage 2: `obsidian-analyzer`

### What This Skill Does

- accepts a source URL from OpenClaw
- detects the source platform and content type
- routes the request to the appropriate capture path
- saves a clipping note into `Clippings/`
- preserves enough structure for later analysis
- emits stable capture metadata for downstream automation

### Current Architectural Contract

The Phase 3 contract is now explicit:
- `obsidian-clipper` owns raw source capture
- short social video capture is asset-first at the architecture level
- short social video download, attachment landing, and sidecar JSON writing belong to `obsidian-clipper`
- `obsidian-analyzer` should read stored records and stored media references instead of re-downloading social sources

### Current Runnable Version

The current implementation includes real entrypoints:
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`
- `scripts/capture_social_playwright.py`
- `scripts/download_social_media.ps1`: downloader + attachment landing helper for short social video
- `scripts/bootstrap_social_auth.py`: local auth bootstrap helper for storage state + cookies export

This version already supports:
- URL input
- full share-text input that contains an embedded URL, such as raw Douyin share text copied from the app
- platform detection
- route selection
- standardized clipping note generation
- direct write into an Obsidian vault in filesystem mode
- built-in article page fetch + main-text extraction
- built-in Playwright-driven social capture for Xiaohongshu / Douyin, with structured social payloads, downloader handoff, attachment landing, and graceful fallback clipping
- real `yt-dlp` integration for the `video_metadata` route, with fallback clipping when remote extraction fails
- built-in podcast page metadata capture, RSS hint extraction, transcript-link discovery, and show-notes-style text extraction for the `podcast` route

What is still incomplete in this version:
- advanced platform-specific selectors for more Xiaohongshu / Douyin layouts
- local auth artifacts still need one-time manual bootstrap on each machine if restricted social comments require login state
- Feishu Bitable upsert is still outside the current runnable clipper path
- remote object storage sync for downloaded binaries is not wired yet
- richer article extraction heuristics

### Current Capture Strategy

- article pages: built-in page fetch + main-text extraction, with fallback clipping when the page cannot be reached
- Xiaohongshu / Douyin: Playwright page capture with platform-specific selectors, optional login-state reuse via storage state / cookies.txt, structured comments and engagement hints, candidate video references, `yt-dlp` first download, direct-candidate fallback download, local attachment landing, and graceful fallback when browser or downloader steps fail
- Bilibili / YouTube: `yt-dlp` metadata + subtitles first, and fallback to minimal clipping if remote extraction fails
- Xiaoyuzhou / podcasts: page metadata + RSS/transcript hint discovery + show-notes-style text extraction, with graceful fallback when the page cannot be reached

Default principles:
- clip first
- keep the stored record stable
- treat short social video as asset-first at the system boundary
- do not block note creation when a heavy step fails

### Storage Model

Phase 1 to Phase 3 now assume:
- Obsidian is the primary store for raw capture notes
- binary assets live in attachment folders or object storage
- Feishu Bitable is an index and workflow view, not the sole source of truth

Recommended local layout:
- `Clippings/`
- `Attachments/ShortVideos/{platform}/{capture_id}/`
- `爆款拆解/`

### Files In This Skill

- `SKILL.md`: agent-facing operating instructions
- `agents/openai.yaml`: UI metadata for the skill
- `references/local-config.example.json`: local machine config template
- `references/platform-routing.md`: routing reference for supported source types
- `references/capture-data-model.md`: capture contract for short social video records
- `references/capture-record.schema.json`: sidecar JSON schema for capture records
- `scripts/run_clipper.ps1`: main PowerShell entrypoint
- `scripts/detect_platform.ps1`: platform routing helper
- `scripts/capture_social_playwright.py`: Playwright-based social capture helper
- `scripts/download_social_media.ps1`: downloader + attachment landing helper for short social video
- `scripts/bootstrap_social_auth.py`: local auth bootstrap helper for storage state + cookies export

### Validation And Debugging

`obsidian-clipper` keeps an explicit user-facing validation path for social capture and download debugging.

Primary command:
- `scripts/dev_validate_social_download.ps1`
- direct clipper runs can also use `scripts/run_clipper.ps1 -DebugDirectory <dir>` to keep raw local artifacts plus a shareable `support-bundle/`

Input handling:
- you can pass either a direct URL or a pasted share text block
- for Douyin share text, the clipper extracts the first embedded `https://...` link before platform detection and capture

What the validator does:
- prints step-by-step terminal status for `detect`, `capture`, `download`, and `clipper`
- prints a short end-of-run summary with the current route, auth state, capture result, download result, and debug folder
- writes a debug bundle under `obsidian-clipper/.tmp/social-download-validation/<timestamp>/`
- keeps raw local debug files in the run folder for machine-local investigation
- writes `support-bundle/` with sanitized copies intended for sharing
- always attempts to produce both raw and sanitized `validation-report.json`, `capture-social.json`, `download-social.json`, `run-clipper.json`, and related `.log` files even when a step fails

Recommended files to share when debugging a failed run:
- `support-bundle/validation-report.json`
- `support-bundle/capture-social.json`
- `support-bundle/download-social.json`
- `support-bundle/capture-social.log`
- `support-bundle/download-social.log`
- `support-bundle/run-clipper.log`

### Debug Privacy Rules

The validation bundle is designed to help debugging without leaking local secrets.

Current guardrails:
- local auth files are used at runtime but not copied into `support-bundle/`
- auth file paths are masked in `support-bundle/` JSON and logs
- real vault paths are masked as `<vault-root>` in `support-bundle/`
- raw source URLs are sanitized before being written to `support-bundle/`
- `.local-auth/`, `.tmp/`, and `references/local-config.json` stay local-only and are excluded from git

Users should never share:
- `obsidian-clipper/.local-auth/*`
- raw browser cookie exports
- unsanitized local config files
- raw debug logs when a sanitized `support-bundle/` exists

### Dependencies

Current runnable version needs:
- OpenClaw
- PowerShell
- an accessible Obsidian vault path
- Python
- Playwright
- `yt-dlp` available on `PATH` for the social and `video_metadata` routes
- optional local auth bootstrap via `scripts/bootstrap_social_auth.py` when restricted social comments require login state
- `ffprobe` on `PATH` is recommended for local video metadata enrichment
- web access for article, social, and podcast routes

This repository does not vendor those external tools.

## 濞戞搩鍘介弸?

### 婵帒鍊介崼?

Obsidian Clipper 闁哄嫷鍨电换鏍ㄧ附濡炴崘鈷堥梻鍐煐椤斿苯顔忛妷銈囩▕婵炵繝绶氶崳鐑芥儍閸曨収鍎戝☉鎾亾闂傚啳鍩栭?skill闁挎稑鐭佺粈瀣嫻閿濆棗惟闁哄鍎茬花顕€宕橀崨顓у晣闊浂鍋婇埀顒傚枂閳ь兛鑳惰彊閻庤鑹惧﹢鎾礈椤忓洦顥戦弶?Obsidian闁挎稑鐭侀埀顒€濂旂粭澶愬及椤栨瑧顏辩€殿喒鍋撳┑顔碱儏濮樸劌顕ｉ崫鍕厬闁圭瑳鍡╂斀閻庣懓鏈弳锝夋儍?AI 婵烇絽宕€规娊宕氶崱妯尖偓浠嬫煣閹规劗鐔呴柕?

鐟滅増鎸告晶鐘诲箳閵娿劌绀冩繛缈犺兌閳诲ジ鏁?
- 缂佹鍏涚粩鎾⒓閼告鍞介柨娑欑摢obsidian-clipper`
- 缂佹鍏涚花鈺呮⒓閼告鍞介柨娑欑摢obsidian-analyzer`

### 閺夆晜鐟ら柌?Skill 闁绘粍婢樺﹢顏嗘嫻閻旇崵鐓戝ù鐘亾濞?

- 闁规亽鍎查弫?OpenClaw 濞磋偐濮撮崣鍡涙儍?URL
- 閻犲洤妫楅崺鍡涚嵁閸愭彃閰卞☉鎾抽閸炲鈧懓婀辩悮顐﹀垂?
- 闁硅泛锕ㄩ顒€效閸屾繄鐔呴柣銏犲船閸╁苯顫㈤敐鍥ｂ偓姗€鎯冮崟顒€顫夐柛娆愮墳閻儳顕?
- 闁?Obsidian 濞戞搩鍘奸崯鎾诲礂閵夈倗顏辩紒?`Clippings/` 缂佹妫侀?
- 闁汇垻鍠愰崹姘辩矙閸愯尙鏆伴柣?capture 闁稿繐鍟弳鐔煎箲椤曞棛绀夊〒姘☉閹绱掗鐐茬€婚柡瀣姇閹蜂即鎳涢鍕楅柛鏍ㄧ墧婵炲洭鎮?

### 鐟滅増鎸告晶鐘差啅閼碱剛鐥呴柡鍕捣閳ユ﹢鎯冮崟顔绘崓閻犳劧缍€缁旂喖鎮?

濞?Phase 2 鐎殿喒鍋撳┑顔碱儜缁辨繄鍖栭懡銈囧煚闁煎崬鐭侀惌妤€顔忛懠顒傜梾闁哄嫬娴烽垾姗€鏁?
- `obsidian-clipper` 閻犳劗鍠曢惌妤呭储閻斿娼楀ù婊冾儏閻ゅ嫰宕楅妷銉ф皑
- 闁硅埖鐗犻悡?/ 閻忓繐绻掔€涒晜绋婇敃浣虹缂侇偉宕甸悡顓犳喆閸℃侗鏆ラ柛锔哄妽閻忥箓寮搁崟顏嗙憪閻忕偟鍋樼花?asset-first闁挎稑鐬奸弫?clipper 闂傚啳鍩栭宀€鎷归悢鑽ょ厬闁告艾娴烽悽缁樼▔鐎ｎ厽绁板☉鎾抽閻°劑宕?
- `obsidian-analyzer` 閻犳劗鍠曢惌妤冩嫚鐠囨彃绲跨€瑰憡褰冮崣鍡樻償閹捐埖鐣辩紒妤佹椤斿洭濡存稊绫璬ecar JSON 闁告粌鑻悰鐔告媴閹惧磭绌块柣銏╃厜缁辨繃绋夊鍛櫃闁瑰灚瀵ф刊鎾煂瀹ュ棙鐓€闁硅埖鎸歌ぐ鍥儗椤撯槅娼掑Λ鐗堝灦濞奸潧鈹冮幇顔界暠闁煎崬鐭侀惌?

闁烩晩鍠栨晶鐘绘儗椤撯槅娼掑Λ?downloader 閺夆晜蓱閻ュ懘寮垫径濠勬殮闁稿繈鍔嶇敮瀛樻交?clipper 濞戞挾绮粊锔剧矙鐎ｅ墎绀夊ù锝呮閺嗙喖骞戦鍓ф尝闁哄瀚幏浼存嚂瀹€鍐厬閺夊牆婀遍弲顐㈩啅閼碱剛鐥呴柛蹇撶墕濞存劗鈧鐭粭鍛村级閵夛絺鍋?

### 鐟滅増鎸告晶鐘诲矗椤栨繄绠ラ悶娑樼灱婢ф寮?

鐟滅増鎸告晶鐘碘偓鍦仧楠炲洤顔忛幓鎺戠樁闁告凹鍋夌换鏍ㄧ濞戞碍鍩傞悗鍦仜閸欏棝宕ｉ敐蹇曠獥
- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`
- `scripts/capture_social_playwright.py`
- `scripts/download_social_media.ps1`: downloader + attachment landing helper for short social video
- `scripts/bootstrap_social_auth.py`: local auth bootstrap helper for storage state + cookies export

鐟滅増鎸告晶鐘绘偋閸喐鎷辩€规瓕灏欑划锟犲绩椤栨稑鐦柨?
- URL 閺夊牊鎸搁崣?
- 妤犵偛鍟胯ぐ瀵告嫚閸℃鐒?
- 閻犱警鍨抽弫閬嶆焻婢跺顏?
- 闁哄秴娲ら崳顖炲礌?`Clippings` 缂佹妫侀鍥偨閻旂鐏?
- 闁哄倸娲ｅ▎銏㈠寲閼姐倗鍩犳俊顖椻偓宕囩濞戞挸顑囧ú鍧楀箳閵夈儱鏅搁柛?Obsidian vault
- 闁告劕鎳庣紓鎾诲棘閸モ晝褰块柟鑸垫尭瑜板洭宕仦缁㈠妧闁哄倸娲﹁ぐ渚€宕?
- 閻忓繐绻掔€涒晜绋?/ 闁硅埖鐗犻悡鍫曟儍?Playwright 濡炪倗鏁诲浼村箮閹惧啿绲块柨娑樼焷缁绘垿宕堕悙鐢垫尝闁哄瀚€垫煡鎯冮崟顒€浼庨弶鈺勫焽閳ь兛娴囬惁搴ｆ媼閹巻鍋撴担椋庨瀺闁告柣鍔嶈ぐ浣虹矆閸濆嫭瀚查柛濠冪懇閳ь剙顦抽～瀣紣閹存繄绌块柣?
- `video_metadata` 閻犱警鍨抽弫杈┾偓?`yt-dlp` 闁汇劌瀚敮鎾礂?
- `podcast` 閻犱警鍨抽弫杈┾偓闈涚秺閵嗗妫?metadata闁靛棔闃淪S 闁?transcript 缂佹崘娉曢崒銊╂儍閸曨剙绲归柛?

### 鐟滅増鎸告晶鐘诲箮閹惧啿绲跨紒娑欑墱閺?

- 闁哄倸娲ㄩ悵鐑芥晬濮橆厼顫夊銈囨暬濞兼澘顫㈤敐鍡樼€柨娑樿嫰閵囨垹鎷归妷锔筋槯闂傚嫬绉舵鍥ㄧ▔閻戞ɑ浠橀悘?clipping
- 閻忓繐绻掔€涒晜绋?/ 闁硅埖鐗犻悡鍫曟晬濮樿鲸鏆?Playwright 闁硅埖鎸歌ぐ鑼喆娴ｇ鏁堕悗鐟扮畭閳ь兛娴囬惁搴ｆ媼閹巻鍋撴担椋庨瀺闁告柣鍔嶈ぐ浣虹矆閸濆嫭瀚查柛濠冪懇閳ь剙顦抽～瀣紣閹存繄绌块柣銏╃厜缁辨繃寰勬潏顐バ曢柡鍐ㄧ埣濡鹃鐥?
- Bilibili / YouTube闁挎稒鐭槐顓㈠礂閸喎顫?metadata 闁告粌鑻悺褔鐛?
- 闁圭虎鍘奸褰掓晬濮橆偆鍠橀柛蹇撶墛婵?metadata闁靛棔澶焗ow notes闁靛棔闃淪S 闁?transcript 缂佹崘娉曢崒?

濮掓稒顭堥濠氬储閻斿嘲鐏熼柨?
- 闁稿繐鐗嗛悾顒勫箣閹邦啚鏃傗偓瑙勮壘閸欏棙鎯?
- 濞ｅ洦绻冪€垫梻鎷嬮弶璺ㄧЭ缂備焦鎸婚悗顖滅矙閸愯尙鏆?
- 闁活収鍙€椤锛愰幋婵囪含缂侇垵宕电划鐑樻綇閸︻厽娅曞☉鎾筹攻鐎?asset-first 閻庣數鎳撶欢?
- 闂佹彃绉甸鐐搭殽閵堝懌浜奸悹鎰╁劜濡炲倹绋夊鍫矗闂傚啳顕ч、?clipping note 闁告劖鐟ラ崣?

### 閻庢稒锚閸嬪秴顕欐ウ娆惧敶

鐟滅増鎸告晶鐘诲棘鐟欏嫷鏀冲娑欘焾椤撳鏁?
- `Obsidian` 闁哄嫷鍨扮敮顐ｆ叏鐎ｂ晝鐨戦悗鍦仧濞堟垶绋夌拠鑼憼闁?
- 濞存粌鐭佺换姗€宕氱捄铏瑰疮濞达絾鎸婚弬渚€姊介崟顏咁偨闁烩晩鍠栫紞宥夊箣閺嵮屽殸閻犵偐鈧磭鎽犻柛?
- `濡炲鍋橀崝鐔稿緞濮樿鲸妯婇悶娑栧妽閻楃珚 闁告瑯浜滄禒娑氭閵忕姷绌块悘鐐插€搁幏鏉棵规担琛℃煠闁活亜顑嗗?

闁规亽鍔忓畷姗€鎯勯鑲╃Э缂備焦鎸婚悗顖炴晬?
- `Clippings/`
- `Attachments/ShortVideos/{platform}/{capture_id}/`
- `爆款拆解/`
