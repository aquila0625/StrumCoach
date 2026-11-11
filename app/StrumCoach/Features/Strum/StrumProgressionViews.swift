import ChordKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 编辑和弦进行

/// 一行和弦块（横向滚动，数量不限）：点一下修改，长按拖动排序，末尾“+”添加；下面是常用进行、我的进行、保存、循环 2 遍。
struct ProgressionCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.noteNaming) private var naming
    @Bindable var trainer: StrumTrainer
    @State private var editing: ProgressionChord?
    @State private var adding = false
    @State private var dragging: UUID?
    @State private var showLibrary = false
    @State private var showSave = false
    @State private var saveName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("和弦进行").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                Text("\(trainer.progression.totalBars) 小节").font(.system(size: 12)).foregroundStyle(theme.sub)
                Spacer()
                Picker("乐器", selection: $trainer.instrumentID) {
                    ForEach(ChordLibrary.strummableInstruments, id: \.id) { inst in
                        Text(verbatim: inst.name).tag(inst.id)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(trainer.progression.chords) { c in
                        ChordBlock(name: naming.chordName(c.chord), bars: c.bars)
                            .opacity(dragging == c.id ? 0.4 : 1)
                            .onTapGesture { editing = c }
                            .onDrag {
                                dragging = c.id
                                return NSItemProvider(object: c.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: ReorderDrop(target: c.id, trainer: trainer, dragging: $dragging))
                            .contextMenu {
                                Button { editing = c } label: { Label("修改", systemImage: "pencil") }
                                Button { trainer.progression.duplicate(c.id) } label: { Label("复制", systemImage: "plus.square.on.square") }
                                if trainer.progression.chords.count > 1 {
                                    Button(role: .destructive) { trainer.progression.delete(c.id) } label: { Label("删除", systemImage: "trash") }
                                }
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(Text("点按修改，长按拖动排序"))
                    }
                    Button { adding = true } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.accent)
                            .frame(width: 52, height: 58)
                            .background(theme.accentTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加和弦")
                }
                .padding(.vertical, 2)
                .animation(.snappy(duration: 0.2), value: trainer.progression.chords)
            }
            .scrollClipDisabled()
            HStack(spacing: 8) {
                Menu {
                    ForEach(ChordProgression.presets) { p in
                        Button(p.name) { trainer.apply(p) }
                    }
                } label: {
                    pill(Text("常用进行"), "music.note.list")
                }
                Button { showLibrary = true } label: { pill(Text("我的进行"), "folder") }
                    .buttonStyle(.plain)
                Button {
                    saveName = trainer.progression.name.isEmpty ? trainer.progression.label(naming.chordName) : trainer.progression.name
                    showSave = true
                } label: { pill(Text("保存"), "square.and.arrow.down") }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            PracticeTargetField(trainer: trainer)
        }
        .padding(16)
        .card(radius: 20)
        .sheet(item: $editing) { c in
            ProgressionChordEditor(chord: c, isNew: false, canDelete: trainer.progression.chords.count > 1,
                                   onSave: { trainer.progression.update($0) },
                                   onDelete: { trainer.progression.delete(c.id) },
                                   onDuplicate: { trainer.progression.duplicate(c.id) })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $adding) {
            let last = trainer.progression.chords.last
            ProgressionChordEditor(chord: ProgressionChord(root: last?.root ?? 0, type: last?.type ?? .major), isNew: true, canDelete: false,
                                   onSave: { trainer.progression.append($0) }, onDelete: {}, onDuplicate: {})
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showLibrary) {
            SavedProgressionsSheet(trainer: trainer).presentationDetents([.medium, .large])
        }
        .alert("保存和弦进行", isPresented: $showSave) {
            TextField("名字", text: $saveName)
            Button("保存") { trainer.saveProgression(named: saveName) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("同名的会被覆盖。")
        }
    }

    private func pill(_ label: Text, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            label
        }
        .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.accent)
        .padding(.horizontal, 11).frame(height: 30)
        .background(theme.accentTint, in: Capsule())
    }
}

