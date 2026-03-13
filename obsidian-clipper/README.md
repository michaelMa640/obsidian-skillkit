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
- built-in Playwright-driven social capture for the social route
- built-in podcast page metadata capture, RSS hint extraction, transcript-link discovery, and show-notes-style text extraction for the podcast route

What is still placeholder-based in this version:
- browser-based social capture

### Current Capture Strategy

- article pages: built-in page fetch + main-text extraction, with fallback clipping when the page cannot be reached
- Xiaohongshu / Douyin: Playwright page capture with graceful fallback when browser extraction fails
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
- Python + Playwright for the built-in social capture route

Future route-specific integrations may additionally need:
- Python
- Playwright
- article extraction tooling

This repository does not vendor those external tools.

## 濞戞搩鍘介弸?

### 閻犲洤鐡ㄥΣ?

Obsidian Clipper 闁哄嫷鍨粩瀛樼▔椤忓牊妗ㄩ柛?OpenClaw 闁汇劌瀚鍥ㄧ▔閳ь剟姊奸懜娈垮斀闊浂鍋婇埀顒傚枎婢光偓闁?skill闁?閻庣懓鍟板▓鎴︽儎椤旂晫鍨奸柡鍕靛灡婵℃悂鏌ч悙顒€澶嶉悘蹇氭閹烩晜绌卞┑鍡欐憼闁?Obsidian 濞戞搩鍙忕槐婵嬫嚀鐏炶偐鐟濋柡鍕靛灠濠€顏嗙箔椤戣法顏辨慨婵勫劚濮樸劎鎹勯幋婵堟殮闁轰礁顕▓?AI 婵烇絽宕€规娊宕氶崱妯尖偓浠嬪Υ?
閺夆晜鐟ら柌?skill 闁哄牆绉存慨鐔哥鎼淬垺鐓€闁汇劌瀚悮閬嶆⒓閼告鍞界€规悶鍎扮紞鏂棵规笟濠勭獥
- 缂佹鍏涚粩鎾⒓閼告鍞介柨娑欑摢obsidian-clipper`
- 缂佹鍏涚花鈺呮⒓閼告鍞介柨娑欑摢obsidian-analyzer`

### 閻庣懓鍟禒娑欑閳ь剚绋?
- 闁规亽鍎查弫?OpenClaw 闁圭粯鍔掑锕傛儍閸曨垱鎳犻柟?- 閻犲洤妫楅崺鍡涚嵁閸愭彃閰遍柛婊冭嫰閸炲鈧懓婀辩悮顐﹀垂?- 閻犱警鍨抽弫閬嶅礆閺夋寧鍊ら梺顐㈠€诲▓鎴﹀箮閹惧啿绲块悹渚灠缁?
- 闁硅泛锕︾划銊╁几濠婂啫鏅搁弶?`Clippings/`
- 濞ｅ洦绻勯弳鈧柛姘捣閻㈠宕氶崱妯尖偓浠嬪箥閳ь剟妫侀埀顒勬儍閸曨厾娉㈤柡?
### 鐟滅増鎸告晶鐘电箔椤戣法顏遍柣妤€鐗嗚ぐ鍙夋交閹邦垼鏀介悗鍦仧楠?

鐟滅増鎸告晶鐘差啅閼碱剛鐥呴柡鍫濐槺濠€锛勨偓鍦仜瑜板弶娼婚幇顖ｆ斀闁?PowerShell 闁稿繈鍎辫ぐ娑㈡晬?- `scripts/run_clipper.ps1`
- `scripts/detect_platform.ps1`

閺夆晜鐟ч鍥ㄧ▔閳ь剟鎮ч崼婵嗗殥缂備礁绻戦弫顕€骞愭笟濠勭獥
- URL 閺夊牊鎸搁崣?
- 妤犵偛鍟胯ぐ瀵告嫚閸℃鐒?
- 閻犱警鍨抽弫閬嶆焻婢跺顏?
- 闁哄秴娲ら崳顖炲礌?Clippings 缂佹妫侀鍥偨閻旂鐏?
- 闁哄倸娲ｅ▎銏㈠寲閼姐倗鍩犳俊顖椻偓宕囩濞戞挸顑囧ú鍧楀箳閵夈儱鏅搁柛?Obsidian vault
- `video_metadata` 閻犱警鍨抽弫閬嶆儑閻旈鏉介悹瀣暟閺?`yt-dlp`
- `podcast` 閻犱警鍨抽弫閬嶅礃閸涱厾绱﹀銈囨暬濞?metadata 闁硅埖鎸歌ぐ鍥Υ娑撶ùS 缂佹崘娉曢崒銊╁箵閹邦剙绲块柕鍡曡緶ranscript 闂佸墽鍋撶敮鎾矗閹寸姴绠涢柕鍡曞how notes 濡炲瀛╅悧鎼佸棘閸ャ劍鎷遍柟缁樺姇瑜?

閺夆晜鐟ょ粩鎾偋閸絿绠锋繛灞稿墲濠€渚€鎯囬悢鍓插妧闁规亽鍎遍妶浠嬫儍閸曨垰鍔ラ柛鎺戞４缁?
- 闁哄倸娲ㄩ悵宄邦潰閿濆棙鐎悗鐟版湰閺嗭綁骞庨幘鍐茬悼
- 缂佲偓閸欍儲鍞夋鐐插暱瑜版潙霉韫囨凹娼旈柛锝冨妽婵嫰宕?
### 鐟滅増鎸告晶鐘诲箮閹惧啿绲跨紒娑欑墱閺?

