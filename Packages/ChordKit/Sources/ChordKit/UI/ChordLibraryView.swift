import SwiftUI
import TunerKit

/// 和弦库界面（对应设计稿画面 05）：乐器切换、和弦名与组成音、试听、指法图、把位翻页、根音与类型网格。
///
/// 标签栏等 App 外壳不在这里。
public struct ChordLibraryView: View {
    @Bindable private var model: ChordLibraryModel
    private let palette: ChordPalette
    private let strings: ChordStrings
    /// 只画当前把位、不用横向滚动的版本：ImageRenderer 渲染不了 ScrollView，测试截图时用。
    private let staticDiagram: Bool
    /// 静态版里固定显示的拨弦动画状态（预览图用）。
    private let staticPluck: [Int: Double]?
    /// 静态版里固定高亮的节奏型格子（预览图用）。
    private let staticActiveCell: Int?

    @Environment(\.noteNaming) private var naming
    @State private var showsPatterns = false
    @State private var showsRhythms = false
    @State private var showsTempo = false
    @State private var editor: CustomEditorTarget?
    @Environment(\.scenePhase) private var scenePhase

    public init(model: ChordLibraryModel, palette: ChordPalette = .dark, strings: ChordStrings = .current) {
        self.init(model: model, palette: palette, strings: strings, staticDiagram: false)
    }

    init(model: ChordLibraryModel, palette: ChordPalette, strings: ChordStrings, staticDiagram: Bool,
         staticPluck: [Int: Double]? = nil, staticActiveCell: Int? = nil) {
        self.model = model
        self.palette = palette
        self.strings = strings
        self.staticDiagram = staticDiagram
        self.staticPluck = staticPluck
        self.staticActiveCell = staticActiveCell
    }

    /// 界面内容（不含滚动容器）；单独拿出来是为了测试里能用 ImageRenderer 截图。
    var content: some View {
        VStack(spacing: 0) {
            topBar
            instrumentControl
            chordCard
            sectionLabel(strings.rootHeader).padding(.top, 14)
            rootGrid
            sectionLabel(strings.typeHeader).padding(.top, 14)
            typeGrid
        }
        .padding(.bottom, 24)
    }

