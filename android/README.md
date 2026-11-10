# TuneBeatChord / 调音节拍和弦库 · Android

原生 Kotlin + Jetpack Compose 的安卓版，和 `../app`（iOS）放在同一个仓库里。功能和 iOS 版一致：调音器、节拍器、和弦库、扫弦训练、练习记录，全部免费、不联网、不收集数据、没有账号、没有内购。

> 状态：开发中。下面「技术路线」是动工前定下的，「已做 / 没做」「未验证清单」会随着提交更新。

## 技术路线（动工前的决定）

### 结论

| 问题 | 决定 | 一句话理由 |
|---|---|---|
| 语言与界面 | Kotlin + Jetpack Compose（Material 3 只用底层组件，配色自己定） | 和 iOS 的 SwiftUI 一一对应，指法图、拨盘等自绘界面用 Canvas 很顺手 |
| 音频 | **先用纯 Kotlin：`AudioTrack`（低延迟模式）出声、`AudioRecord` 收音**，音频层藏在接口后面，以后需要再换 Oboe | 见下文；不引入 NDK/CMake，别人 clone 下来就能编译 |
| 是否用 Kotlin Multiplatform 共享乐理和评分 | **不用** | 见下文 |
| 工程结构 | 单模块 `app`，按功能分包（`chord`、`tuner`、`metronome`、`strum`、`practice`、`audio`、`ui`、`i18n`） | 起步够用；纯逻辑包不依赖 Android，可以直接在 JVM 上跑单元测试 |
| 最低系统版本 | **Android 8.0（API 26）**，目标和编译用当前最新 | 低延迟音频路径（AAudio/MMAP）从 8.0 起可用，覆盖 97% 以上的设备；要放宽到 7.0 只改 `minSdk`（需要自己验证延迟） |
| 包名 | `com.example.tunebeatchord`（占位） | 自己发布时改 `app/build.gradle.kts` 里的 `namespace` 和 `applicationId` |
| 本机存储 | `SharedPreferences` + JSON 文件 | 数据量很小（设置、和弦进行、练习记录），不需要 Room |
| 多语言 | 脚本从 iOS 的译文生成 `strings.xml`（见 `tools/`） | 12 种语言只维护一份译文 |

### 音频：为什么先不用 Oboe

iOS 版的节拍器是「音频回调里按采样位置排点击」：时间精度来自**采样计数**，不来自定时器。这套思路搬到安卓后，精度同样只取决于「我们往声卡写了多少个采样」，和用 Oboe、AAudio 还是 `AudioTrack` 无关；后三者的区别只在**输出延迟**和**回调抖动**，而这两项影响的是「画面高亮和声音对不对齐」「扫弦评分里扣掉的延迟」，不是节拍本身准不准。

- `AudioTrack` + `PERFORMANCE_MODE_LOW_LATENCY` 在 Android 8.0 以上走的就是和 AAudio/Oboe 同一条 MMAP 通路；用高优先级线程循环 `write()`，渲染路径不分配内存（iOS 版已经是这样设计的），GC 影响很小。
- 收音用 `AudioRecord`（`VOICE_RECOGNITION` 或 `UNPROCESSED` 音源，关闭回声消除等处理），用 `getTimestamp` 对时。
- 不引入 NDK 和 CMake，编译环境只需要 JDK 和 Android SDK，开源后别人更容易上手。
- 代价：回调式的真低延迟（Oboe 的数据回调）和更稳的抖动表现拿不到。音频层是 `audio/AudioOutput`、`audio/AudioInput` 两个接口，节拍器、调音器、扫弦都只依赖接口。**如果真机上测出延迟或爆音问题，再加一个 Oboe 实现，业务代码不用改。** 这一点必须真机验证，见下面的未验证清单。

### 为什么不用 Kotlin Multiplatform

- iOS 版是纯 Swift，共有 425 个测试，是行为参照；要共享就得把 iOS 的乐理、评分、调度改成调 Kotlin 编出来的 framework，等于重写并重新验证 iOS 版，风险和工作量都大于收益。
- 要共享的纯逻辑总共约 2500 行，一次性移植一遍的成本不高；而且安卓端是**照着 iOS 的测试逐条移植**，行为一致由测试保证，不靠共用代码。
- KMP 还会带来 Gradle 多目标、Xcode 集成、Swift 与 Kotlin 互操作（枚举、可选值、协程）这些长期维护成本，对一个个人开源项目不划算。
- 真正能共享、也已经共享的是**数据**：译文（`app/tools/l10n/translations/*.json`）、乐器采样和 manifest（`Packages/TunerKit/.../Samples`，转成 OGG）、授权说明。以后两边行为出现差异，以 iOS 的测试和 `app/README.md` 的规则为准。

## 目录

```
android/
├── settings.gradle.kts / build.gradle.kts / gradle/    Gradle Kotlin DSL（版本集中在 gradle/libs.versions.toml）
├── app/                                                  唯一的模块
│   └── src/main/kotlin/com/example/tunebeatchord/
│       ├── chord/       和弦乐理、指法生成、贝斯和弦音位置、收藏（对应 ChordKit 的纯逻辑）
│       ├── tuner/       音高、音名、乐器与定弦、MPM 音高检测、平滑、调准判定
│       ├── rhythm/      拍号、切分、重音、渐进提速、静音训练（对应 RhythmKit / PracticeKit）
│       ├── metronome/   采样级调度、点击音合成、TAP 测速
│       ├── strum/       扫弦节奏型、起音检测、逐下评分、和弦进行、换和弦诊断
│       ├── practice/    练习记录与统计
│       ├── audio/       AudioTrack / AudioRecord、采样库、拨弦合成
│       ├── i18n/        取译文
│       └── ui/          Compose 界面
└── tools/               多语言转换脚本、采样转码脚本
```
