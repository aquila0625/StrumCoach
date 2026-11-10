import ChordKit
import SwiftUI

/// 训练页顶部的主打卡片：扫弦节奏型。
///
/// 卡片里直接能横向滑动换节奏型（预设 + 自定义），格子循环走动预览；下面是当前和弦进行、上次 / 最高分，
/// “听一听”在卡片里扫一小节，“开始练习”打开扫弦页直接开始跟练。点和弦进行打开扫弦页去编辑。
struct StrumHeroCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.noteNaming) private var naming
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(MetronomeController.self) private var metronome
    @Environment(ChordLibraryModel.self) private var chords
    @Bindable var trainer: StrumTrainer
    /// 正在看的那一页（节奏型 id，最后一页是“自定义…”）
    @State private var page: String?
    @State private var showEditor = false

    private static let newPage = "custom-new"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            pager
            dots
            progressionRow
            HStack(spacing: 10) {
                stats
                Spacer(minLength: 0)
            }
            actions
        }
        .padding(18)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
        .onAppear {
            page = trainer.pattern.id
            let naming = naming
            trainer.chordName = { naming.chordName($0) }
        }
        .onChange(of: trainer.pattern.id) { _, id in if page != Self.newPage { page = id } }
        // 换了筛选或排序（收藏、已掌握）后回到选中的节奏型那一页
        .onChange(of: trainer.filter) { _, _ in page = trainer.pattern.id }
        .onChange(of: page) { _, id in
            // 滑到哪个就选哪个
            guard let id, let p = trainer.visiblePatterns.first(where: { $0.id == id }), p.id != trainer.pattern.id else { return }
            trainer.pattern = p
        }
        .sheet(isPresented: $showEditor) {
            CustomRhythmEditor(model: chords, family: trainer.instrument.family, palette: chordPalette, selectsOnSave: false,
                               onSave: { saved in
                                   if let r = saved.rhythm { trainer.pattern = r; page = r.id }
                               },
                               onClose: { showEditor = false })
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    // MARK: 标题

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "guitars.fill")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("扫弦节奏型").font(.system(size: 24, weight: .bold)).foregroundStyle(theme.text)
                Text("跟着节奏扫，麦克风帮你打分").font(.system(size: 13)).foregroundStyle(theme.sub)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            RhythmFilterMenu(trainer: trainer)
                .disabled(trainer.isBusy)
        }
    }

    // MARK: 节奏型（横向滑动）

    private var pageIDs: [String] { trainer.visiblePatterns.map(\.id) + [Self.newPage] }

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(trainer.visiblePatterns) { p in
                    rhythmPage(p).containerRelativeFrame(.horizontal).id(p.id)
                }
                if trainer.visiblePatterns.isEmpty {
                    emptyPage.containerRelativeFrame(.horizontal)
                }
                customPage.containerRelativeFrame(.horizontal).id(Self.newPage)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .frame(height: 128)
        .disabled(trainer.isBusy)
    }

    private func rhythmPage(_ p: StrumRhythm) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(verbatim: p.displayTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                if p.isCustom, p.displayTitle != customLabel {
                    Text(verbatim: customLabel).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.sub)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(theme.card2, in: Capsule())
                }
                Spacer(minLength: 0)
                Text("\(trainer.bpm) BPM").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(theme.sub)
                RhythmMarkButtons(trainer: trainer, rhythm: p).scaleEffect(0.85)
            }
            .frame(height: 30)
            looping(p)
        }
        .padding(.horizontal, 2)
    }

    /// 格子：听一听时跟着声音走；平时按当前速度循环走动（减少动态效果时不动）
    @ViewBuilder
    private func looping(_ p: StrumRhythm) -> some View {
        if trainer.phase == .preview, p.id == trainer.pattern.id {
            StrumGrid(pattern: p, highlight: trainer.position?.step, large: true)
        } else if reduceMotion || trainer.isBusy || page != p.id {
            StrumGrid(pattern: p, large: true)
        } else {
            let step = 60.0 / Double(trainer.bpm) / Double(p.cellsPerBeat)
            TimelineView(.periodic(from: .now, by: step)) { context in
                let i = Int(context.date.timeIntervalSinceReferenceDate / step) % p.cells.count
                StrumGrid(pattern: p, highlight: i, large: true)
            }
        }
    }

    /// 筛选后一个都没有（比如还没收藏）
    private var emptyPage: some View {
        VStack(spacing: 8) {
            Image(systemName: trainer.filter == .favorites ? "star" : "checkmark.seal")
                .font(.system(size: 22)).foregroundStyle(theme.accent)
            Text(trainer.filter == .favorites ? "还没有收藏的节奏型：点星标收藏。" : "这件乐器的节奏型都已掌握。")
                .font(.system(size: 13)).foregroundStyle(theme.sub).multilineTextAlignment(.center)
            Button { trainer.filter = .all } label: {
                Text("显示全部").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customPage: some View {
        Button {
            showEditor = true
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("自定义…")
                }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent)
                Text("用 D（下扫）U（上扫）X（闷音）·（空拍）写出自己的节奏型，和弦库里也能用")
                    .font(.system(size: 12)).foregroundStyle(theme.sub).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(pageIDs, id: \.self) { id in
                Group {
                    if id == Self.newPage {
                        Image(systemName: "plus").font(.system(size: 7, weight: .bold))
                            .foregroundStyle(page == id ? theme.accent : theme.dim)
                    } else {
                        Capsule().fill(page == id ? theme.accent : theme.dim.opacity(0.5))
                            .frame(width: page == id ? 16 : 6, height: 6)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: page)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: 和弦进行

    private var progressionRow: some View {
        Button { router.showStrum = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("和弦进行").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.sub).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.accent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(trainer.progression.chords) { c in
                            HStack(spacing: 2) {
                                Text(verbatim: naming.chordName(c.chord)).font(.system(size: 14, weight: .semibold))
                                if c.bars > 1 {
                                    Text(verbatim: "×\(c.bars)").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.sub)
                                }
                            }
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(theme.card2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(trainer.isBusy)
        .accessibilityLabel(Text("和弦进行"))
        .accessibilityValue(Text(verbatim: trainer.progression.label(naming.chordName)))
        .accessibilityHint(Text("编辑和弦进行"))
    }

    // MARK: 成绩

    private var stats: some View {
        let last = trainer.history.last
        let best = trainer.history.best(for: trainer.pattern.id)
        return HStack(spacing: 8) {
            if last == nil && best == nil {
                Text("还没练过，先听一听再开始").font(.system(size: 13)).foregroundStyle(theme.sub)
            }
            if let last { scorePill(Text("上次"), last.score) }
            if let best { scorePill(Text("最高"), best) }
        }
    }

    private func scorePill(_ label: Text, _ score: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            label.font(.system(size: 12)).foregroundStyle(theme.sub)
            Text("\(score) 分").font(.system(size: 16, weight: .semibold)).monospacedDigit().foregroundStyle(theme.text)
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(theme.card.opacity(0.7), in: Capsule())
    }

    // MARK: 按钮

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                if trainer.phase == .preview {
                    trainer.stop()
                } else {
                    if metronome.isPlaying { metronome.stop() }
                    trainer.playPreview()
                }
            } label: {
                Label(trainer.phase == .preview ? "停止" : "听一听",
                      systemImage: trainer.phase == .preview ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(theme.accentTint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .frame(width: 128)
            .disabled(trainer.isBusy && trainer.phase != .preview)
            Button {
                trainer.stop()
                router.strumAutoStart = true
                router.showStrum = true
            } label: {
                Label("开始练习", systemImage: "mic.fill")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: theme.accent.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(PressableStyle())
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
        }
    }

    // MARK: 背景

    private var background: some View {
        ZStack(alignment: .topTrailing) {
            theme.card
            LinearGradient(colors: [theme.accent.opacity(theme.isLight ? 0.20 : 0.30), theme.accent.opacity(0.02)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // 插画式的大箭头：一下一上
            HStack(spacing: -14) {
                Image(systemName: "arrow.down").font(.system(size: 120, weight: .heavy))
                Image(systemName: "arrow.up").font(.system(size: 120, weight: .heavy)).offset(y: 26)
            }
            .foregroundStyle(theme.accent.opacity(theme.isLight ? 0.09 : 0.12))
            .rotationEffect(.degrees(-12))
            .offset(x: 30, y: -34)
            .accessibilityHidden(true)
        }
    }

    // MARK: 工具

    private var customLabel: String { String(localized: "自定义", bundle: .appLanguage, locale: .appLanguage) }

    private var chordPalette: ChordPalette {
        let p = theme.tunerPalette
        return ChordPalette(background: theme.bg, card: p.card, card2: p.card2, line: p.line, text: p.text, sub: p.sub, dim: p.dim,
                            accent: p.accent, weak: p.weak, onText: theme.bg)
    }
}
