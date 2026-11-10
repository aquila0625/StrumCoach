# TuneBeatChord / 调音节拍和弦库 iOS App

原生 Swift + SwiftUI，iOS 17+，iPhone 和 iPad（iPad 上按 iPhone 排版整体放大）。

五个标签：训练、节拍器、调音器、和弦库、我的，另有设置页。全部功能免费，不联网、不收集数据。

`app/` 是 App，`../Packages/` 是 TunerKit、ChordKit、PracticeKit 三个本地包。

## 目录

```
app/
├── project.yml                 XcodeGen 工程描述（TuneBeatChord.xcodeproj 由它生成，不入库）
├── MetronomeCore/              节拍引擎（纯逻辑 Swift 包，依赖 PracticeKit）
│   ├── Sources/MetronomeCore/
│   │   ├── Model.swift         音频线程用的配置快照 MetronomeConfig；对 RhythmKit 类型的扩展；重音预设；音色
│   │   ├── BeatScheduler.swift 采样级调度：下一拍生效、无累计漂移、按 TrainingPlan 换速/静音
│   │   ├── ClickSynth.swift    程序合成 3 种音色 × 强/次强/弱
│   │   ├── ClickRenderer.swift 把事件混成音频（音频线程用，不分配内存）
│   │   ├── TapTempo.swift      TAP 测速 + 速度术语
│   │   └── LockedValue.swift   界面线程 ↔ 音频线程传值（音频线程只 trylock）
│   └── Tests/MetronomeCoreTests/  42 个测试，含 4 个 10 分钟离线渲染
├── tools/l10n/       多语言：抽取词条、译文、校验、合成 .xcstrings、截图脚本
├── TuneBeatChordTests/      App 集成测试：乐器联动、训练方案、练习记录、扫弦评分、多语言
├── TuneBeatChord/
│   ├── App/        入口、标签定义 AppTab.swift、根视图（标签切换、乐器联动、音频会话交接）、AppModel（设置/路由/演示数据）
│   ├── Theme/      主题令牌（深/浅）、浅色渐变背景、图标和音符绘制
│   ├── Engine/     AVAudioEngine 宿主、Core Haptics、锁屏控制、MetronomeController、训练选项
│   └── Features/   Metronome（主界面与底部面板）、Training、Strum（扫弦跟练与评分）、Profile、Settings
```

## 依赖的本地包

都以本地路径依赖接入（`project.yml` 的 `packages`），不需要网络：

| 包 | 路径 | 用途 |
|---|---|---|
| MetronomeCore | `app/MetronomeCore` | 节拍引擎 |
| PracticeKit（含 RhythmKit） | `../Packages/PracticeKit` | 节奏类型、训练方案、练习记录（SwiftData）与统计 |
| TunerKit | `../Packages/TunerKit` | 调音器（`TunerView` / `TunerModel`）、乐器与定弦 |
| ChordKit | `../Packages/ChordKit` | 和弦库（`ChordLibraryView` / `ChordLibraryModel`），依赖 TunerKit |

**节奏类型只有一套**：拍号 `TimeSignature`、重音 `AccentLevel`、切分 `Subdivision`、音色 ID `ToneID`、`RhythmSettings` 都来自 RhythmKit，训练用 PracticeKit 的 `TrainingPlan`。MetronomeCore 没有自己的同名类型，只做两件事：
- 给 RhythmKit 类型加扩展：`Subdivision.offset(_:)` / `clickCount` 用 switch 实现（RhythmKit 的 `offsets` 返回数组，音频线程里会分配内存；测试保证两者逐项相等），以及界面文案；
- `MetronomeConfig` 是给音频线程的快照：重音打包进 UInt64（`AccentPattern`），整个结构是纯值，复制不触发内存分配或引用计数。它和 `RhythmSettings` 双向转换（`init(rhythm:bpm:…)`、`.rhythm`），存盘的也是 `RhythmSettings`。

## 构建和运行

