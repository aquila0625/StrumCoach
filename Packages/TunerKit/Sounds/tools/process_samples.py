#!/usr/bin/env python3
"""把原始采样处理成 TunerKit 内置的压缩采样（AAC/CAF）和 manifest.json。

流程：切分音符 → 测真实基频 → 裁掉起音前的静音 → 拨弦淡出 / 拉弦找无缝循环点 → 归一化响度 → afconvert 压缩。
用法: python3 process_samples.py --raw /path/to/raw --out ../../Sources/TunerKit/Samples
需要 numpy、scipy、ffmpeg、afconvert（macOS 自带）。
"""
import argparse, json, os, re, subprocess, tempfile
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

SR = 44100
NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def parse_note(s):
    m = re.fullmatch(r"([A-Ga-g])([b#]?)(\d)", s)
    pc = NOTE_NAMES[m.group(1).upper()] + {"": 0, "b": -1, "#": 1}[m.group(2)]
    return (int(m.group(3)) + 1) * 12 + pc


def load(path):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).astype(np.float64)


def nsdf(x):
    n = len(x)
    f = np.fft.rfft(x, 2 * n)
    r = np.fft.irfft(f * np.conj(f))[:n]
    cs = np.cumsum(x * x)
    tau = np.arange(n)
    m = cs[n - 1 - tau] + (cs[n - 1] - np.concatenate(([0.0], cs[:-1]))[tau])
    return 2 * r / np.maximum(m, 1e-12)


def refine(y, k):
    a, b, c = y[k - 1], y[k], y[k + 1]
    d = a - 2 * b + c
    sh = 0.5 * (a - c) / d if abs(d) > 1e-15 else 0.0
    return k + sh, b - 0.25 * (a - c) * sh


