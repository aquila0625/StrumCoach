# ChordKit

「稳拍」的和弦库模块：和弦乐理、吉他/尤克里里指法自动生成、贝斯和弦音位置、Karplus-Strong 试听、SwiftUI 界面（设计稿画面 05）。独立的 Swift Package，iOS 17+ / macOS 14+，无第三方依赖；乐器与定弦直接复用 `../TunerKit`（本地路径依赖，未改动 TunerKit）。

- 指法**全部由乐理自动生成**，再叠加一份人工校对的标准按法；没有照搬任何 App/网站的和弦图或数据，也不含任何歌曲的歌词或和弦谱。
- 预览：`preview.png`（吉他和尤克里里各 6 个常用和弦的第 1 个把位）。重新导出：

  ```bash
  CHORDKIT_PREVIEW_PATH=$PWD/preview.png swift test --filter ViewRenderTests
  ```
  另设 `CHORDKIT_SNAPSHOT_DIR=<目录>` 会把整页界面（深/浅、吉他/贝斯/尤克里里）截成 PNG。

## 接入步骤

1. **加依赖**：Xcode 里 *Add Local Package…* 选 `Packages/ChordKit`（它会连带用到 TunerKit，两个包都要在工程里），把 `ChordKit` 加到 App target。
2. **放界面**：

   ```swift
   import ChordKit

   struct ChordTab: View {
       @State private var model = ChordLibraryModel(current: savedPosition,      // ChordFavorite?，可为 nil
                                                    leftHanded: settings.leftHanded,
                                                    favorites: savedFavorites)   // ChordFavorites
       @Environment(\.colorScheme) private var scheme

       var body: some View {
           ChordLibraryView(model: model, palette: scheme == .dark ? .dark : .light)
               .onAppear {
                   model.onFavoritesChange = { save($0) }                    // 收藏变化时存盘
               }
       }
   }
   ```
   标签栏不在里面，由 App 外壳负责。已有 `TunerPalette` 时可以 `ChordPalette(tunerPalette)` 直接转换，调音器和和弦库用同一套颜色。
3. **持久化**（App 负责）：`model.current`（`ChordFavorite`，Codable，退出时存、启动时传回 `init(current:)`）、`model.favorites`（`ChordFavorites`，编码成 JSON 数组）、`model.leftHanded`。
4. **音频会话**：试听用 `AVAudioEngine`，默认在 iOS 上设 `.playAndRecord`（与 TunerKit 的参考音一致）。App 统一管理会话时设 `model.configuresAudioSession = false`（单独用 `ChordPlayer` 时同名属性）。离开界面时 `ChordLibraryView` 会自动停止试听。

## 对外接口

### 乐理

```swift
ChordRoot.names                          // C C# D … B（升号写法）
let c = Chord("C", .major7)!             // 也可 Chord(root: 0, type: .major7)
c.name        // "Cmaj7"
c.toneNames   // ["C", "E", "G", "B"]
c.pitchClasses
ChordType.builtins                       // 大三 小三 7 maj7 m7 sus2 sus4 dim aug add9（界面顺序）
```

**加新和弦类型**（例如 `m6`、`9`）：在 `ChordType.builtins` 里加一条 `ChordType(id:symbol:shortName:name:englishName:intervals:degrees:optionalIntervals:)`，`id` 一经发布不要再改（会存进收藏）。指法生成、组成音、界面网格都按数据工作。四音以上的类型建议把五度写进 `optionalIntervals`，这样尤克里里（只有 4 根弦）也能凑出按法。

### 指法

```swift
let list = ChordLibrary.voicings(for: c, instrument: InstrumentLibrary.guitar)   // 吉他 / 尤克里里；贝斯和其他乐器返回 []
let v = list[0]
v.frets        // [-1, 3, 2, 0, 0, 0]  -1 不弹，0 空弦（按定弦的物理顺序，吉他 6 弦在前）
v.fingers      // [0, 3, 2, 0, 0, 0]   1 食指 … 4 小指；横按覆盖的弦为 1
v.barre        // 横按：fret / fromString / toString / finger，没有则为 nil
v.baseFret     // 指法图第一行对应的品位（5 品以内为 1，画琴枕；否则为最低按弦品位）
v.noteNames    // ["", "C", "E", "G", "B", "E"] 每根弦发出的音名
v.pitches      // [Pitch?]
v.shorthand    // "x32010"
v.isOpenPosition, v.minFret, v.span, v.fingerCount, v.mutedCount
```

可以传 `tuning:` 用 Drop D、DADGAD、低音 G 尤克里里等其他定弦（走同一套生成规则，没有人工校对表）。每个和弦最多 `ChordLibrary.maxVoicings`（8）个把位，结果有缓存。

