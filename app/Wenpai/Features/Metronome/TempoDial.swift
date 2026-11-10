import MetronomeCore
import SwiftUI

/// BPM 圆环：沿圆环拖动调速，转一圈约 60 BPM，每变一个数轻震一下；点数字弹出数字键盘。
struct TempoDial: View {
    @Environment(MetronomeController.self) private var metronome
    @Environment(\.theme) private var theme
    let onTapNumber: () -> Void

    /// 一整圈对应的 BPM 变化量
    static let bpmPerTurn = 60.0
    private let size: CGFloat = 270
    private let height: CGFloat = 282

    @State private var dragStartBPM: Int?
    @State private var lastAngle: Double = 0
    @State private var accumulated: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            if theme.isLight {
                // .light .dial:before 的中心光晕
                RadialGradient(colors: [theme.accent.opacity(0.12), theme.accent.opacity(0)], center: .center, startRadius: 0, endRadius: 150)
                    .frame(width: 300, height: 300)
                    .offset(y: -4)
                    .allowsHitTesting(false)
            }
            DialFace(value: (Double(metronome.displayBPM) - 20) / 380)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .gesture(rotation, including: metronome.tempoIsControlledByTraining ? .subviews : .all)
                .accessibilityElement()
                .accessibilityLabel("速度")
                .accessibilityValue("\(metronome.displayBPM) BPM")
                .accessibilityAdjustableAction { direction in
                    metronome.nudge(direction == .increment ? 1 : -1)
                }
                .padding(.top, 6)

            Button(action: { if !metronome.tempoIsControlledByTraining { onTapNumber() } }) {
                VStack(spacing: 0) {
                    Text("\(metronome.displayBPM)")
                        .font(.system(size: 92, weight: .thin))
                        .tracking(-2)
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                        .frame(height: 92)
                        .contentTransition(.numericText(value: Double(metronome.displayBPM)))
                    Text("BPM")
                        .font(.system(size: 12)).tracking(3)
                        .foregroundStyle(theme.sub)
                        .padding(.top, 4)
                    Text(metronome.tempoIsControlledByTraining ? String(localized: "渐进提速控制中", bundle: .appLanguage, locale: .appLanguage) : TempoTerm.name(for: Double(metronome.displayBPM)))
                        .font(.system(size: 15))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: 190)
                        .padding(.top, 8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(metronome.displayBPM) BPM，点按输入速度")
            .frame(maxHeight: .infinity)
            .offset(y: -3)

            HStack {
                StepButton(symbol: "−", label: String(localized: "减慢", bundle: .appLanguage, locale: .appLanguage)) { metronome.nudge(-1) }
                Spacer()
                StepButton(symbol: "+", label: String(localized: "加快", bundle: .appLanguage, locale: .appLanguage)) { metronome.nudge(1) }
            }
            .padding(.horizontal, 22)
            .opacity(metronome.tempoIsControlledByTraining ? 0.4 : 1)
            .allowsHitTesting(!metronome.tempoIsControlledByTraining)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 14)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: metronome.displayBPM)
    }

    /// 以圆心为轴累计手指转过的角度：360° = 60 BPM。
    private var rotation: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { g in
                let c = CGPoint(x: size / 2, y: size / 2)
                let angle = atan2(Double(g.location.y - c.y), Double(g.location.x - c.x)) * 180 / .pi
                if dragStartBPM == nil {
                    dragStartBPM = metronome.bpm
                    let a0 = atan2(Double(g.startLocation.y - c.y), Double(g.startLocation.x - c.x)) * 180 / .pi
                    lastAngle = a0
                    accumulated = 0
                }
                var delta = angle - lastAngle
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }
                accumulated += delta
                lastAngle = angle
                let target = Double(dragStartBPM!) + accumulated / 360 * Self.bpmPerTurn
                let clamped = Int(min(max(target.rounded(), 20), 400))
                if clamped != metronome.bpm { metronome.bpm = clamped }
            }
            .onEnded { _ in dragStartBPM = nil }
    }
}

/// 圆环本体（parts1.js 的 dialSvg）：刻度、底轨、进度弧、旋钮。
private struct DialFace: View {
    @Environment(\.theme) private var theme
    let value: Double

    var body: some View {
        Canvas { ctx, size in
            let c = size.width / 2
            let r: CGFloat = 116
            let start = -150.0, span = 300.0
            func pt(_ deg: Double, _ rr: CGFloat) -> CGPoint {
                let a = (deg - 90) * .pi / 180
                return CGPoint(x: c + rr * cos(a), y: c + rr * sin(a))
            }
            var d = start
            while d <= start + span + 0.1 {
                let major = Int((d - start).rounded()) % 30 == 0
                var tick = Path()
                tick.move(to: pt(d, r + 12))
                tick.addLine(to: pt(d, r + (major ? 22 : 17)))
                ctx.stroke(tick, with: .color(major ? theme.dim : theme.tick),
                           style: StrokeStyle(lineWidth: major ? 2 : 1.4, lineCap: .round))
                d += 5
            }
            func arc(_ a0: Double, _ a1: Double) -> Path {
                var p = Path()
                p.addArc(center: CGPoint(x: c, y: c), radius: r, startAngle: .degrees(a0 - 90), endAngle: .degrees(a1 - 90), clockwise: false)
                return p
            }
            let thick = StrokeStyle(lineWidth: 12, lineCap: .round)
            ctx.stroke(arc(start, start + span), with: .color(theme.track), style: thick)
            let end = start + span * min(max(value, 0), 1)
            ctx.stroke(arc(start, end), with: .color(theme.accent), style: thick)
            let k = pt(end, r)
            let knob = Path(ellipseIn: CGRect(x: k.x - 14, y: k.y - 14, width: 28, height: 28))
            ctx.fill(knob, with: .color(.white))
            ctx.stroke(knob, with: .color(theme.knobStroke), lineWidth: 1.5)
            ctx.fill(Path(ellipseIn: CGRect(x: k.x - 5, y: k.y - 5, width: 10, height: 10)), with: .color(theme.accent))
        }
    }
}

/// ± 按钮：点按 ±1；长按连续变化，并逐渐加速。
private struct StepButton: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Text(symbol)
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(theme.text)
            .frame(width: 52, height: 52)
            .card(radius: 26, border: true)
            .scaleEffect(repeater == nil ? 1 : 0.94)
            .animation(.easeOut(duration: 0.1), value: repeater == nil)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard repeater == nil else { return }
                        action()
                        repeater = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            var interval = 0.14
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(for: .seconds(interval))
                                interval = max(0.025, interval * 0.9)
                            }
                        }
                    }
                    .onEnded { _ in
                        repeater?.cancel()
                        repeater = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}
