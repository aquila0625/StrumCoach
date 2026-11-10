import SwiftUI
import TunerKit

/// 指法图（对应设计稿 05 里的 `chordDiagram`）：吉他 / 尤克里里的一个按法。
///
/// 可单独使用，不依赖 `ChordLibraryModel`。尺寸按设计稿的点数画（吉他约 214 × 223），`scale` 整体缩放。
/// 左手模式下左右镜像：最粗的一根弦在右边。
public struct ChordDiagramView: View {
    private let voicing: ChordVoicing
    private let chord: Chord
    private let palette: ChordPalette
    private let leftHanded: Bool
    private let scale: CGFloat
    private let strings: [InstrumentString]
    private let pluck: (() -> [Int: Double])?
    private let onPluck: ((Int) -> Void)?
    @Environment(\.noteNaming) private var naming
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - strings: 乐器的弦（只用来给 VoiceOver 报弦号），可省略。
    ///   - pluck: 试听时给动画用：每一帧返回“弦序号 → 距上一次被拨到过了多久（秒）”（见 `PluckClock`）。
    ///     为 nil 时不做动画、也不刷新。被拨到的弦高亮并横向抖动（振幅随时间衰减），按到的圆点闪一下；
    ///     系统开了“减少动态效果”时只高亮、不抖动。
    ///   - onPluck: 传了就可以点图上的弦：每根弦是一条贯穿整张图的竖条触控区（宽一个弦距），回调弦序号。
    ///     每根弦也是单独的读屏元素（“第 3 弦，G”，双击发声）。不弹的弦（×）也能点，回调照常，由调用方决定要不要发声。
    public init(voicing: ChordVoicing, chord: Chord, palette: ChordPalette = .dark,
                leftHanded: Bool = false, scale: CGFloat = 1, strings: [InstrumentString] = [],
                pluck: (() -> [Int: Double])? = nil, onPluck: ((Int) -> Void)? = nil) {
        self.voicing = voicing; self.chord = chord; self.palette = palette
        self.leftHanded = leftHanded; self.scale = scale; self.strings = strings; self.pluck = pluck
        self.onPluck = onPluck
    }

    // 版式（点）：与设计稿一致
    private let gapX: CGFloat = 34
    private let gapY: CGFloat = 31
    private let rows = 5
    private let x0: CGFloat = 30
    private let y0: CGFloat = 32
    private let radius: CGFloat = 14

    private var n: Int { voicing.stringCount }
    private var size: CGSize {
        CGSize(width: x0 * 2 + gapX * CGFloat(n - 1), height: y0 + gapY * CGFloat(rows) + 34)
    }
    private func x(_ i: Int) -> CGFloat { x0 + gapX * CGFloat(leftHanded ? n - 1 - i : i) }
    private func rowY(_ fret: Int) -> CGFloat { y0 + (CGFloat(fret - voicing.baseFret) + 0.5) * gapY }

