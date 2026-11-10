import SwiftUI

/// 半圆形音分表盘：−50…+50 音分，每 5 音分一格，准音区（±5）为绿色。几何尺寸沿用设计稿 04（340×230 的画布）。
struct TunerGauge: View {
    /// 相对目标的偏差；nil 表示没有信号（指针回中并变淡）。
    var cents: Double?
    var palette: TunerPalette
    var strings: TunerStrings = .current

    private let designWidth: CGFloat = 340
    private let designHeight: CGFloat = 230
    private let cx: CGFloat = 170
    private let cy: CGFloat = 210
    private let r: CGFloat = 160

    private var inTune: Bool { cents.map { abs($0) <= TunerDefaults.inTuneCents } ?? false }
    private var needleAngle: Double { max(-50, min(50, cents ?? 0)) * 1.2 }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / designWidth
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    ctx.scaleBy(x: scale, y: scale)
                    drawScale(&ctx)
                }
                needle
                    .frame(width: designWidth, height: designHeight)
                    .scaleEffect(scale, anchor: .topLeading)
            }
            .frame(width: designWidth * scale, height: designHeight * scale)
        }
        .aspectRatio(designWidth / designHeight, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(strings.gauge)
        .accessibilityValue(cents.map { "\(Int($0.rounded()).formatted(.number.sign(strategy: .always()).locale(L10n.locale))) \(strings.cents)" } ?? strings.noSignal)
    }

    private func point(_ deg: Double, _ radius: CGFloat) -> CGPoint {
        let a = (deg - 90) * .pi / 180
        return CGPoint(x: cx + radius * CGFloat(cos(a)), y: cy + radius * CGFloat(sin(a)))
    }

    private func drawScale(_ ctx: inout GraphicsContext) {
        for v in stride(from: -50, through: 50, by: 5) {
            let d = Double(v) * 1.2
            let major = v % 25 == 0
            var p = Path()
            p.move(to: point(d, r))
            p.addLine(to: point(d, r - (major ? 22 : 13)))
            let color: Color = abs(v) <= 5 ? palette.green : (major ? palette.sub : palette.weak)
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: major ? 2.5 : 1.6, lineCap: .round))
            if major {
                let label = v > 0 ? "+\(v)" : (v < 0 ? "−\(-v)" : "0")
                ctx.draw(Text(label).font(.system(size: 12).monospacedDigit()).foregroundColor(palette.dim),
                         at: point(d, r - 40), anchor: .center)
            }
        }
        // 准音区弧线
        var zone = Path()
        zone.addArc(center: CGPoint(x: cx, y: cy), radius: r + 10,
                    startAngle: .degrees(-90 - 6), endAngle: .degrees(-90 + 6), clockwise: false)
        ctx.stroke(zone, with: .color(palette.green.opacity(0.9)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
    }

    private var needle: some View {
        let color = cents == nil ? palette.weak : (inTune ? palette.green : palette.accent)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: cx, y: cy - (r - 8)))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Circle().fill(color).frame(width: 16, height: 16).position(x: cx, y: cy)
        }
        .frame(width: designWidth, height: designHeight)
        .rotationEffect(.degrees(needleAngle), anchor: UnitPoint(x: cx / designWidth, y: cy / designHeight))
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: needleAngle)
        .animation(.easeOut(duration: 0.2), value: color)
    }
}