**生成规则**（`VoicingGenerator.makeVoicing` 逐条检查）：发声的弦都是和弦音；必须有根音；组成音全有（七和弦及 add9 的纯五度可省）；按弦跨度 ≤ 4 品；最多 4 根手指，允许 1 指横按（横按范围内不能有空弦/不弹的弦）；不弹的弦只在两端；吉他至少 4 根弦、尤克里里至少 3 根弦发声；带空弦的按法最高不超过 4 品；指板 12 品以内。

**排序**：人工校对的标准按法排最前，之后按 ① 最低音是根音（仅吉他）② 完整的在省略五度的前面 ③ 开放把位优先 ④ 位置低优先 ⑤ 不弹的弦少优先 ⑥ 用手指少优先 ⑦ 品位和小优先。同一最低品位最多留 2 个，让结果沿指板分布。

**人工校对表**：`Sources/ChordKit/Voicing/CuratedShapes.swift`，用 `x32010` 这样的写法，手指编号由程序算。目前覆盖吉他和尤克里里常用和弦（大三、小三、7、maj7、m7 等）；测试会保证每一条都合格、且排在最前。要加标准按法，在表里加一行即可。

### 贝斯

```swift
let p = BassPositions.make(chord: c, tuning: InstrumentLibrary.bass.defaultTuning)!   // 4 弦或 5 弦
p.markers      // [Marker]：string / fret / role(.root .third .fifth .octave) / pitch / label("R" "♭3" "5" "8")
p.startFret, p.firstRow, p.fretCount (5), p.showsNut, p.anchor
```
参照根音取品位最低、且高八度的根音也落在框内的那一个；框从它前一品起，共 5 格；根音是空弦时框含空弦。

### 试听

```swift
KarplusStrong(frequency: 220).render(duration: 1)          // 纯计算，可离线渲染
ChordStrummer.render(frequencies:)                          // 按弦序扫一遍
ChordPlayer().play(v)                                       // AVAudioEngine 播放（@MainActor）
```
扫弦顺序是定弦的物理顺序（向下扫弦）：吉他从低音弦到高音弦；尤克里里 G C E A，第一根弦是高音 G。不弹的弦跳过。

声音用 TunerKit 内置的**真实乐器采样**（见 `../TunerKit/Sounds/LICENSES.md`），没有采样才回退到合成：
- 吉他、尤克里里：指法图上实际发声的每根弦各用一个采样，相邻两根弦间隔约 32 毫秒（`ChordStrummer.defaultGap`，带 ±12% 的确定性抖动），低音弦稍重、高音弦稍轻，余音自然衰减约 3 秒；
- 贝斯：`ChordPlayer.play(pitches:)` 在 `voice == .bass` 时只弹第一个音（根音，`bassPlaysRootOnly`）；
- 扫弦间隔固定用 `ChordPlayer.voicingStrumGap`，`strumGap` 只管琶音。

### 扫弦与分解和弦

试听按钮上方有“扫弦 | 分解”两个模式（`model.playMode`，会记在 UserDefaults）。贝斯只有分解（根音、五度、八度、五度，用该和弦的根音和五度，减三和弦是减五度、增三和弦是增五度）。

- **扫弦**：按物理弦序依次拨一遍，播一遍就停。
- **分解**：按选中的指法一个音一个音弹，**循环到再点一次停止**。每个音是一个八分音符，速度用 `model.bpm`（App 传节拍器的 BPM；没有就按 100，即每个音 0.3 秒）。点“分解”旁的列表按钮弹出选择面板（`ArpeggioPickerPanel`，iPhone 上是小弹窗），选中的会记住（`model.arpeggioPattern`，每种乐器各记各的）。
- **指法写法**（`ArpeggioPattern.all`，要加指法在这里加一条，说明文字进 String Catalog）：用弦号写，吉他 6 弦最粗、1 弦最细，**5 代表根音弦**，运行时换成当前把位的根音弦（C = 5 弦、D = 4 弦、G = 6 弦；`model.rootStringNumber`）。当前把位里不弹的弦，这一拍休止（节奏不变）。

  | 乐器 | 指法 |
  | --- | --- |
  | 吉他 | 5-3-2-1 · 四拍上行；5-3-2-3-1-3-2-3 · 八分音符分解；5-3-2-3-1-3 · 三拍子分解；5-2-3-1-3-2 · 交替八分；上行 + 下行琶音（根音弦依次到 1 弦再回来） |
  | 尤克里里 | 4-3-2-1 · 四弦上行；4-3-2-1-2-3 · 来回分解；3-2-1-2 · 常见指弹 |
  | 贝斯 | 根音 · 五度 · 八度 · 五度 |

