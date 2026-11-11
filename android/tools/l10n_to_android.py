#!/usr/bin/env python3 -I
"""把 iOS 版的译文转成安卓的 strings.xml，并生成 Kotlin 查表文件。

输入（都在仓库里，只读）：
  app/tools/l10n/translations/<lang>.json   11 种语言的译文，键是简体中文原文（和 iOS 一样）
  app/StrumCoach/<lang>.lproj/InfoPlist.strings   应用名、麦克风说明

输出：
  android/app/src/main/res/values*/strings.xml                    每种语言一份；values/ 是英文（兜底）
  android/app/src/main/kotlin/.../i18n/StringTable.kt             中文原文 → 资源 ID 的查表（自动生成，不要手改）

用法（在仓库任意位置）：
  python3 -I android/tools/l10n_to_android.py          生成
  python3 -I android/tools/l10n_to_android.py --check  只检查是否与已提交的内容一致（改了译文忘了重新生成会失败）

占位符转换：%@ → %s，%lld → %d；一条里有两个以上占位符时自动改成 %1$s %2$d 这样的带序号写法
（aapt2 不允许多个不带序号的占位符），译文里本来就带序号的保持不变。
"""
import hashlib
import json
import os
import re
import sys
import xml.sax.saxutils as su

HERE = os.path.dirname(os.path.abspath(__file__))
ANDROID = os.path.dirname(HERE)
REPO = os.path.dirname(ANDROID)
TRANSLATIONS = os.path.join(REPO, "app", "tools", "l10n", "translations")
INFOPLIST = os.path.join(REPO, "app", "StrumCoach")
RES = os.path.join(ANDROID, "app", "src", "main", "res")
TABLE = os.path.join(ANDROID, "app", "src", "main", "kotlin", "com", "example", "strumcoach", "i18n", "StringTable.kt")

# iOS 语言代码 → (安卓资源目录, 安卓语言标签)
LANGS = {
    "en": ("values", "en"),
    "zh-Hans": ("values-b+zh+Hans", "zh-Hans"),
    "zh-Hant": ("values-b+zh+Hant", "zh-Hant"),
    "ja": ("values-ja", "ja"),
    "ko": ("values-ko", "ko"),
    "es": ("values-es", "es"),
    "fr": ("values-fr", "fr"),
    "de": ("values-de", "de"),
    "pt-BR": ("values-pt-rBR", "pt-BR"),
    "it": ("values-it", "it"),
    "ru": ("values-ru", "ru"),
    "tr": ("values-tr", "tr"),
}
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?(@|lld|d|s)")


def resource_name(key):
    return "s_" + hashlib.sha1(key.encode("utf-8")).hexdigest()[:10]


def convert(text):
    """iOS 格式串 → 安卓格式串（含转义）。"""
    found = list(PLACEHOLDER.finditer(text))
    numbered = any(m.group(1) for m in found)
    out, last, index = [], 0, 0
    for m in found:
        out.append(escape(text[last:m.start()]))
        kind = "s" if m.group(2) in ("@", "s") else "d"
        if m.group(1):
            out.append(f"%{m.group(1)}${kind}")
        elif len(found) > 1 and not numbered:
            index += 1
            out.append(f"%{index}${kind}")
        else:
            out.append(f"%{kind}")
        last = m.end()
    out.append(escape(text[last:]))
    return "".join(out)


def escape(text):
    text = su.escape(text)                     # & < >
    text = text.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"').replace("\n", "\\n")
    if text.startswith(("@", "?")):
        text = "\\" + text
    return text


def read_strings(path):
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line.startswith('"') and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip().strip('"')] = v.strip().rstrip(";").strip().strip('"')
    return out


def load():
    tr = {}
    for lang in LANGS:
        if lang == "zh-Hans":
            continue
        tr[lang] = json.load(open(os.path.join(TRANSLATIONS, f"{lang}.json"), encoding="utf-8"))
    keys = sorted(tr["en"])
    for lang, d in tr.items():
        if set(d) != set(keys):
            sys.exit(f"{lang}.json 的键和 en.json 不一致：{sorted(set(d) ^ set(keys))[:5]}")
    # 简体中文：原文就是键；复数键只有 other
    plural_keys = {k for d in tr.values() for k, v in d.items() if isinstance(v, dict)}
    tr["zh-Hans"] = {k: ({"other": k} if k in plural_keys else k) for k in keys}
    return keys, tr, plural_keys


def render(lang, keys, tr, plural_keys):
    lines = ['<?xml version="1.0" encoding="utf-8"?>',
             "<!-- 自动生成：android/tools/l10n_to_android.py。要改文案请改 app/tools/l10n/translations/*.json 后重新生成。 -->",
             "<resources>"]
    info = read_strings(os.path.join(INFOPLIST, f"{lang}.lproj", "InfoPlist.strings"))
    name = info.get("CFBundleDisplayName") or "StrumCoach"
    lines.append(f'    <string name="app_name">{escape(name)}</string>')
    if "NSMicrophoneUsageDescription" in info:
        lines.append(f'    <string name="mic_usage">{escape(info["NSMicrophoneUsageDescription"])}</string>')
    for key in keys:
        value = tr[lang][key]
        rid = resource_name(key)
        if key in plural_keys:
            if isinstance(value, str):
                value = {"other": value}
            lines.append(f'    <plurals name="{rid}">')
            for quantity in ("zero", "one", "two", "few", "many", "other"):
                if quantity in value:
                    lines.append(f'        <item quantity="{quantity}">{convert(value[quantity])}</item>')
            lines.append("    </plurals>")
        else:
            lines.append(f'    <string name="{rid}">{convert(value)}</string>')
    lines.append("</resources>")
    return "\n".join(lines) + "\n"


def render_table(keys, plural_keys):
    def kt(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$") + '"'
    out = ["// 自动生成：android/tools/l10n_to_android.py，不要手改。",
           "package com.example.strumcoach.i18n",
           "",
           "import com.example.strumcoach.R",
           "",
           "/** 简体中文原文 → 资源 ID（和 iOS 一样，界面里直接用中文原文当键）。 */",
           "internal object StringTable {",
           "    val strings: Map<String, Int> = mapOf("]
    for k in keys:
        if k not in plural_keys:
            out.append(f"        {kt(k)} to R.string.{resource_name(k)},")
    out += ["    )", "", "    val plurals: Map<String, Int> = mapOf("]
    for k in keys:
        if k in plural_keys:
            out.append(f"        {kt(k)} to R.plurals.{resource_name(k)},")
    out += ["    )", "}"]
    return "\n".join(out) + "\n"


def main():
    check = "--check" in sys.argv
    keys, tr, plural_keys = load()
    files = {}
    for lang, (folder, _) in LANGS.items():
        files[os.path.join(RES, folder, "strings.xml")] = render(lang, keys, tr, plural_keys)
    files[TABLE] = render_table(keys, plural_keys)
    stale = []
    for path, text in files.items():
        old = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if old != text:
            stale.append(path)
            if not check:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text)
    if check:
        if stale:
            sys.exit("这些文件和译文不一致，请重新运行 l10n_to_android.py：\n" + "\n".join(stale))
        print("strings.xml 与译文一致")
    else:
        print(f"{len(keys)} 条（其中复数 {len(plural_keys)} 条），{len(LANGS)} 种语言；更新了 {len(stale)} 个文件")


if __name__ == "__main__":
    main()
