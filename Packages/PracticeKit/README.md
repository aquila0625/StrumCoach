# PracticeKit

「稳拍」节拍器的训练逻辑、练习记录和统计。纯 Swift Package，没有界面，不碰音频。

- 平台：iOS 17 / macOS 14（本机直接 `swift test`）
- 两个库：
  - **RhythmKit**：节奏设置值类型（拍号、重音、切分、音色）。无依赖，Codable + Sendable，节拍引擎也可以只依赖它。
  - **PracticeKit**：练习记录的 SwiftData 模型、训练逻辑、练习统计。会 `@_exported import RhythmKit`，所以 `import PracticeKit` 就够了。

接入：在 App 的 Package 依赖里加本地路径 `Packages/PracticeKit`。

```swift
// 容器里加上这三个模型（也可以用 PracticeKitSchema.makeContainer）
.modelContainer(for: PracticeKitSchema.models)
```

## 一、RhythmKit

| 类型 | 说明 |
|---|---|
| `TimeSignature(beatsPerBar:beatUnit:)` | 拍数 1…32，单位拍 2/4/8/16，非法值自动修正；有 `.fourFour` 等预设和 `presets` |
| `AccentLevel` | `.strong / .medium / .weak / .muted`，`cycled` 给点按切换用 |
| `Subdivision` | `quarter, eighth, triplet, sixteenth, dotted, eighthSixteenth, sixteenthEighth, syncopation`；`offsets` 是一拍内每个发声点的位置（0..<1） |
| `ToneID` | 字符串包装，音色资源由 App 定义；默认 `"click"` |
| `RhythmSettings` | 拍号 + 每拍重音 + 切分 + 音色，**不含 BPM**（BPM 由 App 自己管） |
| `Tempo` | BPM 范围 20…400，`Tempo.clamp(_:)` |

`RhythmSettings` 的不变量：`accents.count == timeSignature.beatsPerBar`，初始化、解码、`setTimeSignature(_:)` 时自动维持（改拍号时已有重音尽量保留，新增拍为弱）。`accent(atBeat:)` 按小节取模，不会越界。

切分的 `offsets`（以一拍为 1）：

| 切分 | offsets |
|---|---|
| 四分 | 0 |
| 八分 | 0, ½ |
| 三连音 | 0, ⅓, ⅔ |
| 十六分 | 0, ¼, ½, ¾ |
| 附点（附点八分 + 十六分） | 0, ¾ |
| 前八后十六 | 0, ½, ¾ |
| 前十六后八 | 0, ¼, ½ |
| 切分音（十六 + 八 + 十六） | 0, ¼, ¾ |

## 二、练习记录模型

只有一个 SwiftData 模型 `PracticeSession`，写法兼容以后的 CloudKit 同步（属性都有默认值、无 unique）。

- 字段：`startedAt, duration(秒), minBPM, maxBPM, mode`；`bpmRange` 是 `minBPM...maxBPM`，`endedAt` 是结束时间。
- `PracticeMode`：`free`（普通）/ `ramp`（渐进提速）/ `mute`（静音小节）/ `rampAndMute`。最近练习列表用 `mode` 加 `bpmRange` 描述一次练习，文案由 App 自己配。
- `PracticeKitSchema.models` / `makeContainer(inMemory:)`：建容器用。

## 三、训练逻辑（纯函数）

**小节序号 `bar` 和拍序号 `beat` 都从 0 开始。** 界面上“第 N 小节”要显示成 `bar + 1`。

### 渐进提速 `RampSettings`

```swift
let ramp = RampSettings(startBPM: 80, targetBPM: 120, step: 2, barsPerStep: 4, endBehavior: .hold)
ramp.bpm(atBar: 32)      // 96
ramp.progress(atBar: 40) // 0.5
ramp.stepCount           // 20
ramp.barsToTarget        // 80：第一次出现目标速度的小节
ramp.isFinished(atBar:)  // 只有 .stop 会结束
```

- `endBehavior`：`.stop`（目标那一档播完后结束，`cycleBars` 处）、`.hold`（一直保持目标）、`.loop`（目标那一档播完回到起始 BPM 重新爬）。
- 目标低于起始是渐进减速；最后一档不足一个 `step` 时直接落到目标（80→121、步长 2，末档 121）。
- 参数非法会被修正（BPM 夹到范围内，`step`、`barsPerStep` 至少 1）。

### 静音 `MuteSettings`

```swift
MuteSettings.bars(audible: 2, muted: 1).isMuted(bar: 2, beat: 0)               // true
MuteSettings.randomBeats(probability: 0.25, seed: 42).isMuted(bar: 7, beat: 2) // 同种子永远同结果
MuteSettings.randomBeats(probability: 0.5, seed: 1, keepsDownbeat: true)       // 每小节第一拍必响
```

随机静音是按 (种子, 小节, 拍) 哈希出来的，可以随机访问，不依赖播放顺序，所以暂停、跳转后结果不变。

### 组合 `TrainingPlan`

```swift
let plan = TrainingPlan(baseBPM: 90, ramp: ramp, mute: .bars(audible: 2, muted: 1))
plan.mode                        // .rampAndMute
plan.state(bar: 33, beat: 1)     // BeatState(bpm: 96, isMuted: false, isFinished: false)
plan.progress(atBar:)            // 没开提速时为 nil
plan.bpmRange(throughBar: 33)    // 80...96，停止时传给 PracticeRecording.record
```

两种训练可以任意组合；都不开就是普通播放（`mode == .free`，BPM 恒为 `baseBPM`）。

## 四、练习记录与统计

```swift
// 停止播放时调用：少于 30 秒返回 nil，不写入；刚好 30 秒算有效。需要自己 context.save()
PracticeRecording.record(startedAt:duration:bpmRange:mode:in:)
PracticeRecording.shouldRecord(duration:)

let stats = PracticeStatistics(calendar: .current)   // 用户当前时区
stats.weeklyTotal(of: sessions, now: .now)           // 本周总时长（秒），周起点取 calendar.firstWeekday
stats.dailyDurations(of: sessions, now: .now)        // 最近 7 天，[DailyPractice]，从旧到新，没练的为 0
stats.currentStreak(of: sessions, now: .now)         // 连续打卡天数
stats.recent(sessions, limit: 20)                    // 最近练习，新的在前
```

`sessions` 可以直接传 `@Query` 的结果（`PracticeSession` 已遵守 `PracticeRecord`），也可以传任何有 `startedAt`、`duration` 的值（测试用）。

规则：

- 少于 30 秒的记录统计时也一律不计（兜底）。
- 一条记录整条算在**开始那天**，不拆分跨午夜部分。
- 日界线用 `calendar` 的日历日计算，夏令时切换日（23 / 25 小时）不会错；内部不会用“减 86400 秒”。
- 连续打卡：今天练了就算上今天；今天还没练则从昨天往前数（今天结束前不会断档）。晚于今天的记录（改过系统时间）不计。

## 测试

```bash
swift test
```

45 个测试，重点是边界：80→120、每 4 小节 +2 时第 32 小节为 96；末档不足一步；`stop / hold / loop`；30 秒边界；跨午夜、美东春季拨快 / 秋季拨回、午夜拨快的圣保罗时区、同一时刻在不同时区算不同日；周起点周日 vs 周一。