- **动画**：弹到哪根弦，指法图上那根弦高亮并做一个短促的横向抖动（振幅随时间指数衰减，约 0.7 秒淡出），按到的圆点（贝斯是标记）闪一下；扫弦时按顺序依次亮。系统开了“减少动态效果”时只高亮不抖动。左手模式下镜像方向正确。
- **和声音同步**：声音和动画共用一份事件表 `ChordPlayback`（`PluckEvent` 的时间就是它在音频缓冲里的位置）。`ChordPlayer` 把整段渲染好交给 `AVAudioPlayerNode` 按采样时钟播放（分解用 `.loops` 无缝循环，超出周期的余音绕回开头），指法图每一帧读 `ChordPlayer.pluckAges()`（节点的渲染时钟减去输出延迟，再交给 `PluckClock` 换算），不靠定时器估计。单独用图时给 `ChordDiagramView(pluck:)` / `BassDiagramView(pluck:)` 传一个每帧返回 `[键: 距上次拨到的秒数]` 的闭包即可。

### 演奏：循环、排队换和弦、点弦发声

点播放后**一直循环，只有再点一次停止**才停（切换乐器、离开和弦库页面、App 进后台时也会停）。

- **循环**：扫弦模式一个循环是一小节 4 拍，每拍下扫一次，第 1 拍重音；分解模式一个循环是选中的指法走完一遍。速度用 `model.bpm`（没有时 100；扫弦一拍是四分音符，分解每个音是八分音符）。
- **无缝衔接**：`ChordPerformer` 把一个接一个的循环按**采样时钟**首尾相接地排好（`LoopTimeline`：每个循环的起点是前一个的整数终点，终点按累计的理想时长取整，误差永远不超过半个采样，不漂移），用多个播放节点轮流承担，上一个循环的余音自然延续进下一个循环。下一个循环在上一个结束前约 0.15 秒才向模型要内容。
- **排队换和弦**：演奏中点另一个根音或类型（或收藏、或翻把位），**不立即切换**，而是在当前循环结束、下一个循环开始时切过去；连续点多次以最后一次为准；点回当前和弦等于取消。排队期间标题旁小字显示“下一个：Dm”（只换把位时是“下一个：C · 3”），对应的根音 / 类型按钮描边闪动（开了“减少动态效果”是静态描边）；真正听到新循环的那一刻，界面才切过去，指法图带过渡动画。已经排队了换和弦时翻把位不生效（卡片弹回）。没在演奏时点和弦，立即切换。模式、分解指法、BPM 的改动也是下一个循环开始生效。
  - 模型接口：`queued`、`queuedChord`、`queuedRoot`、`queuedType`、`queuedVoicingIndex`、`targetVoicingIndex`、`hasQueuedChange`；切换时机的精度是“循环结束前 0.15 秒之后点的算下下个循环”。
- **点弦发声**：指法图上每根弦是一条贯穿整张图的竖条触控区（宽一个弦距），点哪里都算；发这根弦在当前按法上的音（`model.pluckString(_:voicingIndex:)`，音高见 `pluckPitch(forString:)`），叠加在伴奏上，暂停时和演奏中都可以点；那根弦做和分解和弦一样的高亮抖动。贝斯点标记发它的音（`pluckBass(_:)`），点弦的空白处发这根弦上离点击位置最近的那个标记。
  - **不弹的弦（×）不发声**：和弦里本来就不弹它，点它发空弦音会混进和弦外的音；点了只让 × 轻轻抖一下表示收到了。
- **读屏**：每根弦是单独的读屏元素，读“第 3 弦，G”，双击发声（不弹的弦读“3 弦不弹”）；把位卡片的上一个 / 下一个有名字，也可以用读屏的自定义操作换把位。
- 单独用图时：`ChordDiagramView(… onPluck: { string in … })`、`BassDiagramView(… onPluck: { marker in … })`；动画键 `pluck:` 的约定见接口注释（× 弦被点是 1000 + 弦序号）。

### 速度

播放按钮下方、扫弦 / 分解切换那一行的右边有速度按钮（节拍器图标 + 当前 BPM），点开是速度弹窗：大号 BPM、− / +（点按 ±1，按住 0.45 秒后连续变化、越按越快）、滑块（30–200）、“跟随节拍器”开关。一行放不下时（iPhone SE 这样的窄屏）自动换排：先把指法 / 节奏型名挪到第二行，还不行就让速度按钮和名称同一行；所以控件始终可见，不会挤出屏幕。

