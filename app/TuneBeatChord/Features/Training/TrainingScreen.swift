import MetronomeCore
import SwiftUI

/// 训练页（设计稿 03）：最上面是主打的扫弦节奏型大卡片；下面是节拍器的渐进提速、静音小节、练习计时。
/// 提速、静音和计时可以同时开。
/// 训练设置对节拍器全局生效：在这里或主界面开始播放都会按训练方案走。
struct TrainingScreen: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(Router.self) private var router
    @Environment(StrumTrainer.self) private var strum
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("训练").font(.system(size: 30, weight: .bold)).tracking(0.5).foregroundStyle(theme.text)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 12) {
                    StrumHeroCard(trainer: strum)
                    Text("节拍器训练")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                    rampCard
                    muteCard
                    timerCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            startButton
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
        // 切到别的标签：卡片上的“听一听”立刻停
        .onDisappear { if strum.phase == .preview { strum.teardown() } }
    }

    // MARK: 渐进提速

    private var rampCard: some View {
        let t = metronome.training
        let ramp = t.ramp
        // 只有提速开着并且在播放时才显示实时进度
        let bar = t.rampEnabled && (metronome.isPlaying || metronome.liveBar != nil) ? (metronome.liveBar ?? 0) : nil
        let progress = ramp.progress(atBar: bar ?? 0)
        let current = t.rampEnabled ? (metronome.liveBPM ?? ramp.startBPM) : ramp.startBPM
        return TrainingCard(title: "渐进提速", subtitle: t.rampSummary, isOn: trainingBinding(\.rampEnabled),
                            onEdit: { router.sheet = .ramp }) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(current)").font(.system(size: 48, weight: .ultraLight)).monospacedDigit()
                    Text("BPM 当前速度").font(.system(size: 13)).foregroundStyle(theme.sub)
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(theme.accent)
                }
                .padding(.top, 14)
                .padding(.bottom, 10)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.line)
                        Capsule().fill(theme.accent).frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("\(ramp.startBPM)")
                    Spacer()
                    if let bar {
                        Text("第 \(bar + 1) 小节 · 还剩 \(Units.bars(max(0, ramp.barsToTarget - bar)))")
                    } else {
                        Text("\(Units.bars(ramp.barsToTarget))后到达目标 · \(ramp.endBehavior.title)")
                    }
                    Spacer()
                    Text("\(ramp.targetBPM)")
                }
                .font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(theme.sub)
                .padding(.top, 6)
            }
        }
    }

    // MARK: 静音

    private var muteCard: some View {
        let t = metronome.training
        return TrainingCard(title: "静音小节", subtitle: t.muteSummary, isOn: trainingBinding(\.muteEnabled),
                            onEdit: { router.sheet = .mute }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(muteCells, id: \.index) { cell in
                        ZStack {
                            if cell.muted {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(theme.dim, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                // 用图标而不是文字：任何语言都不会碰到虚线边框
                                Image(systemName: "speaker.slash.fill")
                                    .font(.system(size: 11)).foregroundStyle(theme.sub)
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(cell.current ? theme.accent : theme.accentSoft)
                            }
                        }
                        .frame(height: 34)
                    }
                }
                .padding(.top, 14)
                .accessibilityHidden(true)
                Text("静音时保持心里的节拍，恢复时检查有没有跑快或跑慢")
                    .font(.system(size: 12)).foregroundStyle(theme.sub)
                    .padding(.top, 8)
            }
        }
    }

    private struct MuteCell { var index: Int; var muted: Bool; var current: Bool }

    /// 8 个格子：按小节静音时是当前 8 小节一组；随机静音时是当前小节起的 8 拍。
    private var muteCells: [MuteCell] {
        let mute = metronome.training.mute
        let bar = metronome.liveBar ?? 0
        switch mute.pattern {
        case .bars:
            let first = bar / 8 * 8
            return (0..<8).map { i in
                MuteCell(index: i, muted: mute.isMuted(bar: first + i, beat: 0), current: metronome.liveBar == first + i)
            }
        case .randomBeats:
            let beats = metronome.config.timeSignature.beatsPerBar
            let beat = metronome.currentBeat ?? 0
            return (0..<8).map { i in
                let n = bar * beats + beat + i
                return MuteCell(index: i, muted: mute.isMuted(bar: n / beats, beat: n % beats), current: i == 0 && metronome.isPlaying)
            }
        }
    }

    // MARK: 练习计时

    private var timerCard: some View {
        let t = metronome.training
        let goal = t.timerMinutes * 60
        let done = metronome.todaySeconds
        let ratio = goal > 0 ? min(1, Double(done) / Double(goal)) : 0
        return TrainingCard(title: "练习计时", subtitle: t.timerSummary, isOn: timerBinding,
                            onEdit: { router.sheet = .timer }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(theme.line, lineWidth: 7)
                    Circle().trim(from: 0, to: ratio)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 54, height: 54)
                .padding(5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Self.clock(done)).font(.system(size: 30, weight: .light)).monospacedDigit()
                        Text("/ \(Self.clock(goal))").font(.system(size: 15)).monospacedDigit().foregroundStyle(theme.sub)
                    }
                    Text("今天已练 \(ratio.formatted(.percent.precision(.fractionLength(0)).locale(.appLanguage)))").font(.system(size: 12)).foregroundStyle(theme.sub)
                }
                Spacer()
            }
            .padding(.top, 12)
        }
    }

    private static func clock(_ seconds: Int) -> String {
        seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                        : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: 开始

    private var startButton: some View {
        Button {
            metronome.togglePlay()
        } label: {
            HStack(spacing: 10) {
                Icon(kind: metronome.isPlaying ? .pause : .playTriangle, color: .white)
                    .scaleEffect(metronome.isPlaying ? 0.6 : 0.85)
                    .frame(width: 22, height: 24)
                (metronome.isPlaying ? Text("停止训练") : Text("开始训练")).font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func trainingBinding(_ key: WritableKeyPath<TrainingOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { metronome.training[keyPath: key] },
            set: { metronome.training[keyPath: key] = $0 })
    }

    private var timerBinding: Binding<Bool> {
        Binding(
            get: { metronome.training.timerEnabled },
            set: { on in
                metronome.training.timerEnabled = on
                if on { metronome.requestNotificationPermission() }
            })
    }
}

/// 训练卡片：标题 + 说明 + 开关，下面是内容。点卡片打开参数面板。
private struct TrainingCard<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: LocalizedStringKey
    let subtitle: String
    let isOn: Binding<Bool>
    let onEdit: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.text)
                    HStack(spacing: 4) {
                        Text(subtitle).lineLimit(2).minimumScaleFactor(0.85)
                        Icon(kind: .chevron, color: theme.sub).rotationEffect(.degrees(-90)).scaleEffect(0.8)
                    }
                    .font(.system(size: 13)).foregroundStyle(theme.sub)
                }
                Spacer()
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .tint(theme.green)
            }
            content
        }
        .foregroundStyle(theme.text)
        .padding(16)
        .card(radius: 20)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityAction(named: "修改参数", onEdit)
    }
}

