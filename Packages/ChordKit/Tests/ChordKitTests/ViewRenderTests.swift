import XCTest
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import TunerKit
@testable import ChordKit

@MainActor
final class ViewRenderTests: XCTestCase {
    private func write(_ image: CGImage, to url: URL) throws {
        #if canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        #endif
    }

    private func model(_ instrument: String, root: Int, type: ChordType) -> ChordLibraryModel {
        ChordLibraryModel(current: ChordFavorite(instrumentID: instrument, tuningID: "", root: root, typeID: type.id, voicingIndex: 0))
    }

    /// 渲染整页（深浅两种主题、三种乐器）；设置环境变量 CHORDKIT_SNAPSHOT_DIR 时把 PNG 写到该目录，便于肉眼检查。
    func testLibraryViewRendersBothThemes() throws {
        let cases: [(String, ChordPalette, ColorScheme, ChordLibraryModel)] = [
            ("dark-guitar", .dark, .dark, model("guitar", root: 0, type: .major7)),
            ("light-guitar", .light, .light, model("guitar", root: 0, type: .major7)),
            ("dark-ukulele", .dark, .dark, model("ukulele", root: 5, type: .major)),
            ("dark-bass", .dark, .dark, model("bass", root: 9, type: .minor)),
            ("light-bass-d7", .light, .light, model("bass", root: 2, type: .dominant7)),
            ("dark-guitar-g", .dark, .dark, model("guitar", root: 7, type: .major)),
            ("dark-eb-maj7", .dark, .dark, model("guitar", root: 3, type: .major7)),
            ("light-eb-maj7", .light, .light, model("guitar", root: 3, type: .major7)),
        ]
        for (name, palette, scheme, m) in cases {
            let view = ChordLibraryView(model: m, palette: palette, strings: .zhHans, staticDiagram: true)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.background)
                .environment(\.colorScheme, scheme)
                .frame(width: 390, height: 844)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "\(name) 渲染失败")
            XCTAssertEqual(image.width, 780)
            if let dir = ProcessInfo.processInfo.environment["CHORDKIT_SNAPSHOT_DIR"] {
                try write(image, to: URL(fileURLWithPath: dir).appendingPathComponent("library-\(name).png"))
            }
        }
    }

    /// 唱名、德语写法下根音和类型按钮不能被截断：渲染出来，设置了目录就写 PNG 供肉眼检查。
    func testLongNamesRenderInSolfegeAndGerman() throws {
        let cases: [(String, NoteNaming, ChordPalette, ColorScheme, Int, ChordType)] = [
            ("solfege-it", NoteNaming(style: .solfege, languageCode: "it"), .dark, .dark, 8, .major7),
            ("solfege-ru", NoteNaming(style: .solfege, languageCode: "ru"), .light, .light, 10, .sus2),
            ("german", NoteNaming(style: .letters, languageCode: "de"), .dark, .dark, 10, .minor),
        ]
        for (name, naming, palette, scheme, root, type) in cases {
            let view = ChordLibraryView(model: model("guitar", root: root, type: type), palette: palette,
                                        strings: .zhHans, staticDiagram: true)
                .environment(\.noteNaming, naming)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.background)
                .environment(\.colorScheme, scheme)
                .frame(width: 390, height: 844)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "\(name) 渲染失败")
            if let dir = ProcessInfo.processInfo.environment["CHORDKIT_SNAPSHOT_DIR"] {
                try write(image, to: URL(fileURLWithPath: dir).appendingPathComponent("library-\(name).png"))
            }
        }
    }

    /// 导出深色、浅色各一张界面预览（Packages/ChordKit/preview-dark.png、preview-light.png）。
    func testExportScreenPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHORDKIT_SCREEN_PREVIEW_DIR"] else { return }
        for (name, palette, scheme) in [("dark", ChordPalette.dark, ColorScheme.dark), ("light", .light, .light)] {
            let view = ChordLibraryView(model: model("guitar", root: 3, type: .major7), palette: palette,
                                        strings: .zhHans, staticDiagram: true)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.background)
                .environment(\.colorScheme, scheme)
                .frame(width: 390, height: 780)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            try write(try XCTUnwrap(renderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("preview-\(name).png"))
        }
    }

    /// 导出“分解”模式的预览图：左边是弹奏中（C 和弦弹到 3 弦，那根弦高亮并抖动、圆点闪一下，2 弦的高亮正在淡出），
    /// 右边是点开分解指法选择面板。文件：Packages/ChordKit/preview-arpeggio-dark.png、preview-arpeggio-light.png。
    func testExportArpeggioPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHORDKIT_SCREEN_PREVIEW_DIR"] else { return }
        for (name, palette, scheme) in [("dark", ChordPalette.dark, ColorScheme.dark), ("light", .light, .light)] {
            let suite = "chordkit.preview.\(name)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let m = ChordLibraryModel(current: ChordFavorite(instrumentID: "guitar", tuningID: "", root: 0, typeID: ChordType.major.id, voicingIndex: 0),
                                      defaults: defaults)
            m.select(playMode: .arpeggio)
            let panel = ArpeggioPickerPanel(patterns: m.arpeggioPatterns, selectedID: m.arpeggioPattern?.id,
                                            rootString: m.rootStringNumber, palette: palette, strings: .zhHans) { _ in }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            func phone(pluck: [Int: Double]?, showsPanel: Bool) -> some View {
                ZStack(alignment: .topLeading) {
                    ChordLibraryView(model: m, palette: palette, strings: .zhHans, staticDiagram: true, staticPluck: pluck)
                    if showsPanel { panel.offset(x: 70, y: 296) }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.background)
                .frame(width: 390, height: 840)
            }
            let view = HStack(spacing: 24) {
                phone(pluck: [3: 0.04, 2: 0.3], showsPanel: false)
                phone(pluck: nil, showsPanel: true)
            }
            .padding(24)
            .background(palette.line)
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            try write(try XCTUnwrap(renderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("preview-arpeggio-\(name).png"))
        }
    }

    /// 演奏中排队切换的界面：标题旁“下一个：Dm”，D 和 m 按钮描边。设置 CHORDKIT_SNAPSHOT_DIR 时写 PNG。
    func testQueuedStateRenders() throws {
        for (name, palette, scheme) in [("dark", ChordPalette.dark, ColorScheme.dark), ("light", .light, .light)] {
            let m = model("guitar", root: 0, type: .major)
            m.audioEnabled = false
            m.startPlayback()
            m.select(root: 2); m.select(type: .minor)
            XCTAssertEqual(m.queuedChord?.name, "Dm")
            let view = ChordLibraryView(model: m, palette: palette, strings: .zhHans, staticDiagram: true)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(palette.background)
                .environment(\.colorScheme, scheme)
                .frame(width: 390, height: 844)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            if let dir = ProcessInfo.processInfo.environment["CHORDKIT_SNAPSHOT_DIR"] {
                try write(image, to: URL(fileURLWithPath: dir).appendingPathComponent("queued-\(name).png"))
            }
        }
    }

    /// 导出扫弦节奏型的预览图：左边是弹奏中（节奏型小格子同步高亮，被扫到的弦高亮抖动），右边是节奏型选择面板（含一个自定义的）。
    /// （编辑页里的输入框、分段控件是系统控件，离屏渲染不出来，要在模拟器 / 真机上看。）文件：preview-strum-dark.png、preview-strum-light.png。
    func testExportStrumRhythmPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHORDKIT_SCREEN_PREVIEW_DIR"] else { return }
        for (name, palette, scheme) in [("dark", ChordPalette.dark, ColorScheme.dark), ("light", .light, .light)] {
            let suite = "chordkit.preview.strum.\(name)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let m = ChordLibraryModel(current: ChordFavorite(instrumentID: "guitar", tuningID: "", root: 0, typeID: ChordType.major.id, voicingIndex: 0),
                                      defaults: defaults)
            m.audioEnabled = false
            m.saveCustomRhythm(name: "我的节奏", text: "D . D U . U D U", cellsPerBeat: 2)
            m.select(rhythm: .folk1)
            let panel = RhythmPickerPanel(rhythms: m.strumRhythms, selectedID: m.strumRhythm.id, palette: palette, strings: .zhHans,
                                          onNew: {}, onEdit: { _ in }, onDelete: { _ in }) { _ in }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            func phone<V: View>(_ content: V) -> some View {
                content
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(palette.background)
                    .frame(width: 390, height: 840)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
            }
            let view = HStack(spacing: 24) {
                phone(ChordLibraryView(model: m, palette: palette, strings: .zhHans, staticDiagram: true,
                                       staticPluck: [4: 0.05, 3: 0.3], staticActiveCell: 3))
                phone(ZStack(alignment: .topLeading) {
                    ChordLibraryView(model: m, palette: palette, strings: .zhHans, staticDiagram: true)
                    panel.offset(x: 70, y: 296)
                })
            }
            .padding(24)
            .background(palette.line)
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            try write(try XCTUnwrap(renderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("preview-strum-\(name).png"))
        }
    }

    /// 导出速度控件所在行的预览：390 点宽（一行放得下）和 320 点宽（放不下时指法名挪到下一行），扫弦和分解各一张。
    /// （速度弹窗里的滑块、开关是系统控件，离屏渲染不出来，要在模拟器 / 真机上看。）文件：preview-tempo-dark.png、preview-tempo-light.png。
    func testExportTempoRowPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHORDKIT_SCREEN_PREVIEW_DIR"] else { return }
        for (name, palette, scheme) in [("dark", ChordPalette.dark, ColorScheme.dark), ("light", .light, .light)] {
            func phone(width: CGFloat, mode: ChordLibraryModel.PlayMode, follow: Bool, suite: String) -> some View {
                let defaults = UserDefaults(suiteName: suite)!
                defaults.removePersistentDomain(forName: suite)
                let m = ChordLibraryModel(current: ChordFavorite(instrumentID: "guitar", tuningID: "", root: 0, typeID: "major", voicingIndex: 0),
                                          defaults: defaults)
                m.audioEnabled = false
                m.select(playMode: mode)
                if mode == .strum { m.select(rhythm: .waltz) } else { m.select(arpeggio: ArpeggioPattern.pattern(id: "g-sweep")!) }
                m.bpm = 112
                m.setFollowsMetronome(follow)
                return ChordLibraryView(model: m, palette: palette, strings: .zhHans, staticDiagram: true)
                    .frame(width: width, height: 560, alignment: .top)
                    .clipped()
                    .background(palette.background)
            }
            let view = HStack(alignment: .top, spacing: 20) {
                phone(width: 390, mode: .strum, follow: false, suite: "chordkit.preview.tempo.a\(name)")
                phone(width: 320, mode: .strum, follow: true, suite: "chordkit.preview.tempo.b\(name)")
                phone(width: 320, mode: .arpeggio, follow: false, suite: "chordkit.preview.tempo.c\(name)")
            }
            .padding(20)
            .background(palette.line)
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            try write(try XCTUnwrap(renderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("preview-tempo-\(name).png"))
        }
    }

    /// 导出两个自定义编辑页里“能看见”的部分：快捷键行（有空拍、删除）和空格子预览。
    /// （输入框和分段控件是系统控件，离屏渲染不出来；这里用同样的组件拼一个示意。）文件：preview-rest-dark.png、preview-rest-light.png。
    func testExportRestEditorPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHORDKIT_SCREEN_PREVIEW_DIR"] else { return }
        for (name, palette, scheme) in [("dark", ChordPalette.dark, ColorScheme.dark), ("light", .light, .light)] {
            let s = ChordStrings.zhHans
            let arpKeys = QuickKeys.arpeggio(stringCount: 6, strings: s)
            let rhythmKeys = QuickKeys.rhythm(strings: s)
            func mock<V: View>(_ title: String, field: String, @ViewBuilder _ rest: () -> V) -> some View {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity)
                    Text(field).font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
                    rest()
                    Spacer(minLength: 0)
                }
                .foregroundStyle(palette.text)
                .padding(20)
                .frame(width: 390, height: 430, alignment: .top)
                .background(palette.background)
            }
            let view = HStack(spacing: 24) {
                mock(s.arpeggioEditorTitle, field: "5-3-2-  5032") {
                    QuickKeyPad(rows: arpKeys, palette: palette) { _ in }
                    ArpeggioStepStrip(steps: ArpeggioInput.parse("5-3-2- 5032", stringCount: 6).steps, palette: palette)
                    Text(s.arpeggioHelp(6)).font(.system(size: 13)).foregroundStyle(palette.sub)
                }
                mock(s.rhythmEditorTitle, field: "B.dUB...DU.XU.UX") {
                    QuickKeyPad(rows: rhythmKeys, palette: palette) { _ in }
                    Text(s.rhythmLegend).font(.system(size: 12)).foregroundStyle(palette.sub)
                    StrumCellStrip(cells: StrumInput.parse("B.dUB...DU.XU.UX", cellsPerBeat: 2).cells, cellsPerBeat: 2, activeCell: 2, palette: palette)
                    Text(s.rhythmHelp).font(.system(size: 13)).foregroundStyle(palette.sub)
                }
            }
            .padding(24)
            .background(palette.line)
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            try write(try XCTUnwrap(renderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("preview-rest-\(name).png"))
        }
    }

    func testDiagramSizesAndMirrorRender() throws {
        let chord = Chord("F", .major)!
        let v = ChordLibrary.voicings(for: chord, instrument: InstrumentLibrary.guitar)[0]
        for left in [false, true] {
            let r = ImageRenderer(content: ChordDiagramView(voicing: v, chord: chord, palette: .dark, leftHanded: left)
                .background(ChordPalette.dark.card))
            r.scale = 2
            let image = try XCTUnwrap(r.cgImage)
            XCTAssertEqual(image.width, Int((30 * 2 + 34 * 5) * 2))      // 6 根弦：2·30 + 5·34 = 230 点
        }
    }

    // MARK: 预览图 preview.png

    private struct Sample { let name: String; let voicing: ChordVoicing; let chord: Chord }

    private func samples(_ inst: Instrument, _ names: [(String, ChordType)]) -> [Sample] {
        names.map { r, t in
            let c = Chord(r, t)!
            return Sample(name: c.name, voicing: ChordLibrary.voicings(for: c, instrument: inst)[0], chord: c)
        }
    }

    private func sheet(title: String, items: [Sample], palette: ChordPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundColor(palette.text)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(250), spacing: 12), count: 3), spacing: 12) {
                ForEach(items, id: \.name) { s in
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.name).font(.system(size: 24, weight: .bold))
                            Spacer()
                            Text(s.voicing.shorthand).font(.system(size: 13, design: .monospaced)).foregroundColor(palette.sub)
                        }
                        ChordDiagramView(voicing: s.voicing, chord: s.chord, palette: palette)
                    }
                    .foregroundColor(palette.text)
                    .padding(14)
                    .frame(width: 250)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    func testExportPreviewSheet() throws {
        let palette = ChordPalette.dark
        let guitar = samples(InstrumentLibrary.guitar, [("C", .major), ("G", .major), ("D", .major), ("A", .minor), ("E", .minor), ("F", .major)])
        let ukulele = samples(InstrumentLibrary.ukulele, [("C", .major), ("G", .major), ("A", .minor), ("F", .major), ("D", .minor), ("G", .dominant7)])
        let view = VStack(alignment: .leading, spacing: 22) {
            sheet(title: "吉他 · 标准定弦（每个和弦的第 1 个把位）", items: guitar, palette: palette)
            sheet(title: "尤克里里 · GCEA（每个和弦的第 1 个把位）", items: ukulele, palette: palette)
        }
        .padding(24)
        .background(palette.background)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.width, 1000)
        if let path = ProcessInfo.processInfo.environment["CHORDKIT_PREVIEW_PATH"] {
            try write(image, to: URL(fileURLWithPath: path))
        }
    }
}
