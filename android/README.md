# TuneBeatChord / 调音节拍和弦库 · Android

原生 Kotlin + Jetpack Compose 的安卓版，和 `../app`（iOS）放在同一个仓库里。功能和 iOS 版一致：调音器、节拍器、和弦库、扫弦训练、练习记录，全部免费、不联网、不收集数据、没有账号、没有内购。

功能和行为以 iOS 版为准（见 `../app/README.md`），逻辑是照着 iOS 的测试逐条移植的。

## 编译和运行

需要 JDK 17 以上（Android Studio 自带的就行）和 Android SDK（`compileSdk 37`）。没有 NDK、没有 CMake。

```bash
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties     # 或者设环境变量 ANDROID_HOME；local.properties 不入库
./gradlew :app:assembleDebug                                    # 产物：app/build/outputs/apk/debug/app-debug.apk
./gradlew :app:testDebugUnitTest                                # 单元测试（在 JVM 上跑，不需要模拟器）
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.example.tunebeatchord/.MainActivity
```

也可以直接用 Android Studio 打开 `android/` 目录。麦克风权限在第一次进调音器或扫弦跟练时才会弹出；用模拟器的话，麦克风没有真实输入（见下面的未验证清单）。

要自己发布：把 `app/build.gradle.kts` 里的 `namespace` 和 `applicationId` 改成自己的，换掉 `res/drawable/ic_launcher.xml`，签名自己配（仓库里没有任何密钥，`.gitignore` 已排除 `*.jks`、`*.keystore`、`local.properties`）。

## 重新生成多语言和采样

```bash
python3 -I android/tools/l10n_to_android.py            # 改了 app/tools/l10n/translations/*.json 后重新生成 strings.xml 和 StringTable.kt
python3 -I android/tools/l10n_to_android.py --check    # 只检查是否一致
python3 -I android/tools/convert_samples.py            # 把 iOS 的乐器采样（CAF/AAC）转成 OGG，需要 ffmpeg
```

界面里和 iOS 一样直接用简体中文原文当键（`tr("节拍器")`）；`StringsCoverageTest` 保证源码里用到的键都有译文、12 种语言都齐、占位符一致。语言在设置里切换，立刻生效（不依赖系统语言）。

## 已做（和 iOS 版对应）

| 功能 | 安卓上的实现 | 测试 |
|---|---|---|
| 和弦库 | 10 种和弦类型 × 12 个根音、吉他/尤克里里指法生成（含人工校对的标准按法）、贝斯和弦音位置、Canvas 指法图、翻把位、收藏、左手模式、试听（扫弦：按节奏型一小节一小节循环；分解：按指法一圈一圈循环，贝斯是根音-五度-八度-五度）、扫弦 / 分解切换、自定义分解指法和自定义扫弦节奏型（编辑、试听、命名、每类乐器最多 10 个） | 乐理、拼法、按法规则、贝斯位置、收藏（逐条对照 iOS 的 ChordKit 测试） |
| 节拍器 | 采样级调度（无累计漂移、改动下一拍生效）、重音（强/次强/弱/静音，预设）、8 种切分、16 种合成音色、TAP、速度圆环、渐进提速（停止/保持/循环）、静音小节和随机静音（同种子与 iOS 逐位一致）、练习记录 | 调度、训练、10 分钟离线渲染（120 BPM 和 137 BPM@44.1 kHz 零漂移，渐进提速 10 分钟） |
| 调音器 | MPM 音高检测、平滑、吉他/贝斯/尤克里里/提琴/中提琴/大提琴定弦、半音阶、自动识别弦或锁定一根弦、±5 音分持续 0.5 秒判定调准（只提示一次）、“叮咚”提示音、参考音（真实采样/正弦/拨弦合成）、标准音 A4 | 检测精度（含噪声、八度误判）、平滑、判定、模型 |
| 扫弦训练 | 节奏型（12 种预设 + 自定义，和和弦库共用；收藏、已掌握、筛选；连续 3 次 ≥ 90 分建议标为已掌握）、和弦进行（点按编辑、长按拖动排序、常用进行、我的进行、保存）、听示范、跟练（多遍）、起音检测、逐下评分（±60 毫秒准、±120 毫秒偏）、按和弦分段、换和弦诊断、延迟校准、成绩历史 | 评分、起音检测（合成扫弦）、进行、诊断、多遍 |
| 练习计时 | 训练页卡片：今天累计的练习时长、目标分钟数、到点提醒一次（每天一次：顶部提示条 + 震动）、可选自动停止 | 今天累计、每天只提醒一次、旧版存档迁移 |
| 我的 / 设置 | 本周时长、连续打卡、近 7 天、练习历史；主题、12 种语言、音名（字母/唱名/德语 H）、左手模式、A4 | 统计（含夏令时、跨时区）、设置 |
| 隐私 | 无 INTERNET 权限，无统计/广告/支付依赖，`allowBackup=false` | `PrivacyTest` |

