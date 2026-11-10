"""从编译产物（*.stringsdata）收集每个模块的可本地化词条，输出 keys.json。

用法：先 xcodebuild build（DerivedData 在 app/build/DerivedData），再运行
    python3 -I tools/l10n/extract.py build/DerivedData tools/l10n/keys.json
"""
import json, os, re, sys

dd, out = sys.argv[1], sys.argv[2]
modules = {"Wenpai": "Wenpai.build", "MetronomeCore": "MetronomeCore-t.build",
           "TunerKit": "TunerKit-t.build", "ChordKit": "ChordKit-t.build"}
result = {m: {} for m in modules}
root = os.path.join(dd, "Build", "Intermediates.noindex")
for dirpath, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".stringsdata"):
            continue
        for mod, marker in modules.items():
            if f"/{marker}/" not in dirpath + "/":
                continue
            data = json.load(open(os.path.join(dirpath, f)))
            src = os.path.basename(data.get("source", ""))
            for table, entries in data.get("tables", {}).items():
                if table != "Localizable":
                    continue
                for e in entries:
                    k = e["key"]
                    if not re.search(r"[一-鿿]", k):
                        continue  # 纯数字、符号、英文缩写不需要翻译
                    loc = f'{src}:{e["location"]["startingLine"]}'
                    result[mod].setdefault(k, set()).add(loc)
for mod in result:
    result[mod] = {k: sorted(v) for k, v in sorted(result[mod].items())}
json.dump(result, open(out, "w"), ensure_ascii=False, indent=1)
for mod, keys in result.items():
    print(mod, len(keys))
