import SwiftUI
import TunerKit

/// 贝斯的和弦音位置图：一个把位框里标出根音 / 三度 / 五度 / 八度。
public struct BassDiagramView: View {
    private let positions: BassPositions
    private let palette: ChordPalette
    private let leftHanded: Bool
    private let scale: CGFloat
    private let pluck: (() -> [Int: Double])?
    private let onPluck: ((BassPositions.Marker) -> Void)?

    @Environment(\.noteNaming) private var naming
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter pluck: 试听时给动画用：每一帧返回“弦 × 100 + 品 → 距上一次被拨到过了多久（秒）”（见 `PluckEvent.key`）。
    /// - Parameter onPluck: 传了就可以点弦：每根弦是一条贯穿整张图的竖条触控区，点哪里就发离点击位置最近的那个标记的音
    ///   （这根弦上没有标记则没有反应）；读屏每根弦一个元素，双击发这根弦上品位最低的标记。
    public init(positions: BassPositions, palette: ChordPalette = .dark, leftHanded: Bool = false, scale: CGFloat = 1,
                pluck: (() -> [Int: Double])? = nil, onPluck: ((BassPositions.Marker) -> Void)? = nil) {
        self.positions = positions; self.palette = palette; self.leftHanded = leftHanded; self.scale = scale
        self.pluck = pluck; self.onPluck = onPluck
    }

    private let gapX: CGFloat = 40
    private let gapY: CGFloat = 31
    private let x0: CGFloat = 32
    private let y0: CGFloat = 30
    private let radius: CGFloat = 13

    private var n: Int { positions.stringCount }
    private var rows: Int { positions.fretCount }
    private var size: CGSize { CGSize(width: x0 * 2 + gapX * CGFloat(n - 1), height: y0 + gapY * CGFloat(rows) + 8) }
    private func x(_ i: Int) -> CGFloat { x0 + gapX * CGFloat(leftHanded ? n - 1 - i : i) }
    private func y(_ fret: Int) -> CGFloat { fret == 0 ? y0 - 16 : y0 + (CGFloat(fret - positions.firstRow) + 0.5) * gapY }

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
                    let onString = positions.markers.filter { $0.string == i }
                    Color.clear
                        .frame(width: gapX * scale, height: size.height * scale)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 1, coordinateSpace: .local) { location in
                            if let m = nearest(onString, toY: location.y / scale) { onPluck(m) }
                        }
                        .position(x: x(i) * scale, y: size.height * scale / 2)
                        .accessibilityElement()
                        .accessibilityLabel(stringLabel(i, onString))
                        .accessibilityHint(onString.isEmpty ? "" : ChordStrings.current.pluckHint)
                        .accessibilityAddTraits(onString.isEmpty ? [] : .isButton)
                        .accessibilityAction {
                            if let m = onString.min(by: { $0.fret < $1.fret }) { onPluck(m) }
                        }
                }
            }
            .frame(width: size.width * scale, height: size.height * scale)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ChordStrings.current.bassDiagramLabel(naming.chordName(positions.chord)))
        } else {
            canvas
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ChordStrings.current.bassDiagramLabel(naming.chordName(positions.chord)))
        }
    }

    /// 这根弦上离点击位置（图内纵坐标）最近的标记。
    private func nearest(_ markers: [BassPositions.Marker], toY y: CGFloat) -> BassPositions.Marker? {
        markers.min { abs(self.y($0.fret) - y) < abs(self.y($1.fret) - y) }
    }

    /// 读屏：“第 3 弦，A、E”（这根弦上标出的和弦音，按品位从低到高）。
    private func stringLabel(_ i: Int, _ markers: [BassPositions.Marker]) -> String {
        let text = ChordStrings.current
        let number = n - i
        guard !markers.isEmpty else { return String(number) }
        let notes = markers.sorted { $0.fret < $1.fret }
            .map { naming.toneName(pitchClass: $0.pitch.pitchClass, in: positions.chord) }
        return text.stringNote(number, notes.joined(separator: text.listSeparator))
    }

    private func fill(_ role: BassPositions.Role) -> Color {
        switch role {
        case .root: return palette.accent
        case .third: return palette.text
        case .fifth: return palette.sub
        case .octave: return palette.onText
        }
    }
    private func textColor(_ role: BassPositions.Role) -> Color {
        switch role {
        case .root: return palette.onAccent
        case .octave: return palette.accent
        default: return palette.onText
        }
    }

    private func glow(_ age: Double?) -> Double { age.map { max(0, 1 - $0 / 0.7) } ?? 0 }
    private func decay(_ age: Double?) -> Double { age.map { exp(-$0 / 0.2) } ?? 0 }

    private func draw(_ base: GraphicsContext, ages: [Int: Double]) {
        var ctx = base
        ctx.scaleBy(x: scale, y: scale)
        let left = x(leftHanded ? n - 1 : 0), right = x(leftHanded ? 0 : n - 1)
        for r in 0...rows {
            var p = Path()
            let yy = y0 + CGFloat(r) * gapY
            p.move(to: CGPoint(x: left, y: yy)); p.addLine(to: CGPoint(x: right, y: yy))
            if r == 0 && positions.showsNut {
                ctx.stroke(p, with: .color(palette.text), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            } else {
                ctx.stroke(p, with: .color(palette.dim), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        if !positions.showsNut {
            let label = ctx.resolve(Text("\(positions.firstRow)").font(.system(size: 13, weight: .semibold)).foregroundColor(palette.sub))
            ctx.draw(label, at: CGPoint(x: leftHanded ? right + 18 : left - 18, y: y0 + gapY / 2), anchor: .center)
        }
        for i in 0..<n {
            let top = CGPoint(x: x(i), y: y0), bottom = CGPoint(x: x(i), y: y0 + gapY * CGFloat(rows))
            let width = 1.2 + CGFloat(n - 1 - i) * 0.3
            // 这根弦上最近被拨到的标记决定弦的抖动
            let age = ages.filter { $0.key >= 0 && $0.key / 100 == i }.map(\.value).min()
            var p = Path()
            p.move(to: top)
            if let age, glow(age) > 0 {
                let shake = reduceMotion ? 0 : CGFloat(5 * decay(age) * sin(2 * .pi * 12 * age))
                p.addQuadCurve(to: bottom, control: CGPoint(x: top.x + shake * 2, y: (top.y + bottom.y) / 2))
                ctx.stroke(p, with: .color(palette.dim), lineWidth: width)
                ctx.stroke(p, with: .color(palette.accent.opacity(glow(age))), lineWidth: width + 1.6)
            } else {
                p.addLine(to: bottom)
                ctx.stroke(p, with: .color(palette.dim), lineWidth: width)
            }
        }
        for m in positions.markers {
            let c = CGPoint(x: x(m.string), y: y(m.fret))
            let r: CGFloat = m.fret == 0 ? 10 : radius
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(fill(m.role)))
            if m.role == .octave {
                ctx.stroke(Path(ellipseIn: rect), with: .color(palette.accent), lineWidth: 2)
            }
            if glow(ages[m.string * 100 + m.fret]) > 0 {
                let age = ages[m.string * 100 + m.fret]
                let rr = r + 3 + (reduceMotion ? 0 : CGFloat(3.5 * decay(age)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(palette.accent.opacity(glow(age))), lineWidth: 2.4)
            }
            let t = ctx.resolve(Text(m.label).font(.system(size: m.fret == 0 ? 11 : 13, weight: .bold)).foregroundColor(textColor(m.role)))
            ctx.draw(t, at: c, anchor: .center)
        }
    }
}
