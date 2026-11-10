#!/usr/bin/env python3
"""下载原始采样到 --out 目录（不进仓库）。来源与授权见 ../LICENSES.md。

用法: python3 fetch_sources.py --out /path/to/raw
"""
import argparse, os, subprocess, sys, urllib.parse

GUITAR_NOTES = "db2 e2 gb2 a2 c3 eb3 gb3 a3 c4 eb4 gb4 a4 c5 eb5 gb5 a5 c6".split()
BASS_NOTES = "b1 d2 e2 gb2 ab2 bb2 c3 d3 e3 gb3 ab3 bb3 c4 d4 e4 gb4".split()

SOURCES = []   # (相对路径, URL)
GH = "https://raw.githubusercontent.com/sfzinstruments"
for n in GUITAR_NOTES:
    SOURCES.append((f"guitar/{n}.wav", f"{GH}/karoryfer.shinyguitar/master/Samples/acoustic/{n}_vl3_rr1_1.wav"))
for n in BASS_NOTES:
    SOURCES.append((f"bass/{n}.wav", f"{GH}/karoryfer.black-and-blue-basses/main/Samples/babyblue/reg/babyblue_{n}_f_rr1.wav"))

UIOWA = "https://theremin.music.uiowa.edu/sound files/MIS/"
for f in ["Violin.arco.mf.sulG.G3B3", "Violin.arco.mf.sulG.B3B4", "Violin.arco.mf.sulG.C5G5",
          "Violin.arco.mf.sulD.D4A4", "Violin.arco.mf.sulD.Bb4C6",
          "Violin.arco.mf.sulA.A4B4", "Violin.arco.mf.sulA.C5C6",
          "Violin.arco.mf.sulE.E5B5", "Violin.arco.mf.sulE.C6Gb7"]:
    SOURCES.append((f"violin/{f}.aiff", UIOWA + f"Strings/violin/{f}.aiff"))
for f in ["Viola.arco.sulC.mf.C3B3", "Viola.arco.sulC.mf.C4B4", "Viola.arco.sulG.mf.G3B3", "Viola.arco.sulG.mf.C4B4",
          "Viola.arco.sulG.mf.C5G5", "Viola.arco.sulD.mf.D4B4", "Viola.arco.sulD.mf.C5B5",
          "Viola.arco.sulA.mf.A4B4", "Viola.arco.sulA.mf.C5B5"]:
    SOURCES.append((f"viola/{f}.aiff", UIOWA + f"Strings/viola/{f}.aiff"))
for f in ["Cello.arco.mf.sulC.C2Ab2", "Cello.arco.mf.sulC.A2Gb3", "Cello.arco.mf.sulC.C4Gb4",
          "Cello.arco.mf.sulG.G2Bb2", "Cello.arco.mf.sulG.B2A3", "Cello.arco.mf.sulG.Bb3Eb4",
          "Cello.arco.mf.sulD.D3B3", "Cello.arco.mf.sulD.C4Bb4",
          "Cello.arco.mf.sulA.A3B3", "Cello.arco.mf.sulA.C4C5"]:
    SOURCES.append((f"cello/{f}.aiff", UIOWA + f"Strings/cello/{f}.aiff"))
PIANO = ["C1","Eb1","Gb1","A1","C2","Eb2","Gb2","A2","C3","Eb3","Gb3","A3","C4","Eb4","Gb4","A4","C5","Eb5","Gb5","A5","C6","Eb6","Gb6","A6","C7"]
for n in PIANO:
    SOURCES.append((f"piano/Piano.mf.{n}.aiff", UIOWA + f"Piano_Other/piano/Piano.mf.{n}.aiff"))

# Freesound 上 zhankster 的尤克里里单音（CC0），取 hq 预览 mp3
FS = {"723355": "G4_open", "723354": "Gs4", "723348": "A4_onG", "723349": "A4_open", "723347": "As4",
      "723350": "B4", "723352": "C4_open", "723351": "C5_onG", "723353": "E4_open"}
FS_USER = "13209636"
for sid, name in FS.items():
    SOURCES.append((f"ukulele/{name}.mp3", f"https://cdn.freesound.org/previews/{sid[:3]}/{sid}_{FS_USER}-hq.mp3"))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--out", required=True)
    out = ap.parse_args().out
    fail = 0
    for rel, url in SOURCES:
        path = os.path.join(out, rel)
        if os.path.exists(path) and os.path.getsize(path) > 1000: continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        r = subprocess.run(["curl", "-sfL", "-m", "120", "-A", "Mozilla/5.0", "-o", path, urllib.parse.quote(url, safe=":/%")], capture_output=True)
        if r.returncode != 0 or not os.path.exists(path) or os.path.getsize(path) < 1000:
            print("失败:", rel, url); fail += 1
            if os.path.exists(path): os.remove(path)
    print("完成，失败", fail, "个")
    sys.exit(1 if fail else 0)

main()