- **和弦库自己的速度**：`model.tempo`（默认 70，范围 30–200，取整），`setTempo(_:)`、`adjustTempo(by:)`；**跟随节拍器**：`model.followsMetronome`（默认关闭），`setFollowsMetronome(_:)`，打开时用 App 传进来的 `model.bpm`（夹在 30–300；App 没传就用自己的速度）。两个选择都存进 UserDefaults。`model.effectiveBPM` 是此刻实际用的速度。
- **播放中改速度，从下一拍开始生效，不打断、不跳拍**：连续演奏改成每拍排一个片段（`BarPlan.segment`），每一拍按“当时”的速度换算成秒，片段在采样时钟上首尾相接（`LoopTimeline`，累计误差不超过半个采样）；换和弦、换节奏型 / 指法仍然只在小节开头生效。节拍器改速度（跟随时）也一样，下一拍生效。
- 注意：App 以前直接设 `model.bpm` 就会让和弦库按它的速度播；现在 `bpm` 只在“跟随节拍器”打开时才生效（默认关闭，用自己的 70）。

### 扫弦节奏型（`StrumRhythm`，和弦库与训练页共用）

扫弦模式的一个循环是选中节奏型的一小节：每个 `D` / `U` / `X` 格在它的时间点用 `RhythmStrum` 的下扫 / 上扫 / 闷音发声（默认：吉他民谣 1，尤克里里岛屿扫弦）。速度用 `model.bpm`（没有时 100），一拍是一个四分音符。扫弦旁的列表按钮弹出节奏型列表（名称 + 箭头），选中的会记住（每种乐器各记各的）；弹奏时节奏型的小格子在和弦卡片上同步高亮当前格。

```swift
let r = StrumRhythm.folk1              // "D.DU.UDU"，八分格，4 拍
r.cells                                // [.down, .rest, .down, .up, .rest, .up, .down, .up]
r.cellsPerBeat, r.beatsPerBar          // 2, 4（十六分格是 4；3/4 拍的 beatsPerBar 是 3）
r.arrows                               // "↓· ↓↑ ·↑ ↓↑"
r.barDuration(bpm: 120)                // 2.0 秒
r.strokes(bpm: 120)                    // [(index, time, cell)]：要扫的格和它相对小节起点的时间（不含空拍）
r.cellIndex(at: 1.3, bpm: 120)         // 某时刻在第几格
r.velocity(ofCell: 0)                  // 力度：第 1 格最重，其余拍点下扫次之，上扫最轻
StrumRhythm(id: "mine", code: "D-DU-UDU", cellsPerBeat: 2)   // 自己建：D 下扫、U 上扫、X 闷音、. 或 - 空拍；格数要是每拍格数的整数倍
StrumRhythm.presets(for: .ukulele)     // 推荐列表，第一个是默认
```

| 类型 / 接口 | 说明 |
| --- | --- |
| `StrumCell` | `.bass`（B 根音）`.down`（D 下扫·全扫）`.downTreble`（d 下扫·半扫）`.up`（U 上扫）`.mute`（X 闷音）`.rest`（. 空拍），`isStroke`、`arrow`（文字箭头）、`init?(typed:)`（认一个输入字符） |
| `StrumRhythm` | 公开的节奏型模型：`id`、`cells`、`cellsPerBeat`、`beatsPerBar`、`title`、`englishTitle`、`code`、`arrows`、`countLabel(_:)`、`cellDuration/barDuration(bpm:)`、`strokes(bpm:)`、`cellIndex(at:bpm:)`、`velocity(ofCell:)`、`isCustom` |
| 预设 | `.folk1` `.folk2` `.eighths` `.quarters` `.waltz`（3/4）`.chunk` `.funk`（十六分格）`.island` `.ukeBasic`，以及新增的 `.rootStrum`（根音扫弦 `B.D.B.D.`）`.country`（乡村 `B.dUB.dU`）`.waltzBass`（华尔兹根音 `B.d.d.`，3/4）；`StrumRhythm.allPresets`、`presets(for: family)`、`preset(id:)`。id 和训练页现有的一致（`folk1`、`folk2`、`eighths`、`quarters`、`waltz`、`chunk`、`funk`、`island`、`ukeBasic`），名称是 String Catalog 的键（`StrumRhythm.title`，用 `ChordStrings.title(_:)` 取本地化名称） |
| `StrumInput.parse(_:cellsPerBeat:)` | 解析输入：每个字符一格，D 下扫、U 上扫、X 闷音、`-` 或 `.` 空拍（不分大小写，全角也认），空格 / `\|` / 逗号只用来分组；返回 `StrumParse`（`tokens` 含每个字符是否有效、`cells`、`failure`：`.empty` `.invalidCharacters` `.tooLong`（超过 8 拍）`.notWholeBeats`、`normalized`） |
| `CustomStrumRhythm` | 保存的自定义节奏型（`Codable`：`id`、`name`、`code`、`cellsPerBeat`），`.rhythm` 转成 `StrumRhythm` |
| `PlaybackBuilder.strumRhythmBar(voicing:rhythm:voice:a4:bpm:)` | 一小节节奏型的事件表（含闷音的 `hold`） |
| 模型 | `model.strumRhythms`、`strumRhythm`、`select(rhythm:)`、`validateRhythm(_:cellsPerBeat:)`、`saveCustomRhythm(id:name:text:cellsPerBeat:)`、`deleteCustomRhythm(id:)`、`previewRhythm(text:cellsPerBeat:)`、`playingCell()` |