- 闁哄倸娲ㄩ悵椋庣磾閹达负鈧鏁嶅顒€鍤掗柟鎭掑劚閸欏棙銇勯悽鍛婃〃闁硅埖鎸歌ぐ鍥椽鐏炵虎鍔€闁哄倸娲﹁ぐ渚€宕ｉ弽鐢电濡炪倗鏁诲鐗堢▔瀹ュ懎璁查弶鍫㈠亾濡炲倿鎳涢鍕楅梻鍕Ф妤?
- 閻忓繐绻掔€涒晜绋?/ 闁硅埖鐗犻悡鍫曟晬濮橆剙甯ュΛ鏉垮閺嗏偓婵炴潙绻楅～宥夊闯閵婏箑顫夐柛娆愮墳閻儳顕ラ崟鍓佺鐟滅増鎸告晶鐘绘偨閵娿劋姘﹂梺鎻掔箰瀹曠増鎷呭鍛梾闁?- Bilibili / YouTube闁挎稒鑹鹃崙锟犲箳閵夈儱寮?`yt-dlp`闁挎稑濂旂槐顓㈠礂閸喎顫夐柛蹇撳暞閺嗙喖骞戦鍏煎閻庢稒顨呯粻鐑芥晬鐏炲浜奸悹鎰╁劜濡炲倿鎳涢鍕楅梻鍕Ф妤犲洦绋夐悜妯讳粯閻?clipping
- 閻忓繐绻愰悾銈団偓?/ 闁圭虎鍘奸褰掓晬濮橆剙鍤掗柟鎭掑劚閸欏棙銇勯悽鍛婃〃 metadata闁靛棔闃淪S/transcript 缂佹崘娉曢崒銊╁Υ娑旂爆ow notes 濡炲瀛╅悧鎼佸棘閸ャ劍鎷遍柟缁樺姇瑜板洭鏁嶅畝鍕┾偓澶愭椤厾鐟濋柛娆樺灥閹活亪寮幆鏉挎闁告柣鍔戝椋庣棯?
濮掓稒顭堥濠氬储閻斿嘲鐏熼柨?- 闁稿繐鐗嗘竟鈧柦?- 濞ｅ洦绻冪€垫梹娼繝姘
- 闂傚嫨鍊濆顏堝及閹呯闂傚洠鍋撻悷鏇氱筏缁辨繈宕ラ敃鈧崹顖涚▔瀹ュ懍绮甸梺鎻掔Т閻庨攱鍒婇幒宥囩Ъ濞戞挸顑堝ù?

### 閺夆晜鐟ら柌?skill 闁烩晩鍠栫紞宥夋煂瀹€鈧▓鎴﹀棘閸ワ附顐?

- `SKILL.md`闁挎稒姘ㄧ划鐗堢閿濆洦鍊為柣顏勵儑濞堟垹鎷犵€涙ɑ顫?
- `agents/openai.yaml`闁挎稒顒璳ill 闁汇劌瀚崢鎾诲极閻楀牆绁?
- `references/local-config.example.json`闁挎稒纰嶅﹢浼村捶娴兼潙甯崇紓鍐惧枟鑶╅柡?- `references/platform-routing.md`闁挎稒鑹鹃柦鈺呭矗閹峰瞼鐔呴柣銏犲船瀵剟鎳?- `scripts/run_clipper.ps1`闁挎稒姘ㄩ鍥ㄧ▔閳ь剟鎮ч崼婵嗚閺夆晜鍔橀、鎴﹀礂閵夈儱缍?
- `scripts/detect_platform.ps1`闁挎稒鑹鹃柦鈺呭矗閹峰瞼妲曢柛鎺濆亯缁剁喖宕濋埡鍕闁?
### 濞撴碍绻嗙粋?

鐟滅増鎸告晶鐘虫交濞嗘垵顣奸柡鍫氬亾閻忓繐绻愯ぐ鍙夋交閹邦垼鏀介悗鍦仧楠炲洭妫侀埀顒傛啺娓氬﹦绐?
- OpenClaw
- PowerShell
- 闁告瑯鍨甸鏍⒒椤旂偓鐣?Obsidian vault
- `PATH` 濞戞搩鍘艰ぐ鏌ユ偨閵娧勭暠 `yt-dlp`闁挎稑鐬奸弫銈嗙?`video_metadata` 閻犱警鍨抽弫?
- 闁告瑯鍨甸鏍⒒椤旂偓绐楅柡宥呮处閹歌京鈧箍鍨介妴澶愭閵忋垺鐣辩紓鍐╁灩缁爼鎮抽姘兼殧闁挎稑鐬奸弫銈嗙?`podcast` 閻犱警鍨抽弫?

闁告艾娴烽悽濠氬箳閵夈儱寮抽柣顏嗗枎閻ゅ嫮鎹勯婊冩疇闁哄啳顔愮槐婵嬪矗椤栨繂鍘撮弶鈺傦耿濞撳墎鎲版笟濠勭獥
- Python
- Playwright
- 婵繐绲鹃弸鍐箵閹邦剙绲跨€规悶鍎遍崣?
