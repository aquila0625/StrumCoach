import ChordKit
import MetronomeCore
import SwiftData
import SwiftUI
import TunerKit

/// 我的（设计稿 06）：本周练习、偏好设置和关于。原来的设置页并进了这里。
/// 统计全部用 PracticeKit 的 PracticeStatistics。
struct ProfileScreen: View {
    @Environment(\.theme) private var theme
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(MetronomeController.self) private var metronome
    @Environment(TunerModel.self) private var tuner
    @Environment(ChordLibraryModel.self) private var chords
    @Environment(\.noteNaming) private var naming
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var showLanguages = false

    /// 周一为一周第一天（柱状图从周一排到今天所在的周日）。
    static var calendar: Calendar {
        var c = Calendar.current
        c.locale = .appLanguage
        c.firstWeekday = 2
        return c
    }

    private var stats: PracticeStatistics { PracticeStatistics(calendar: Self.calendar) }

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            HStack {
                Text("我的").font(.system(size: 30, weight: .bold)).tracking(0.5).foregroundStyle(theme.text)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summaryCard
                    Text("偏好设置").font(.system(size: 13)).foregroundStyle(theme.sub)
                        .padding(.horizontal, 2).padding(.top, 2)
                    preferences
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(isPresented: $router.showHistory) {
            HistoryScreen(sessions: historySessions)
                .modifier(ThemeProvider())
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .sheet(isPresented: $showLanguages) {
            LanguagePicker()
                .modifier(ThemeProvider())
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    private var historySessions: [PracticeSession] {
        stats.recent(sessions, limit: .max)
    }

    // MARK: 本周 + 迷你柱状图

    private var summaryCard: some View {
        let now = Date()
        let weeklySeconds = stats.weeklyTotal(of: sessions, now: now)
        // 按分钟四舍五入；练过但不足 1 分钟时算 1 分钟，免得显示 0
        let weeklyMinutes = weeklySeconds > 0 ? max(1, Int((weeklySeconds / 60).rounded())) : 0
        let streak = stats.currentStreak(of: sessions, now: now)
        let days = stats.dailyDurations(of: sessions, now: now)
        let minutes = days.map { $0.duration > 0 ? max(1, Int(($0.duration / 60).rounded())) : 0 }
        let maxMinutes = max(50, minutes.max() ?? 0)
        let barArea: CGFloat = 52
        let latest = stats.recent(sessions, limit: 1).first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本周练习").font(.system(size: 12)).foregroundStyle(theme.sub)
                    Text(styled(.seconds(weeklyMinutes * 60), units: [.hours, .minutes], width: .abbreviated, number: theme.text))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("连续打卡").font(.system(size: 12)).foregroundStyle(theme.sub)
                    Text(styled(.seconds(streak * 86_400), units: [.days], width: .wide, number: theme.accent))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(minutes.enumerated()), id: \.offset) { i, m in
                        let isToday = i == minutes.count - 1
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isToday ? theme.accent : (m > 0 ? theme.accentSoft : theme.line))
                            .frame(height: max(CGFloat(m) / CGFloat(maxMinutes) * barArea, 3))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: barArea)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: zip(days, minutes).map { "\(Self.weekdayName($0.day)) \(Units.minutes($1))" }.joined(separator: ", ")))
            }
            Rectangle().fill(theme.line).frame(height: 1).padding(.top, 12)
            Button { router.showHistory = true } label: {
                HStack(spacing: 6) {
                    Text("练习记录").foregroundStyle(theme.text)
                    Spacer()
                    if let latest {
                        Text(verbatim: "\(SessionRow.dayText(latest.startedAt)) · \(Units.minutes(max(1, Int((latest.duration / 60).rounded()))))")
                            .foregroundStyle(theme.sub).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Icon(kind: .chevron, color: theme.dim).rotationEffect(.degrees(-90))
                }
                .font(.system(size: 14))
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, -4)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .card(radius: 20)
    }

    // MARK: 偏好设置

    private var preferences: some View {
        @Bindable var chords = chords
        @Bindable var metronome = metronome
        return VStack(spacing: 0) {
            row(title: "外观") {
                Segmented(options: AppearanceMode.allCases, selected: settings.appearance, title: \.shortTitle) {
                    settings.appearance = $0
                }
                .frame(maxWidth: 190)
            }
            divider
            Button { showLanguages = true } label: {
                row(title: "语言") {
                    Text(verbatim: "\(settings.language == nil ? "🌐" : AppLanguage.current.flag) \(AppLanguage.current.nativeName)")
                        .font(.system(size: 15)).foregroundStyle(theme.sub).lineLimit(1).minimumScaleFactor(0.8)
                    chevron
                }
            }
            .buttonStyle(.plain)
            divider
            row(title: "音名显示") {
                Segmented(options: NoteNaming.Style.allCases, selected: settings.noteStyle, title: noteStyleSample) {
                    settings.noteStyleOverride = $0
                }
                .frame(maxWidth: 190)
            }
            divider
            Button { router.sheet = .sound } label: {
                row(title: "节拍音色") {
                    Text(metronome.config.sound.title).font(.system(size: 15)).foregroundStyle(theme.sub).lineLimit(1)
                    chevron
                }
            }
            .buttonStyle(.plain)
            divider
            row(title: "标准音 \(naming.fullName(Pitch(midi: 69)))") {
                MiniStepper(value: Int(tuner.a4.rounded()), display: Units.hertz,
                            range: Int(TunerDefaults.a4Range.lowerBound)...Int(TunerDefaults.a4Range.upperBound)) {
                    tuner.setA4(Double($0))
                }
            }
            divider
            row(title: "跟拍震动") {
                Toggle("", isOn: $metronome.hapticsEnabled).labelsHidden().tint(theme.green)
            }
            divider
            row(title: "左手模式") {
                Toggle("", isOn: $chords.leftHanded).labelsHidden().tint(theme.green)
            }
        }
        .card(radius: 18)
    }

    private var aboutCard: some View {
        VStack(spacing: 0) {
            row(title: "版本") {
                Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.system(size: 15)).foregroundStyle(theme.sub)
            }
        }
        .card(radius: 18)
    }

    private var divider: some View {
        Rectangle().fill(theme.line).frame(height: 1).padding(.leading, 16)
    }

    private var chevron: some View {
        Icon(kind: .chevron, color: theme.dim).rotationEffect(.degrees(-90))
    }

    private func row<Trailing: View>(title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 16)).foregroundStyle(theme.text)
                .lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    /// 分段按钮上的示例：“C D E”“Do Re Mi”（按当前语言的写法）。
    private func noteStyleSample(_ style: NoteNaming.Style) -> String {
        let sample = NoteNaming(style: style, languageCode: settings.languageCode)
        return [0, 2, 4].map { sample.name(pitchClass: $0) }.joined(separator: " ")
    }

    static func weekdayName(_ date: Date) -> String {
        Self.calendar.standaloneWeekdaySymbols[Self.calendar.component(.weekday, from: date) - 1]
    }

    /// 时长：数字大、单位小（“3 小时 25 分”“3 hr, 25 min”），格式交给系统按语言处理。
    private func styled(_ duration: Duration, units: Set<Duration.UnitsFormatStyle.Unit>,
                        width: Duration.UnitsFormatStyle.UnitWidth, number: Color) -> AttributedString {
        // 为 0 时只显示最小的那个单位（“0 分钟”“0 天”），不显示“0 小时 0 分钟”
        let shown: Set<Duration.UnitsFormatStyle.Unit> = duration == .zero ? [units.contains(.minutes) ? .minutes : .days] : units
        var text = duration.formatted(.units(allowed: shown, width: width,
                                             zeroValueUnits: duration == .zero ? .show(length: 1) : .hide).locale(.appLanguage).attributed)
        for run in text.runs {
            if run.measurement == .value {
                text[run.range].font = .system(size: 26, weight: .light)
                text[run.range].foregroundColor = number
            } else {
                text[run.range].font = .system(size: 13)
                text[run.range].foregroundColor = theme.sub
            }
        }
        return text
    }
}

