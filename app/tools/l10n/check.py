"""检查译文：缺词条、占位符数量或类型不一致。用法：python3 -I tools/l10n/check.py en ja …"""
import json, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
source = json.load(open(os.path.join(here, "source.json")))
PH = re.compile(r"%(?:\d+\$)?(@|lld|d|lf)")


def placeholders(s):
    return sorted(PH.findall(s.replace("%%", "")))


ok = True
for lang in sys.argv[1:]:
    path = os.path.join(here, "translations", f"{lang}.json")
    if not os.path.exists(path):
        print(lang, "MISSING FILE"); ok = False; continue
    t = json.load(open(path))
    missing = [e["key"] for e in source if e["key"] not in t]
    extra = [k for k in t if k not in {e["key"] for e in source}]
    # 值可以是字符串，也可以是复数变体 {"one": …, "few": …, "many": …, "other": …}（必须有 other）
    def forms(v):
        return list(v.values()) if isinstance(v, dict) else [v]
    keys = {e["key"] for e in source}
    bad = [k for k in t if k in keys and any(placeholders(k) != placeholders(f) for f in forms(t[k]))]
    bad += [k for k in t if isinstance(t[k], dict) and ("other" not in t[k] or set(t[k]) - {"zero", "one", "two", "few", "many", "other"})]
    empty = [k for k, v in t.items() if any(not str(f).strip() for f in forms(v)) and k != "，"]
    print(f"{lang}: {len(t)} keys, missing {len(missing)}, extra {len(extra)}, placeholder mismatch {len(bad)}, empty {len(empty)}")
    for k in missing[:20]: print("  missing:", k)
    for k in extra[:20]: print("  extra:", k)
    for k in bad[:20]: print("  placeholder:", k, "->", t[k])
    for k in empty[:20]: print("  empty:", k)
    ok = ok and not (missing or bad or empty)
sys.exit(0 if ok else 1)