需要 Xcode 27 和 XcodeGen（`brew install xcodegen`）。

```bash
cd app
xcodegen generate
open TuneBeatChord.xcodeproj
```

命令行编译、跑测试（`TuneBeatChord` 方案的测试包含 App 集成测试 TuneBeatChordTests 和 MetronomeCore、RhythmKit、PracticeKit、TunerKit、ChordKit 的测试）：

```bash
xcodebuild -project TuneBeatChord.xcodeproj -scheme TuneBeatChord -destination 'platform=iOS Simulator,name=<模拟器名>' -derivedDataPath build/DerivedData build
xcodebuild -project TuneBeatChord.xcodeproj -scheme TuneBeatChord -destination 'platform=iOS Simulator,name=<模拟器名>' -derivedDataPath build/DerivedData test
```

也可以在每个包目录里直接 `swift test`（macOS 上跑，不需要模拟器）：

```bash
cd MetronomeCore && swift test
```

装到模拟器并启动：

```bash
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/TuneBeatChord.app
xcrun simctl launch booted com.example.tunebeatchord
```

真机：在 Xcode 里给 TuneBeatChord target 选自己的 Team，并把 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER`（现在是占位的 `com.example.tunebeatchord`）改成你自己的。触感反馈、麦克风调音只有真机才能完整验证。

### 截图用的启动参数

| 参数 | 作用 |
|---|---|
| `-appearance light` / `dark` | 强制浅色/深色（和设置页的“主题”是同一个键） |
| `-demo YES` | 演示数据：和设计稿一致的状态，不出声，不读写真实设置；练习记录用内存库并填入设计稿 06 的一周数据 |
| `-demoTab metronome\|training\|tuner\|chords\|profile` | 启动时停在哪个标签 |
| `-demoSheet rhythm\|sound\|bpm\|ramp\|mute\|timer\|settings\|history` | 启动时打开的面板或页面 |
| `-demoSubdivision sixteenth` `-demoTime 12/8` `-demoBeat 4` `-demoSub 3` | 演示其他切分、拍号，以及正在响的拍和切分点（`-demoSub` 从 0 起） |

## 节拍引擎

- **不用 Timer。** `AVAudioSourceNode` 的渲染回调里，`BeatScheduler` 按采样位置算出这一段里有哪些点击，`ClickRenderer` 直接把预先合成好的音写到对应采样上。
- **无累计漂移。** 每拍位置 = `速度段起点 + n × 每拍采样数`，四舍五入到整数采样，不逐拍累加；换速度时以那个拍头为新速度段起点。
- **改动在下一拍生效。** BPM、拍号、重音、切分、音色、训练开关都先存成 pending，到下一拍拍头才换；小节内位置接着走，不回到第 1 拍。
- **训练。** 调度器带着 PracticeKit 的 `TrainingPlan`：每进入新小节问一次 `bpm(atBar:)`，变了就在这个小节的第一拍换速（和手动改速同一套机制，所以同样是采样级精度）；每拍问 `isMuted(bar:beat:)`，静掉的拍照常调度（界面高亮、计数都不受影响），只是增益为 0、不震动；“到目标后停止”在 `isFinished(atBar:)` 时停止调度，App 随即停止并记一次练习。两种训练可以同时开。
- **线程。** 界面线程把配置写进 `LockedValue`（版本号 +1），音频线程每个周期 `tryWithLock` 读一次，拿不到就沿用上一轮。渲染路径不分配内存、不阻塞。
- **当前拍高亮和触感按音频时钟。** 音频线程每个周期发布“最近一拍 + 预测的后两拍”的设备时间（`mHostTime` + 输出延迟）以及小节号、实际 BPM。界面只看“时间到了没有”；触感提前 70 ms 内用 `CHHapticPatternPlayer.start(atTime:)` 排到同一时刻。
- **测试。** 10 分钟 120 BPM（每拍误差 0 ms、漂移 0）；137 BPM @ 44.1 kHz；渐进提速 10 分钟（80→120、每 4 小节 +2，每拍和理论位置差 ≤ 0.5 采样）；静音小节 10 分钟（静音小节里波形没有任何起音，恢复的第一拍精确到采样）；提速 + 随机静音同时开。

## 音频会话

| 场景 | 会话 |
|---|---|
| 节拍器播放 | `.playback`（不混音，锁屏/控制中心才有播放控制）；Background Modes → Audio 已开 |
| 进入调音器 | 节拍器在响就先暂停，并立即停掉引擎（不延迟释放会话，免得把调音器刚打开的录音会话关掉）；TunerKit 自己设 `.playAndRecord` |
| 离开调音器再播放 | 发现会话类别不是 `.playback` 就整个重建引擎（硬件采样率可能变了），再开始 |
| 调音器在前台时从锁屏开始播放 | 先关麦克风再播放 |
| 和弦库试听 | `ChordLibraryModel.configuresAudioSession = false`，进入和弦库时把会话设回 `.playback`，试听和节拍器共用会话，不会打断节拍 |
| 来电、闹钟打断 | 暂停，结束后不自动恢复；耳机拔出也暂停 |

## 各标签

- **节拍器**：拍子方块点按循环 强→次强→弱→静音；方块里按当前切分分格（八分 2 格、三连音 3 格、十六分 4 格，附点 3:1、前八后十六 2:1:1、前十六后八 1:1:2、切分音 1:2:1），播放时正在响的那一格保持原色、其余变淡，按音频时钟跟着每个切分点走（音频线程在 `BeatSnapshot` 里发布最近一个点和后两个点，界面用 `MetronomeController.soundingClick` 选当前点）；格子窄时分隔变成 1 pt 细线；BPM 圆环转一圈 60 BPM；± 长按加速；点数字弹出键盘；TAP 取最近 4 次点按；计时点按清零。开了训练时标题旁显示“渐进提速/静音小节”，开了渐进提速时速度由训练控制（圆环、±、TAP 不可用，显示实际速度）。
- **训练**：三张卡片各有开关，点卡片改参数。渐进提速：起始/目标/每档变化/每档小节数/到目标后（停止、保持、循环）；静音：按小节（有声 N 小节 + 静音 M 小节）或随机静音（概率、是否保留每小节第一拍）；练习计时：今天累计到目标时提醒（顶部提示 + 震动；在后台时发本地通知），可选自动停止。训练设置对节拍器全局生效。
- **调音器**：TunerKit 的 `TunerView`，颜色用 App 主题（背景透明，透出浅色渐变）。
- **和弦库**：ChordKit 的 `ChordLibraryView`。收藏、当前和弦、左手模式存 UserDefaults。
- **乐器联动**：和弦库选吉他/贝斯/尤克里里 → 调音器切到该乐器的标准定弦；调音器选了这三种乐器的任意定弦 → 和弦库切到同一乐器和定弦。调音器选择和标准音存 UserDefaults，下次启动恢复。
- **我的**：PracticeKit 的 `PracticeStatistics`（周一为一周第一天）。节拍器每次停止时自动记一次（不足 30 秒不记，由 `PracticeRecording` 判断），BPM 范围取这次实际播放过的最低/最高速度，模式取训练方案。本周时长、连续打卡、近 7 天柱状图、最近练习。
- **设置**（我的、调音器右上角）：主题（跟随系统/浅色/深色）、语言、音名、跟拍震动、左手模式、标准音 A4。

## 扫弦节奏型（训练页）

训练页第一张卡片进入（`TuneBeatChord/Features/Strum/`）：选乐器、编和弦进行（可以只有一个和弦）、选节奏型、调速度（默认跟随节拍器 BPM），然后：

乐器不写死：凡是 ChordKit 标记为可扫弦的乐器（`ChordLibrary.strummableInstruments`，现在是吉他和尤克里里）都会出现，以后 ChordKit 加了曼陀林、班卓琴等会自动出现。

1. **听示范**：倒数一小节（木鱼声），用 ChordKit 的 `RhythmStrummer` 按主机时间预约，按节奏型把和弦进行扫一遍，格子同步高亮。
2. **跟我练**：倒数一小节后收音（长度见下文“和弦进行”）。外放时不放任何节拍声（免得麦克风收进去），靠屏幕高亮、倒数数字和倒数时的震动引导；检测到耳机（有线、蓝牙、USB）才在耳机里放节拍声。
3. **评分**：收音结束后整段做起音检测，和每个该扫的格对齐打分，显示结果卡片，并记进练习记录（模式 `PracticeMode.strum`，时长为收音的几小节）和本机的成绩历史（`StrumHistory`，训练页卡片显示上次成绩）。

**和弦进行**（`StrumProgression.swift`、`StrumProgressionViews.swift`）：和弦是一行可横向滚动的和弦块，数量不限。末尾“+”添加（根音 + 类型 + 持续 1 / 2 / 4 小节），点一下修改，长按拖动排序，长按菜单或编辑页里复制、删除（至少留一个）。“常用进行”一键套用 C–G–Am–F、G–D–Em–C、Am–F–C–G、D–A–Bm–G、C–Am–F–G、12 小节布鲁斯（A，A7×4 D7×2 A7×2 E7 D7 A7 E7）；“保存”按名字存进“我的进行”（本机、数量不限，同名覆盖，左滑删除）。当前进行也存在本机，下次打开还是它（旧版的单个和弦会变成进行的第一个和弦）。

- 节奏型按小节套到每个和弦上（`ProgressionPlan`：第几小节弹第几个和弦），每小节的扫弦用那个和弦在和弦库里的第一个把位。
- 示范把整个进行走一遍，超过 8 小节只示范前 8 小节（界面上会说明）；跟练把整个进行走一遍（打开“跟练时循环 2 遍”就两遍），不到 4 小节时整遍循环补足。
- 示范和跟练时顶部显示当前和弦（大字 + 小指法图）和下一个和弦；换和弦前一拍，下一个和弦块放大加框闪一下，提醒提前换把。
- 评分：总分规则不变；另外按和弦分段打分（每段只算属于它的小节，多扫按落在哪一小节算），统计“换和弦后第一下”的偏差（按换到哪个和弦分组），建议例如“换到 F 时普遍晚了 69 毫秒，可以提前准备按法”。结果每一行前面写着这一小节的和弦。成绩历史里存这次用的进行名和和弦。
- 演示参数：`-demoSheet strum-edit`（停在编辑进行）、`-demoProgression 0…5`（套用第几个常用进行，5 是 12 小节布鲁斯）。

节奏型（以八分为单位，D 下扫、U 上扫、· 不扫、X 闷音）按乐器推荐（`StrumRhythm.presets(for:)`），也可以用 D U X · 写自己的节奏型（和和弦库共用）：

- 吉他（以及还没有专门列表的可扫弦乐器）：民谣 1 `D·DU·UDU`（默认）、民谣 2 `D·DUDUDU`、八分全扫、四分、慢摇 / 华尔兹 3/4 `D·DUDU`、切音节奏 `D·XU·UXU`、十六分 Funk `DUDUXUDU` ×2（按十六分）；
- 尤克里里：岛屿扫弦 `D·DU·UDU`（默认）、基础扫弦 `D·DUDUDU`，后面同吉他的八分全扫……十六分 Funk。

换乐器时，当前节奏型不在新乐器的列表里就换成它的默认节奏型。

- **时钟**：所有时间都是主机时钟的秒（和 `CACurrentMediaTime` 同一时基）。示范和耳机节拍声提前 `outputLatency` 预约，耳朵听到的正好在格子上；录音的每个缓冲带主机时间，起音时间 = 缓冲时间 + 采样位置 ÷ 采样率 − `inputLatency` − 校准偏差。画面每帧按“现在”在时间线上的位置高亮。
- **起音检测**（`OnsetDetector`）：1024 点 FFT、步长 256 的频谱通量（对数幅度）+ 自适应阈值（前后 0.25 秒中位数 × 1.5，再加整段最大通量的 8%）+ 至少隔 70 毫秒 + 音量下限；最后在一阶差分（高通）后的约 1.3 毫秒能量块上找扫弦第一根弦的起音。
- **评分**（`StrumScore`）：每个该扫的格和起音按时间差一对一配对，±60 毫秒内“准”（1 分）、±120 毫秒内“偏”（0.5 分），否则“漏”；没配上的起音算“多扫”（扣 0.5）。总分 =（准 + 0.5 × 偏 − 0.5 × 多扫）÷ 应扫次数 × 100，限制在 0…100。另给平均偏快 / 偏慢（毫秒）和稳定度（偏差的标准差），以及一句按数据给出的建议（例如“该上扫的那几下平均比下扫慢 38 毫秒”是按节奏型里该上扫的格分组算的）。
- **延迟校准**：右上角“延迟校准”，跟着节拍每拍扫一下（8 拍、90 BPM），取偏差的中位数存起来（限制在 ±200 毫秒），以后跟练都扣掉。
- **已知限制**：第一版不判断实际是上扫还是下扫，只看时间；闷音和普通扫弦一样按起音算；外放时屏幕高亮是唯一的节拍引导，倒数之后不震动（震动会被麦克风收到）；很吵的环境、离手机很远时会漏检；蓝牙耳机的输出延迟靠系统报告的 `outputLatency` 补偿，个别耳机不准时用延迟校准。
- **演示参数**：`-demoTab training -demoSheet strum`（停在收音中）/ `strum-result`（样例成绩），`-demoPattern funk` 选节奏型。

## 多语言

12 种界面语言：简体中文（开发语言）、繁體中文、English、日本語、한국어、Español、Français、Deutsch、Português（巴西）、Italiano、Русский、Türkçe。**译文由 AI 生成，欢迎母语者校对。**

- **String Catalog**：App 是 `TuneBeatChord/Resources/Localizable.xcstrings`；MetronomeCore、TunerKit、ChordKit 各自是 `Sources/<包>/Resources/Localizable.xcstrings`，包里用 `Bundle.module` 查。键一律是简体中文原文（命令行 `swift test` 编不编 catalog 都能显示中文）。PracticeKit 没有面向用户的文字（模式名由 App 配）。
- **回退**：`CFBundleDevelopmentRegion` 是 `en`，用户的语言都不在列表里时显示英文；开发语言（catalog 的源语言）仍是简体中文。包内的 `L10n.bundle` 跟随 App 主界面实际用的语言，避免 App 回退英文而包回退中文。
- **权限说明、App 名**：`TuneBeatChord/<语言>.lproj/InfoPlist.strings`。简体“调音节拍和弦库”、繁体“調音節拍和弦庫”，其他语言用 “TuneBeatChord”。
- **速度术语**：意大利文不变，前面加本地名称（中文“快板 Allegro”、日文“アレグロ Allegro”、德文“schnell Allegro”）；英文、意大利文只显示意大利文。
- **音名显示**（设置页）：字母（C D E）或唱名（Do Re Mi）。法、意、西、葡、俄默认唱名，其他默认字母；唱名按语言拼写（法 Ré、葡 Lá、俄 Ля）；德语字母写法 B → H、B♭ → B。实现是 TunerKit 的 `NoteNaming`，通过环境值 `\.noteNaming` 注入，调音器（音名、弦、参考音、A4）、和弦库（根音、和弦名、组成音、指法图下的音名、读屏文字）都遵守，和弦名如 Rem、Sol7、Hm。
- **复数**：小节数（`%lld 小节`）在 String Catalog 里有复数变体，按各语言的 CLDR 规则写（俄语 one/few/many：1 такт、2 такта、5 тактов；法、西、葡、意 one/many/other；中日韩土只有一种）。带数量的句子不直接写数字，而是把 `Units.bars(n)`（“N 小节”）或 `Units.minutes(n)`（系统时长格式）整体嵌进去，所以德语是 “1 Takt stumm”。`translations/<语言>.json` 里复数词条的值写成 `{"one": …, "few": …, "many": …, "other": …}`。测试见 `TuneBeatChordTests/LocalizationTests.swift` 的 `PluralTests`。
- **数字和日期**：时长用 `Duration` 的格式化（“3 小时 25 分钟”“3 hr, 25 min”），连续天数、日期、百分比、频率小数点都用系统格式化；星期用日历的本地符号。
- **排版**：标签栏、卡片说明、分段按钮、切分名、提示文字都允许换两行或按比例缩小（`lineLimit` + `minimumScaleFactor`），德语、俄语截图检查过没有截断。暂不支持从右到左的语言。
- **语言设置（App 内切换）**：设置页“语言”一项显示当前语言的国旗和名字，点开是语言列表：“跟随系统”加 12 种语言，每种配国旗（繁体中文用香港旗、英文用美国旗、巴西葡语用巴西旗），选完**立即生效**，不用重启、不跳系统设置。实现见 `TuneBeatChord/App/AppLanguage.swift`：
  - 选择写进 App 自己的 `AppleLanguages`（下次启动系统也按它加载），“跟随系统”就删掉这个键；
  - App 里的 `String(localized:)` 都带 `bundle: .appLanguage, locale: .appLanguage`，从选中语言的 lproj 取文字、按它的复数规则；
  - 根视图注入 `\.locale`，SwiftUI 的 `Text("…")` 跟着变；根视图内容、设置页、语言列表按语言加 `.id`，换语言时整页重建；
  - 三个包的 `L10n` 每次查表都读同一个 `AppleLanguages`，所以调音器、和弦库、速度术语也一起换；
  - 日期、时长、百分比、价格、频率小数都用 `.locale(.appLanguage)` 格式化。
  - 语言解析规则（App 和包一致）：先精确匹配，再按语言匹配（zh-TW/HK → 繁体，pt-PT → 巴西葡语，de-AT → 德语），都不支持时用英文。

改文案的流程（`tools/l10n/`）：

```bash
# 1. 编译一次，从编译产物抽取词条
xcodebuild -project TuneBeatChord.xcodeproj -scheme TuneBeatChord -destination 'platform=iOS Simulator,name=<模拟器名>' -derivedDataPath build/DerivedData build
python3 -I tools/l10n/extract.py build/DerivedData tools/l10n/keys.json
python3 -I tools/l10n/make_source.py tools/l10n/keys.json tools/l10n/source.json tools/l10n/entries.json
# 2. 补 tools/l10n/translations/<语言>.json（译者说明见 TRANSLATOR_BRIEF.md），校验占位符
python3 -I tools/l10n/check.py zh-Hant en ja ko es fr de pt-BR it ru tr
# 3. 合成各模块的 .xcstrings 和 InfoPlist.strings，打印覆盖率
python3 -I tools/l10n/assemble.py
```

多语言截图：`zsh tools/l10n/shots_i18n.sh <模拟器 UDID>` → `screenshots/i18n/`（英、日、德、西的主界面和和弦库，另有德、俄长词页面和法语唱名）。

## 已知限制 / 只能在真机验证

- 只能在真机验证：麦克风调音和扫弦评分的实际效果；节拍器 ↔ 调音器 ↔ 和弦试听之间的音频会话切换；锁屏和后台继续播放、锁屏/控制中心控制；来电打断；触感和声音对齐；后台到达练习目标时的本地通知。
- 没有 UI 自动化测试；不支持从右到左的语言。
- 11 种语言的译文由 AI 生成，欢迎母语者校对。