    public var body: some View {
        let canvas = TimelineView(.animation(paused: pluck == nil)) { _ in
            let ages = pluck?() ?? [:]
            Canvas { ctx, _ in draw(ctx, ages: ages) }
        }
        .frame(width: size.width * scale, height: size.height * scale)
        if let onPluck {
            ZStack {
                canvas.accessibilityHidden(true)
                ForEach(0..<n, id: \.self) { i in
                    Color.clear
                        .frame(width: gapX * scale, height: size.height * scale)
                        .contentShape(Rectangle())
                        .onTapGesture { onPluck(i) }
                        .position(x: x(i) * scale, y: size.height * scale / 2)
                        .accessibilityElement()
                        .accessibilityLabel(stringLabel(i))
                        .accessibilityHint(voicing.frets[i] < 0 ? "" : ChordStrings.current.pluckHint)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onPluck(i) }
                }
            }
            .frame(width: size.width * scale, height: size.height * scale)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ChordStrings.current.diagramLabel(naming.chordName(chord)))
        } else {
            canvas
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ChordStrings.current.diagramLabel(naming.chordName(chord)))
                .accessibilityValue(strings.count == n ? ChordStrings.current.spokenDescription(voicing, strings: strings) : voicing.shorthand)
        }
    }

    /// 读屏：每根弦“第 3 弦，G”；不弹的弦读“3 弦不弹”。
    private func stringLabel(_ i: Int) -> String {
        let text = ChordStrings.current
        let number = strings.count == n ? strings[i].number : n - i
        guard let pitch = voicing.pitches[i] else { return text.stringMuted(number) }
        return text.stringNote(number, naming.toneName(pitchClass: pitch.pitchClass, in: chord))
    }

    /// 拨弦动画：高亮随时间淡出（约 0.7 秒），抖动的振幅按指数衰减。
    private func glow(_ age: Double?) -> Double { age.map { max(0, 1 - $0 / 0.7) } ?? 0 }
    private func decay(_ age: Double?) -> Double { age.map { exp(-$0 / 0.2) } ?? 0 }

    private func draw(_ base: GraphicsContext, ages: [Int: Double]) {
        var ctx = base
        ctx.scaleBy(x: scale, y: scale)
        let left = x(leftHanded ? n - 1 : 0), right = x(leftHanded ? 0 : n - 1)

        // 横线（品丝），第一条在 1 品开头时是粗的琴枕
        for r in 0...rows {
            var p = Path()
            let y = y0 + CGFloat(r) * gapY
            p.move(to: CGPoint(x: left, y: y)); p.addLine(to: CGPoint(x: right, y: y))
            if r == 0 && voicing.showsNut {
                ctx.stroke(p, with: .color(palette.text), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            } else {
                ctx.stroke(p, with: .color(palette.dim), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        // 起始品位
        if !voicing.showsNut {
            let label = ctx.resolve(Text("\(voicing.baseFret)").font(.system(size: 13, weight: .semibold)).foregroundColor(palette.sub))
            let lx = leftHanded ? right + 17 : left - 17
            ctx.draw(label, at: CGPoint(x: lx, y: y0 + gapY / 2), anchor: .center)
        }

        // 竖线（弦）：越粗的弦越粗
        for i in 0..<n {
            let top = CGPoint(x: x(i), y: y0), bottom = CGPoint(x: x(i), y: y0 + gapY * CGFloat(rows))
            let width = 1.2 + CGFloat(n - 1 - i) * 0.25
            let age = ages[i]
            if let age, glow(age) > 0 {
                // 被拨到的弦：横向抖动（振幅 5 点，随时间衰减，约 16 Hz）+ 强调色高亮
                let shake = reduceMotion ? 0 : CGFloat(5 * decay(age) * sin(2 * .pi * 16 * age))
                var p = Path()
                p.move(to: top)
                p.addQuadCurve(to: bottom, control: CGPoint(x: top.x + shake * 2, y: (top.y + bottom.y) / 2))
                ctx.stroke(p, with: .color(palette.dim), lineWidth: width)
                ctx.stroke(p, with: .color(palette.accent.opacity(glow(age))), lineWidth: width + 1.6)
            } else {
                var p = Path()
                p.move(to: top); p.addLine(to: bottom)
                ctx.stroke(p, with: .color(palette.dim), lineWidth: width)
            }
        }

        // 横按
        if let b = voicing.barre {
            let a = x(b.fromString), z = x(b.toString)
            let rect = CGRect(x: min(a, z) - radius, y: rowY(b.fret) - radius, width: abs(a - z) + radius * 2, height: radius * 2)
            ctx.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(palette.text))
        }

        for i in 0..<n {
            let f = voicing.frets[i]
            let cx = x(i)
            if f < 0 {
                // 点了不弹的弦：× 轻轻抖一下表示收到了（不发声）
                let tap = ages[1000 + i]
                let dx = (reduceMotion || tap == nil) ? 0 : CGFloat(4 * decay(tap) * sin(2 * .pi * 14 * (tap ?? 0)))
                var p = Path()
                p.move(to: CGPoint(x: cx - 6 + dx, y: y0 - 22)); p.addLine(to: CGPoint(x: cx + 6 + dx, y: y0 - 10))
                p.move(to: CGPoint(x: cx + 6 + dx, y: y0 - 22)); p.addLine(to: CGPoint(x: cx - 6 + dx, y: y0 - 10))
                ctx.stroke(p, with: .color(glow(tap) > 0 ? palette.text : palette.sub), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else if f == 0 {
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - 6.5, y: y0 - 22.5, width: 13, height: 13)),
                           with: .color(palette.text), lineWidth: 2)
                if glow(ages[i]) > 0 {
                    let grow = reduceMotion ? 0 : CGFloat(3 * decay(ages[i]))
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - 6.5 - grow, y: y0 - 22.5 - grow, width: 13 + grow * 2, height: 13 + grow * 2)),
                               with: .color(palette.accent.opacity(glow(ages[i]))), lineWidth: 2.4)
                }
            } else {
                let isRoot = voicing.pitches[i]?.pitchClass == chord.root
                let cy = rowY(f)
                let inBarre = voicing.barre.map { f == $0.fret && i >= $0.fromString && i <= $0.toString } ?? false
                // 横按里只有根音画成圆点（强调色）；其余由横按条表示，数字只标在条的一端
                if !inBarre || isRoot {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)),
                             with: .color(isRoot ? palette.accent : palette.text))
                }
                // 按到的圆点闪一下：外圈光晕，并略微放大
                if glow(ages[i]) > 0 {
                    let grow = reduceMotion ? 0 : CGFloat(3.5 * decay(ages[i]))
                    let r = radius + 3 + grow
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                               with: .color(palette.accent.opacity(glow(ages[i]))), lineWidth: 2.4)
                }
                let showNumber = !inBarre || isRoot || i == (leftHanded ? voicing.barre!.toString : voicing.barre!.fromString)
                if showNumber && voicing.fingers[i] > 0 {
                    let t = ctx.resolve(Text("\(voicing.fingers[i])").font(.system(size: 14, weight: .bold))
                        .foregroundColor(isRoot ? palette.onAccent : palette.onText))
                    ctx.draw(t, at: CGPoint(x: cx, y: cy), anchor: .center)
                }
            }
            // 底部的音名
            if f >= 0 {
                let isRoot = voicing.pitches[i]?.pitchClass == chord.root
                let lit = glow(ages[i]) > 0.25
                let t = ctx.resolve(Text(voicing.pitches[i].map { naming.toneName(pitchClass: $0.pitchClass, in: chord) } ?? "")
                    .font(.system(size: 13, weight: isRoot || lit ? .bold : .medium))
                    .foregroundColor(isRoot || lit ? palette.accent : palette.sub))
                ctx.draw(t, at: CGPoint(x: cx, y: size.height - 12), anchor: .center)
            }
        }
    }
}
