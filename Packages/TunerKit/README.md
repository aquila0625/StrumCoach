# TunerKit

「稳拍」的调音器模块：音高检测、乐器与定弦数据、参考音、SwiftUI 界面。独立的 Swift Package，iOS 17+ / macOS 14+，无第三方依赖。

- 检测算法：McLeod（MPM）——归一化平方差函数 + 峰值挑选 + 抛物线插值，用 Accelerate 加速；
- 乐器与定弦是纯数据（`Instrument` → `Tuning` → `InstrumentString`），以后的和弦库直接复用同一份；
- `TunerModel` 是 `@Observable`，管麦克风、权限、检测、弦匹配、参考音。

## 接入步骤

1. **加依赖**：Xcode 里 *Add Local Package…* 选 `Packages/TunerKit`，把 `TunerKit` 加到 App target。
2. **Info.plist 加麦克风说明**（缺了 App 一请求权限就会崩溃）：

   ```xml
   <key>NSMicrophoneUsageDescription</key>
   <string>调音器需要使用麦克风来听你弹奏的音高。</string>
   ```
   macOS 版还需要在 Sandbox 里勾选 *Audio Input*。
3. **放界面**：

   ```swift
   import TunerKit

   struct TunerTab: View {
       @State private var model = TunerModel(selection: savedSelection, a4: savedA4)
       @Environment(\.colorScheme) private var scheme

       var body: some View {
           TunerView(model: model,
                     palette: scheme == .dark ? .dark : .light,   // 或传自己的 TunerPalette
                     onSettings: { /* 打开设置页 */ })
       }
   }
   ```
   `TunerView` 出现时自动请求权限并开始监听，消失时停止（`autoStart: false` 可关闭，改由 App 自己调 `model.start()` / `model.stop()`）。标签栏不在里面，由 App 外壳负责。
4. **持久化**：`model.selection`（`Codable`，乐器 + 定弦）和 `model.a4` 由 App 自己存 UserDefaults。
5. **和节拍器共用音频会话**：默认会设置 `.playAndRecord`（iOS）。如果 App 自己统一管理 `AVAudioSession`，设 `model.configuresAudioSession = false`，并保证会话类别允许录音和播放。

## 对外接口

### 音高

| 类型 | 说明 |
| --- | --- |
| `Pitch` | 音高（MIDI 号），`Pitch("E2")`、`.name`（"A♯"）、`.octave`、`.fullName`、`.frequency(a4:)`。与 A4 无关 |
| `PitchReading` | 一次读数：`frequency`、`clarity`（0…1）、`pitch`（最近的半音）、`cents`（−50…+50）、`noteName`、`octave` |
| `PitchDetector` | `detect(_ samples: [Float], sampleRate:) -> RawPitch?`，静音/无音高返回 nil。不是线程安全的，每个队列一个实例 |
| `PitchSmoother` | 中值 + 指数平滑，单帧误判会被丢弃，信号消失时保持约 12 帧再清空 |
| `TunerDefaults` | `a4 = 440`、`a4Range = 415...466`、`inTuneCents = 5` |

分析窗口建议用 `PitchDetector.recommendedFrameLength(sampleRate:)`（约 4000 个采样），这样才能覆盖 5 弦贝斯的 B0。

### 乐器与定弦

```swift
InstrumentLibrary.all            // 自动、吉他、贝斯、尤克里里、小提琴、中提琴、大提琴
let guitar = InstrumentLibrary.guitar
guitar.tunings                   // 标准 / Drop D / 降半音 E♭ / DADGAD
let t = guitar.defaultTuning     // Tuning
t.strings                        // [InstrumentString]：index、number（6…1）、pitch
t.match(reading, lockedString: nil) -> TuningResult   // 自动选最近的弦；传弦 index 则按锁定的弦算偏差
```

