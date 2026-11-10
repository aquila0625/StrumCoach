import SwiftUI
import TunerKit

/// 选择面板里的一行。
struct PickerRow: Identifiable, Equatable {
    let id: String
    /// 主要内容：分解指法的数字串，或节奏型的箭头。
    let lead: String
    /// 说明 / 名称（可能为空）。
    let title: String
    let isCustom: Bool
    /// 名称放在上面、主要内容放在下面（节奏型的箭头串比较长）。
    var stacked = false
    /// 节奏型：用格子符号（长箭头、短箭头、根音圆点…）画，不用文字 `lead`。
    var cells: [StrumCell]? = nil
    var cellsPerBeat = 2
}

/// 选择面板（小弹窗）：分解指法和扫弦节奏型共用。列出预设和自定义的，选中的打勾；
/// 自定义的右边有“…”菜单（编辑、删除），最后一行“自定义…”新建。
struct PatternPickerPanel: View {
    let title: String
    let rows: [PickerRow]
    let selectedID: String?
    var footer: String?
    var canAddCustom = true
    let palette: ChordPalette
    let strings: ChordStrings
    let onSelect: (String) -> Void
    var onNew: (() -> Void)?
    var onEdit: ((String) -> Void)?
    var onDelete: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.sub)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            ForEach(rows) { row in rowView(row) }
            if let onNew {
                if canAddCustom {
                    Button(action: onNew) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                            Text(strings.customRow).font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 16).frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(strings.limitReached(ArpeggioInput.maxSaved))
                        .font(.system(size: 12)).foregroundStyle(palette.sub)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .frame(width: 300, alignment: .leading)
        .background(palette.card)
        .foregroundStyle(palette.text)
    }

    @ViewBuilder private func rowView(_ row: PickerRow) -> some View {
        let on = row.id == selectedID
        HStack(spacing: 0) {
            Button { onSelect(row.id) } label: {
                HStack(spacing: 8) {
                    if row.stacked {
                        VStack(alignment: .leading, spacing: 2) {
                            if !row.title.isEmpty { Text(row.title).font(.system(size: 13)).foregroundStyle(palette.sub).lineLimit(1) }
                            if let cells = row.cells {
                                StrumGlyphRow(cells: cells, cellsPerBeat: row.cellsPerBeat,
                                              color: on ? palette.accent : palette.text, accent: palette.accent, onAccent: palette.onAccent)
                            } else {
                                Text(row.lead)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(on ? palette.accent : palette.text)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                        }
                        .padding(.vertical, 6)
                    } else {
                        Text(row.lead)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(on ? palette.accent : palette.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        if !row.title.isEmpty {
                            Text("·").foregroundStyle(palette.dim)
                            Text(row.title)
                                .font(.system(size: 14))
                                .foregroundStyle(palette.sub)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 8)
                    if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.accent) }
                }
                .padding(.leading, 16).padding(.trailing, row.isCustom ? 4 : 16).frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.title.isEmpty ? row.lead : "\(row.lead)\(strings.listSeparator)\(row.title)")
            .accessibilityAddTraits(on ? .isSelected : [])
            if row.isCustom, onEdit != nil || onDelete != nil {
                Menu {
                    if let onEdit { Button { onEdit(row.id) } label: { Label(strings.edit, systemImage: "pencil") } }
                    if let onDelete { Button(role: .destructive) { onDelete(row.id) } label: { Label(strings.delete, systemImage: "trash") } }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.sub)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
            }
        }
    }
}

/// 分解指法选择面板：数字串 + 一行说明，选中的打勾。
struct ArpeggioPickerPanel: View {
    let patterns: [ArpeggioPattern]
    let selectedID: String?
    let rootString: Int?
    let palette: ChordPalette
    let strings: ChordStrings
    var canAddCustom = true
    var onNew: (() -> Void)?
    var onEdit: ((ArpeggioPattern) -> Void)?
    var onDelete: ((ArpeggioPattern) -> Void)?
    let onSelect: (ArpeggioPattern) -> Void