/// 一个和弦块：和弦名 + 持续几小节
struct ChordBlock: View {
    @Environment(\.theme) private var theme
    let name: String
    let bars: Int
    var current = false
    var flash = false

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: name).font(.system(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(current ? .white : theme.text)
            Text("\(bars) 小节").font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(current ? .white.opacity(0.85) : theme.sub)
        }
        .frame(minWidth: 52).padding(.horizontal, 10).frame(height: 58)
        .background(current ? theme.accent : theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.accent, lineWidth: flash ? 3 : 0)
        }
        .scaleEffect(flash ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: flash)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name)，\(bars) 小节"))
    }
}

/// 长按拖到另一个和弦块上：挪到它的位置
private struct ReorderDrop: DropDelegate {
    let target: UUID
    let trainer: StrumTrainer
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        trainer.progression.move(dragging, to: target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// 改一个和弦：根音 + 类型 + 持续几小节；也能删除、复制。
struct ProgressionChordEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.noteNaming) private var naming
    @State var chord: ProgressionChord
    let isNew: Bool
    let canDelete: Bool
    let onSave: (ProgressionChord) -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    init(chord: ProgressionChord, isNew: Bool, canDelete: Bool, onSave: @escaping (ProgressionChord) -> Void,
         onDelete: @escaping () -> Void, onDuplicate: @escaping () -> Void) {
        _chord = State(initialValue: chord)
        self.isNew = isNew; self.canDelete = canDelete
        self.onSave = onSave; self.onDelete = onDelete; self.onDuplicate = onDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("取消") { dismiss() }.font(.system(size: 17)).foregroundStyle(theme.sub)
                Spacer()
                Text(verbatim: naming.chordName(chord.chord)).font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                Button(isNew ? "添加" : "完成") { onSave(chord); dismiss() }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent)
            }
            Text("根音").font(.system(size: 13)).foregroundStyle(theme.sub)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(0..<12, id: \.self) { pc in
                    chip(Text(verbatim: naming.rootName(pitchClass: pc)), selected: chord.root == pc) { chord.root = pc }
                }
            }
            Text("类型").font(.system(size: 13)).foregroundStyle(theme.sub)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(ChordLibrary.types, id: \.id) { type in
                    chip(Text(verbatim: naming.chordName(pitchClass: chord.root, type: type)), selected: chord.typeID == type.id) {
                        chord.typeID = type.id
                    }
                }
            }
            Text("持续").font(.system(size: 13)).foregroundStyle(theme.sub)
            Picker("持续", selection: $chord.bars) {
                ForEach(ProgressionChord.barChoices, id: \.self) { n in Text("\(n) 小节").tag(n) }
            }
            .pickerStyle(.segmented)
            if !isNew {
                HStack(spacing: 12) {
                    Button { onDuplicate(); dismiss() } label: {
                        Label("复制", systemImage: "plus.square.on.square").font(.system(size: 15, weight: .medium))
                    }
                    Spacer()
                    if canDelete {
                        Button(role: .destructive) { onDelete(); dismiss() } label: {
                            Label("删除", systemImage: "trash").font(.system(size: 15, weight: .medium))
                        }
                    }
                }
                .foregroundStyle(theme.accent)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(ScreenBackground())
    }

    private func chip(_ label: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(selected ? .white : theme.text)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(selected ? theme.accent : theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 我的进行：点一下套用，左滑删除。
struct SavedProgressionsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.noteNaming) private var naming
    @Bindable var trainer: StrumTrainer

    var body: some View {
        NavigationStack {
            Group {
                if trainer.savedProgressions.isEmpty {
                    Text("还没有保存的进行。编辑好和弦后点“保存”。")
                        .font(.system(size: 14)).foregroundStyle(theme.sub)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(trainer.savedProgressions.reversed()) { p in
                            Button {
                                trainer.apply(p)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: p.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.text)
                                    Text(verbatim: p.label(naming.chordName)).font(.system(size: 13)).foregroundStyle(theme.sub).lineLimit(2)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { trainer.deleteSaved(p.id) } label: { Label("删除", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("我的进行"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

// MARK: - 练习时：当前和弦 + 下一个

/// 示范和跟练时顶部：当前和弦（大字 + 小指法图），旁边预告下一个；换和弦前一拍下一个块闪一下。
struct ProgressionNowView: View {
    @Environment(\.theme) private var theme
    @Environment(\.noteNaming) private var naming
    let trainer: StrumTrainer

    var body: some View {
        let chords = trainer.progression.chords
        let cur = trainer.currentChordIndex ?? 0
        let next = trainer.nextChordIndex
        HStack(alignment: .center, spacing: 14) {
            if chords.indices.contains(cur) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("现在").font(.system(size: 12)).foregroundStyle(theme.sub)
                    Text(verbatim: naming.chordName(chords[cur].chord))
                        .font(.system(size: 40, weight: .bold)).foregroundStyle(theme.text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                if let v = trainer.voicing(at: cur) {
                    ChordDiagramView(voicing: v, chord: chords[cur].chord, palette: palette, scale: 0.42)
                        .frame(maxHeight: 110)
                        .allowsHitTesting(false)
                }
            }
            Spacer(minLength: 4)
            VStack(spacing: 4) {
                Text("下一个").font(.system(size: 12)).foregroundStyle(theme.sub)
                if let next, chords.indices.contains(next) {
                    ChordBlock(name: naming.chordName(chords[next].chord), bars: chords[next].bars, flash: trainer.changeIsComing)
                } else {
                    Text(verbatim: "—").font(.system(size: 19, weight: .bold)).foregroundStyle(theme.dim).frame(width: 52, height: 58)
                }
            }
        }
        .padding(16)
        .card(radius: 20)
        .accessibilityElement(children: .combine)
    }

    private var palette: ChordPalette {
        let p = theme.tunerPalette
        return ChordPalette(background: .clear, card: p.card, card2: p.card2, line: p.line, text: p.text, sub: p.sub, dim: p.dim,
                            accent: p.accent, weak: p.weak, onText: theme.bg)
    }
}

// MARK: - 结果：按和弦分段

struct ProgressionResultSection: View {
    @Environment(\.theme) private var theme
    let report: ProgressionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按和弦").font(.system(size: 13)).foregroundStyle(theme.sub)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(report.segments, id: \.index) { seg in
                        VStack(spacing: 2) {
                            Text(verbatim: seg.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                            Text("\(seg.score)").font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(color(seg.score))
                        }
                        .frame(minWidth: 56).padding(.horizontal, 8).padding(.vertical, 8)
                        .background(theme.card2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .scrollClipDisabled()
            if let c = report.changeMeanMs {
                let v = Int(abs(c).rounded())
                (v < 5 ? Text("换和弦后第一下：刚好") : (c > 0 ? Text("换和弦后第一下：平均偏慢 \(v) 毫秒") : Text("换和弦后第一下：平均偏快 \(v) 毫秒")))
                    .font(.system(size: 13)).foregroundStyle(theme.sub)
            }
            if let advice = report.advice {
                Text(verbatim: advice).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func color(_ score: Int) -> Color {
        score >= 85 ? theme.green : (score >= 60 ? Color(red: 0.95, green: 0.68, blue: 0.1) : Color(red: 0.92, green: 0.26, blue: 0.24))
    }
}

// MARK: - 练习遍数

/// 跟练练几遍：数字键盘输入 1–99，留空表示一直练（直到点“结束”）。一遍 = 整个和弦进行走一遍。
struct PracticeTargetField: View {
    @Environment(\.theme) private var theme
    @Bindable var trainer: StrumTrainer
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("练习遍数").font(.system(size: 14)).foregroundStyle(theme.text)
            TextField(text: $text, prompt: Text(verbatim: "∞")) { Text("练习遍数") }
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 58, height: 34)
                .background(theme.card2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .focused($focused)
            Text("留空表示一直练").font(.system(size: 12)).foregroundStyle(theme.sub)
                .lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if focused {
                Button("完成") { focused = false }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
            }
        }
        .disabled(trainer.isBusy)
        .onAppear { text = trainer.practiceTarget.map(String.init) ?? "" }
        .onChange(of: text) { _, new in
            // 只要数字，最多两位；0 和空一样是“一直练”
            let digits = String(new.filter(\.isNumber).prefix(2))
            if digits != new { text = digits; return }
            trainer.practiceTarget = Int(digits).flatMap { $0 >= PracticeRun.targetRange.lowerBound ? $0 : nil }
        }
    }
}