**记号：根音、全扫、半扫（`StrumCell`）**

| 记号 | 含义 | 发声（`RhythmStrum.strings(for:cell:rootPitchClass:)`） |
| --- | --- | --- |
| `B` | 根音 | 只拨**根音弦**一下（力度略重）。根音弦 = 发声的弦里音高最低的、音名是根音的那根（`RhythmStrum.rootString(of:rootPitchClass:)`） |
| `D` | 下扫 · 全扫 | 从根音弦扫到 1 弦，音高比根音弦低的弦不扫（吉他 C/E 的低 E 弦不扫；尤克里里的高音 G 比根音弦高，照扫，所以是 4 根弦全扫） |
| `d` | 下扫 · 半扫 | 只扫高音的 3–4 根弦：发声 5 根以上取 4 根（1–4 弦），否则 3 根（1–3 弦），尤克里里 1–3 弦；从低往高 |
| `U` | 上扫 | 半扫：同样的高音弦，从 1 弦往回（和以前的上扫一样） |
| `X` | 闷音 | 全部发声的弦，只响约 0.1 秒（和以前一样） |
| `.` `-` | 空拍 | 不发声 |

- **大小写**：解析里**只有 `D` 和 `d` 区分大小写**，其他字母不分大小写（`b` = `B`，`u` = `U`，`x` = `X`）。快捷键里的 d 就是半扫；输入框对节奏型不再自动大写（分解指法的输入框仍然自动大写，R 不分大小写）。
- **兼容**：`StrumCell` 的旧成员（`.down` `.up` `.mute` `.rest`）和它们的原始值都没变；现有 9 个预设一个字符都没改；`D` 在标准按法上（低音是根音）和以前的“全部发声的弦”完全一样。`CustomStrumRhythm` 带存储格式版本 `v`（新格式 `v = 2`）：旧版本不分大小写，所以没有版本号的数据解码时整体转大写（含义不变，旧版本存的本来就是大写的规范写法），新数据里的小写 `d`（半扫）不会被改。
- **发声接口**：`RhythmStrum.playback(voicing:cell:rootPitchClass:velocity:voice:a4:gap:)` 生成一格的事件表；`PlaybackBuilder.strumRhythmPlan(…, rootPitchClass:)` 和 `strumRhythmBar(…, rootPitchClass:)` 按节奏型生成一小节（`rootPitchClass` 不传就取按法里最低的音）；预约发声：`RhythmStrummer.strum(_:instrument:chord:cell:velocity:at:)` / `…after:`（`ScheduledStrum.cell` 回传是哪一格；空拍和不能扫弦的乐器返回 nil）。按方向的旧接口 `strum(…direction:…)` 不变：`.down` 仍是全部发声的弦。
- **显示**（`StrumGlyph`）：`D` 长箭头，`d` 和 `U` 短箭头，`B` 是带 R 的圆点，`X` 是 ✕，空拍是虚线空格子；格子预览、和弦卡片下的小格子、选择面板、编辑页快捷键一致。文字里的箭头（`StrumCell.arrow`、`StrumRhythm.arrows`）：D ↓、d ⇣、U ↑、B ●、X ✕。
- **编辑页快捷键**：B、↓D、↓d、↑U、✕，第二行空拍和退格；每个键下面一个字的说明（根音 / 全扫 / 半扫 / 上扫 / 闷音），第一次打开编辑页时还会显示一行图例（`model.shouldShowStrumLegend`，只显示一次）。