    init(patterns: [ArpeggioPattern], selectedID: String?, rootString: Int?, palette: ChordPalette, strings: ChordStrings,
         canAddCustom: Bool = true, onNew: (() -> Void)? = nil, onEdit: ((ArpeggioPattern) -> Void)? = nil,
         onDelete: ((ArpeggioPattern) -> Void)? = nil, onSelect: @escaping (ArpeggioPattern) -> Void) {
        self.patterns = patterns; self.selectedID = selectedID; self.rootString = rootString
        self.palette = palette; self.strings = strings; self.canAddCustom = canAddCustom
        self.onNew = onNew; self.onEdit = onEdit; self.onDelete = onDelete; self.onSelect = onSelect
    }

    var body: some View {
        PatternPickerPanel(
            title: strings.arpeggioTitle,
            rows: patterns.map { PickerRow(id: $0.id, lead: $0.digits, title: strings.summary($0), isCustom: $0.isCustom) },
            selectedID: selectedID,
            footer: rootString.map(strings.rootStringNote),
            canAddCustom: canAddCustom, palette: palette, strings: strings,
            onSelect: { id in if let p = patterns.first(where: { $0.id == id }) { onSelect(p) } },
            onNew: onNew,
            onEdit: onEdit.map { edit in { id in if let p = patterns.first(where: { $0.id == id }) { edit(p) } } },
            onDelete: onDelete.map { del in { id in if let p = patterns.first(where: { $0.id == id }) { del(p) } } })
    }
}

/// 扫弦节奏型选择面板：名称 + 箭头，选中的打勾。
struct RhythmPickerPanel: View {
    let rhythms: [StrumRhythm]
    let selectedID: String?
    let palette: ChordPalette
    let strings: ChordStrings
    var canAddCustom = true
    var onNew: (() -> Void)?
    var onEdit: ((StrumRhythm) -> Void)?
    var onDelete: ((StrumRhythm) -> Void)?
    let onSelect: (StrumRhythm) -> Void

    init(rhythms: [StrumRhythm], selectedID: String?, palette: ChordPalette, strings: ChordStrings, canAddCustom: Bool = true,
         onNew: (() -> Void)? = nil, onEdit: ((StrumRhythm) -> Void)? = nil, onDelete: ((StrumRhythm) -> Void)? = nil,
         onSelect: @escaping (StrumRhythm) -> Void) {
        self.rhythms = rhythms; self.selectedID = selectedID; self.palette = palette; self.strings = strings
        self.canAddCustom = canAddCustom; self.onNew = onNew; self.onEdit = onEdit; self.onDelete = onDelete; self.onSelect = onSelect
    }

    var body: some View {
        PatternPickerPanel(
            title: strings.rhythmPickerTitle,
            rows: rhythms.map { PickerRow(id: $0.id, lead: $0.arrows, title: strings.title($0), isCustom: $0.isCustom, stacked: true,
                                          cells: $0.cells, cellsPerBeat: $0.cellsPerBeat) },
            selectedID: selectedID, footer: nil, canAddCustom: canAddCustom, palette: palette, strings: strings,
            onSelect: { id in if let r = rhythms.first(where: { $0.id == id }) { onSelect(r) } },
            onNew: onNew,
            onEdit: onEdit.map { edit in { id in if let r = rhythms.first(where: { $0.id == id }) { edit(r) } } },
            onDelete: onDelete.map { del in { id in if let r = rhythms.first(where: { $0.id == id }) { del(r) } } })
    }
}

/// 节奏型一格的符号：`D` 全扫是长箭头，`d` 半扫和 `U` 上扫是短箭头，`B` 根音是带 R 的圆点，`X` 闷音是 ✕，空拍什么都不画。
public struct StrumGlyph: View {
    let cell: StrumCell
    let color: Color
    /// 根音圆点的颜色（和圆点里字的颜色）。
    let accent: Color
    let onAccent: Color
    var size: CGFloat = 1

