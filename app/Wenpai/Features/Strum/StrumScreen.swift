import ChordKit
import SwiftData
import SwiftUI

/// 训练页 → 扫弦节奏型：选和弦、选节奏型、听示范、跟我练、看评分。
struct StrumScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.noteNaming) private var naming
    @Environment(AppSettings.self) private var settings
    @Environment(MetronomeController.self) private var metronome
    @Environment(Router.self) private var router
    @State private var trainer: StrumTrainer
    @State private var showCalibration = false
    /// 自定义节奏型编辑页：新建或修改哪一个
    @State private var rhythmEditor: RhythmEditorTarget?
    private let chords: ChordLibraryModel

    /// 编辑页的对象：新建（nil）或修改已保存的
    private struct RhythmEditorTarget: Identifiable {
        var editing: CustomStrumRhythm?
        var id: String { editing?.id ?? "new" }
    }

    init(trainer: StrumTrainer, chords: ChordLibraryModel) {
        self.chords = chords
        _trainer = State(initialValue: trainer)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if trainer.phase == .demo || trainer.phase == .practice {
                        ProgressionNowView(trainer: trainer)
                    } else {
                        ProgressionCard(trainer: trainer)
                    }
                    patternPicker
                    gridCard
                    if let score = trainer.score, let tl = trainer.scoredTimeline {
                        StrumResultCard(score: score, timeline: tl, gridScore: trainer.gridScore, run: trainer.run,
                                        best: trainer.history.best(for: tl.pattern.id), report: trainer.report,
                                        barLabels: barLabels(tl))
                            .id("result")
                    }
                    Text("第一版只看扫弦的时间准不准，不判断你实际是上扫还是下扫；箭头是节奏型里该用的扫法。")
                        .font(.system(size: 12)).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            // 出了成绩就滚到结果
            .onChange(of: trainer.score) { _, new in
                if new != nil { withAnimation { proxy.scrollTo("result", anchor: .top) } }
            }
            .onAppear {
                if trainer.score != nil { DispatchQueue.main.async { proxy.scrollTo("result", anchor: .top) } }
            }
            }
            actions
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
        .background(ScreenBackground())
        .onAppear {
            trainer.modelContext = modelContext
            let naming = naming
            trainer.chordName = { naming.chordName($0) }
            // 节拍器在响就先停：收音时不能有节拍声从扬声器出来
            if metronome.isPlaying { metronome.stop(forRecording: true) }
            // 从训练页卡片的“开始练习”进来：直接开始跟练（先倒数一小节）
            if router.strumAutoStart {
                router.strumAutoStart = false
                trainer.stop()
                Task { await trainer.startPractice() }
            }
        }
        .onDisappear { trainer.teardown() }
        .sheet(isPresented: $showCalibration) {
            StrumCalibrationSheet(trainer: trainer)
                .modifier(ThemeProvider())
                .preferredColorScheme(settings.appearance.colorScheme)
                .presentationDetents([.medium])
        }
        // 连续 3 次 ≥ 90 分：建议标记为已掌握（用户确认才标）
        .alert("标记为已掌握？", isPresented: Binding(get: { trainer.masterySuggestion != nil },
                                                  set: { if !$0, trainer.masterySuggestion != nil { trainer.answerMastery(false) } })) {
            Button("标记") { trainer.answerMastery(true) }
            Button("暂不", role: .cancel) { trainer.answerMastery(false) }
        } message: {
            Text("“\(trainer.masterySuggestion?.displayTitle ?? "")”最近 3 次都在 90 分以上。")
        }
        .sheet(item: $rhythmEditor) { target in
            // 和和弦库共用同一份自定义节奏型；存进训练页当前乐器的列表，保存后在这里选中
            CustomRhythmEditor(model: chords, family: trainer.instrument.family, editing: target.editing,
                               palette: chordPalette, selectsOnSave: false,
                               onSave: { saved in if let r = saved.rhythm { trainer.pattern = r } },
                               onClose: { rhythmEditor = nil })
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    private var chordPalette: ChordPalette {
        let p = theme.tunerPalette
        return ChordPalette(background: theme.bg, card: p.card, card2: p.card2, line: p.line, text: p.text, sub: p.sub, dim: p.dim,
                            accent: p.accent, weak: p.weak, onText: theme.bg)
    }

    /// 结果每一行（小节）前面写这一小节的和弦
    private func barLabels(_ tl: StrumTimeline) -> [String]? {
        guard let plan = trainer.plan, plan.bars == tl.bars else { return nil }
        let chords = trainer.progression.chords
        return (0..<tl.bars).map { bar in
            let i = plan.chordIndex(atBar: bar)
            return chords.indices.contains(i) ? naming.chordName(chords[i].chord) : "\(bar + 1)"
        }
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            Button { trainer.stop(); dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                    .frame(width: 40, height: 40).card(radius: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
            Text("扫弦节奏型").font(.system(size: 22, weight: .bold)).foregroundStyle(theme.text)
            Spacer()
            Button { showCalibration = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dial.low")
                    Text("延迟校准")
                }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.sub)
                .padding(.horizontal, 10).frame(height: 32).card(radius: 16)
            }
            .buttonStyle(.plain)
            .disabled(trainer.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: 节奏型

    private var patternPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("节奏型").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.sub)
                Spacer()
                RhythmFilterMenu(trainer: trainer)
            }
            .padding(.horizontal, 4)
            if trainer.visiblePatterns.isEmpty {
                Text(trainer.filter == .favorites ? "还没有收藏的节奏型：长按节奏型或点格子上方的星标收藏。" : "这件乐器的节奏型都已掌握。")
                    .font(.system(size: 13)).foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            patternChips
        }
    }

    private var patternChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(trainer.visiblePatterns) { p in
                    let selected = p.id == trainer.pattern.id
                    Button {
                        trainer.pattern = p
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(verbatim: p.displayTitle).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(selected ? theme.accent : theme.text).lineLimit(1)
                                if p.isCustom, p.displayTitle != customLabel {
                                    Text(verbatim: customLabel).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.sub)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(theme.card2, in: Capsule())
                                }
                                RhythmMarkIcons(favorite: trainer.isFavorite(p), mastered: trainer.isMastered(p))
                            }
                            Text(verbatim: p.arrows).font(.system(size: 13, weight: .medium)).monospaced()
                                .foregroundStyle(theme.sub).lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .card(radius: 14, fill: selected ? theme.accentTint : nil)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? theme.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(trainer.isBusy)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .contextMenu {
                        RhythmMarkMenuItems(trainer: trainer, rhythm: p)
                        if p.isCustom, let saved = savedCustom(p) {
                            Button { rhythmEditor = RhythmEditorTarget(editing: saved) } label: { Label("编辑…", systemImage: "pencil") }
                            Button(role: .destructive) {
                                chords.deleteCustomRhythm(id: saved.id, family: trainer.instrument.family)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
                // 自定义：和弦库里也能编辑，两边共用
                Button {
                    rhythmEditor = RhythmEditorTarget()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自定义…").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent).lineLimit(1)
                        Text(verbatim: "D U X ·").font(.system(size: 13, weight: .medium)).monospaced()
                            .foregroundStyle(theme.sub).lineLimit(1)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .disabled(trainer.isBusy)
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var customLabel: String { String(localized: "自定义", bundle: .appLanguage, locale: .appLanguage) }

    /// 节奏型对应的已保存自定义项（当前乐器）
    private func savedCustom(_ r: StrumRhythm) -> CustomStrumRhythm? {
        chords.customRhythms(for: trainer.instrument.family).first { StrumRhythm.customPrefix + $0.id == r.id }
    }

    // MARK: 格子 + 速度

    private var gridCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(verbatim: trainer.pattern.displayTitle).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                Spacer(minLength: 0)
                RhythmMarkButtons(trainer: trainer, rhythm: trainer.pattern)
            }
            .disabled(trainer.isBusy)
            ZStack {
                StrumGrid(pattern: trainer.pattern, highlight: trainer.position?.step)
                    .opacity(trainer.countIn == nil ? 1 : 0.35)
                if let n = trainer.countIn {
                    Text("\(n)").font(.system(size: 64, weight: .bold)).monospacedDigit().foregroundStyle(theme.accent)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel(Text("倒数 \(n)"))
                }
            }
            .animation(.easeOut(duration: 0.12), value: trainer.countIn)
            .frame(minHeight: 96)
            status
            HStack(spacing: 16) {
                stepButton("minus", -5)
                VStack(spacing: 0) {
                    Text("\(trainer.bpm)").font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(theme.text)
                    Text("BPM").font(.system(size: 11, weight: .medium)).tracking(1).foregroundStyle(theme.sub)
                }
                .frame(minWidth: 70)
                stepButton("plus", 5)
                Spacer()
                Button { trainer.setBPM(metronome.bpm) } label: {
                    Text("跟随节拍器").font(.system(size: 13)).foregroundStyle(trainer.bpm == metronome.bpm ? theme.dim : theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(trainer.bpm == metronome.bpm)
            }
            .disabled(trainer.isBusy)
        }
        .padding(16)
        .card(radius: 20)
    }

    private func stepButton(_ icon: String, _ delta: Int) -> some View {
        Button { trainer.setBPM(trainer.bpm + delta) } label: {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.text)
                .frame(width: 40, height: 40).background(theme.card2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? Text("加快") : Text("放慢"))
    }

    private var status: some View {
        Group {
            switch trainer.phase {
            case .demo, .preview:
                Text("示范中：一直循环，点“停止”结束")
            case .practice:
                VStack(spacing: 3) {
                    if let bar = trainer.position?.bar {
                        if let target = trainer.run?.target {
                            Text("收音中 · 第 \(trainer.pass) / \(target) 遍 · 第 \(bar + 1) / \(trainer.plan?.bars ?? 0) 小节")
                        } else {
                            Text("收音中 · 第 \(trainer.pass) 遍 · 第 \(bar + 1) / \(trainer.plan?.bars ?? 0) 小节")
                        }
                    } else if trainer.pass == 1 {
                        trainer.headphones ? Text("准备，跟着耳机里的节拍") : Text("准备，跟着倒数和高亮（外放时不放节拍声）")
                    }
                    // 刚练完的那一遍：小字，不打断
                    if let last = trainer.lastPass {
                        Text("第 \(last.pass) 遍：\(last.score) 分").font(.system(size: 12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(theme.accent)
                    }
                }
            case .calibrating: Text("每一拍扫一下")
            case .analyzing: Text("正在评分…")
            case .idle:
                if let message = trainer.message { Text(verbatim: message) } else { Text("先听示范，再跟着练；戴耳机可以听着节拍练。") }
            }
        }
        .font(.system(size: 13)).foregroundStyle(trainer.message != nil && trainer.phase == .idle ? theme.accent : theme.sub)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    // MARK: 按钮

    private var actions: some View {
        HStack(spacing: 12) {
            if trainer.isBusy {
                Button { if trainer.phase == .practice { trainer.endPractice() } else { trainer.stop() } } label: {
                    (trainer.phase == .practice ? Text("结束") : Text("停止"))
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(trainer.phase == .analyzing)
            } else {
                Button { trainer.playDemo() } label: {
                    Label("听示范", systemImage: "speaker.wave.2.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(theme.accentTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                Button { Task { await trainer.startPractice() } } label: {
                    Label("跟我练", systemImage: "mic.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

// MARK: - 格子

/// 一小节的格子：箭头 + 读法（1 & 2 &），每拍之间留空；当前格高亮；结果页按准 / 偏 / 漏上色。
struct StrumGrid: View {
    @Environment(\.theme) private var theme
    let pattern: StrumRhythm
    var highlight: Int?
    /// 结果页：每格的评价（空格没有）
    var grades: [Int: StrumScore.Grade] = [:]
    var compact = false
    /// 训练页大卡片：格子更高、箭头更大
    var large = false

    var body: some View {
        let n = pattern.cells.count
        let cellSpacing: CGFloat = n > 8 ? 2 : 4
        HStack(spacing: compact ? 6 : 10) {
            ForEach(0..<pattern.beatsPerBar, id: \.self) { beat in
                HStack(spacing: cellSpacing) {
                    ForEach(0..<pattern.cellsPerBeat, id: \.self) { sub in
                        cell(beat * pattern.cellsPerBeat + sub)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: pattern.arrows))
    }

    private func cell(_ i: Int) -> some View {
        let stroke = pattern.cells[i]
        let on = highlight == i
        let color = gradeColor(grades[i])
        let small = pattern.cells.count > 8 || compact
        // 和和弦库同一套符号：D 长箭头，d / U 短箭头，B 带 R 的圆点，X ✕，空拍是虚线空格子
        let glyphSize: CGFloat = compact ? 0.9 : (small ? (large ? 1.45 : 1.15) : (large ? 2.1 : 1.7))
        let ink = on ? Color.white : (color ?? theme.text)
        let radius: CGFloat = compact ? 6 : 10
        return VStack(spacing: compact ? 2 : 6) {
            ZStack {
                if stroke.isStroke {
                    // 高亮格子里箭头用白色，根音圆点自动反色（白底、R 用强调色）；结果页按准 / 偏 / 漏的颜色画圆点
                    StrumGlyph(cell: stroke, color: ink, accent: color ?? theme.accent, onAccent: on ? .white : theme.bg, size: glyphSize)
                } else {
                    RoundedRectangle(cornerRadius: radius - 2, style: .continuous)
                        .strokeBorder((on ? Color.white : theme.dim).opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .padding(compact ? 3 : 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 24 : (small ? (large ? 54 : 40) : (large ? 68 : 52)))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(on ? theme.accent : (color.map { $0.opacity(0.16) } ?? (stroke.isStroke ? theme.card2 : .clear)))
            }
            if !compact {
                Text(verbatim: pattern.countLabel(i))
                    .font(.system(size: small ? 10 : 12, weight: i % pattern.cellsPerBeat == 0 ? .semibold : .regular))
                    .foregroundStyle(on ? theme.accent : theme.sub)
            }
        }
    }

    private func gradeColor(_ g: StrumScore.Grade?) -> Color? {
        switch g {
        case .good?: return theme.green
        case .off?: return Color(red: 0.95, green: 0.68, blue: 0.1)
        case .missed?: return Color(red: 0.92, green: 0.26, blue: 0.24)
        case nil: return nil
        }
    }
}

// MARK: - 结果

struct StrumResultCard: View {
    @Environment(\.theme) private var theme
    /// 所有遍加起来的成绩（准 / 偏 / 漏、偏差、建议）
    let score: StrumScore
    /// 格子显示的那一遍（最后一遍）的时间线
    let timeline: StrumTimeline
    /// 格子显示的那一遍的成绩；nil 就用 `score`
    var gridScore: StrumScore? = nil
    /// 这次跟练的逐遍成绩
    var run: PracticeRun? = nil
    var best: Int?
    var report: ProgressionReport?
    /// 每一行前面的标签（和弦名）；没有就写小节号
    var barLabels: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if multiPass { Text("平均").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.sub) }
                Text("\(mainScore)").font(.system(size: 54, weight: .bold)).monospacedDigit().foregroundStyle(theme.accent)
                Text("分").font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.text)
                Spacer()
                if let best { Text("这个节奏型最好 \(best) 分").font(.system(size: 12)).foregroundStyle(theme.sub) }
            }
            if multiPass, let run { PassChart(run: run) }
            HStack(spacing: 8) {
                tally(Text("准"), score.good, theme.green)
                tally(Text("偏"), score.off, Color(red: 0.95, green: 0.68, blue: 0.1))
                tally(Text("漏"), score.missed, Color(red: 0.92, green: 0.26, blue: 0.24))
                tally(Text("多扫"), score.extras.count, theme.sub)
            }
            if multiPass {
                Text("最后一遍").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.sub)
            }
            VStack(spacing: 6) {
                ForEach(0..<timeline.bars, id: \.self) { bar in
                    HStack(spacing: 8) {
                        Text(verbatim: barLabels?[bar] ?? "\(bar + 1)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(theme.sub).lineLimit(1).minimumScaleFactor(0.6).frame(width: barLabels == nil ? 12 : 30, alignment: .leading)
                        StrumGrid(pattern: timeline.pattern, grades: grades(bar), compact: true)
                    }
                }
            }
            HStack(spacing: 16) {
                stat(Text("平均"), offsetText)
                stat(Text("稳定度"), score.spreadMs.map { Text("±\(Int($0.rounded())) 毫秒") } ?? Text(verbatim: "—"))
            }
            Text(verbatim: score.advice)
                .font(.system(size: 14)).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let report, report.segments.count > 1 {
                ProgressionResultSection(report: report)
            }
            Text("±60 毫秒内算准，±120 毫秒内算偏，再远算漏；多出来的一下扣半格。")
                .font(.system(size: 11)).foregroundStyle(theme.dim)
        }
        .padding(16)
        .card(radius: 20)
    }

    private var multiPass: Bool { (run?.passes.count ?? 0) > 1 }
    private var mainScore: Int { multiPass ? (run?.averageScore ?? score.score) : score.score }

    private var offsetText: Text {
        guard let ms = score.meanOffsetMs else { return Text(verbatim: "—") }
        let v = Int(abs(ms).rounded())
        if v < 5 { return Text("刚好") }
        return ms > 0 ? Text("偏慢 \(v) 毫秒") : Text("偏快 \(v) 毫秒")
    }

    private func grades(_ bar: Int) -> [Int: StrumScore.Grade] {
        Dictionary(uniqueKeysWithValues: (gridScore ?? score).hits.filter { $0.bar == bar }.map { ($0.step, $0.grade) })
    }

    private func tally(_ label: Text, _ n: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(color)
            label.font(.system(size: 12)).foregroundStyle(theme.sub)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(theme.card2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stat(_ label: Text, _ value: Text) -> some View {
        HStack(spacing: 6) {
            label.font(.system(size: 13)).foregroundStyle(theme.sub)
            value.font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text)
        }
    }
}

// MARK: - 延迟校准

struct StrumCalibrationSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var trainer: StrumTrainer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("延迟校准").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                Button("完成") { trainer.stop(); dismiss() }.font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent)
            }
            Text("麦克风收到声音会晚一点。倒数之后，跟着屏幕上的节拍（戴耳机时听节拍声）每一拍扫一下或拍一下琴身，一共 8 拍。")
                .font(.system(size: 14)).foregroundStyle(theme.sub).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { beat in
                    let on = trainer.phase == .calibrating && trainer.position.map { $0.step == beat } == true
                    Circle().fill(on ? theme.accent : theme.card2).frame(width: 34, height: 34)
                        .overlay(Text("\(beat + 1)").font(.system(size: 14, weight: .semibold)).foregroundStyle(on ? .white : theme.sub))
                }
                Spacer()
                if let n = trainer.countIn {
                    Text("\(n)").font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(theme.accent)
                }
            }
            if let message = trainer.message, trainer.phase == .idle {
                Text(verbatim: message).font(.system(size: 13)).foregroundStyle(theme.accent).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("当前补偿：\(Int((trainer.latencyOffset * 1000).rounded())) 毫秒").font(.system(size: 13)).foregroundStyle(theme.sub)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("恢复默认") { trainer.resetCalibration() }
                    .font(.system(size: 15)).foregroundStyle(theme.sub)
                    .disabled(trainer.isBusy)
                Spacer()
                Button {
                    if trainer.isBusy { trainer.stop() } else { Task { await trainer.calibrate() } }
                } label: {
                    (trainer.isBusy ? Text("停止") : Text("开始校准"))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 24).frame(height: 46)
                        .background(theme.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(trainer.phase == .analyzing)
            }
        }
        .padding(20)
        .background(ScreenBackground())
    }
}

// MARK: - 逐遍分数

/// 一直练 / 练了好几遍时：每遍的分数柱状图，最好的一遍高亮
struct PassChart: View {
    @Environment(\.theme) private var theme
    let run: PracticeRun

    var body: some View {
        let scores = run.passScores
        let best = run.best
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: scores.count > 20 ? 2 : 4) {
                ForEach(Array(scores.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(i + 1 == best?.pass ? theme.accent : theme.accent.opacity(0.35))
                        .frame(height: max(4, 46 * CGFloat(v) / 100))
                        .frame(maxWidth: 22)
                }
            }
            .frame(height: 46, alignment: .bottom)
            .accessibilityHidden(true)
            HStack(spacing: 12) {
                Text("共 \(scores.count) 遍")
                if let best { Text("最好一遍：第 \(best.pass) 遍 \(best.score) 分") }
            }
            .font(.system(size: 12)).foregroundStyle(theme.sub)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 收藏、已掌握

/// 节奏型名字旁边的小标记：星标（收藏）、勾（已掌握）
struct RhythmMarkIcons: View {
    @Environment(\.theme) private var theme
    let favorite: Bool
    let mastered: Bool

    var body: some View {
        HStack(spacing: 3) {
            if favorite { Image(systemName: "star.fill").foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.1)) }
            if mastered { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.green) }
        }
        .font(.system(size: 11, weight: .semibold))
    }
}

/// 两个开关按钮：收藏、已掌握
struct RhythmMarkButtons: View {
    @Environment(\.theme) private var theme
    let trainer: StrumTrainer
    let rhythm: StrumRhythm

    var body: some View {
        let favorite = trainer.isFavorite(rhythm)
        let mastered = trainer.isMastered(rhythm)
        HStack(spacing: 6) {
            Button { trainer.setFavorite(!favorite, rhythm) } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? Color(red: 0.98, green: 0.72, blue: 0.1) : theme.sub)
                    .frame(width: 34, height: 34).background(theme.card2, in: Circle())
            }
            .accessibilityLabel(favorite ? Text("取消收藏") : Text("收藏"))
            Button { trainer.setMastered(!mastered, rhythm) } label: {
                Image(systemName: mastered ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(mastered ? theme.green : theme.sub)
                    .frame(width: 34, height: 34).background(theme.card2, in: Circle())
            }
            .accessibilityLabel(mastered ? Text("取消已掌握") : Text("标记为已掌握"))
        }
        .font(.system(size: 15, weight: .semibold))
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: favorite)
        .sensoryFeedback(.success, trigger: mastered)
    }
}

/// 长按菜单里的收藏、已掌握
struct RhythmMarkMenuItems: View {
    let trainer: StrumTrainer
    let rhythm: StrumRhythm

    var body: some View {
        let favorite = trainer.isFavorite(rhythm)
        let mastered = trainer.isMastered(rhythm)
        Button { trainer.setFavorite(!favorite, rhythm) } label: {
            favorite ? Label("取消收藏", systemImage: "star.slash") : Label("收藏", systemImage: "star")
        }
        Button { trainer.setMastered(!mastered, rhythm) } label: {
            mastered ? Label("取消已掌握", systemImage: "xmark.circle") : Label("标记为已掌握", systemImage: "checkmark.circle")
        }
    }
}

/// 筛选：全部 / 收藏 / 未掌握
struct RhythmFilterMenu: View {
    @Environment(\.theme) private var theme
    @Bindable var trainer: StrumTrainer

    var body: some View {
        Menu {
            Picker(selection: $trainer.filter) {
                ForEach(RhythmMarks.Filter.allCases) { f in Text(verbatim: f.title).tag(f) }
            } label: { Text("筛选") }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(verbatim: trainer.filter.title)
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(trainer.filter == .all ? theme.sub : theme.accent)
            .padding(.horizontal, 9).frame(height: 26)
            .background(theme.card2.opacity(0.8), in: Capsule())
        }
        .accessibilityLabel(Text("筛选"))
        .accessibilityValue(Text(verbatim: trainer.filter.title))
    }
}
