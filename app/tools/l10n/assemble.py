"""把 translations/<lang>.json 合成各模块的 Localizable.xcstrings 和 App 的 InfoPlist.strings，并打印覆盖率。

用法（在 Metronome/app 下）：python3 -I tools/l10n/assemble.py
"""
import json, os

here = os.path.dirname(os.path.abspath(__file__))
app = os.path.dirname(os.path.dirname(here))           # Metronome/app
metronome = os.path.dirname(app)                        # Metronome
LANGS = ["zh-Hant", "en", "ja", "ko", "es", "fr", "de", "pt-BR", "it", "ru", "tr"]
CATALOGS = {
    "StrumCoach": os.path.join(app, "StrumCoach/Resources/Localizable.xcstrings"),
    "MetronomeCore": os.path.join(app, "MetronomeCore/Sources/MetronomeCore/Resources/Localizable.xcstrings"),
    "TunerKit": os.path.join(metronome, "Packages/TunerKit/Sources/TunerKit/Resources/Localizable.xcstrings"),
    "ChordKit": os.path.join(metronome, "Packages/ChordKit/Sources/ChordKit/Resources/Localizable.xcstrings"),
}

entries = json.load(open(os.path.join(here, "entries.json")))
tr = {l: json.load(open(os.path.join(here, "translations", f"{l}.json"))) for l in LANGS}
tr["zh-Hans"] = {"%lld 小节": {"other": "%lld 小节"}, "查看全部 %lld 条记录": {"other": "查看全部 %lld 条记录"}}

coverage = {}
for module, path in CATALOGS.items():
    strings = {}
    mine = [e for e in entries if e["module"] == module]
    for e in sorted(mine, key=lambda e: e["key"]):
        k = e["key"]
        item = {}
        if e["where"] == ["runtime lookup"]:
            item["extractionState"] = "manual"   # 运行时按原文查表，编译器抽不到
        if e.get("note"):
            item["comment"] = e["note"]
        locs = {}
        for l in LANGS:
            v = tr[l].get(k)
            if isinstance(v, dict):
                # 复数变体（俄语 one/few/many/other，法、西、葡、意 one/many/other …）
                if set(v) == {"other"}:
                    locs[l] = {"stringUnit": {"state": "translated", "value": v["other"]}}
                else:
                    locs[l] = {"variations": {"plural": {c: {"stringUnit": {"state": "translated", "value": s}}
                                                         for c, s in v.items()}}}
            elif v is not None and (v.strip() or k == "，"):
                locs[l] = {"stringUnit": {"state": "translated", "value": v}}
        # 源语言也写一份（值就是原文），这样 zh-Hans.lproj 里有文字表，
        # App 内切到简体中文时按 locale 查找不会回退到英文
        src = tr.get("zh-Hans", {}).get(k)
        if isinstance(src, dict):
            locs["zh-Hans"] = {"variations": {"plural": {c: {"stringUnit": {"state": "translated", "value": v}} for c, v in src.items()}}}
        else:
            locs["zh-Hans"] = {"stringUnit": {"state": "translated", "value": k}}
        item["localizations"] = locs
        strings[k] = item
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump({"sourceLanguage": "zh-Hans", "strings": strings, "version": "1.0"}, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    for l in LANGS:
        done = sum(1 for k, it in strings.items() if l in it["localizations"])
        coverage.setdefault(l, {})[module] = (done, len(strings))

# InfoPlist.strings：麦克风说明 + 显示名（中英文名沿用 logo 会话的定稿，其他语言用英文名）
mic = {
    "zh-Hans": "调音器和录制自己的节拍音色需要使用麦克风。",
    "zh-Hant": "調音器和錄製自己的節拍音色需要使用麥克風。",
    "en": "The microphone is used by the tuner and to record your own metronome sound.",
    "ja": "チューナーと、自分の声でメトロノーム音を録音するためにマイクを使用します。",
    "ko": "튜너와 내 소리로 메트로놈 소리를 녹음할 때 마이크를 사용합니다.",
    "es": "El micrófono se usa para el afinador y para grabar tu propio sonido de metrónomo.",
    "fr": "Le micro sert à l’accordeur et à enregistrer votre propre son de métronome.",
    "de": "Das Mikrofon wird für das Stimmgerät und zum Aufnehmen deines eigenen Metronomklangs verwendet.",
    "pt-BR": "O microfone é usado pelo afinador e para gravar seu próprio som de metrônomo.",
    "it": "Il microfono serve all’accordatore e per registrare il tuo suono del metronomo.",
    "ru": "Микрофон нужен тюнеру и для записи собственного звука метронома.",
    "tr": "Mikrofon, akort aleti ve kendi metronom sesini kaydetmek için kullanılır."
}


def read_strings(path):
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line.startswith('"') and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip().strip('"')] = v.strip().rstrip(";").strip().strip('"')
    return out


en_name = read_strings(os.path.join(app, "StrumCoach/en.lproj/InfoPlist.strings")).get("CFBundleDisplayName", "StrumCoach")
zh_name = read_strings(os.path.join(app, "StrumCoach/zh-Hans.lproj/InfoPlist.strings")).get("CFBundleDisplayName")
for l, text in mic.items():
    path = os.path.join(app, f"StrumCoach/{l}.lproj/InfoPlist.strings")
    current = read_strings(path)
    fallback = {"zh-Hans": zh_name, "zh-Hant": "掃弦教練" if zh_name == "扫弦教练" else zh_name}.get(l) or en_name
    name = current.get("CFBundleDisplayName") or fallback
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f'"CFBundleDisplayName" = "{name}";\n"NSMicrophoneUsageDescription" = "{text}";\n')

print("coverage (translated / total):")
for l in LANGS:
    parts = ", ".join(f"{m} {d}/{t}" for m, (d, t) in coverage[l].items())
    total = sum(d for d, _ in coverage[l].values()), sum(t for _, t in coverage[l].values())
    print(f"  {l:7} {total[0]}/{total[1]} = {100 * total[0] / total[1]:.1f}%   ({parts})")