单元测试共 220 个，全部通过。

## 和 iOS 版的差异、还没做的部分

- **没做**：扫弦示范只放 8 小节以内（和 iOS 一样）；和弦块的右键式菜单（iOS 长按出菜单，安卓长按是拖动排序，修改 / 复制 / 删除放在点开的编辑面板里）；和弦库分解时指法图上的“拨弦动画”；贝斯的自定义指法只支持“弦号 + R”，没有 iOS 那样按把位框细分；
- **没做**：人声报数和“我的声音”两种节拍音色（设置里不显示，iOS 存下来的这两种设置会按咔嗒/木鱼播放）；练习计时到点时 App 在后台的**系统通知**（需要通知权限和前台服务，现在只在 App 里显示提示条并震动）；跟拍震动已接上，但没在真机上确认手感；
- **没做**：节拍器退到后台继续响并带通知栏控制（需要前台服务）；耳机拔出、来电时自动暂停；iPad 式的大屏排版（现在只按手机竖屏做，`screenOrientation=portrait`）；
- 乐器采样从 AAC 转成了 Vorbis（OGG，约 3.6 MB），声音和 iOS 版是同一批录音；
- 起音时间换算用 `AudioRecord.getTimestamp` 和 `AudioTrack.getTimestamp`，没有 iOS 那样直接读 `inputLatency`/`outputLatency`；用「延迟校准」补剩下的差；
- 界面是 Material 3 的底层组件加自绘，配色沿用 iOS 版（深浅色都是渐变）。节拍器、调音器、和弦库、训练、我的这几页的版式已按 iOS 版对齐（拍子方块分阶、速度圆环、乐器图标卡片、表盘、星标菜单、偏好设置卡片、语言面板等）；扫弦页（和弦进行卡片、节奏型标签条、格子卡片）、训练页（节奏型滑动卡片、练习计时）、和弦库的分解模式也已按 iOS 版排版；各种面板的细节、阴影和光晕还不是逐像素复刻。
- 升降号（♯ ♭）用内置的 3 个字形的小字体画在字母右上方，因为有些手机的系统字体缺这两个符号，回退字体又宽又歪，会在窄按钮里被裁掉。

## 未验证清单（需要真机，这里没有声称已验证）

已在 API 37 的 arm64 模拟器（`Medium_Phone`）上验证：应用能启动；训练、节拍器、调音器、和弦库、我的五个页面都能打开；节拍器能播放（音频输出在系统里处于活动状态，拍子高亮跟着走）；调音器能打开麦克风（系统出现麦克风指示）；扫弦示范能循环播放并高亮格子；扫弦跟练能走完两遍并出评分卡（模拟器的麦克风没有输入，所以得分是 0、漏 48）；切换语言立刻生效。

**必须真机才能确认**：

1. 麦克风收音的实际效果：调音器在真实琴弦上的稳定度、扫弦起音检测在真实吉他/尤克里里、不同距离和房间噪声下的命中率。起音检测目前只在合成信号上测过。
2. 延迟：`AudioTrack`（低延迟模式）的实际输出延迟和抖动、各机型上的 `getTimestamp` 是否可靠、录音和播放的相对偏差，以及延迟校准能不能把偏差补到 ±20 毫秒以内。**如果真机上节拍有爆音、扫弦评分系统性偏差很大，下一步是加一个 Oboe 实现**（`audio/AudioEngine` 的公开接口不用变）。
3. OGG 采样里拉弦音（提琴、中提琴、大提琴）的循环点接缝：转码后帧数对得上（按 manifest 对齐），但有没有听得出的咔哒要用耳朵听。
4. 蓝牙耳机、有线耳机下的节拍声同步，外放时的回声。
5. 长时间播放（10 分钟以上）时后台被系统杀掉的情况、省电模式的影响。
6. 不同屏幕尺寸、字体放大、深色模式下的排版（只在一台 1080×2400 的模拟器上看过，主要是浅色）。

## 许可证

Apache-2.0，见仓库根目录的 `LICENSE`。乐器采样不在 Apache 授权范围内，沿用原来的授权，说明在 `app/src/main/assets/samples/LICENSES.md`（和 `../Packages/TunerKit/Sounds/LICENSES.md` 相同），仓库根目录的 `NOTICE` 里也有。

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