- `strings` 按物理顺序排（最粗 → 最细），不保证音高递增（尤克里里高音 G 的第 1 根弦就比第 2 根高），匹配永远按真实音高算；
- `TuningResult`：`target`（目标音）、`stringIndex`、`cents`（相对目标，可能超过 ±50）、`targetFrequency`、`isInTune`（±5 音分）；
- `InstrumentSelection { instrumentID, tuningID }`：Codable，调音器和和弦库共用；`.resolve()` 取回对象，id 失效自动回退；
- **加新乐器/定弦**：在 `InstrumentLibrary.swift` 里加一条 `Tuning(id:name:englishName:notes: "E2 A2 D3 G3 B3 E4")`，界面自动出现。半音阶用空弦的 `Tuning` 表示（`isChromatic`）。

### TunerModel（`@MainActor @Observable`）

读：`permission`、`isRunning`、`reading`（实时，没信号为 nil）、`lastReading`、`result`（`TuningResult?`）、`tunedStrings`、`tunedEventCount`、`playingReference`、`instrument`、`tuning`、`a4`、`lockedString`、`selection`。

写：

```swift
await model.start();  model.stop()
model.select(instrument: .., tuning: ..) / model.select(selection) / model.select(tuning:)
model.lockString(i)            // 再点同一根解锁；nil 回到自动
model.setA4(442) / adjustA4(by: 1)    // 夹在 415…466，整数 Hz
model.toggleReference(Pitch("A4")!) / playReference / stopReference
model.referenceTimbre = .sine   // 或 .pluck（默认）
model.ingest(samples:sampleRate:)     // 不经麦克风直接喂数据（测试、预览）
model.inject(reading)                 // 直接指定读数（预览）
```

“调准打勾”：目标弦连续约 0.25 秒在 ±5 音分内即打勾，偏出 12 音分以上取消；换乐器或定弦会清空。播放参考音期间默认暂停检测。

### 界面

- `TunerView(model:palette:strings:autoStart:onSettings:)`：表盘（−50…+50，±5 绿色准音区）、音名与偏差、乐器 + 定弦菜单、一排弦按钮（高亮当前弦、调准打勾、点按锁定）、标准音 ±1 Hz、参考音键盘；
- `TunerPalette`：`.dark` / `.light` 与设计稿一致，也可自己构造：`background card card2 line text sub dim accent onAccent weak green`；
- `TunerStrings`：文字默认简体中文，`.en` 为英文，可自行构造接入多语言；
- 需要音频硬件的类可单独用：`MicrophoneInput`（AVAudioEngine 输入）、`ReferenceTonePlayer`（持续发声）、`ToneSynth`（纯合成，可测试）、`MicrophonePermission`。
- 预览：`TunerView_Previews` 里有深色、浅色两个预览。

## 调准提示（叮咚 + 打勾）

- **判定**（`TuneConfirmation`，纯逻辑）：目标音（弦；半音阶模式按识别到的音名+八度）的偏差**连续 0.5 秒**在 ±5 音分内才算调准；
  同一个音只提示一次，偏出 ±10 音分后再回到准音区才会再次提示；目标换了、信号丢了、出了准音区，计时都从头算。
- **提示**：`TunerModel` 在调准时 `tunedEventCount` +1、写 `lastTunedEvent`、弦加入 `tunedStrings`（偏出 10 音分取消），并播放“叮咚”（程序合成的两个钟琴音 E6→C6，约 0.85 秒，峰值 0.4）。
  提示音播放期间和结束后 0.6 秒（`chimeGuardSeconds`）内忽略麦克风检测结果，免得把提示音当成琴弦。
- **界面**：弦按钮上的对勾带弹出缩放 + 描边绘制动画，“已准”文字轻微放大并闪一下绿色底，同时一次轻触感反馈；系统“减少动态效果”打开时只淡入、不缩放不描边。
- **开关**：`model.tuneChimeEnabled`（默认开，存在 UserDefaults 的 `TunerKit.tuneChimeEnabled`）。`TunerView` 右上角的设置按钮：App 传了 `onSettings` 就交给 App，
  App 自己的设置页里放 `TunerChimeToggle(model:palette:)` 即可；没传 `onSettings` 时按钮会弹出包自带的小面板（里面就是这个开关）。
