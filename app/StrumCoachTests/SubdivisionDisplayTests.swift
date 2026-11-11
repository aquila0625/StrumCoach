import MetronomeCore
import SwiftUI
import XCTest
@testable import StrumCoach

/// 拍子方块里的切分格：时间线（音频时钟）、分格几何、实际画出来的像素。
@MainActor
final class SubdivisionDisplayTests: XCTestCase {

    // MARK: 时间线

    /// 模拟音频线程和显示刷新：音频每 256 个采样渲染一次并发布“最近一个点 + 后两个点”（和 AudioEngineHost 一样），
    /// 界面按 120 Hz 读快照、用 soundingClick 选当前点。快速的十六分里每个切分点都按顺序出现一次，
    /// 不跳格、不重复，而且出现得不比发声晚过一帧。中途改切分，方块的分格在下一拍拍头跟着换。
    func testHighlightFollowsEveryClickOnTheAudioClock() {
        let sr = 48_000.0
        let latency = 0.012
        var config = MetronomeConfig(bpm: 240, subdivision: .sixteenth)
        let renderer = ClickRenderer(voices: VoiceBank(sampleRate: sr), config: config)
        renderer.start(config: config)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer { buffer.deallocate() }
        func hostTime(_ sample: Int64) -> Double { Double(sample) / sr + latency }

        var snapshot = BeatSnapshot()
        var lastClick: ClickMark?
        var rendered: [ClickMark] = []
        var shown: [(mark: ClickMark, at: Double)] = []
        var shownOrder: Int64 = -1
        var nextFrame = 0.0
        var changed = false

        while renderer.cursor < Int64(sr * 4) {
            if !changed && renderer.cursor >= Int64(sr * 2.1) {
                config.subdivision = .syncopation
                renderer.update(config)
                changed = true
            }
            // 音频线程：渲染一个周期，发布快照
            let bufferStart = renderer.cursor
            renderer.render(into: buffer, frames: 256) { event in
                let mark = ClickMark(event, hostTime: hostTime(event.sample))
                lastClick = mark
                rendered.append(mark)
            }
            var next: ClickMark?, afterNext: ClickMark?
            renderer.peekClicks(frames: Int(sr * 0.4)) { event in
                if next == nil { next = ClickMark(event, hostTime: hostTime(event.sample)) }
                else if afterNext == nil { afterNext = ClickMark(event, hostTime: hostTime(event.sample)) }
            }
            snapshot.lastClick = lastClick
            snapshot.nextClick = next
            snapshot.afterNextClick = afterNext
            // 界面线程：这段音频“时间”里每 1/120 秒刷新一次
            let cycleEnd = Double(bufferStart + 256) / sr
            while nextFrame < cycleEnd {
                if let c = MetronomeController.soundingClick(snapshot.clicks, now: nextFrame, after: shownOrder) {
                    shownOrder = c.order
                    shown.append((c, nextFrame))
                }
                nextFrame += 1.0 / 120
            }
        }
        let heard = rendered.filter { $0.hostTime < nextFrame - 1.0 / 120 }
        XCTAssertEqual(shown.map(\.mark.order), heard.map(\.order), "每个点都按顺序高亮一次")
        for s in shown {
            XCTAssertLessThanOrEqual(s.at - s.mark.hostTime, 1.0 / 120 + 1e-9, "高亮最多晚一帧")
            XCTAssertGreaterThanOrEqual(s.at, s.mark.hostTime, "不会比发声早")
        }
        // 改切分之后：从下一拍起是切分音（3 个点），之前的拍都是十六分（4 个点）
        let firstSync = shown.first { $0.mark.subdivision == .syncopation }!.mark
        XCTAssertEqual(firstSync.subIndex, 0, "分格在拍头才换")
        XCTAssertTrue(shown.filter { $0.mark.beatSerial < firstSync.beatSerial }.allSatisfy { $0.mark.subdivision == .sixteenth })
    }

    func testSoundingClickIgnoresFutureAndAlreadyShownClicks() {
        func mark(_ beat: Int64, _ sub: Int, _ t: Double) -> ClickMark {
            ClickMark(beatSerial: beat, beatInBar: Int(beat), subIndex: sub, subdivision: .eighth, hostTime: t)
        }
        let clicks = [mark(1, 1, 1.25), mark(2, 0, 1.5), mark(1, 0, 1.0)]
        XCTAssertEqual(MetronomeController.soundingClick(clicks, now: 1.3, after: -1)?.order, mark(1, 1, 0).order)
        XCTAssertNil(MetronomeController.soundingClick(clicks, now: 1.3, after: mark(1, 1, 0).order))
        XCTAssertNil(MetronomeController.soundingClick(clicks, now: 0.5, after: -1))
    }

