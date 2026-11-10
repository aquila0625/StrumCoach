import SwiftUI

/// 乐器的线条图标（自绘，28×28 的设计坐标）：吉他、贝斯、尤克里里、小提琴、中提琴、大提琴；“自动”用波形。
public struct InstrumentIcon: View {
    public let family: InstrumentFamily
    public var color: Color
    public var size: CGFloat

    public init(_ family: InstrumentFamily, color: Color, size: CGFloat = 28) {
        self.family = family; self.color = color; self.size = size
    }

    public var body: some View {
        Group {
            if family == .chromatic {
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.7, weight: .medium))
                    .foregroundStyle(color)
            } else {
                Canvas { ctx, canvas in
                    let s = canvas.width / 28
                    ctx.scaleBy(x: s, y: s)
                    draw(&ctx)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
    }

    private func union(_ a: Path, _ b: Path) -> Path {
        Path(a.cgPath.union(b.cgPath))
    }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addLine(to: b); return p
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let stroke = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
        let thin = StrokeStyle(lineWidth: 1.1, lineCap: .round)
        let shade = GraphicsContext.Shading.color(color)
        switch family {
        case .guitar, .ukulele, .bass:
            // 斜放（像常见的吉他图标），绕中心转 -35°
            ctx.translateBy(x: 14, y: 14)
            ctx.rotate(by: .degrees(35))
            ctx.translateBy(x: -14, y: -14)
            // 琴体：上下两个圆合成葫芦形；尤克里里琴体更小、琴颈更短；贝斯琴颈更长、琴体更窄
            let (upper, lower, neckTop): ((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat), CGFloat) = switch family {
            case .ukulele: ((14, 17, 3.7), (14, 22.2, 4.7), 6)
            case .bass: ((14, 17.5, 3.2), (14, 22.4, 4.4), 1.5)
            default: ((14, 16.2, 4.1), (14, 21.8, 5.3), 3)
            }
            let body = union(circle(upper.0, upper.1, upper.2), circle(lower.0, lower.1, lower.2))
            ctx.stroke(body, with: shade, style: stroke)
            // 琴颈和琴头
            let neckBottom = upper.1 - upper.2 + 0.6
            ctx.stroke(line(CGPoint(x: 14, y: neckTop + 1.6), CGPoint(x: 14, y: neckBottom)), with: shade, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            ctx.fill(Path(roundedRect: CGRect(x: 12.4, y: neckTop - 1.2, width: 3.2, height: 2.8), cornerRadius: 0.8), with: shade)
            if family == .bass {
                // 四个弦钮
                for (x, y) in [(11.4, neckTop - 0.6), (11.4, neckTop + 1.2), (16.6, neckTop - 0.6), (16.6, neckTop + 1.2)] {
                    ctx.fill(circle(x, y, 0.55), with: shade)
                }
            } else {
                // 音孔
                ctx.stroke(circle(14, upper.1 + upper.2 * 0.45, family == .ukulele ? 1.3 : 1.6), with: shade, style: thin)
            }
            // 琴桥
            let bridgeY = lower.1 + lower.2 * 0.35
            ctx.stroke(line(CGPoint(x: 12, y: bridgeY), CGPoint(x: 16, y: bridgeY)), with: shade, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        case .violin, .viola, .cello:
            // 提琴：上下两个椭圆合成带腰的琴体，琴头是涡卷，f 孔两道；大提琴更大、底下有尾柱
            let scale: CGFloat = family == .cello ? 1.12 : (family == .viola ? 1.04 : 0.96)
            let cy: CGFloat = family == .cello ? 15.5 : 16.5
            func y(_ v: CGFloat) -> CGFloat { cy + (v - 16.5) * scale }
            let body = union(ellipse(14, y(13.6), 4.3 * scale, 3.7 * scale), ellipse(14, y(20.6), 5.2 * scale, 4.4 * scale))
            ctx.stroke(body, with: shade, style: stroke)
            let top = y(13.6) - 3.7 * scale
            ctx.stroke(line(CGPoint(x: 14, y: top + 0.3), CGPoint(x: 14, y: top - 6 * scale)), with: shade, style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
            ctx.stroke(circle(14, top - 6.8 * scale, 1.2), with: shade, style: thin)
            // f 孔
            for x in [11.6, 16.4] as [CGFloat] {
                var f = Path()
                f.move(to: CGPoint(x: x, y: y(15.6)))
                f.addCurve(to: CGPoint(x: x, y: y(20.4)), control1: CGPoint(x: x + (x < 14 ? 1.2 : -1.2), y: y(17.2)),
                           control2: CGPoint(x: x - (x < 14 ? 1.2 : -1.2), y: y(18.8)))
                ctx.stroke(f, with: shade, style: thin)
            }
            if family == .cello {
                let bottom = y(20.6) + 4.4 * scale
                ctx.stroke(line(CGPoint(x: 14, y: bottom), CGPoint(x: 14, y: min(27.6, bottom + 2.4))), with: shade, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        case .chromatic:
            break
        }
    }
}