- 时间来源 `model.clock` 可替换，单元测试里用假时钟精确推进（`TuneChimeModelTests`）。

## 乐器声音（真实采样）

参考音和 ChordKit 的和弦试听用的是**真实乐器录音**：吉他（钢弦原声）、贝斯、尤克里里、小提琴、中提琴、大提琴，「自动」模式用钢琴。
采样放在 `Sources/TunerKit/Samples/`（AAC/CAF + `manifest.json`，合计约 5.5 MB），来源与授权见 [`Sounds/LICENSES.md`](Sounds/LICENSES.md)。

- `SampleBank.shared`：解码并缓存采样；`sample(for:nearestTo:)` 取离目标频率最近的那一段（每 1–3 个半音一个音）。
- `SamplePlayback`：把采样重采样（四点 Hermite）到精确的目标频率，包括 A4 改成 415–466 Hz 的情况；
  拉弦采样在循环区间无缝循环（可一直发声），拨弦采样自然衰减 3–4 秒后结束（`ReferenceTonePlayer.onEnded` 通知界面）。
- 每段采样入库前都测过真实基频并把起音/衰减的音高漂移拉平，所以任何音高发出来都能过 ±1 音分的检测（见 `SampleBankTests`）。
- `InstrumentTone.render(...)` 默认走采样；采样库里没有这件乐器、或传 `useSamples: false` 时回退到原来的物理建模合成。
- 重新生成采样：`Sounds/tools/fetch_sources.py` 下载原始录音，`Sounds/tools/process_samples.py` 处理（需要 numpy、scipy、ffmpeg、afconvert）。

## 测试

```bash
cd Packages/TunerKit && swift test
```

覆盖：检测精度（82.41…440 Hz 正弦，44.1/48 kHz，误差 ≤ ±1 音分）、锯齿波与弱基频信号无八度误判、白噪声下识别、静音/纯噪声不输出音高、B0 低音、平滑器、乐器数据与弦匹配（含回弦尤克里里、锁定、A4 偏移）、参考音合成的音准、真实采样的音准（每件乐器整个音域 × A4=415/440/466）与无缝循环、模型行为（打勾、锁定、静音清空）、深浅主题渲染。设环境变量 `TUNERKIT_SNAPSHOT_DIR=<目录>` 会把渲染截图写出来。

## 已知限制

- 单帧检测在 12 dB 信噪比的噪声里只保证识别对音（偏差 < 15 音分），±1 音分的精度靠多帧平滑；
- 只处理单音。和弦（多根弦同时响）不会给出可靠读数；
- 手机喇叭、小音箱放出的低音可能没有基频，只有泛音，会被识别成高八度；
- 麦克风灵敏度、回声消除未在真机上调校（静音门限 RMS 0.003 是估计值，需真机微调 `PitchDetector.Configuration`）；
- 参考音和麦克风同时工作时，默认暂停检测，不支持边放参考音边检测；
- 尤克里里只有 C4、E4、G4–B4 共 7 个单音的录音，离它们远的音（尤其是低音 G 定弦的 G3 和 A5 以上）靠变速得到，音色不如其他乐器自然；
- 小提琴、中提琴、大提琴的循环段是单一的无颤音长音（已做低通让声音柔和一点），没有揉弦；钢琴最低几个音（A0–D1 附近）因为泛音不和谐，检测器可能认不出；
- 爱荷华大学录音的授权措辞是“可用于任何项目，没有限制”，上架前建议邮件确认（见 LICENSES.md）；
- 麦克风 / 音频会话中断（来电、耳机拔插）的恢复尚未处理。