// MARK: - 参数面板

/// 一行“标签  −  值  +”。长按 ± 连续变化。
struct ValueStepper: View {
    @Environment(\.theme) private var theme
    @Environment(\.sheetCard) private var cardColor
    let title: LocalizedStringKey
    let value: Int
    /// 数值的显示方式（带单位，随语言变化）
    var display: (Int) -> String = { "\($0)" }
    let range: ClosedRange<Int>
    var step = 1
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(theme.text)
            Spacer()
            RepeatingButton(symbol: "−", enabled: value > range.lowerBound) { set(value - step) }
            Text(display(value))
                .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                .foregroundStyle(theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(minWidth: 64)
            RepeatingButton(symbol: "+", enabled: value < range.upperBound) { set(value + step) }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(display(value))
        .accessibilityAdjustableAction { set($0 == .increment ? value + step : value - step) }
    }

    private func set(_ v: Int) { onChange(min(max(v, range.lowerBound), range.upperBound)) }
}

/// 带单位的数量（随语言变化）。小节数在 String Catalog 里有复数变体（俄语三种形式）；
/// 分钟用系统的时长格式化，本身按语言处理单复数。带数量的句子都先用这里生成“N 小节”再嵌进去。
enum Units {
    static func bpm(_ v: Int) -> String { "\(v) BPM" }
    static func hertz(_ v: Int) -> String { "\(v) Hz" }
    static func bars(_ v: Int) -> String { String(localized: "\(v) 小节", bundle: .appLanguage, locale: .appLanguage) }
    static func minutes(_ v: Int) -> String {
        Duration.seconds(v * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(.appLanguage))
    }
    static func percent(_ v: Int) -> String { (Double(v) / 100).formatted(.percent.precision(.fractionLength(0)).locale(.appLanguage)) }
}

/// 点按一次，长按连续触发并逐渐加速。
struct RepeatingButton: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Text(symbol)
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(enabled ? theme.text : theme.dim)
            .frame(width: 34, height: 34)
            .background(theme.card2, in: Circle())
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, repeater == nil else { return }
                        action()
                        repeater = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            var interval = 0.12
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(for: .seconds(interval))
                                interval = max(0.03, interval * 0.9)
                            }
                        }
                    }
                    .onEnded { _ in
                        repeater?.cancel()
                        repeater = nil
                    }
            )
            .sensoryFeedback(.selection, trigger: repeater == nil)
    }
}

