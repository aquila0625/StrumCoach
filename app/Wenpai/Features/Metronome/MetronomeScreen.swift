import MetronomeCore
import SwiftUI

/// 节拍器主界面（设计稿 01）。
struct MetronomeScreen: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(\.theme) private var theme
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            topBar
            BeatBlocks()
                .padding(.horizontal, 20)
                .padding(.top, 10)
            TempoDial(onTapNumber: { router.sheet = .bpm })
            chips
                .padding(.horizontal, 20)
                .padding(.top, 6)
            actions
                .padding(.horizontal, 34)
                .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .alert("出错了", isPresented: .constant(metronome.lastError != nil)) {
            Button("好") {}
        } message: {
            Text(metronome.lastError ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Text("节拍器")
                .font(.system(size: 30, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            if let label = trainingLabel {
                // 训练开着时提示一下，点按去训练页
                Button { router.tab = .training } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(theme.accentTint, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var chips: some View {
        HStack(spacing: 10) {
            Chip(caption: "拍号", action: { router.sheet = .rhythm }) {
                Text(metronome.config.timeSignature.displayName)
                    .font(.system(size: 17, weight: .semibold)).monospacedDigit()
            }
            Chip(caption: "\(metronome.config.subdivision.title)切分", action: { router.sheet = .rhythm }) {
                NoteGlyph(metronome.config.subdivision.glyph, color: theme.text)
            }
            Chip(caption: "音色", action: { router.sheet = .sound }) {
                Text(metronome.config.sound.title).font(.system(size: 17, weight: .semibold))
            }
        }
    }

    private var actions: some View {
        HStack {
            SideButton(title: "TAP", caption: "测速", action: metronome.tap)
                .accessibilityLabel("TAP 测速")
                .accessibilityHint("按节奏连续点按来设定速度")
            Spacer()
            PlayButton(isPlaying: metronome.isPlaying, action: metronome.togglePlay)
            Spacer()
            SideButton(title: timerText, caption: "计时", monospaced: true, action: metronome.resetTimer)
                .accessibilityLabel("计时 \(timerText)")
                .accessibilityHint("点按清零")
        }
    }

    private var trainingLabel: String? {
        let t = metronome.training
        switch (t.rampEnabled, t.muteEnabled) {
        case (true, true): return String(localized: "提速 + 静音", bundle: .appLanguage, locale: .appLanguage)
        case (true, false): return String(localized: "渐进提速", bundle: .appLanguage, locale: .appLanguage)
        case (false, true): return String(localized: "静音小节", bundle: .appLanguage, locale: .appLanguage)
        default: return nil
        }
    }

    private var timerText: String {
        let s = metronome.elapsedSeconds
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 拍子方块

private struct BeatBlocks: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(\.theme) private var theme

    var body: some View {
        let accents = metronome.config.accents
        let count = accents.count
        let gap: CGFloat = count > 8 ? 4 : (count > 6 ? 6 : 10)
        let radius: CGFloat = count > 8 ? 6 : 10
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    let isNow = metronome.currentBeat == i
                    BeatBlock(accent: accents[i], isNow: isNow, radius: radius,
                              pattern: metronome.displayedSubdivision,
                              activeSub: isNow && metronome.isPlaying ? metronome.currentSub : nil)
                        .onTapGesture { metronome.cycleAccent(at: i) }
                        .accessibilityElement()
                        .accessibilityLabel("第 \(i + 1) 拍，\(accents[i].title)")
                        .accessibilityHint("点按切换重音")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(height: 96)
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    let on = metronome.currentBeat == i
                    Text("\(i + 1)")
                        .font(.system(size: count > 12 ? 11 : 13, weight: on ? .bold : .regular)).monospacedDigit()
                        .foregroundStyle(on ? theme.text : theme.sub)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
            .accessibilityHidden(true)
            Text("点按方块切换重音：强 · 次强 · 弱 · 静音")
                .font(.system(size: 12))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                .foregroundStyle(theme.dim)
                .padding(.top, 8)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
        .card(radius: 20)
    }
}

private struct BeatBlock: View {
    @Environment(\.theme) private var theme
    let accent: AccentLevel
    let isNow: Bool
    let radius: CGFloat
    /// 方块里按这种切分分格（四分不分格）
    var pattern: Subdivision = .quarter
    /// 正在响的切分点（只有正在响的那一拍才有）
    var activeSub: Int?

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let h = geo.size.height * heightFraction
            ZStack {
                switch accent {
                case .strong: shape.fill(theme.accent)
                case .medium: shape.fill(theme.accent2)
                case .weak: shape.fill(isNow ? theme.weakNow : theme.weak)
                case .muted: shape.strokeBorder(theme.weak, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
                SubdivisionCells(pattern: pattern, active: activeSub, filled: accent != .muted)
                    .clipShape(shape)
            }
            .frame(height: h)
            .background {
                if isNow {
                    // 0 0 24px rgba(255,122,26,.55) 的橙色光晕
                    // 只画在方块外面（CSS box-shadow 不会透到半透明的方块底下）
                    shape.fill(theme.glow.opacity(0.55)).blur(radius: 12)
                        .mask {
                            ZStack {
                                Rectangle().padding(-40)
                                shape.blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        }
                }
            }
            .overlay {
                if isNow {
                    // box-shadow: 0 0 0 3px bg, 0 0 0 5px text —— 外面一圈 3pt 底色空隙 + 2pt 描边
                    RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous)
                        .stroke(theme.bg, lineWidth: 3).padding(-1.5)
                    RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                        .stroke(theme.text, lineWidth: 2).padding(-4)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .contentShape(Rectangle())
    }

    private var heightFraction: CGFloat {
        switch accent {
        case .strong: return 1
        case .medium: return 0.66
        case .weak, .muted: return 0.40
        }
    }
}

/// 一拍里的切分格：按节奏型的实际位置和长短在方块里画分隔（附点是 3:1、前八后十六是 2:1:1……）。
/// 播放时正在响的那一格保持原色，其余几格变淡，所以高亮会随着每个切分点移动。
/// 格子很窄时（例如 12/8 配十六分）分隔变成细线，不会挤乱。
struct SubdivisionCells: View {
    @Environment(\.theme) private var theme
    let pattern: Subdivision
    let active: Int?
    /// 方块是实心的（强、次强、弱）；静音拍是虚线框
    let filled: Bool

    /// 第 i 格在一拍里的起止位置（0…1）
    static func cell(_ pattern: Subdivision, _ i: Int) -> ClosedRange<Double> {
        let end = i + 1 < pattern.clickCount ? pattern.offset(i + 1) : 1
        return pattern.offset(i)...end
    }

    /// 分隔线宽度：按最窄那一格的宽度决定
    static func separatorWidth(boxWidth: CGFloat, pattern: Subdivision) -> CGFloat {
        let narrowest = (0..<pattern.clickCount).map { cell(pattern, $0) }.map { $0.upperBound - $0.lowerBound }.min() ?? 1
        let w = boxWidth * narrowest
        return w >= 14 ? 3 : (w >= 7 ? 2 : 1)
    }

    var body: some View {
        Canvas { ctx, size in
            let n = pattern.clickCount
            guard n > 1 else { return }
            let line = Self.separatorWidth(boxWidth: size.width, pattern: pattern)
            // 正在响：其他格盖一层淡色
            if let active, active < n {
                if filled {
                    for i in 0..<n {
                        let c = Self.cell(pattern, i)
                        let rect = CGRect(x: size.width * c.lowerBound, y: 0, width: size.width * (c.upperBound - c.lowerBound), height: size.height)
                        if i == active {
                            // 深色主题里再提亮一点，窄格也看得出
                            if !theme.isLight { ctx.fill(Path(rect), with: .color(.white.opacity(0.22))) }
                        } else {
                            ctx.fill(Path(rect), with: .color(theme.bg.opacity(theme.isLight ? 0.42 : 0.5)))
                        }
                    }
                } else {
                    // 虚线框：正在响的那一格填上淡色
                    let c = Self.cell(pattern, active)
                    ctx.fill(Path(CGRect(x: size.width * c.lowerBound, y: 0, width: size.width * (c.upperBound - c.lowerBound), height: size.height)),
                             with: .color(theme.weak.opacity(0.6)))
                }
            }
            // 分隔：实心方块用底色“切开”，虚线框用虚线色
            for i in 1..<n {
                let x = size.width * pattern.offset(i)
                let rect = CGRect(x: x - line / 2, y: 0, width: line, height: size.height)
                ctx.fill(Path(rect), with: .color(filled ? theme.bg : theme.weak))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 底部按钮

private struct Chip<Content: View>: View {
    @Environment(\.theme) private var theme
    let caption: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                content.foregroundStyle(theme.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(caption).font(.system(size: 11)).foregroundStyle(theme.sub)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .card(radius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct SideButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let caption: LocalizedStringKey
    var monospaced = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: monospaced ? 14 : 15, weight: .bold))
                    .tracking(monospaced ? 0 : 1)
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                Text(caption).font(.system(size: 10)).foregroundStyle(theme.sub)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .frame(width: 72, height: 56)
            .card(radius: 28, border: true)
        }
        .buttonStyle(PressableStyle())
    }
}

private struct PlayButton: View {
    @Environment(\.theme) private var theme
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(theme.accent)
                    .shadow(color: theme.glow.opacity(0.45), radius: 15, y: 10)
                if isPlaying {
                    Icon(kind: .pause, color: .white)
                } else {
                    Icon(kind: .playTriangle, color: .white).scaleEffect(1.35).offset(x: 3)
                }
            }
            .frame(width: 92, height: 92)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityLabel(isPlaying ? Text("暂停") : Text("播放"))
        .sensoryFeedback(.impact(weight: .medium), trigger: isPlaying)
    }
}

/// 按下时轻微缩小。
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Subdivision {
    /// 设计稿 parts1.js 的 N 表。
    var glyph: SubdivisionGlyph {
        typealias N = NoteGlyph.Note
        switch self {
        case .quarter: return .init(notes: [N(beams: 0)], tuplet: nil)
        case .eighth: return .init(notes: [N(beams: 1), N(beams: 1)], tuplet: nil)
        case .triplet: return .init(notes: [N(beams: 1), N(beams: 1), N(beams: 1)], tuplet: 3)
        case .sixteenth: return .init(notes: Array(repeating: N(beams: 2), count: 4), tuplet: nil)
        case .dotted: return .init(notes: [N(beams: 1, dotted: true), N(beams: 2)], tuplet: nil)
        case .eighthSixteenth: return .init(notes: [N(beams: 1), N(beams: 2), N(beams: 2)], tuplet: nil)
        case .sixteenthEighth: return .init(notes: [N(beams: 2), N(beams: 2), N(beams: 1)], tuplet: nil)
        case .syncopation: return .init(notes: [N(beams: 2), N(beams: 1), N(beams: 2)], tuplet: nil)
        }
    }
}