def f0_near(x, guess, span=0.08):
    """在 guess（Hz）附近找基频，返回 (f0, 清晰度)。"""
    y = nsdf(x)
    lo = max(2, int(SR / guess / (1 + span)))
    hi = min(len(y) // 2, int(SR / guess * (1 + span)) + 1)
    k = lo + int(np.argmax(y[lo:hi]))
    lag, val = refine(y, k)
    return SR / lag, val


def f0_blind(x):
    """没有参考音高时：取第一个不低于最高峰 0.9 倍的峰（MPM）。"""
    y = nsdf(x)
    lo, hi = int(SR / 2200), min(int(SR / 28), len(y) // 2)
    i = 1
    while i < hi and y[i] > 0:
        i += 1
    peaks, best = [], 0
    while i < hi:
        while i < hi and y[i] <= 0:
            i += 1
        if i >= hi:
            break
        j = i
        while i < hi and y[i] > 0:
            if y[i] > y[j]:
                j = i
            i += 1
        if j >= lo and 0 < j < len(y) - 1:
            peaks.append(j); best = max(best, y[j])
    for j in peaks:
        if y[j] >= 0.9 * best:
            lag, _ = refine(y, j)
            return SR / lag
    return None



from scipy.interpolate import CubicSpline
from scipy.ndimage import median_filter, gaussian_filter1d


def f0_track(x, guess, hop=512):
    """逐帧测基频：返回 (帧中心采样序号, f0)，不可靠的帧为 nan。"""
    win = max(4096, int(5 * SR / guess))
    peak = float(np.max(np.abs(x))) + 1e-12
    centers, vals = [], []
    for i in range(0, len(x) - win, hop):
        seg = x[i:i + win]
        if rms(seg) < 0.01 * peak:
            f = np.nan
        else:
            f, cl = f0_near(seg, guess, span=0.05)
            if cl < 0.8:
                f = np.nan
        centers.append(i + win // 2)
        vals.append(f)
    return np.array(centers), np.array(vals)


def flatten_pitch(x, guess, ref_range):
    """把采样里的音高漂移（起音的音高滑动、拨弦衰减时的变调、揉弦）用变速重采样拉平，
    使整段音高恒定等于 ref_range（采样序号区间）里的中位音高。返回 (拉平后的采样, 参考基频)。"""
    centers, vals = f0_track(x, guess)
    ok = ~np.isnan(vals)
    if ok.sum() < 4:
        return x, None
    vals = np.interp(centers, centers[ok], vals[ok])
    vals = gaussian_filter1d(median_filter(vals, size=5, mode="nearest"), 1.5, mode="nearest")
    a, b = ref_range
    sel = (centers >= a) & (centers <= b)
    ref = float(np.median(vals[sel])) if sel.any() else float(np.median(vals))
    # 音高在 [第一个到最后一个可靠帧] 之外保持不变速
    track = np.interp(np.arange(len(x)), centers, vals, left=vals[0], right=vals[-1])
    speed = ref / track            # 音高偏高就放慢一点
    pos, p = [], 0.0
    n = len(x) - 1
    while p < n - 1:
        pos.append(p)
        p += speed[int(p)]
    pos = np.array(pos)
    y = CubicSpline(np.arange(len(x)), x)(pos)
    return y, ref


def midi_of(f):
    return int(round(69 + 12 * np.log2(f / 440.0)))


def named_midi(fn, offset):
    """Karoryfer 的文件名 'gb3' → midi。吉他按 C4=60（offset=1），贝斯文件名比标准低两个八度（offset=0）。"""
    m = re.match(r"([a-g])(b?)(\d)", fn)
    pc = NOTE_NAMES[m.group(1).upper()] - (1 if m.group(2) else 0)
    return (int(m.group(3)) + offset) * 12 + pc


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def envelope(x, win=441):
    p = np.convolve(x * x, np.ones(win) / win, mode="same")
    return np.sqrt(p)


def segment_run(x, gap=0.12, min_len=0.5, floor_db=-27):
    """把一整段半音阶练习切成单个音符 [(start, end)]。"""
    env = envelope(x)
    thr = env.max() * 10 ** (floor_db / 20)
    on = env > thr
    idx = np.flatnonzero(np.diff(on.astype(np.int8)))
    edges = ([0] if on[0] else []) + list(idx + 1) + ([len(x)] if on[-1] else [])
    regs = list(zip(edges[0::2], edges[1::2]))
    merged = []
    for s, e in regs:
        if merged and s - merged[-1][1] < gap * SR:
            merged[-1] = (merged[-1][0], e)
        else:
            merged.append((s, e))
    return [(s, e) for s, e in merged if e - s > min_len * SR]


def onset_of(x, frac=0.1):
    env = envelope(x, 221)
    k = int(np.argmax(env > env.max() * frac))
    return max(0, k - int(0.012 * SR))


def fade(n, kind):
    t = np.linspace(0, 1, n)
    return 0.5 - 0.5 * np.cos(np.pi * t) if kind == "in" else 0.5 + 0.5 * np.cos(np.pi * t)


def rms(x):
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def finish_plucked(x, midi, max_sec, tail_sec=0.6):
    s = onset_of(x, 0.05)
    x = x[s:s + int((max_sec + 0.5) * SR)].copy()
    x, ref = flatten_pitch(x, hz(midi), (int(0.15 * SR), int(1.0 * SR)))
    x = x[: int(max_sec * SR)]
    n = int(tail_sec * SR)
    x[-n:] *= fade(n, "out")
    x[: int(0.004 * SR)] *= fade(int(0.004 * SR), "in")
    # 拉平后再量一遍（起音后 0.2–0.7 s），作为这段采样的基频
    a, b = int(0.2 * SR), min(len(x), int(0.7 * SR))
    f0, clarity = f0_near(x[a:b], ref or hz(midi))
    return x, f0, clarity, None, rms(x[: int(0.5 * SR)])


# 爱荷华的录音在消声室里完成，没有琴体/房间的“暖”，直接听偏尖。拉弦类整体柔和一点：二阶低通（零相位，不改音高和相位）。
SOFTEN_HZ = {"violin": 4200, "viola": 4800, "cello": 6500}


def finish_bowed(x, midi, soften_hz=None):
    """拉弦音：去掉慢得过分的渐强和释放段，在平稳段里找一个波形吻合的循环 [ls, le)，并在末尾做交叉淡化。
    midi 可以是带小数的实测音高；f0 与循环都按它的周期算。"""
    if soften_hz:
        x = sosfiltfilt(butter(2, soften_hz, btype="low", fs=SR, output="sos"), x)
    env = envelope(x, 2205)                     # 50 ms RMS
    smooth = np.convolve(env, np.ones(4410) / 4410, mode="same")
    peak = float(smooth.max())
    for ratio in (0.85, 0.75, 0.65):
        plateau = np.flatnonzero(smooth >= ratio * peak)
        if plateau[-1] - plateau[0] > 0.75 * SR:
            break
    # 先把音高拉平：参考音高取平稳段的中位数（起音的音高滑动、揉弦都被抹掉）
    x, ref = flatten_pitch(x, hz(midi), (int(plateau[0]), int(plateau[-1])))
    if ref:
        midi = 69 + 12 * np.log2(ref / 440.0)
    env = envelope(x, 2205)
    smooth = np.convolve(env, np.ones(4410) / 4410, mode="same")
    peak = float(smooth.max())
    for ratio in (0.85, 0.75, 0.65):
        plateau = np.flatnonzero(smooth >= ratio * peak)
        ps, pe = int(plateau[0]), int(plateau[-1])
        if pe - ps > 0.75 * SR:
            break
    start = int(np.argmax(env >= 0.35 * peak))
    start = max(0, min(start, ps) - int(0.01 * SR))
    ps = max(ps, start + int(0.15 * SR))
    if pe - ps < 0.5 * SR:
        raise RuntimeError(f"平稳段太短（{(pe - ps) / SR:.2f}s），无法循环")
    x = x[start:]
    ps -= start; pe -= start
    T = SR / hz(midi)
    W = int(max(6 * T, 0.06 * SR))
    xfade = int(min(max(8 * T, 0.10 * SR), 0.18 * SR, 0.45 * (pe - ps)))
    want = min(int(1.2 * SR), pe - ps - xfade)
    best = None
    tried = 0
    for ls in range(ps + xfade, min(pe - int(0.3 * SR), ps + xfade + int(0.35 * SR))):
        if not (x[ls - 1] <= 0 < x[ls]):
            continue
        tried += 1
        if tried > 60:
            break
        a_win = x[ls - W: ls + W]
        lo_e = ls + max(int(0.3 * SR), want - int(0.3 * SR))
        hi_e = min(pe, len(x) - W - 1, ls + want + int(0.2 * SR))
        if hi_e <= lo_e:
            continue
        seg = x[lo_e - W: hi_e + W]
        corr = np.correlate(seg, a_win, mode="valid")[: hi_e - lo_e + 1]
        e_b = np.cumsum(np.concatenate(([0.0], seg * seg)))
        eb = e_b[2 * W: 2 * W + len(corr)] - e_b[: len(corr)]
        ea = np.sum(a_win * a_win) + 1e-12
        err = (ea + eb - 2 * corr) / ea
        k = int(np.argmin(err))
        if best is None or err[k] < best[0]:
            best = (float(err[k]), ls, lo_e + k)
    if best is None:
        raise RuntimeError("找不到循环点")
    err, ls, le = best
    xf = min(xfade, ls)
    b = x[:le].copy()
    for i in range(xf):
        w = (i + 1) / xf
        b[le - xf + i] = (1 - w) * b[le - xf + i] + w * b[ls - xf + i]
    n_in = int(0.03 * SR)
    b[:n_in] *= fade(n_in, "in")
    f0, clarity = f0_near(x[ls:le], hz(midi), span=0.06)
    return b, f0, clarity, (ls, le), rms(b[ls:le]), err


def write_caf(x, path, bitrate):
    x = np.clip(x, -1, 1)
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, "t.wav")
        wavfile.write(wav, SR, (x * 32767).astype(np.int16))
        subprocess.run(["afconvert", wav, path, "-f", "caff", "-d", f"aac@{SR}", "-b", str(bitrate), "-q", "127", "-s", "0"],
                       check=True, capture_output=True)


# ---------- 各乐器的素材清单 ----------
OPEN = {"violin": [55, 62, 69, 76], "viola": [48, 55, 62, 69], "cello": [36, 43, 50, 57]}
BOWED_RANGE = {"violin": (55, 84), "viola": (48, 77), "cello": (36, 65)}
SUL = {"G": 0, "D": 1, "A": 2, "E": 3, "C": 0}


def string_open(voice, sul):
    opens = OPEN[voice]
    if voice in ("viola", "cello"):
        order = ["C", "G", "D", "A"]
    else:
        order = ["G", "D", "A", "E"]
    return opens[order.index(sul)]


def collect_bowed(voice, raw):
    """切出 Iowa 半音阶/四分音练习里的每个音，测实际音高，为每个半音挑一个最接近的（偏差不超过半个半音）。"""
    lo, hi = BOWED_RANGE[voice]
    segs = []   # (midi_float, open_pitch_of_string, audio, name)
    d = os.path.join(raw, voice)
    for fn in sorted(os.listdir(d)):
        m = re.search(r"sul([CGDAE])", fn)
        if not m or not fn.endswith(".aiff"):
            continue
        x = load(os.path.join(d, fn))
        op = string_open(voice, m.group(1))
        for s, e in segment_run(x):
            mids = []
            for fr in (0.3, 0.5, 0.7):
                a = s + int(fr * (e - s))
                f = f0_blind(x[a:a + 8192])
                if f:
                    mids.append(69 + 12 * np.log2(f / 440.0))
            if len(mids) < 3 or max(mids) - min(mids) > 0.35:
                print(f"  丢弃 {fn} @{s / SR:.1f}s：音高不稳 {mids}")
                continue
            mf = float(np.median(mids))
            if lo - 0.5 <= mf <= hi + 0.5:
                segs.append((mf, op, x[s:e], fn))
    chosen = {}
    for midi in range(lo, hi + 1):
        best = None
        for mf, op, audio, fn in segs:
            dev = abs(mf - midi)
            if dev > 0.5:
                continue
            score = dev * 100 + (0 if op <= midi and midi - op <= 14 else 40)
            if best is None or score < best[0]:
                best = (score, mf, audio, fn)
        if best:
            chosen[midi] = (best[2], best[3], best[1])
        else:
            print(f"  警告 {voice} 缺 midi {midi}")
    return chosen


def process_voice(voice, items, out, kind, bitrate, max_sec=None, tail=0.6, target_rms=0.12):
    """items: {midi: (audio, srcname)}"""
    entries = []
    for midi in sorted(items):
        audio, src = items[midi][0], items[midi][1]
        guess = items[midi][2] if len(items[midi]) > 2 else midi
        try:
            if kind == "bowed":
                x, f0, cl, loop, level, err = finish_bowed(audio, guess, SOFTEN_HZ.get(voice))
            else:
                x, f0, cl, loop, level = finish_plucked(audio, midi, max_sec, tail)
                err = None
        except RuntimeError as e:
            print(f"  跳过 {voice} {midi} ({src}): {e}")
            continue
        if err is not None and err > 0.5:
            print(f"  跳过 {voice} {midi}: 循环接缝不够吻合（误差 {err:.2f}），运行时由相邻音变速代替")
            continue
        gain = target_rms / max(level, 1e-6)
        peak = np.max(np.abs(x)) * gain
        if peak > 0.95:
            gain *= 0.95 / peak
        x = x * gain
        cents = 1200 * np.log2(f0 / hz(midi))   # 相对整数半音的偏差（真人演奏不是平均律）
        name = f"{voice}/{voice}_{midi}.caf"
        os.makedirs(os.path.join(out, voice), exist_ok=True)
        write_caf(x, os.path.join(out, name), bitrate)
        e = {"file": name, "midi": midi, "f0": round(float(f0), 4), "frames": int(len(x))}
        if loop:
            e["loopStart"], e["loopEnd"] = int(loop[0]), int(loop[1])
        entries.append(e)
        extra = f" 循环误差 {err:.4f}" if err is not None else ""
        print(f"  {voice:7s} midi {midi:3d}  f0 {f0:8.3f} Hz  偏 {cents:+6.1f} 音分  清晰度 {cl:.3f}  {len(x) / SR:4.1f}s{extra}")
    return {"sampleRate": SR, "samples": entries}


UKE_MIDI = {"G4_open": 67, "Gs4": 68, "A4_open": 69, "As4": 70, "B4": 71, "C4_open": 60, "E4_open": 64}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    raw, out = a.raw, a.out
    os.makedirs(out, exist_ok=True)
    manifest = {"version": 1, "voices": {}}

    # 吉他（Karoryfer Shinyguitar，文件名 note = 琴键名，音高以实测为准）
    items = {}
    for fn in sorted(os.listdir(os.path.join(raw, "guitar"))):
        x = load(os.path.join(raw, "guitar", fn))
        s = onset_of(x, 0.05)
        f = f0_blind(x[s + int(0.1 * SR): s + int(0.1 * SR) + 16384])
        nm = named_midi(fn, 1)
        if f is None or abs(midi_of(f) - nm) > 1:
            print(f"  警告 吉他 {fn}: 文件名 {nm}，实测 {midi_of(f) if f else None}，按文件名")
        items[nm] = (x, fn)
    manifest["voices"]["guitar"] = process_voice("guitar", items, out, "plucked", 96000, max_sec=3.8)

    items = {}
    for fn in sorted(os.listdir(os.path.join(raw, "bass"))):
        x = load(os.path.join(raw, "bass", fn))
        s = onset_of(x, 0.05)
        f = f0_blind(x[s + int(0.15 * SR): s + int(0.15 * SR) + 32768])
        nm = named_midi(fn, 0)
        if f is None or abs(midi_of(f) - nm) > 1:
            print(f"  警告 贝斯 {fn}: 文件名 {nm}，实测 {midi_of(f) if f else None}，按文件名")
        items[nm] = (x, fn)
    manifest["voices"]["bass"] = process_voice("bass", items, out, "plucked", 96000, max_sec=4.0)

    items = {}
    for fn in sorted(os.listdir(os.path.join(raw, "ukulele"))):
        x = load(os.path.join(raw, "ukulele", fn))
        if fn.startswith(("A4_onG", "C5_onG")):
            continue   # A4_onG 与 A4_open 重复；C5_onG 实测是 B4（标注有误），都不用
        s = onset_of(x, 0.05)
        f = f0_blind(x[s + int(0.08 * SR): s + int(0.08 * SR) + 16384])
        nm = UKE_MIDI[fn.split(".")[0]]
        if f is None or abs(midi_of(f) - nm) > 1:
            print(f"  警告 尤克里里 {fn}: 文件名 {nm}，实测 {midi_of(f) if f else None}，按文件名")
        items[nm] = (x, fn)
    manifest["voices"]["ukulele"] = process_voice("ukulele", items, out, "plucked", 96000, max_sec=3.4, tail=0.5)

    items = {}
    for fn in sorted(os.listdir(os.path.join(raw, "piano"))):
        m = re.search(r"\.([A-G][b#]?\d)\.aiff$", fn)
        items[parse_note(m.group(1))] = (load(os.path.join(raw, "piano", fn)), fn)
    manifest["voices"]["piano"] = process_voice("piano", items, out, "plucked", 96000, max_sec=4.0)

    for voice in ("violin", "viola", "cello"):
        manifest["voices"][voice] = process_voice(voice, collect_bowed(voice, raw), out, "bowed", 96000)

    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    total = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(out) for f in fs)
    print(f"合计 {total / 1e6:.2f} MB")


main()