**自定义**：扫弦列表最后一行“自定义…”打开编辑页（输入框下面有 ↓ D、↑ U、✕ X、空拍、退格快捷键；空拍在预览里是虚线空格子）：输入字符串，可选格子单位（八分 / 十六分），实时显示成箭头格子，非法字符标红，错误一句话说明（只能输入 D U X - .、最多 8 拍、格数要是每拍格数的整数倍），可以起名（不填就用箭头当名字）、试听一小节、保存；每种乐器最多保存 10 个，可编辑、删除，存在 UserDefaults 里。

**训练页复用（按乐器大类存取）**：自定义节奏型按乐器大类分别保存在同一份存储里，和弦库和训练页可以各选不同的乐器：

```swift
model.customRhythms(for: .ukulele)                          // 已保存的 [CustomStrumRhythm]
model.strumRhythms(for: .ukulele)                           // 预设 + 自定义，可直接给列表用
model.canAddCustomRhythm(for: .ukulele)                     // 还能不能再存（每类最多 10 个）
model.saveCustomRhythm(id: nil, name: "我的", text: "D.DU.UDU", cellsPerBeat: 2,
                       family: .ukulele, select: false)     // family 为 nil 用和弦库当前乐器；select 为 false 不动和弦库里的选择
model.deleteCustomRhythm(id: id, family: .ukulele)
model.previewRhythm(text: "D.DU", cellsPerBeat: 2, family: .ukulele)   // 用那件乐器的采样试听一小节

// 公开的编辑页，可以直接放进 .sheet：
CustomRhythmEditor(model: model, family: .ukulele, editing: nil /* 或要修改的 CustomStrumRhythm */,
                   palette: palette, strings: .current, selectsOnSave: false,
                   onSave: { saved in /* 训练页在这里选中它 */ }, onClose: { showEditor = false })
```

**空拍（`.` / `-`）在真机上“设不了”的原因**：解析本身一直认 `.` 和 `-`，问题出在输入：①iPhone 的智能标点会把连着输入的 `--` 换成一个 `–`、`...` 换成一个 `…`——旧版本把 `–` 当成 1 个空拍（吃掉了一格）、把 `…` 当成非法字符（标红），所以连续空拍几乎输不对；②输入框用 `asciiCapable` 键盘，`.` 和 `-` 在“123”页，不好找；③输入框开着自动更正。现在：输入框关掉智能标点和自动更正，解析按原来的个数还原 `–` `—` `‥` `…`，编辑页加了带“空拍”键的快捷键行，空拍在预览里是虚线空格子。

### 自定义分解指法

分解指法列表最后一行“自定义…”：输入一串弦号，每个数字是一根弦（吉他 1–6，1 弦最细；尤克里里、贝斯 1–4），可以用空格、逗号分隔，也可以连着写（`53231323`、`5 3 2 1`）；字母 `R` 代表“当前和弦的根音弦”，同一套指法可以用在不同和弦上。

- **空拍**：`-` 或 `0` 表示这一下不弹（休止），占一个音的时值：`5032` 是 5 弦、空、3 弦、2 弦，`5-3-2-` 是 5、空、3、空、2、空。试听和演奏时空拍不发声但占时值，预览里显示成虚线空格子。当前把位不弹的弦也是同样的休止。长度 1–32 步（空拍也算一步），至少要有一个会响的音。
- **分隔符**：空格、逗号、顿号等只用来分隔，**短横不再是分隔符，是空拍**。预设和已保存指法的显示 / 规范写法也都改成用空格隔开（`5 3 2 1`、`R 3 - 1`）。
- **旧数据兼容**：以前保存的指法 `text` 是 `5-3-2-1`（短横分隔）。`CustomArpeggio` 现在带存储格式版本 `v`（新格式 `v = 2`）；解码时没有 `v` 就按旧规则迁移（去掉短横、逐字符用空格隔开：`5-3-2-1` → `5 3 2 1`），重新编码时写 `v = 2`，所以旧指法含义不变，也不会被迁移两次。
- **实时校验**：超出弦数的数字和其他字符标红并提示，输入时可以点“试听”；保存后进列表（每种乐器最多 10 个，可命名、编辑、删除，持久化到本机，按乐器分别保存）。
- **输入框和快捷键**：编辑页的输入框关掉自动大小写、自动更正、拼写检查和**智能标点**（UIKit 的 `UITextField`，`smartDashesType = .no`），输入框下面有一排快捷键，不用切键盘：弦号 1…（按乐器弦数）、R，第二行是**空拍**和退格。扫弦节奏型的编辑页同样有快捷键：↓ D、↑ U、✕ X、空拍、退格。
- **智能标点**：iPhone 的智能标点会把连着输入的 `--` 换成 `–`、`---` 换成 `—`、`..` 换成 `‥`、`...` 换成 `…`。解析时按原来的个数还原（`–` = 2 个空拍，`—` / `…` = 3 个），所以连续的空拍不会被吃掉或标红（这是“扫弦设不了空拍”的原因之一，见下）。