    // MARK: 分格几何

    func testCellsFollowTheRhythm() {
        func widths(_ s: Subdivision) -> [Double] {
            (0..<s.clickCount).map { SubdivisionCells.cell(s, $0) }.map { $0.upperBound - $0.lowerBound }
        }
        XCTAssertEqual(widths(.quarter), [1])
        XCTAssertEqual(widths(.eighth), [0.5, 0.5])
        XCTAssertEqual(widths(.sixteenth), [0.25, 0.25, 0.25, 0.25])
        XCTAssertEqual(widths(.dotted), [0.75, 0.25])
        XCTAssertEqual(widths(.eighthSixteenth), [0.5, 0.25, 0.25])
        XCTAssertEqual(widths(.sixteenthEighth), [0.25, 0.25, 0.5])
        XCTAssertEqual(widths(.syncopation), [0.25, 0.5, 0.25])
        for (a, b) in zip(widths(.triplet), [1.0 / 3, 1.0 / 3, 1.0 / 3]) { XCTAssertEqual(a, b, accuracy: 1e-9) }
        for s in Subdivision.allCases {
            XCTAssertEqual(widths(s).reduce(0, +), 1, accuracy: 1e-9, "\(s) 的格子要正好铺满一拍")
        }
    }

    /// 方块窄时分隔变细线：iPhone 上 4/4 每个方块约 70 pt，12/8 约 24 pt。
    func testSeparatorsThinOutWhenCellsGetNarrow() {
        XCTAssertEqual(SubdivisionCells.separatorWidth(boxWidth: 70, pattern: .eighth), 3)
        XCTAssertEqual(SubdivisionCells.separatorWidth(boxWidth: 70, pattern: .sixteenth), 3)
        XCTAssertEqual(SubdivisionCells.separatorWidth(boxWidth: 24, pattern: .sixteenth), 1)
        XCTAssertEqual(SubdivisionCells.separatorWidth(boxWidth: 40, pattern: .dotted), 2)
        // 再窄（32 拍配十六分）也只是 1 pt，格子仍有宽度
        let w = (402.0 - 72 - 31 * 4) / 32
        XCTAssertEqual(SubdivisionCells.separatorWidth(boxWidth: w, pattern: .sixteenth), 1)
        XCTAssertGreaterThan(w / 4 - 1, 0.5)
    }

    // MARK: 实际画出来的样子

    /// 用 ImageRenderer 画一个附点方块（正在响第 2 个点）：分隔在 3/4 处，第 1 格被盖上淡色，第 2 格不盖。
    func testRenderedCellsShowSeparatorAndHighlight() throws {
        let view = SubdivisionCells(pattern: .dotted, active: 1, filled: true)
            .frame(width: 100, height: 40)
            .environment(\.theme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let alpha = try alphaColumn(image)
        XCTAssertGreaterThan(alpha[30], 0.3, "第 1 格（没在响）盖了淡色")
        XCTAssertLessThan(alpha[88], 0.05, "第 2 格（正在响）不盖")
        XCTAssertGreaterThan(alpha[75], 0.9, "3/4 处有分隔")

        let idle = ImageRenderer(content: SubdivisionCells(pattern: .dotted, active: nil, filled: true)
            .frame(width: 100, height: 40).environment(\.theme, .light))
        idle.scale = 1
        let idleAlpha = try alphaColumn(XCTUnwrap(idle.cgImage))
        XCTAssertLessThan(idleAlpha[30], 0.05, "没在播放时不变淡")
        XCTAssertGreaterThan(idleAlpha[75], 0.9)

        let quarter = ImageRenderer(content: SubdivisionCells(pattern: .quarter, active: 0, filled: true)
            .frame(width: 100, height: 40).environment(\.theme, .light))
        quarter.scale = 1
        XCTAssertTrue(try alphaColumn(XCTUnwrap(quarter.cgImage)).allSatisfy { $0 < 0.05 }, "四分不分格")
    }

    /// 图片中间一行每一列的不透明度（0…1）
    private func alphaColumn(_ image: CGImage) throws -> [Double] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let row = h / 2
        return (0..<w).map { Double(data[(row * w + $0) * 4 + 3]) / 255 }
    }
}