/// 行内的小步进器（标准音）：− 数值 +，可长按连续变化。
private struct MiniStepper: View {
    @Environment(\.theme) private var theme
    let value: Int
    let display: (Int) -> String
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            RepeatingButton(symbol: "−", enabled: value > range.lowerBound) { set(value - 1) }
            Text(display(value)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .foregroundStyle(theme.text).lineLimit(1).frame(minWidth: 58)
            RepeatingButton(symbol: "+", enabled: value < range.upperBound) { set(value + 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(display(value))
        .accessibilityAdjustableAction { set($0 == .increment ? value + 1 : value - 1) }
    }

    private func set(_ v: Int) { if range.contains(v) { onChange(v) } }
}

/// 最近练习列表（卡片里一行一条）。
struct RecentList: View {
    @Environment(\.theme) private var theme
    let sessions: [PracticeSession]

    var body: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                Text("还没有练习记录。播放 30 秒以上会自动记一次。")
                    .font(.system(size: 14)).foregroundStyle(theme.sub)
                    .frame(maxWidth: .infinity, minHeight: 62)
            }
            ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                if i > 0 { Rectangle().fill(theme.line).frame(height: 1) }
                SessionRow(session: s)
            }
        }
        .card(radius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SessionRow: View {
    @Environment(\.theme) private var theme
    let session: PracticeSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(Self.dayText(session.startedAt)) · \(session.mode.title)")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(theme.text)
                Text(bpmText).font(.system(size: 12)).monospacedDigit().foregroundStyle(theme.sub)
            }
            Spacer()
            Text(Units.minutes(max(1, Int((session.duration / 60).rounded()))))
                .font(.system(size: 15)).monospacedDigit().foregroundStyle(theme.text)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .accessibilityElement(children: .combine)
    }

    private var bpmText: String {
        let r = session.bpmRange
        if r.lowerBound == r.upperBound { return "\(r.lowerBound) BPM" }
        let arrow = session.mode == .ramp || session.mode == .rampAndMute ? "→" : "–"
        return "\(r.lowerBound) \(arrow) \(r.upperBound) BPM"
    }

    static func dayText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "今天", bundle: .appLanguage, locale: .appLanguage) }
        if cal.isDateInYesterday(date) { return String(localized: "昨天", bundle: .appLanguage, locale: .appLanguage) }
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let thisYear = cal.component(.year, from: Date()) == c.year
        return thisYear ? date.formatted(.dateTime.month().day().locale(.appLanguage))
                        : date.formatted(.dateTime.year().month().day().locale(.appLanguage))
    }
}

/// 全部练习历史。
private struct HistoryScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let sessions: [PracticeSession]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("练习历史").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.accent)
            }
            .padding(20)
            ScrollView {
                RecentList(sessions: sessions)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .background(ScreenBackground())
    }
}

/// App 图标（设计稿 parts5.js 的 logo）：橙色渐变圆角方块 + 三根高低不同的白条。
struct AppLogo: View {
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFF9A3D), Color(hex: 0xF0590A)], startPoint: .topLeading, endPoint: .bottomTrailing))
            bar(x: 0.20, y: 0.30, h: 0.50, opacity: 1)
            bar(x: 0.43, y: 0.48, h: 0.32, opacity: 0.75)
            bar(x: 0.66, y: 0.58, h: 0.22, opacity: 0.55)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func bar(x: CGFloat, y: CGFloat, h: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: size * 0.05)
            .fill(.white.opacity(opacity))
            .frame(width: size * 0.14, height: size * h)
            .offset(x: size * x, y: size * y)
    }
}