贝斯没有指法图，每个数字发这根弦上品位最低的和弦音，`R` 发根音。

接口：`ArpeggioInput.parse(_:stringCount:)`（→ `ArpeggioParse`：`tokens`、`steps`、`failure`、`normalized`）、`ArpeggioStep`（`.string(n)` / `.root`）、`CustomArpeggio`（`Codable`）、`model.validateArpeggio(_:)`、`saveCustomArpeggio(id:name:text:)`、`deleteCustomArpeggio(id:)`、`previewArpeggio(text:)`、`canAddCustomArpeggio`。

### 节奏扫弦（训练页的“扫弦节奏型”跟练）

`RhythmStrummer` 在**音频时钟上的指定时间点**扫一下当前和弦，App 可以把整个节奏型提前排好，和节拍精确对齐。声音复用 TunerKit 的真实乐器采样；每种扫弦的缓冲只渲染一次并缓存，预约时不占 CPU。

```swift
let strummer = RhythmStrummer()                       // @MainActor
strummer.configuresAudioSession = false               // App 统一管理音频会话时
try strummer.prepare()                                // 提前启动引擎（不调用则第一次 strum 时启动，会有启动延迟）

let guitar = InstrumentLibrary.guitar
let v = ChordLibrary.voicings(for: Chord("C", .major)!, instrument: guitar)[0]

// 1) 按主机时间预约：t0 可以取节拍器引擎的某个 AVAudioTime（hostTime），或从现在算起
let t0 = RhythmStrummer.hostTime(afterSeconds: 0.1)
strummer.strum(v, instrument: guitar, direction: .down, velocity: 1.25, at: t0)       // 重音下扫
// 2) 相对现在的秒数
strummer.strum(v, instrument: guitar, direction: .up, velocity: 0.7, after: 0.4)      // 弱上扫
strummer.strum(v, instrument: guitar, direction: .down, muted: true, after: 0.7)      // 闷音（切音）
// 3) 立即停止全部预约和正在发声的扫弦
strummer.stopAll()
```

| 接口 | 说明 |
| --- | --- |
| `RhythmStrummer.strum(_:instrument:direction:velocity:muted:at:)` / `…after:` | 按乐器 + 指法发声。`at` 是主机时间的 `AVAudioTime`（nil = 立即），`after` 是相对现在的秒数。返回 `ScheduledStrum?`（`hostTime`、`seconds`、每根弦的 `events`，可用来对齐画面）；乐器不能扫弦、没有可弹的弦、引擎启动失败时返回 nil |
| `RhythmStrummer.strum(_:voice:…)` | 同上，直接指定 `InstrumentTone.Voice`（不检查乐器） |
| `RhythmStrummer.schedule(_ playback:direction:at:)` | 预约任意一段单次的 `ChordPlayback` 事件表 |
| `RhythmStrummer.stopAll()` | 立即停止全部预约；之后还能继续预约 |
| `RhythmStrummer.hostTime(afterSeconds:)` / `nowHostTime` | 从现在起若干秒后的主机时间 / 现在的主机时间 |
| `StrumDirection` | `.down`：所有发声的弦从低音弦扫到高音弦；`.up`：从最高的弦往回，只扫较高的 3–4 根弦（6 根弦的和弦取 4 根，4 根弦的取 3 根） |
| `velocity` | 力度，1 普通，重音 1.25，弱拍 0.7；夹在 0.05…1.6 |
| `muted` | 闷音：只发一声短促的“嚓”，余音立刻切掉（约 0.1 秒） |
| `RhythmStrum.playback(voicing:direction:velocity:muted:voice:a4:gap:)` | 纯计算：生成事件表。弦间隔下扫约 12 毫秒、上扫约 9 毫秒（各带 ±10% 起伏），比和弦库试听里的扫弦（约 32 毫秒）快 |

- `at` 是 `mach_absolute_time` 刻度的主机时间：同一台设备上不同的 `AVAudioEngine` 共用它，所以节拍器引擎和这里能对齐；早于现在的时间点按“立即”处理。
- 重叠的余音靠一组播放节点轮流承担（`maxVoices`，默认 8），上一下的余音不会被下一下打断；节奏型很快（16 分音符）时可以把 `maxVoices` 加大。
- 音频会话默认设 `.playAndRecord`（与调音器、节拍器一致）；`configuresAudioSession = false` 可关。