    /// - Parameters:
    ///   - color: 箭头、✕ 的颜色；根音圆点在 `color == onAccent`（高亮格子里）时反色画。
    ///   - accent: 根音圆点的底色；`onAccent`：圆点里 R 的颜色。
    ///   - size: 整体缩放，1 是和弦库里的大小（长箭头 15 点、短箭头 10 点、圆点 14 点）。
    public init(cell: StrumCell, color: Color, accent: Color, onAccent: Color, size: CGFloat = 1) {
        self.cell = cell; self.color = color; self.accent = accent; self.onAccent = onAccent; self.size = size
    }

    public var body: some View {
        switch cell {
        case .down:
            Image(systemName: "arrow.down").font(.system(size: 15 * size, weight: .bold)).foregroundStyle(color)
        case .downTreble:
            Image(systemName: "arrow.down").font(.system(size: 10 * size, weight: .bold)).foregroundStyle(color)
        case .up:
            Image(systemName: "arrow.up").font(.system(size: 10 * size, weight: .bold)).foregroundStyle(color)
        case .mute:
            Image(systemName: "xmark").font(.system(size: 11 * size, weight: .bold)).foregroundStyle(color)
        case .bass:
            ZStack {
                Circle().fill(color == onAccent ? onAccent : accent)
                Text("R").font(.system(size: 8 * size, weight: .heavy)).foregroundStyle(color == onAccent ? accent : onAccent)
            }
            .frame(width: 14 * size, height: 14 * size)
        case .rest:
            Color.clear.frame(width: 6 * size, height: 6 * size)
        }
    }
}

