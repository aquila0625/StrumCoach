"""合并 keys.json 和运行时查表的词条，生成给译者用的 source.json（每条带模块、出现位置和说明）。"""
import json, sys
keys = json.load(open(sys.argv[1]))
extra = {
    "TunerKit": {  # InstrumentLibrary 里的乐器、定弦名（运行时按原文查表）
        "自动": "Instrument picker option: automatic/chromatic detection",
        "半音阶": "Tuning name: chromatic", "吉他": "Instrument: guitar", "标准": "Tuning name: standard",
        "Drop D": "Tuning name, keep as is in most languages", "降半音 E♭": "Tuning name: half step down (E♭ tuning)",
        "DADGAD": "Tuning name, keep", "贝斯": "Instrument: bass guitar", "4 弦 EADG": "Bass tuning: 4-string EADG",
        "5 弦 BEADG": "Bass tuning: 5-string BEADG", "尤克里里": "Instrument: ukulele", "标准 GCEA": "Ukulele tuning: standard GCEA",
        "低音 G 版": "Ukulele tuning: low G", "小提琴": "Instrument: violin", "标准 GDAE": "Violin tuning: standard GDAE",
        "中提琴": "Instrument: viola", "标准 CGDA": "Viola/cello tuning: standard CGDA", "大提琴": "Instrument: cello",
    },
    "ChordKit": {  # ChordType 的名字与短名
        "大三": "Chord type button (short, max ~5 chars): major", "小三": "Chord type button (short, max ~5 chars): minor",
        "大三和弦": "Chord type full name: major triad", "小三和弦": "minor triad", "属七和弦": "dominant 7th chord",
        "大七和弦": "major 7th chord", "小七和弦": "minor 7th chord", "挂二和弦": "suspended 2nd chord",
        "挂四和弦": "suspended 4th chord", "减三和弦": "diminished triad", "增三和弦": "augmented triad", "加九和弦": "add 9 chord",
        "四拍上行": "Arpeggio pattern description for 5-3-2-1 (guitar): four notes rising, one per beat. Short",
        "八分音符分解": "Arpeggio pattern description for 5-3-2-3-1-3-2-3: classic eighth-note picking. Short",
        "三拍子分解": "Arpeggio pattern description for 5-3-2-3-1-3: waltz / 3-4 time picking. Short",
        "交替八分": "Arpeggio pattern description for 5-2-3-1-3-2: alternating eighth-note picking. Short",
        "上行下行琶音": "Arpeggio pattern description: sweep from the root string up to string 1 and back down. Short",
        "四弦上行": "Ukulele arpeggio pattern description for 4-3-2-1: all four strings rising. Short",
        "来回分解": "Ukulele arpeggio pattern description for 4-3-2-1-2-3: up and back. Short",
        "常见指弹": "Ukulele arpeggio pattern description for 3-2-1-2: classic fingerpicking. Short",
        "根音 · 五度 · 八度 · 五度": "Bass arpeggio pattern description: root, fifth, octave, fifth. Keep the ' · ' separators",
        "民谣 1": "Strum pattern name",
        "民谣 2": "Strum pattern name",
        "八分全扫": "Strum pattern name: all eighth notes",
        "四分": "Strum pattern name: quarter notes",
        "慢摇 / 华尔兹 3/4": "Strum pattern name: slow / waltz in 3/4",
        "切音节奏": "Strum pattern name: chuck / chop",
        "十六分 Funk": "Strum pattern name: sixteenth-note funk",
        "岛屿扫弦": "Ukulele strum pattern name: island strum",
        "基础扫弦": "Ukulele strum pattern name: basic strum",
        "根音扫弦": "Strum pattern name: strum with root-note bass notes (root, full strum, root, full strum)",
        "乡村": "Strum pattern name: country (bass note then half strums)",
        "华尔兹根音": "Strum pattern name: waltz in 3/4 with a root bass note then two half strums",
        "，": "List separator used between items in VoiceOver text (Chinese full-width comma). Use the language's normal separator, e.g. ', '",
    },
    "MetronomeCore": {  # 速度术语的本地名称；界面显示为“本地名称 + 意大利文”
        "庄板": "TEMPO-LOCAL Grave", "广板": "TEMPO-LOCAL Largo", "小广板": "TEMPO-LOCAL Larghetto",
        "柔板": "TEMPO-LOCAL Adagio", "行板": "TEMPO-LOCAL Andante", "中板": "TEMPO-LOCAL Moderato",
        "快板": "TEMPO-LOCAL Allegro", "活板": "TEMPO-LOCAL Vivace", "急板": "TEMPO-LOCAL Presto",
        "最急板": "TEMPO-LOCAL Prestissimo",
    },
}
notes = {
    "%@切分": "Caption under the subdivision chip; %@ is the subdivision name (e.g. 'Eighth'). Short.",
    "四分": "Subdivision: quarter notes (one click per beat)", "八分": "Subdivision: eighth notes", "三连音": "Subdivision: triplets",
    "十六分": "Subdivision: sixteenth notes", "附点": "Subdivision: dotted eighth + sixteenth", "前八后十六": "Subdivision: eighth + two sixteenths",
    "前十六后八": "Subdivision: two sixteenths + eighth", "切分音": "Subdivision: syncopation (sixteenth-eighth-sixteenth)",
    "强": "Accent level: strong", "次强": "Accent level: medium", "弱": "Accent level: weak", "静音": "Accent level / box label: muted (silent)",
    "木鱼": "Click sound: woodblock", "电子": "Click sound: electronic beep", "牛铃": "Click sound: cowbell",
    "首拍强": "Accent preset: first beat strong", "全部均等": "Accent preset: all beats equal", "按拍号分组": "Accent preset: grouped by time signature",
    "TAP 测速": "VoiceOver label of the tap-tempo button", "测速": "Small caption under 'TAP' button: tap tempo. Very short (≤8 chars)",
    "计时": "Small caption under the elapsed-time button: timer. Very short", "拍号": "Time signature (chip caption, short)",
    "音色": "Sound (chip caption, short)",
"第 %lld 拍，%@": "VoiceOver: 'Beat %lld, %@' where %@ is accent level",
    "%lld → %lld BPM · 每 %lld 小节 %@%lld": "Ramp summary: 'start → target BPM · every N bars ±step'. %@ is '+' or '−' sign directly before the step number",
    "第 %lld 小节 · 还剩 %lld 小节": "Training progress: 'Bar N · M bars left'",
    "%lld 小节后到达目标 · %@": "'Reaches target in N bars · <end behavior>'",
    "%lld 小节": "Value with unit: N bars", "节拍器 · %lld BPM": "Lock screen now-playing title",
    "字母 %@": "Note name style option: Letters, %@ is an example like 'C D E'", "唱名 %@": "Note name style option: Solfège, %@ is an example like 'Do Re Mi'",
    "标准音 %@": "'Reference pitch %@' where %@ is the note A4 (or La4)", "标准音": "Reference pitch (A4 = 440 Hz label prefix)",
    "相对主拍 %@": "Subdivision volume relative to the main beat, %@ is a percentage",
    "今天已练 %@": "'Practiced today: %@' where %@ is a percentage of the goal",
    "随机静音 %@ 的拍": "'Randomly mute %@ of beats', %@ is a percentage", "随机静音 %@ 的拍 · 保留首拍": "same + '· keep downbeat'",
    "%lld 弦 %@": "VoiceOver: 'String %lld, %@' (string number, note name)", "参考音 %@": "VoiceOver: 'Reference tone %@'",
    "%lld 弦 %lld 品": "VoiceOver: 'String %lld, fret %lld'", "%lld 弦不弹": "VoiceOver: 'String %lld not played'",
    "%lld 弦空弦": "VoiceOver: 'String %lld open'", "%lld 品把位": "Chord position label: 'Fret %lld' (position starting at fret N)",
    "横按 · %lld 品": "Chord position label: 'Barre · fret %lld'", "%@ 指法": "VoiceOver: '%@ fingering' (%@ = chord name)",
    "%@ 贝斯和弦音位置": "VoiceOver: 'Chord tones of %@ on bass'", "三度": "Bass legend: third (interval)", "五度": "Bass legend: fifth",
    "八度": "Octave (tuner reference octave label; bass legend: octave)", "根音": "Root (note of a chord)",
    "开放把位": "Chord position: open position", "大三": "Chord type button: major (very short)", "小三": "Chord type button: minor (very short)",
    "已准": "Tuner status: in tune", "偏低": "Tuner status: flat", "偏高": "Tuner status: sharp", "音分": "cents (unit of pitch deviation)",
    "拍号 %lld %lld": "VoiceOver: 'Time signature %lld over %lld'", "按小节": "Mute mode option: by bars", "随机静音": "Mute mode option: random beats",
    "有声": "Mute pattern stepper: audible bars", "%@，需要 Pro": "VoiceOver: '%@, requires Pro'",
    "无法启动音频：%@": "Error: 'Could not start audio: %@'", "查看全部 %lld 条记录": "'View all %lld sessions'",
    "目标 %lld 分钟，到时提醒": "Timer card subtitle: 'Goal %lld min, remind when reached'",
    "目标 %lld 分钟，到时提醒并停止": "'Goal %lld min, remind and stop when reached'",
    "今天已练够 %lld 分钟": "Banner: 'You've practiced %lld minutes today'", "今天已练够 %lld 分钟，已自动停止": "same + ', stopped automatically'",
    "提速 + 静音": "Short badge: tempo ramp + muting both on", "渐进提速": "Training mode: tempo ramp (gradual speed-up)",
    "静音小节": "Training mode: muted bars", "渐进提速控制中": "Shown instead of tempo term when ramp controls the tempo: 'Controlled by tempo ramp'",
    "每档变化": "Ramp stepper: BPM change per step", "每档持续": "Ramp stepper: bars per step", "起始": "Start (BPM)", "目标": "Target",
    "目标比起始低就是渐进减速": "Hint: target lower than start = gradual slow-down", "渐进减速": "gradual slow-down",
    "单位：分钟": "Chart footnote: 'Unit: minutes'", "连续打卡": "Practice streak (consecutive days)", "本周练习": "Practice this week",
    "清除": "Keypad key: clear", "确定": "Confirm/OK button", "好": "OK button in an alert", "完成": "Done button",
    "范围 20–400 BPM": "Hint: range 20–400 BPM", "请输入 20–400 之间的数": "Error hint: enter a number between 20 and 400",
    "设置": "Settings", "语言": "Settings section: Language", "在系统设置中更改": "Row hint: change in system Settings",
    "音名显示": "Settings section: note name display", "跟随系统": "Appearance option: follow system", "浅色": "Appearance: light", "深色": "Appearance: dark",
    "调试（只在 Debug 构建出现）": "Debug section title (debug builds only)", "模拟 Pro": "Debug toggle: simulate Pro",
    # Pro 付费页（包年订阅 / 买断 / 苹果优惠码）
    "包年": "Plan card title: yearly subscription (short)", "买断": "Plan card title: lifetime one-time purchase (short)",
    "推荐": "Small badge on the lifetime plan: Recommended / Best value (very short)",
    "每年自动续订": "Yearly plan caption: renews automatically every year", "当前方案": "Plan caption: your current plan",
    "一次购买，永久使用": "Lifetime plan caption: pay once, use forever",
    "买断 %@": "Purchase button for the lifetime plan; %@ is the price, e.g. '$1.99'. Means 'Buy lifetime %@' / 'Unlock forever %@'",
    "订阅 %@/年": "Purchase button for the yearly plan; %@ is the price, e.g. '$0.99'. 'Subscribe %@/year'",
    "可随时取消 · 无广告 · 支持家人共享": "Small line under the yearly purchase button: 'Cancel anytime · No ads · Family Sharing'",
    "无订阅 · 无广告 · 支持家人共享": "Small line under the lifetime purchase button: 'No subscription · No ads · Family Sharing'",
    "解锁全部功能": "Pro page subtitle: unlock all features", "已永久解锁，感谢支持": "Pro page subtitle after lifetime purchase: unlocked forever, thanks for your support",
    "包年有效期至 %@": "Pro page subtitle while subscribed: 'Yearly plan active until %@' (%@ is a date)",
    "兑换码": "Link that opens Apple's offer code redemption sheet: 'Redeem Code'", "管理订阅": "Link: Manage Subscription",
    "使用条款": "Link: Terms of Use (EULA)", "隐私政策": "Link: Privacy Policy",
    "包年订阅到期前 24 小时内会自动续订，可随时在 App Store 账户设置里取消。": "Subscription legal footnote: auto-renews within 24 hours before the end of the period unless cancelled; cancel anytime in App Store account settings",
    "购买未完成": "Alert title: purchase not completed", "暂时连不上 App Store，请检查网络后再试。": "Alert: can't reach the App Store right now, check the network and try again",
    "没有找到这个 Apple 账户的购买记录。": "Alert after Restore Purchases finds nothing: no purchases found for this Apple Account",
    "购买无法验证，请稍后在“恢复购买”里重试。": "Alert: the purchase could not be verified; try 'Restore Purchases' later",
    # 公告
    "公告": "Announcements (Profile row and sheet title; news from the developer)", "暂时没有公告": "Empty state: no announcements yet",
    "了解更多": "Link button under an announcement: Learn more", "未读": "VoiceOver label of the unread dot: unread",
    "%lld 条未读": "VoiceOver label of the unread count badge: '%lld unread' (plural)",
    "欢迎使用": "Sample announcement title (demo screenshots): Welcome",
    "节拍器、调音器和和弦库都在下面的标签里。有问题或建议，欢迎在 App Store 留言。": "Sample announcement body (demo screenshots)",
    "和弦库新增尤克里里试听": "Sample announcement title (demo screenshots): chord library can now play ukulele chords",
    "选好尤克里里的和弦，点播放就能听到真实的拨弦声。调音器的参考音也换成了各乐器自己的音色。": "Sample announcement body (demo screenshots)",
    "自由练习": "Practice mode: free practice", "练习计时": "Practice timer (training card title / sheet title)",
}
out = []
for mod, d in keys.items():
    for k, locs in d.items():
        out.append({"module": mod, "key": k, "where": locs[:3], "note": notes.get(k, "")})
for mod, d in extra.items():
    for k, note in d.items():
        out.append({"module": mod, "key": k, "where": ["runtime lookup"], "note": note})
# 合并成按 key 去重的列表，供翻译
merged = {}
for e in out:
    m = merged.setdefault(e["key"], {"key": e["key"], "modules": [], "where": [], "note": e["note"]})
    m["modules"].append(e["module"]); m["where"] += e["where"]
    if e["note"] and not m["note"]: m["note"] = e["note"]
json.dump(list(merged.values()), open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
json.dump(out, open(sys.argv[3], "w"), ensure_ascii=False, indent=1)
print(len(merged), "unique keys,", len(out), "module entries")
