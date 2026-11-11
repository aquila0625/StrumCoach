import SwiftUI

/// 设计稿里的线性图标（parts1.js 的 ICON），按原 SVG 坐标用 Canvas 重画。
enum IconKind {
    case metronome, train, tuner, chord, me, gear, chevron, playTriangle, pause
}

struct Icon: View {
    let kind: IconKind
    var color: Color
    /// gear 图标两个小圆的填充色（等于所在卡片底色）
    var fill: Color = .clear

    private var viewBox: CGSize {
        switch kind {
        case .metronome, .train, .tuner, .chord, .me: return CGSize(width: 26, height: 26)
        case .gear: return CGSize(width: 22, height: 22)
        case .chevron: return CGSize(width: 12, height: 12)
        case .playTriangle: return CGSize(width: 22, height: 24)
        case .pause: return CGSize(width: 30, height: 34)
        }
    }

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / viewBox.width, y: size.height / viewBox.height)
            draw(&ctx)
        }
        .frame(width: viewBox.width, height: viewBox.height)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let round = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        func stroke(_ p: Path, _ style: StrokeStyle = round) { ctx.stroke(p, with: .color(color), style: style) }
        func fill(_ p: Path) { ctx.fill(p, with: .color(color)) }
        func line(_ pts: [CGPoint]) -> Path {
            var p = Path()
            p.addLines(pts)
            return p
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }

        switch kind {
        case .metronome:
            var body = line([.init(x: 9, y: 3), .init(x: 17, y: 3), .init(x: 22, y: 23), .init(x: 4, y: 23)])
            body.closeSubpath()
            stroke(body)
            stroke(line([.init(x: 13, y: 18), .init(x: 19, y: 6)]))
            fill(circle(17, 10, 2))
        case .train:
            stroke(line([.init(x: 4, y: 21), .init(x: 22, y: 21)]))
            fill(rect(5, 14, 4, 5, 1))
            fill(rect(11, 10, 4, 9, 1))
            fill(rect(17, 5, 4, 14, 1))
        case .tuner:
            var fork = Path()
            fork.move(to: .init(x: 9, y: 3))
            fork.addLine(to: .init(x: 9, y: 11))
            fork.addArc(center: .init(x: 13, y: 11), radius: 4, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            fork.addLine(to: .init(x: 17, y: 3))
            stroke(fork)
            stroke(line([.init(x: 13, y: 15), .init(x: 13, y: 23)]))
        case .chord:
            stroke(rect(5, 3, 16, 20, 2.5))
            let thin = StrokeStyle(lineWidth: 1.4)
            stroke(line([.init(x: 10.3, y: 3), .init(x: 10.3, y: 23)]), thin)
            stroke(line([.init(x: 15.7, y: 3), .init(x: 15.7, y: 23)]), thin)
            stroke(line([.init(x: 5, y: 9.5), .init(x: 21, y: 9.5)]), thin)
            stroke(line([.init(x: 5, y: 16), .init(x: 21, y: 16)]), thin)
            fill(circle(15.7, 12.8, 2.6))
        case .me:
            stroke(circle(13, 9, 4.5))
            var p = Path()
            p.move(to: .init(x: 4.5, y: 22))
            p.addCurve(to: .init(x: 13, y: 15.5), control1: .init(x: 5.7, y: 17.8), control2: .init(x: 8.9, y: 15.5))
            p.addCurve(to: .init(x: 21.5, y: 22), control1: .init(x: 17.1, y: 15.5), control2: .init(x: 20.3, y: 17.8))
            stroke(p)
        case .gear:
            let s = StrokeStyle(lineWidth: 1.8, lineCap: .round)
            stroke(line([.init(x: 3, y: 6), .init(x: 19, y: 6)]), s)
            stroke(line([.init(x: 3, y: 16), .init(x: 19, y: 16)]), s)
            for (x, y) in [(8.0, 6.0), (14.0, 16.0)] {
                ctx.fill(circle(x, y, 2.6), with: .color(self.fill))
                stroke(circle(x, y, 2.6), s)
            }
        case .chevron:
            stroke(line([.init(x: 2, y: 4), .init(x: 6, y: 8), .init(x: 10, y: 4)]), StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        case .playTriangle:
            var p = Path()
            p.move(to: .init(x: 3, y: 2.5))
            p.addLine(to: .init(x: 3, y: 21.5))
            p.addQuadCurve(to: .init(x: 4.5, y: 22.4), control: .init(x: 3, y: 22.9))
            p.addLine(to: .init(x: 20.5, y: 12.9))
            p.addQuadCurve(to: .init(x: 20.5, y: 11.1), control: .init(x: 22, y: 12))
            p.addLine(to: .init(x: 4.5, y: 1.6))
            p.addQuadCurve(to: .init(x: 3, y: 2.5), control: .init(x: 3, y: 1.1))
            fill(p)
        case .pause:
            fill(rect(3, 2, 8, 30, 2.5))
            fill(rect(19, 2, 8, 30, 2.5))
        }
    }
}

