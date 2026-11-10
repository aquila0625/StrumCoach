#!/usr/bin/env python3 -I
"""把 iOS 版的乐器采样（CAF/AAC）转成安卓用的 OGG Vorbis，放进 app/src/main/assets/samples/。

输入：Packages/TunerKit/Sources/TunerKit/Samples/（manifest.json 和各乐器的 .caf）
输出：android/app/src/main/assets/samples/（manifest.json 里的文件名改成 .ogg，其余字段不变）

需要 ffmpeg。用 ffmpeg 自带的 Vorbis 编码器（保持 44.1 kHz（编码器只支持双声道，两个声道一样，读取时取一个声道），帧数不变，循环点才对得上）。
授权说明见 Packages/TunerKit/Sounds/LICENSES.md，已拷到 assets/samples/LICENSES.md。
用法：python3 -I android/tools/convert_samples.py
"""
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, "Packages", "TunerKit", "Sources", "TunerKit", "Samples")
DST = os.path.join(REPO, "android", "app", "src", "main", "assets", "samples")


def main():
    if shutil.which("ffmpeg") is None:
        sys.exit("需要先安装 ffmpeg")
    manifest = json.load(open(os.path.join(SRC, "manifest.json"), encoding="utf-8"))
    total = 0
    for voice, data in manifest["voices"].items():
        for entry in data["samples"]:
            src = os.path.join(SRC, entry["file"])
            out_name = os.path.splitext(entry["file"])[0] + ".ogg"
            dst = os.path.join(DST, out_name)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-ac", "2", "-ar", str(int(data["sampleRate"])),
                 "-c:a", "vorbis", "-strict", "-2", "-q:a", "4", dst],
                check=True)
            entry["file"] = out_name
            total += os.path.getsize(dst)
    with open(os.path.join(DST, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
        f.write("\n")
    shutil.copyfile(os.path.join(REPO, "Packages", "TunerKit", "Sounds", "LICENSES.md"), os.path.join(DST, "LICENSES.md"))
    print(f"转换完成：{sum(len(v['samples']) for v in manifest['voices'].values())} 个文件，共 {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
