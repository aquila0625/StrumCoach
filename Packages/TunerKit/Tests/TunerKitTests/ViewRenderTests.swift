import XCTest
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
@testable import TunerKit

@MainActor
final class ViewRenderTests: XCTestCase {
    /// 渲染深浅两种主题；设置环境变量 TUNERKIT_SNAPSHOT_DIR 时把 PNG 写到该目录，便于肉眼检查。
    func testRendersBothThemes() throws {
        let cases: [(String, TunerPalette, ColorScheme, String)] = [
            ("dark", .dark, .dark, "guitar"), ("light", .light, .light, "guitar"),
            ("dark-auto", .dark, .dark, "auto"), ("light-ukulele", .light, .light, "ukulele"),
        ]
        for (name, palette, scheme, inst) in cases {
            let i = InstrumentLibrary.instrument(id: inst)!
            let model = TunerModel(selection: InstrumentSelection(instrumentID: i.id, tuningID: i.defaultTuningID))
            model.inject(PitchReading(frequency: inst == "auto" ? 440.8 : (inst == "ukulele" ? 441 : 110.9), clarity: 0.97))
            let view = TunerView(model: model, palette: palette, autoStart: false, onSettings: {}).content
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.background)
                .environment(\.colorScheme, scheme)
                .frame(width: 390, height: 844)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "\(name) 渲染失败")
            XCTAssertEqual(image.width, 780)
            if let dir = ProcessInfo.processInfo.environment["TUNERKIT_SNAPSHOT_DIR"] {
                let url = URL(fileURLWithPath: dir).appendingPathComponent("tuner-\(name).png")
                #if canImport(AppKit)
                let rep = NSBitmapImageRep(cgImage: image)
                try rep.representation(using: .png, properties: [:])?.write(to: url)
                #endif
            }
        }
    }
}