struct RampEditor: View {
    @Environment(MetronomeController.self) private var metronome

    var body: some View {
        let r = metronome.training.ramp
        VStack(spacing: 8) {
            SectionLabel(title: "速度", note: r.isAscending ? "目标比起始低就是渐进减速" : "渐进减速").padding(.top, -14)
            ValueStepper(title: "起始", value: r.startBPM, display: Units.bpm, range: Tempo.range) { update(start: $0) }
            ValueStepper(title: "目标", value: r.targetBPM, display: Units.bpm, range: Tempo.range) { update(target: $0) }
            SectionLabel(title: "节奏")
            ValueStepper(title: "每档变化", value: r.step, display: Units.bpm, range: 1...20) { update(step: $0) }
            ValueStepper(title: "每档持续", value: r.barsPerStep, display: Units.bars, range: 1...32) { update(bars: $0) }
            SectionLabel(title: "到达目标后")
            Segmented(options: RampSettings.EndBehavior.allCases, selected: r.endBehavior, title: \.title) { update(end: $0) }
        }
        .padding(.bottom, 8)
    }

    private func update(start: Int? = nil, target: Int? = nil, step: Int? = nil, bars: Int? = nil, end: RampSettings.EndBehavior? = nil) {
        let r = metronome.training.ramp
        metronome.training.ramp = RampSettings(startBPM: start ?? r.startBPM, targetBPM: target ?? r.targetBPM,
                                               step: step ?? r.step, barsPerStep: bars ?? r.barsPerStep,
                                               endBehavior: end ?? r.endBehavior)
    }
}

struct MuteEditor: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(\.theme) private var theme
    @Environment(\.sheetCard) private var cardColor

    private enum Kind: String, CaseIterable { case bars, random }

    var body: some View {
        let mute = metronome.training.mute
        VStack(spacing: 8) {
            SectionLabel(title: "方式").padding(.top, -14)
            Segmented(options: Kind.allCases, selected: kind(of: mute), title: { $0 == .bars ? String(localized: "按小节", bundle: .appLanguage, locale: .appLanguage) : String(localized: "随机静音", bundle: .appLanguage, locale: .appLanguage) }) { k in
                switch k {
                case .bars: metronome.training.mute = .bars(audible: 3, muted: 1)
                case .random: metronome.training.mute = .randomBeats(probability: 0.25, seed: UInt64.random(in: 1...UInt64.max), keepsDownbeat: true)
                }
            }
            switch mute.pattern {
            case let .bars(audible, muted):
                SectionLabel(title: "循环")
                ValueStepper(title: "有声", value: audible, display: Units.bars, range: 1...16) {
                    metronome.training.mute = .bars(audible: $0, muted: muted)
                }
                ValueStepper(title: "静音", value: muted, display: Units.bars, range: 1...16) {
                    metronome.training.mute = .bars(audible: audible, muted: $0)
                }
            case let .randomBeats(probability, seed):
                SectionLabel(title: "概率", note: "同一组随机结果可以重复练")
                ValueStepper(title: "静音的拍", value: Int((probability * 100).rounded()), display: Units.percent, range: 5...90, step: 5) {
                    metronome.training.mute = .randomBeats(probability: Double($0) / 100, seed: seed, keepsDownbeat: mute.keepsDownbeat)
                }
                Toggle(isOn: Binding(get: { mute.keepsDownbeat }, set: {
                    metronome.training.mute = .randomBeats(probability: probability, seed: seed, keepsDownbeat: $0)
                })) {
                    Text("每小节第一拍总是响").font(.system(size: 15)).foregroundStyle(theme.text)
                }
                .tint(theme.green)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.bottom, 8)
    }

    private func kind(of mute: MuteSettings) -> Kind {
        if case .bars = mute.pattern { return .bars }
        return .random
    }
}

struct TimerEditor: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(\.theme) private var theme
    @Environment(\.sheetCard) private var cardColor

    var body: some View {
        @Bindable var m = metronome
        VStack(spacing: 8) {
            SectionLabel(title: "今天的目标", note: "按当天累计的练习时间算").padding(.top, -14)
            ValueStepper(title: "目标", value: metronome.training.timerMinutes, display: Units.minutes, range: 5...180, step: 5) {
                metronome.training.timerMinutes = $0
            }
            SectionLabel(title: "到时")
            Toggle(isOn: $m.training.autoStop) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自动停止").font(.system(size: 15)).foregroundStyle(theme.text)
                    Text("到点时先提醒，再停止节拍器").font(.system(size: 12)).foregroundStyle(theme.sub)
                }
            }
            .tint(theme.green)
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.bottom, 8)
    }
}