/// 音符组（parts1.js 的 notes()）：每个音符 beams = 符杠数（0 = 四分），dotted = 附点。
struct NoteGlyph: View {
    struct Note {
        var beams: Int
        var dotted = false
    }

    let notes: [Note]
    var tuplet: Int? = nil
    var color: Color
    var gap: CGFloat = 11

    private let h: CGFloat = 30
    private let top: CGFloat = 6

    var size: CGSize { CGSize(width: CGFloat(notes.count - 1) * gap + 22, height: h + 2) }

    var body: some View {
        // 连音数字画在符杠上方、超出原本的高度（SVG 里是 overflow:visible），所以画布向上多留 12pt。
        Canvas { ctx, _ in
            ctx.translateBy(x: 0, y: 12)
            draw(&ctx)
        }
        .frame(width: size.width, height: size.height + 12)
        .padding(.top, -12)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let n = notes.count
        let xs = (0..<n).map { 5 + CGFloat($0) * gap }
        let shading = GraphicsContext.Shading.color(color)
        for (i, note) in notes.enumerated() {
            let x = xs[i]
            var head = Path(ellipseIn: CGRect(x: -4.6, y: -3.4, width: 9.2, height: 6.8))
            head = head.applying(CGAffineTransform(rotationAngle: -20 * .pi / 180).concatenating(.init(translationX: x, y: h - 3)))
            ctx.fill(head, with: shading)
            ctx.fill(Path(CGRect(x: x + 3.4, y: top, width: 1.6, height: h - 3 - top)), with: shading)
            if note.dotted {
                ctx.fill(Path(ellipseIn: CGRect(x: x + 9 - 1.6, y: h - 3 - 1.6, width: 3.2, height: 3.2)), with: shading)
            }
        }
        let sx = { (i: Int) in xs[i] + 4.2 }
        if n > 1 {
            ctx.fill(Path(CGRect(x: sx(0) - 0.8, y: top, width: sx(n - 1) - sx(0) + 1.6, height: 3.4)), with: shading)
            for i in 0..<n where notes[i].beams >= 2 {
                let joinsNext = i + 1 < n && notes[i + 1].beams >= 2
                if joinsNext {
                    ctx.fill(Path(CGRect(x: sx(i) - 0.8, y: top + 5.5, width: sx(i + 1) - sx(i) + 1.6, height: 3.4)), with: shading)
                } else if !(i > 0 && notes[i - 1].beams >= 2) {
                    let pointsLeft = i == n - 1
                    let len: CGFloat = 6
                    ctx.fill(Path(CGRect(x: pointsLeft ? sx(i) - len : sx(i) - 0.8, y: top + 5.5, width: len + 0.8, height: 3.4)), with: shading)
                }
            }
        }
        if let tuplet {
            let text = Text("\(tuplet)").font(.system(size: 9, weight: .bold)).foregroundColor(color)
            ctx.draw(text, at: CGPoint(x: (sx(0) + sx(n - 1)) / 2, y: top - 1), anchor: .bottom)
        }
    }
}

extension NoteGlyph {
    init(_ subdivision: SubdivisionGlyph, color: Color, gap: CGFloat = 11) {
        self.init(notes: subdivision.notes, tuplet: subdivision.tuplet, color: color, gap: gap)
    }
}

/// 每种切分对应的音符写法（parts1.js 的 N）。
struct SubdivisionGlyph {
    let notes: [NoteGlyph.Note]
    let tuplet: Int?
}