**“可扫弦”属性**：`Instrument.supportsStrumming` / `InstrumentFamily.supportsStrumming`（吉他、尤克里里为 true，贝斯和其他为 false），`ChordLibrary.strummableInstruments` 列出所有可扫弦的乐器。数据在 `ChordLibrary.strummableFamilies`，**以后新增能扫弦的乐器（班卓、曼陀林……）只要在这里加一项**（并给它做好指法），训练页就会自动出现它。`RhythmStrummer` 的 `instrument:` 版本只对可扫弦的乐器发声，和弦库里的“扫弦”模式也读这个属性（不可扫弦的乐器只有分解）。

### 左手模式、收藏

- `ChordDiagramView(voicing:chord:palette:leftHanded:scale:)` 与 `BassDiagramView` 的 `leftHanded: true` 即左右镜像；`ChordLibraryModel.leftHanded` 同步控制整页（右上角星标菜单里也有开关）。
- `ChordFavorite { instrumentID, tuningID, root, typeID, voicingIndex }`、`ChordFavorites`（`toggle` / `add` / `remove` / `contains`），都是 `Codable`。

### 和弦记号与升降拼法

- 类型按钮用标准和弦记号并带当前根音：根音 C 时依次是 C、Cm、C7、Cmaj7、Cm7、Csus2、Csus4、Cdim、Caug、Cadd9（大三不加后缀，小三写 m），换根音一起变；和弦大标题同一套写法。读屏仍念“大三和弦”“小三和弦”等完整名称（`ChordStrings.name(_:)`，12 种语言）。
- 五个黑键根音按钮只用常用的一种写法：C♯、E♭、F♯、A♭、B♭（不再把升降并列；唱名为 Do♯、Mi♭、Fa♯、La♭、Si♭，德语 B♭ 记 B），网格保持 6 列；读屏也读这一种。
- 和弦标题用常用拼法 C♯ E♭ F♯ A♭ B♭，组成音和指法图弦下的音名与根音一致（E♭ 大三是 E♭ G B♭，F 小三是 F A♭ C）；按字母推出 E♯、F♭ 之类少见写法时，整个和弦退回统一的升号或降号（C♯ 大三写 C♯ F G♯）。规则见 `ChordSpelling`，显示用 `NoteNaming` 的扩展：`rootName`、`chordName`、`chordName(pitchClass:type:)`、`toneNames`、`toneName(pitchClass:in:)`、`rootButtonNames`。
- 数据层的 `Chord.name`、`Chord.toneNames` 仍是 ASCII 升号写法（"C#m7"），只用来做键和查表，不要拿去显示。

### 界面

| 类型 | 说明 |
| --- | --- |
| `ChordLibraryView(model:palette:strings:)` | 整页：星标菜单（收藏/左手模式/收藏列表）、乐器切换、和弦名与组成音、试听按钮、指法图画廊（横向分页，跟手拖动、松手吸附整页，不循环；箭头和页码点同步，点箭头也带滑动动画；滑到被锁的把位会弹回并回调 `onLocked`）、根音网格、类型网格 |
| `ChordDiagramView` | 单独可复用的指法图，设计稿尺寸，`scale` 缩放；根音用强调色，横按画成圆角条 |
| `BassDiagramView` | 贝斯和弦音位置图 |
| `ChordLibraryModel` | `@MainActor @Observable`：`select(instrument:/root:/type:/voicingIndex:)`、`go(to:)`、`toggleFavorite()`、`togglePlayback()` |
| `ChordPalette` / `ChordStrings` | 颜色与文字，调法同 `TunerPalette` / `TunerStrings`（含英文） |

SwiftUI Preview：`ChordLibraryView_Previews`（深色、浅色、贝斯）和 `ChordDiagramView_Previews`（右手/左手）。

## 测试

```bash
swift test        # 约 205 个用例
xcodebuild -scheme ChordKit -destination 'generic/platform=iOS Simulator' build
```

覆盖：12 根音 × 10 类型的组成音；吉他和尤克里里的标准按法与指法（含 F 横按）；所有乐器 × 12 根音 × 10 类型都能生成按法，每个按法都过独立的校验（跨度、手指数、只含和弦音、含根音、横按合理、不弹的弦在两端）；排序规则；人工校对表全部合格；贝斯框；收藏编码；合成音的音准（用 TunerKit 的 `PitchDetector` 检测，误差 ≤ 6 音分）；界面渲染（深浅主题、唱名与德语下的长名字）；和弦记号与升降拼法；String Catalog 12 种语言齐全；分解指法（根音弦替换、跳过不弹的弦、各指法的音序列、贝斯根五八五）、事件时间与渲染位置对得上、动画时钟、选择的持久化。