/// 一行符号（拍与拍之间留空隙），选择面板里用。
struct StrumGlyphRow: View {
    let cells: [StrumCell]
    let cellsPerBeat: Int
    let color: Color
    let accent: Color
    let onAccent: Color

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(stride(from: 0, to: cells.count, by: max(1, cellsPerBeat))), id: \.self) { start in
                HStack(spacing: 2) {
                    ForEach(start..<min(cells.count, start + cellsPerBeat), id: \.self) { i in
                        ZStack {
                            if cells[i].isStroke {
                                StrumGlyph(cell: cells[i], color: color, accent: accent, onAccent: onAccent)
                            } else {
                                RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    .frame(width: 9, height: 14)
                            }
                        }
                        .frame(width: cells.count > 8 && cellsPerBeat == 4 ? 12 : 16, height: 18)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 小格子

/// 一小节的小格子：每格一个箭头（↓ 下扫、↑ 上扫、✕ 闷音、· 空拍），拍与拍之间留空隙；`activeCell` 高亮。
struct StrumCellStrip: View {
    let cells: [StrumCell]
    let cellsPerBeat: Int
    var activeCell: Int?
    let palette: ChordPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: cells.count, by: max(1, cellsPerBeat))), id: \.self) { start in
                HStack(spacing: 2) {
                    ForEach(start..<min(cells.count, start + cellsPerBeat), id: \.self) { i in cell(i) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func cell(_ i: Int) -> some View {
        let on = activeCell == i
        let stroke = cells[i].isStroke
        return Group {
            if stroke {
                StrumGlyph(cell: cells[i], color: on ? palette.onAccent : palette.text, accent: palette.accent,
                           onAccent: palette.onAccent, size: cells.count > 16 ? 0.8 : 1)
            } else {
                Color.clear      // 空拍：什么都不画，只有虚线框，一眼看出这一格是空的
            }
        }
        .frame(maxWidth: 26)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(on ? palette.accent : (stroke ? palette.card2 : Color.clear), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if !stroke && !on {
                RoundedRectangle(cornerRadius: 6).strokeBorder(palette.dim, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .scaleEffect(on ? 1.08 : 1)
        .animation(.easeOut(duration: 0.08), value: on)
    }
}

/// 演奏时跟着播放位置高亮当前格子的版本。
struct LiveStrumCellStrip: View {
    let model: ChordLibraryModel
    let rhythm: StrumRhythm
    let palette: ChordPalette

    var body: some View {
        TimelineView(.animation(paused: !model.isPlaying)) { _ in
            StrumCellStrip(cells: rhythm.cells, cellsPerBeat: rhythm.cellsPerBeat,
                           activeCell: model.isPlaying ? model.playingCell() : nil, palette: palette)
        }
    }
}

// MARK: - 输入辅助

/// 输入框下面的一排快捷键：不用切键盘就能输入，空拍和删除一定在。
struct QuickKey: Identifiable {
    let id: String
    /// 按键上显示的字。
    let title: String
    /// 点一下追加到输入里的内容；删除键为 nil。
    let text: String?
    /// 读屏名称。
    let label: String
    var isRest = false
    var isDelete = false
    /// 节奏型的键：符号（长 / 短箭头、根音圆点、✕）和字母，以及一个字的说明（根音 / 全扫 / 半扫 / 上扫 / 闷音 / 空拍）。
    var glyph: StrumCell? = nil
    var letter: String? = nil
    var caption: String? = nil
}

/// 两个编辑页的快捷键：不用切键盘就能输入，空拍和删除一定在。
enum QuickKeys {
    /// 分解指法：弦号 1…（按这件乐器的弦数）、R（根音弦），第二行是空拍和删除。
    static func arpeggio(stringCount: Int, strings: ChordStrings) -> [[QuickKey]] {
        let digits = (1...max(1, stringCount)).map { QuickKey(id: "s\($0)", title: "\($0)", text: "\($0)", label: "\($0)") }
        return [digits + [QuickKey(id: "r", title: "R", text: "R", label: "R")],
                [QuickKey(id: "rest", title: "-", text: "-", label: strings.restKey, isRest: true),
                 QuickKey(id: "del", title: "", text: nil, label: strings.backspaceKey, isDelete: true)]]
    }

    /// 扫弦节奏型：B 根音、↓D 全扫、↓d 半扫、↑U 上扫、✕ 闷音，第二行是空拍和删除；每个键下面一个字的说明。
    static func rhythm(strings: ChordStrings) -> [[QuickKey]] {
        [[QuickKey(id: "b", title: "B", text: "B", label: strings.bassRoot, glyph: .bass, letter: "B", caption: strings.bassRoot),
          QuickKey(id: "D", title: "D", text: "D", label: strings.cellFull, glyph: .down, letter: "D", caption: strings.cellFull),
          QuickKey(id: "d", title: "d", text: "d", label: strings.cellHalf, glyph: .downTreble, letter: "d", caption: strings.cellHalf),
          QuickKey(id: "u", title: "U", text: "U", label: strings.cellUp, glyph: .up, letter: "U", caption: strings.cellUp),
          QuickKey(id: "x", title: "X", text: "X", label: strings.cellMute, glyph: .mute, letter: "X", caption: strings.cellMute)],
         [QuickKey(id: "rest", title: ".", text: ".", label: strings.restKey, isRest: true),
          QuickKey(id: "del", title: "", text: nil, label: strings.backspaceKey, isDelete: true)]]
    }

    /// 按一下键之后的输入内容。
    static func apply(_ key: QuickKey, to text: String) -> String {
        if key.isDelete { return deletingLastToken(text) }
        return text + (key.text ?? "")
    }
}

struct QuickKeyPad: View {
    let rows: [[QuickKey]]
    let palette: ChordPalette
    let onKey: (QuickKey) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { key in keyView(key) }
                }
            }
        }
    }

    private func keyView(_ key: QuickKey) -> some View {
        Button { onKey(key) } label: {
            Group {
                if key.isDelete {
                    Image(systemName: "delete.left").font(.system(size: 16, weight: .semibold))
                } else if key.isRest {
                    // 空拍键：虚线空格子 + 一个短横，和预览里的空格子一个样
                    Image(systemName: "minus").font(.system(size: 15, weight: .bold))
                } else if let glyph = key.glyph {
                    VStack(spacing: 1) {
                        HStack(spacing: 3) {
                            StrumGlyph(cell: glyph, color: palette.text, accent: palette.accent, onAccent: palette.onAccent, size: 1.05)
                            if let letter = key.letter { Text(letter).font(.system(size: 14, weight: .semibold, design: .monospaced)) }
                        }
                        if let caption = key.caption {
                            Text(caption).font(.system(size: 10)).foregroundStyle(palette.sub).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                } else {
                    Text(key.title).font(.system(size: 17, weight: .semibold, design: .monospaced))
                }
            }
            .frame(maxWidth: .infinity, minHeight: key.glyph == nil ? 40 : 46)
            .foregroundStyle(palette.text)
            .background(key.isRest || key.isDelete ? Color.clear : palette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                if key.isRest || key.isDelete {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(key.isRest ? palette.accent : palette.dim,
                                      style: StrokeStyle(lineWidth: 1.5, dash: key.isRest ? [4, 3] : []))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key.label)
    }
}

/// 删掉最后一个字符（先去掉结尾的分隔符）。
func deletingLastToken(_ text: String) -> String {
    var t = text
    while let last = t.last, last.isWhitespace || ",，、;；/|".contains(last) { t.removeLast() }
    if !t.isEmpty { t.removeLast() }
    return t
}

/// 分解指法的预览：一步一个格子，弦号 / R 是实心格子，空拍是虚线空格子；输入里有非法字符时由调用方改用标红的文字。
struct ArpeggioStepStrip: View {
    let steps: [ArpeggioStep]
    let palette: ChordPalette

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 34), spacing: 5)], alignment: .leading, spacing: 5) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                cell(step)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func cell(_ step: ArpeggioStep) -> some View {
        switch step {
        case .rest:
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(palette.dim, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 30)
        case .root:
            Text("R").font(.system(size: 15, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(palette.onAccent)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 7))
        case .string(let n):
            Text("\(n)").font(.system(size: 15, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(palette.text)
                .background(palette.card2, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

/// 输入弦号 / 节奏型字符用的输入框：关掉自动大小写、自动更正、拼写检查，以及**智能标点**
/// （智能标点会把连着输入的 `--` 变成 `–`、`...` 变成 `…`，空拍就乱了）。
struct SymbolInputField: View {
    @Binding var text: String
    let placeholder: String
    let palette: ChordPalette
    /// 是否自动大写：分解指法里 R 不分大小写，可以大写；节奏型里 `D`（全扫）和 `d`（半扫）要分大小写，所以不能自动大写。
    var capitalizesAll = true

    var body: some View {
        #if canImport(UIKit) && !os(macOS)
        UIKitSymbolField(text: $text, placeholder: placeholder, palette: palette, capitalizesAll: capitalizesAll)
            .frame(height: 24)
        #else
        TextField(placeholder, text: $text)
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .autocorrectionDisabled()
        #endif
    }
}

#if canImport(UIKit) && !os(macOS)
import UIKit

private struct UIKitSymbolField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let palette: ChordPalette
    let capitalizesAll: Bool

    func makeUIView(context: Context) -> UITextField {
        let f = UITextField()
        f.font = UIFont.monospacedSystemFont(ofSize: 20, weight: .semibold)
        f.autocorrectionType = .no
        f.autocapitalizationType = capitalizesAll ? .allCharacters : .none
        f.spellCheckingType = .no
        f.smartDashesType = .no
        f.smartQuotesType = .no
        f.smartInsertDeleteType = .no
        f.keyboardType = .asciiCapable
        f.returnKeyType = .done
        f.clearButtonMode = .never
        f.delegate = context.coordinator
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }

    func updateUIView(_ f: UITextField, context: Context) {
        if f.text != text { f.text = text }
        f.textColor = UIColor(palette.text)
        f.tintColor = UIColor(palette.accent)
        f.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor(palette.dim)])
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: UIKitSymbolField
        init(_ parent: UIKitSymbolField) { self.parent = parent }
        @objc func changed(_ f: UITextField) { parent.text = f.text ?? "" }
        func textFieldShouldReturn(_ f: UITextField) -> Bool { f.resignFirstResponder(); return true }
    }
}
#endif

// MARK: - 自定义编辑

/// 正在编辑的自定义内容；nil 表示新建。
enum CustomEditorTarget: Identifiable {
    case arpeggio(CustomArpeggio?)
    case rhythm(CustomStrumRhythm?)

    var id: String {
        switch self {
        case .arpeggio(let a): return "arpeggio-\(a?.id ?? "new")"
        case .rhythm(let r): return "rhythm-\(r?.id ?? "new")"
        }
    }
}

/// 把解析出的字符拼成一行，无效的标红。
private func tokenLine(_ tokens: [(text: String, isValid: Bool)], palette: ChordPalette, separator: String) -> Text {
    var result = Text("")
    for (i, t) in tokens.enumerated() {
        if i > 0, !separator.isEmpty { result = result + Text(separator) }
        result = result + Text(t.text).foregroundColor(t.isValid ? palette.text : .red)
    }
    return result
}

private struct EditorField: ViewModifier {
    let palette: ChordPalette
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).frame(height: 44)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(palette.text)
    }
}

/// 自定义分解指法：输入一串弦号，实时校验，可以试听、命名、保存。
struct CustomArpeggioEditor: View {
    let model: ChordLibraryModel
    let editing: CustomArpeggio?
    let palette: ChordPalette
    let strings: ChordStrings
    let onClose: () -> Void

    @State private var text: String
    @State private var name: String

    init(model: ChordLibraryModel, editing: CustomArpeggio?, palette: ChordPalette, strings: ChordStrings, onClose: @escaping () -> Void) {
        self.model = model; self.editing = editing; self.palette = palette; self.strings = strings; self.onClose = onClose
        _text = State(initialValue: editing?.text ?? "")
        _name = State(initialValue: editing?.name ?? "")
    }

    private var parsed: ArpeggioParse { model.validateArpeggio(text) }

    private var keyRows: [[QuickKey]] { QuickKeys.arpeggio(stringCount: model.tuning.strings.count, strings: strings) }
    private var isNewAndFull: Bool { editing == nil && !model.canAddCustomArpeggio }

    private var message: (text: String, isError: Bool) {
        if isNewAndFull { return (strings.limitReached(ArpeggioInput.maxSaved), true) }
        switch parsed.failure {
        case .invalidCharacters: return (strings.invalidArpeggio(model.tuning.strings.count), true)
        case .tooLong: return (strings.tooManyNotes(ArpeggioInput.maxSteps), true)
        default: return (strings.arpeggioHelp(model.tuning.strings.count), false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(title: strings.arpeggioEditorTitle, canSave: parsed.isValid && !isNewAndFull) {
                if model.saveCustomArpeggio(id: editing?.id, name: name, text: text) != nil { onClose() }
            }
            SymbolInputField(text: $text, placeholder: "5 3 2 1", palette: palette)
                .modifier(EditorField(palette: palette))
            QuickKeyPad(rows: keyRows, palette: palette) { key in text = QuickKeys.apply(key, to: text) }
            if parsed.tokens.contains(where: { !$0.isValid }) {
                tokenLine(parsed.tokens.map { ($0.text, $0.isValid) }, palette: palette, separator: " ")
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
            } else if !parsed.steps.isEmpty {
                ArpeggioStepStrip(steps: parsed.steps, palette: palette)
            }
            Text(message.text)
                .font(.system(size: 13))
                .foregroundStyle(message.isError ? Color.red : palette.sub)
                .fixedSize(horizontal: false, vertical: true)
            TextField(parsed.isValid ? parsed.normalized : strings.nameLabel, text: $name)
                .font(.system(size: 16))
                .modifier(EditorField(palette: palette))
            footer(canPreview: parsed.isValid, preview: { model.previewArpeggio(text: text) },
                   delete: editing.map { e in { model.deleteCustomArpeggio(id: e.id); onClose() } })
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func header(title: String, canSave: Bool, save: @escaping () -> Void) -> some View {
        EditorHeader(title: title, canSave: canSave, palette: palette, strings: strings, onCancel: onClose, onSave: save)
    }

    private func footer(canPreview: Bool, preview: @escaping () -> Void, delete: (() -> Void)?) -> some View {
        EditorFooter(canPreview: canPreview, palette: palette, strings: strings, onPreview: preview, onDelete: delete)
    }
}

/// 自定义扫弦节奏型的编辑页：每个字符一格（D 下扫、U 上扫、X 闷音、- 或 . 空拍），实时显示成箭头格子，
/// 非法字符标红，可以选格子单位（八分 / 十六分）、试听、命名、保存、删除。
///
/// 训练页也可以直接用：传自己要存进哪类乐器（`family`），保存后收到 `onSave`。
/// 存储和和弦库共用 `ChordLibraryModel` 的自定义节奏型（每类乐器最多 10 个）。
public struct CustomRhythmEditor: View {
    let model: ChordLibraryModel
    let family: InstrumentFamily
    let editing: CustomStrumRhythm?
    let palette: ChordPalette
    let strings: ChordStrings
    let selectsOnSave: Bool
    let onSave: ((CustomStrumRhythm) -> Void)?
    let onClose: () -> Void

    @State private var text: String
    @State private var name: String
    @State private var cellsPerBeat: Int
    /// 图例只在第一次打开编辑页时显示（打开时读一次，同一次编辑里一直显示）。
    @State private var showsLegend: Bool

    /// - Parameters:
    ///   - family: 存进哪类乐器的列表（试听也用这件乐器的声音）；nil 用和弦库当前的乐器。
    ///   - editing: 修改已有的；nil 是新建。
    ///   - selectsOnSave: 保存后是否同时设为和弦库里这类乐器选中的节奏型；训练页自己管选择时传 false。
    ///   - onSave: 保存成功后回调（再回调 `onClose`）。
    ///   - onClose: 取消、保存、删除之后调用，调用方在这里关掉页面。
    public init(model: ChordLibraryModel, family: InstrumentFamily? = nil, editing: CustomStrumRhythm? = nil,
                palette: ChordPalette = .dark, strings: ChordStrings = .current, selectsOnSave: Bool = true,
                onSave: ((CustomStrumRhythm) -> Void)? = nil, onClose: @escaping () -> Void) {
        self.model = model; self.family = family ?? model.instrument.family; self.editing = editing
        self.palette = palette; self.strings = strings; self.selectsOnSave = selectsOnSave
        self.onSave = onSave; self.onClose = onClose
        _text = State(initialValue: editing?.code ?? "")
        _name = State(initialValue: editing?.name ?? "")
        _cellsPerBeat = State(initialValue: editing?.cellsPerBeat ?? 2)
        _showsLegend = State(initialValue: model.shouldShowStrumLegend)
    }

    private var parsed: StrumParse { model.validateRhythm(text, cellsPerBeat: cellsPerBeat) }

    private var keyRows: [[QuickKey]] { QuickKeys.rhythm(strings: strings) }
    private var isNewAndFull: Bool { editing == nil && !model.canAddCustomRhythm(for: family) }

    private var message: (text: String, isError: Bool) {
        if isNewAndFull { return (strings.limitReached(StrumInput.maxSaved), true) }
        switch parsed.failure {
        case .invalidCharacters: return (strings.invalidRhythm, true)
        case .tooLong: return (strings.tooManyBeats(StrumInput.maxBeats), true)
        case .notWholeBeats: return (strings.notWholeBeats(cellsPerBeat), true)
        default: return (strings.rhythmHelp, false)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorHeader(title: strings.rhythmEditorTitle, canSave: parsed.isValid && !isNewAndFull, palette: palette,
                         strings: strings, onCancel: onClose) {
                if let saved = model.saveCustomRhythm(id: editing?.id, name: name, text: text, cellsPerBeat: cellsPerBeat,
                                                      family: family, select: selectsOnSave) {
                    onSave?(saved)
                    onClose()
                }
            }
            SymbolInputField(text: $text, placeholder: "D.DU.UDU", palette: palette, capitalizesAll: false)
                .modifier(EditorField(palette: palette))
            QuickKeyPad(rows: keyRows, palette: palette) { key in text = QuickKeys.apply(key, to: text) }
            if showsLegend {
                // 第一次打开编辑页时显示一行图例
                Text(strings.rhythmLegend)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(strings.unitLabel).font(.system(size: 13)).foregroundStyle(palette.sub)
                Picker(strings.unitLabel, selection: $cellsPerBeat) {
                    Text(strings.eighthUnit).tag(2)
                    Text(strings.sixteenthUnit).tag(4)
                }
                .pickerStyle(.segmented)
            }
            if parsed.tokens.contains(where: { !$0.isValid }) {
                tokenLine(parsed.tokens.map { ($0.text, $0.isValid) }, palette: palette, separator: "")
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
            } else if !parsed.cells.isEmpty {
                StrumCellStrip(cells: parsed.cells, cellsPerBeat: cellsPerBeat,
                               activeCell: nil, palette: palette)
            }
            Text(message.text)
                .font(.system(size: 13))
                .foregroundStyle(message.isError ? Color.red : palette.sub)
                .fixedSize(horizontal: false, vertical: true)
            TextField(parsed.isValid ? parsed.normalized : strings.nameLabel, text: $name)
                .font(.system(size: 16))
                .modifier(EditorField(palette: palette))
            EditorFooter(canPreview: parsed.isValid && family.supportsStrumming, palette: palette, strings: strings,
                         onPreview: { model.previewRhythm(text: text, cellsPerBeat: cellsPerBeat, family: family) },
                         onDelete: editing.map { e in { model.deleteCustomRhythm(id: e.id, family: family); onClose() } })
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(palette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { model.markStrumLegendSeen() }
    }
}

private struct EditorHeader: View {
    let title: String
    let canSave: Bool
    let palette: ChordPalette
    let strings: ChordStrings
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Button(strings.cancel, action: onCancel).foregroundStyle(palette.sub)
            Spacer()
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(palette.text)
            Spacer()
            Button(strings.save, action: onSave)
                .fontWeight(.bold)
                .foregroundStyle(canSave ? palette.accent : palette.dim)
                .disabled(!canSave)
        }
        .font(.system(size: 16))
    }
}

private struct EditorFooter: View {
    let canPreview: Bool
    let palette: ChordPalette
    let strings: ChordStrings
    let onPreview: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        HStack {
            Button(action: onPreview) {
                Label(strings.play, systemImage: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16).frame(height: 40)
                    .foregroundStyle(canPreview ? palette.onAccent : palette.dim)
                    .background(canPreview ? palette.accent : palette.card, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canPreview)
            Spacer()
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(strings.delete, systemImage: "trash").font(.system(size: 15))
                }
                .foregroundStyle(Color.red)
            }
        }
    }
}