    public var body: some View {
        Group {
            if staticDiagram { content } else { ScrollView { content }.scrollBounceBehavior(.basedOnSize) }
        }
            .background(palette.background.ignoresSafeArea())
            .foregroundStyle(palette.text)
            .sensoryFeedback(.selection, trigger: model.targetVoicingIndex)
            .onDisappear { model.stopPlayback() }
            // 进后台就停，免得一直响
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.stopPlayback() } }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack {
            Text(strings.title).font(.system(size: 34, weight: .bold))
            Spacer()
            Menu {
                Button {
                    model.toggleFavorite()
                } label: {
                    Label(model.isFavorite ? strings.unfavorite : strings.favorite,
                          systemImage: model.isFavorite ? "star.slash" : "star")
                }
                Toggle(isOn: $model.leftHanded) { Text(strings.leftHanded) }
                Section(strings.favoritesHeader) {
                    if model.favorites.items.isEmpty {
                        Text(strings.noFavorites)
                    } else {
                        ForEach(model.favorites.items) { f in
                            Button(favoriteTitle(f)) { model.go(to: f) }
                        }
                    }
                }
            } label: {
                Image(systemName: model.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(model.isFavorite ? palette.accent : palette.text)
                    .frame(width: 40, height: 40)
                    .background(palette.card, in: Circle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel(strings.favoritesHeader)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func favoriteTitle(_ f: ChordFavorite) -> String {
        let inst = ChordLibrary.instruments.first { $0.id == f.instrumentID }.map(strings.name) ?? f.instrumentID
        let name = f.chord.map(naming.chordName) ?? "?"
        return f.instrumentID == "bass" ? "\(name) · \(inst)" : "\(name) · \(inst) · \(f.voicingIndex + 1)"
    }

    // MARK: 乐器

    private var instrumentControl: some View {
        HStack(spacing: 0) {
            ForEach(ChordLibrary.instruments) { inst in
                let on = inst.id == model.instrument.id
                Button { model.select(instrument: inst) } label: {
                    Text(strings.name(inst))
                        .font(.system(size: 16, weight: on ? .bold : .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .foregroundStyle(on ? palette.onAccent : palette.sub)
                        .background(on ? palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    // MARK: 和弦卡片

    private var chordCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(naming.rootName(model.chord)).font(.system(size: 34, weight: .bold))
                        Text(model.chord.type.symbol).font(.system(size: 22, weight: .semibold))
                        if let hint = queuedHint {
                            Text(hint)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .padding(.leading, 10)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: queuedHint)
                    Text(verbatim: "\(strings.tones) \(naming.toneNames(model.chord).joined(separator: " · "))")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(palette.sub)
                }
                Spacer()
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 48, height: 48)
                        .background(palette.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isPlaying ? strings.stop : strings.play)
            }
            playModeRow
                .padding(.top, 10)
            diagram
                .padding(.top, 4)
            if model.isBass { bassLegend } else { pager }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20)
    }

    /// 演奏中排队的切换：“下一个：Dm”；只排队了换把位时是“下一个：C · 3”。
    private var queuedHint: String? {
        if let q = model.queuedChord { return strings.queuedNext(naming.chordName(q)) }
        if let i = model.queuedVoicingIndex { return strings.queuedNext("\(naming.chordName(model.chord)) · \(i + 1)") }
        return nil
    }

    @ViewBuilder private var diagram: some View {
        if let v = model.voicing {
            if staticDiagram {
                ChordDiagramView(voicing: v, chord: model.chord, palette: palette, leftHanded: model.leftHanded,
                                 strings: model.tuning.strings, pluck: staticPluck.map { ages in { ages } })
            } else {
                VoicingGallery(voicings: model.voicings, chord: model.chord, palette: palette,
                               leftHanded: model.leftHanded, strings: model.tuning.strings,
                               currentIndex: model.targetVoicingIndex, audibleIndex: model.voicingIndex,
                               text: strings, pluck: pluckProvider,
                               select: { model.select(voicingIndex: $0) },
                               onPluck: { page, string in model.pluckString(string, voicingIndex: page) })
                    // 换乐器、定弦、和弦时整个重建，直接从第一页开始，不要滑过去；演奏中换和弦带过渡动画
                    .id("\(model.instrument.id)-\(model.tuning.id)-\(model.chord.id)")
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        } else if let b = model.bassPositions {
            BassDiagramView(positions: b, palette: palette, leftHanded: model.leftHanded, pluck: pluckProvider,
                            onPluck: staticDiagram ? nil : { model.pluckBass($0) })
                .id("\(model.tuning.id)-\(model.chord.id)")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    /// 试听时给指法图的动画时钟；没在播放时为 nil（图不刷新）。
    private var pluckProvider: (() -> [Int: Double])? {
        guard model.isAnimating, !staticDiagram else { return nil }
        return { [model] in model.pluckAges() }
    }

    // MARK: 试听方式（扫弦 / 分解）

    @ViewBuilder private var playModeRow: some View {
        VStack(spacing: 8) {
            // 三种排法，取第一个放得下的：①一行（切换、列表按钮、指法 / 节奏型名、速度）；
            // ②名称挪到第二行；③iPhone SE 这样的窄屏：速度也挪到第二行，和名称同一行
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if model.supportsStrum { modeSwitch.fixedSize() }
                    pickerButton
                    patternCaption.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 4)
                    tempoChip.fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if model.supportsStrum { modeSwitch.fixedSize() }
                        pickerButton
                        Spacer(minLength: 4)
                        tempoChip.fixedSize()
                    }
                    patternCaption
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if model.supportsStrum { modeSwitch.fixedSize() }
                        pickerButton
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        patternCaption
                        Spacer(minLength: 4)
                        tempoChip.fixedSize()
                    }
                }
            }
            if model.supportsStrum && model.playMode == .strum {
                if staticDiagram {
                    StrumCellStrip(cells: model.strumRhythm.cells, cellsPerBeat: model.strumRhythm.cellsPerBeat,
                                   activeCell: staticActiveCell, palette: palette)
                } else {
                    LiveStrumCellStrip(model: model, rhythm: model.strumRhythm, palette: palette)
                }
            }
        }
        .sheet(item: $editor) { target in
            switch target {
            case .arpeggio(let item):
                CustomArpeggioEditor(model: model, editing: item, palette: palette, strings: strings) { editor = nil }
            case .rhythm(let item):
                CustomRhythmEditor(model: model, editing: item, palette: palette, strings: strings, onClose: { editor = nil })
            }
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(ChordLibraryModel.PlayMode.allCases, id: \.self) { mode in
                let on = mode == model.playMode
                Button { model.select(playMode: mode) } label: {
                    Text(mode == .strum ? strings.strumMode : strings.arpeggioMode)
                        .font(.system(size: 13, weight: on ? .bold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 52).frame(height: 28)
                        .foregroundStyle(on ? palette.onAccent : palette.sub)
                        .background(on ? palette.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(palette.card2, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.playModeLabel)
    }

    private func listButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "list.bullet")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(palette.text)
                .background(palette.card2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .foregroundStyle(palette.sub)
    }

    /// 当前方式的选择按钮：分解是指法列表，扫弦是节奏型列表；点开是弹窗。
    @ViewBuilder private var pickerButton: some View {
        if model.effectiveMode == .arpeggio { arpeggioButton } else { rhythmButton }
    }

    /// 当前指法的数字串 / 节奏型的名称。
    @ViewBuilder private var patternCaption: some View {
        if model.effectiveMode == .arpeggio {
            if let p = model.arpeggioPattern { caption(p.digits) }
        } else {
            Text(strings.title(model.strumRhythm))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(palette.sub)
        }
    }

    private var arpeggioButton: some View {
        listButton(strings.arpeggioTitle) { showsPatterns = true }
            .popover(isPresented: $showsPatterns, arrowEdge: .top) {
                ArpeggioPickerPanel(
                    patterns: model.arpeggioPatterns, selectedID: model.arpeggioPattern?.id,
                    rootString: model.rootStringNumber, palette: palette, strings: strings,
                    canAddCustom: model.canAddCustomArpeggio,
                    onNew: { showsPatterns = false; editor = .arpeggio(nil) },
                    onEdit: { p in
                        showsPatterns = false
                        let id = String(p.id.dropFirst(ArpeggioPattern.customPrefix.count))
                        editor = .arpeggio(model.customArpeggios[model.instrument.family.rawValue]?.first { $0.id == id })
                    },
                    onDelete: { p in model.deleteCustomArpeggio(id: String(p.id.dropFirst(ArpeggioPattern.customPrefix.count))) }
                ) {
                    model.select(arpeggio: $0)
                    showsPatterns = false
                }
                .presentationCompactAdaptation(.popover)
            }
    }

    private var rhythmButton: some View {
        listButton(strings.rhythmPickerTitle) { showsRhythms = true }
            .popover(isPresented: $showsRhythms, arrowEdge: .top) {
                RhythmPickerPanel(
                    rhythms: model.strumRhythms, selectedID: model.strumRhythm.id, palette: palette, strings: strings,
                    canAddCustom: model.canAddCustomRhythm,
                    onNew: { showsRhythms = false; editor = .rhythm(nil) },
                    onEdit: { r in
                        showsRhythms = false
                        let id = String(r.id.dropFirst(StrumRhythm.customPrefix.count))
                        editor = .rhythm(model.customRhythms[model.instrument.family.rawValue]?.first { $0.id == id })
                    },
                    onDelete: { r in model.deleteCustomRhythm(id: String(r.id.dropFirst(StrumRhythm.customPrefix.count))) }
                ) {
                    model.select(rhythm: $0)
                    showsRhythms = false
                }
                .presentationCompactAdaptation(.popover)
            }
    }

    /// 速度：节拍器图标 + 当前 BPM；点开弹出速度弹窗（−/+、滑块、跟随节拍器）。
    private var tempoChip: some View {
        Button { showsTempo = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "metronome").font(.system(size: 12, weight: .semibold))
                Text("\(Int(model.effectiveBPM.rounded()))")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                if model.followsMetronome {
                    Image(systemName: "link").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .foregroundStyle(palette.text)
            .background(palette.card2, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(strings.tempoLabel(Int(model.effectiveBPM.rounded())))
        .accessibilityHint(strings.tempoTitle)
        .popover(isPresented: $showsTempo, arrowEdge: .top) {
            TempoPanel(model: model, palette: palette, strings: strings)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var pager: some View {
        let count = model.voicingCount
        return HStack {
            Button { model.previousVoicing() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 32)
            }
            .accessibilityLabel(strings.previous)
            .disabled(model.targetVoicingIndex == 0)
            Spacer()
            HStack(spacing: 8) {
                if let v = model.voicings[safe: model.targetVoicingIndex] {
                    Text("\(strings.positionLabel(v)) · \(model.targetVoicingIndex + 1) / \(count)")
                        .font(.system(size: 13).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { i in dot(i) }
                }
            }
            .foregroundStyle(palette.sub)
            Spacer()
            Button { model.nextVoicing() } label: {
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .medium))
                    .frame(width: 36, height: 32)
            }
            .accessibilityLabel(strings.next)
            .disabled(model.targetVoicingIndex >= count - 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.sub)
        .padding(.top, 2)
    }

    /// 页码点。
    private func dot(_ i: Int) -> some View {
        Circle().fill(i == model.targetVoicingIndex ? palette.accent : palette.weak).frame(width: 6, height: 6)
    }

    private var bassLegend: some View {
        HStack(spacing: 14) {
            ForEach([BassPositions.Role.root, .third, .fifth, .octave], id: \.self) { role in
                HStack(spacing: 5) {
                    Circle().fill(legendColor(role)).frame(width: 10, height: 10)
                        .overlay { if role == .octave { Circle().stroke(palette.accent, lineWidth: 1.5) } }
                    Text(legendName(role)).font(.system(size: 12))
                }
            }
        }
        .foregroundStyle(palette.sub)
        .padding(.top, 6)
    }

    private func legendColor(_ role: BassPositions.Role) -> Color {
        switch role {
        case .root: return palette.accent
        case .third: return palette.text
        case .fifth: return palette.sub
        case .octave: return palette.card
        }
    }
    private func legendName(_ role: BassPositions.Role) -> String {
        switch role {
        case .root: return strings.bassRoot
        case .third: return strings.bassThird
        case .fifth: return strings.bassFifth
        case .octave: return strings.bassOctave
        }
    }

    // MARK: 根音与类型

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(palette.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private var rootGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 6), spacing: 7) {
            ForEach(ChordRoot.all, id: \.self) { r in
                let name = naming.rootName(pitchClass: r)
                pillShell(on: r == model.root, height: 36, pending: r == model.queuedRoot, label: name) {
                    model.select(root: r)
                } content: {
                    Text(name)
                        .font(.system(size: 15, weight: r == model.root ? .bold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var typeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
            ForEach(ChordLibrary.types) { t in
                let name = naming.chordName(pitchClass: model.root, type: t)
                pillShell(on: t.id == model.type.id, height: 34,
                          pending: t.id == model.queuedType?.id, label: strings.name(t), value: name) {
                    model.select(type: t)
                } content: {
                    Text(name).font(.system(size: 15, weight: t.id == model.type.id ? .bold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.55)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func pillShell<Content: View>(on: Bool, height: CGFloat, pending: Bool = false,
                                          label: String, value: String? = nil,
                                          action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .foregroundStyle(on ? palette.onAccent : palette.text)
                .background(on ? palette.accent : palette.card, in: Capsule())
                .overlay { if pending { PendingRing(color: palette.accent) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pending ? "\(label)\(strings.listSeparator)\(strings.nextBadge)" : label)
        .accessibilityValue(value ?? "")
    }
}

/// 把位卡片：横向分页的画廊。跟手拖动，松手吸附到整页；第一页和最后一页不循环。
/// 页码由外面的 `currentIndex` 驱动（箭头、圆点同步），点箭头时带滑动动画。
/// 滑到被锁住的把位时 `select` 返回 false，画廊弹回原来那一页。
struct VoicingGallery: View {
    let voicings: [ChordVoicing]
    let chord: Chord
    let palette: ChordPalette
    let leftHanded: Bool
    let strings: [InstrumentString]
    /// 卡片显示的页（用户滑到的，排队中的也算）。
    let currentIndex: Int
    /// 正在发声（有动画）的那一页。
    let audibleIndex: Int
    let text: ChordStrings
    let pluck: (() -> [Int: Double])?
    let select: (Int) -> Bool
    /// 点了某一页上的某根弦：(页, 弦序号)。
    let onPluck: (Int, Int) -> Void

    @State private var scrolled: Int?
    @Environment(\.noteNaming) private var naming

    init(voicings: [ChordVoicing], chord: Chord, palette: ChordPalette, leftHanded: Bool,
         strings: [InstrumentString], currentIndex: Int, audibleIndex: Int, text: ChordStrings,
         pluck: (() -> [Int: Double])?, select: @escaping (Int) -> Bool, onPluck: @escaping (Int, Int) -> Void) {
        self.voicings = voicings; self.chord = chord; self.palette = palette; self.leftHanded = leftHanded
        self.strings = strings; self.currentIndex = currentIndex; self.audibleIndex = audibleIndex
        self.text = text; self.pluck = pluck; self.select = select; self.onPluck = onPluck
        _scrolled = State(initialValue: currentIndex)
    }

    private var spokenValue: String {
        guard voicings.indices.contains(currentIndex) else { return "" }
        let page = text.pageLabel(currentIndex + 1, voicings.count)
        return page + text.listSeparator + text.spokenDescription(voicings[currentIndex], strings: strings)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(voicings.enumerated()), id: \.offset) { i, v in
                    ChordDiagramView(voicing: v, chord: chord, palette: palette, leftHanded: leftHanded, strings: strings,
                                     pluck: i == audibleIndex ? pluck : nil, onPluck: { onPluck(i, $0) })
                        .accessibilityHidden(i != currentIndex)
                        .frame(maxWidth: .infinity)
                        .containerRelativeFrame(.horizontal)
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolled)
        .scrollIndicators(.hidden)
        .onChange(of: scrolled) { _, new in
            guard let new, new != currentIndex else { return }
            if !select(new) { withAnimation(.smooth) { scrolled = currentIndex } }
        }
        .onChange(of: currentIndex) { _, new in
            if scrolled != new { withAnimation(.smooth) { scrolled = new } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.diagramLabel(naming.chordName(chord)))
        .accessibilityValue(spokenValue)
        .accessibilityAction(named: Text(text.next)) { _ = select(min(currentIndex + 1, voicings.count - 1)) }
        .accessibilityAction(named: Text(text.previous)) { _ = select(max(currentIndex - 1, 0)) }
    }
}

/// 排队中的按钮：描边轻轻闪动（开了“减少动态效果”时是静态描边）。
struct PendingRing: View {
    let color: Color
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .strokeBorder(color, lineWidth: 2)
            .opacity(dim && !reduceMotion ? 0.3 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { dim = true }
            }
            .allowsHitTesting(false)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - 预览

@MainActor
private func previewModel(instrument: String = "guitar", root: Int = 0, type: ChordType = .major7) -> ChordLibraryModel {
    ChordLibraryModel(current: ChordFavorite(instrumentID: instrument, tuningID: "", root: root, typeID: type.id, voicingIndex: 0))
}

struct ChordLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChordLibraryView(model: previewModel(), palette: .dark)
                .preferredColorScheme(.dark)
                .previewDisplayName("深色 · 吉他 Cmaj7（设计稿 05）")
            ChordLibraryView(model: previewModel(), palette: .light)
                .preferredColorScheme(.light)
                .previewDisplayName("浅色 · 吉他 Cmaj7（设计稿 light-05）")
            ChordLibraryView(model: previewModel(instrument: "bass", root: 9, type: .minor), palette: .dark)
                .preferredColorScheme(.dark)
                .previewDisplayName("深色 · 贝斯 Am")
        }
    }
}

struct ChordDiagramView_Previews: PreviewProvider {
    static var previews: some View {
        let chord = Chord("F", .major)!
        let v = ChordLibrary.voicings(for: chord, instrument: InstrumentLibrary.guitar)[0]
        HStack {
            ChordDiagramView(voicing: v, chord: chord, palette: .dark)
            ChordDiagramView(voicing: v, chord: chord, palette: .dark, leftHanded: true)
        }
        .padding()
        .background(ChordPalette.dark.background)
        .previewDisplayName("指法图 · 右手 / 左手")
    }
}
