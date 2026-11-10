import Foundation
import TunerKit

/// 界面文字。`.current` 跟随 App 语言（String Catalog），`.zhHans`、`.en` 是固定的两份（测试、预览用）。
public struct ChordStrings: Sendable {
    public var title = "和弦库"
    public var rootHeader = "根音"
    public var typeHeader = "类型"
    public var tones = "组成音"
    public var play = "试听"
    public var stop = "停止"
    public var previous = "上一个把位"
    public var next = "下一个把位"
    public var favorite = "收藏当前按法"
    public var unfavorite = "取消收藏"
    public var favoritesHeader = "已收藏"
    public var noFavorites = "还没有收藏"
    public var leftHanded = "左手模式"
    public var openPosition = "开放把位"
    public var bassHint = "一个把位里的和弦音"
    public var bassRoot = "根音"
    public var bassThird = "三度"
    public var bassFifth = "五度"
    public var bassOctave = "八度"
    /// 试听方式：扫弦 / 分解和弦
    public var strumMode = "扫弦"
    public var arpeggioMode = "分解"
    public var playModeLabel = "弹奏方式"
    public var arpeggioTitle = "分解指法"
    /// 演奏中排队的下一个和弦：“下一个：Dm”
    public var queuedNext: @Sendable (String) -> String = { "下一个：\($0)" }
    /// 排队中的按钮在读屏里的后缀
    public var nextBadge = "下一个"
    /// 读屏：每根弦，“第 3 弦，G”
    public var stringNote: @Sendable (Int, String) -> String = { "第 \($0) 弦，\($1)" }
    public var pluckHint = "双击发声"
    /// 速度控制
    public var tempoTitle = "速度"
    public var followMetronome = "跟随节拍器"
    public var followingNote: @Sendable (Int) -> String = { "用节拍器的速度（\($0) BPM）" }
    public var slower = "减慢"
    public var faster = "加快"
    public var tempoLabel: @Sendable (Int) -> String = { "速度 \($0) BPM" }
    /// 自定义分解指法 / 扫弦节奏型
    public var customRow = "自定义…"
    public var arpeggioEditorTitle = "自定义指法"
    public var rhythmEditorTitle = "自定义节奏型"
    public var rhythmPickerTitle = "扫弦节奏型"
    public var arpeggioHelp: @Sendable (Int) -> String = { "输入弦号，1 弦最细（最多 \($0) 弦）。- 或 0 是空拍（不弹，占一个音的时值）；可以用空格或逗号分隔，也可以连着写；R 代表当前和弦的根音弦。" }
    public var rhythmHelp = "每个字符一格：B 根音、D 全扫、d 半扫、U 上扫、X 闷音、- 或 . 空拍（D 和 d 分大小写）。空格只用来分组。"
    public var nameLabel = "名称"
    public var invalidArpeggio: @Sendable (Int) -> String = { "只能输入 1–\($0) 的弦号、0 或 -（空拍）和字母 R" }
    public var invalidRhythm = "只能输入 B、D、d、U、X、- 和 ."
    public var tooManyNotes: @Sendable (Int) -> String = { "最多 \($0) 个音" }
    public var tooManyBeats: @Sendable (Int) -> String = { "最多 \($0) 拍" }
    public var notWholeBeats: @Sendable (Int) -> String = { "格数要是 \($0) 的整数倍" }
    public var limitReached: @Sendable (Int) -> String = { "每种乐器最多保存 \($0) 个" }
    public var save = "保存"
    public var cancel = "取消"
    public var delete = "删除"
    public var edit = "编辑"
    public var cellFull = "全扫"
    public var cellHalf = "半扫"
    public var cellUp = "上扫"
    public var cellMute = "闷音"
    public var rhythmLegend = "B 只拨根音弦；D 从根音弦扫到 1 弦；d 和 U 只扫高音的 3–4 根弦。"
    public var restKey = "空拍"
    public var backspaceKey = "退格"
    public var unitLabel = "格子单位"
    public var eighthUnit = "八分"
    public var sixteenthUnit = "十六分"
    /// 面板底部的说明：吉他的 5 换成当前和弦的根音弦
    public var rootStringNote: @Sendable (Int) -> String = { "数字是弦号，5 代表根音弦（当前和弦是 \($0) 弦）" }
    /// “横按 · 3 品”
    public var barrePosition: @Sendable (Int) -> String = { "横按 · \($0) 品" }
    /// “3 品把位”
    public var fretPosition: @Sendable (Int) -> String = { "\($0) 品把位" }
    /// 读屏：“Cmaj7 指法”“Am 贝斯和弦音位置”
    public var diagramLabel: @Sendable (String) -> String = { "\($0) 指法" }
    public var bassDiagramLabel: @Sendable (String) -> String = { "\($0) 贝斯和弦音位置" }
    /// 读屏：每根弦怎么按
    public var stringMuted: @Sendable (Int) -> String = { "\($0) 弦不弹" }
    public var stringOpen: @Sendable (Int) -> String = { "\($0) 弦空弦" }
    public var stringFretted: @Sendable (Int, Int) -> String = { "\($0) 弦 \($1) 品" }
    /// 读屏：“第 2 个把位，共 8 个”
    public var pageLabel: @Sendable (Int, Int) -> String = { "第 \($0) 个把位，共 \($1) 个" }
    public var listSeparator = "，"
    public var useEnglishNames = false
    /// 和弦类型名按 String Catalog 翻译（`.current` 打开）。
    public var localizesNames = false

    public init() {}

    public static let zhHans = ChordStrings()

    /// 跟随 App 当前语言（App 内可以切换语言，所以每次重新取）。
    public static var current: ChordStrings { makeCurrent() }

    private static func makeCurrent() -> ChordStrings {
        var s = ChordStrings()
        s.title = L10n.string("和弦库"); s.rootHeader = L10n.string("根音"); s.typeHeader = L10n.string("类型")
        s.tones = L10n.string("组成音"); s.play = L10n.string("试听"); s.stop = L10n.string("停止")
        s.previous = L10n.string("上一个把位"); s.next = L10n.string("下一个把位")
        s.favorite = L10n.string("收藏当前按法"); s.unfavorite = L10n.string("取消收藏")
        s.favoritesHeader = L10n.string("已收藏"); s.noFavorites = L10n.string("还没有收藏")
        s.leftHanded = L10n.string("左手模式"); s.openPosition = L10n.string("开放把位")
        s.bassHint = L10n.string("一个把位里的和弦音"); s.bassRoot = L10n.string("根音")
        s.strumMode = L10n.string("扫弦"); s.arpeggioMode = L10n.string("分解")
        s.playModeLabel = L10n.string("弹奏方式"); s.arpeggioTitle = L10n.string("分解指法")
        s.queuedNext = { name in L10n.string("下一个：\(name)") }
        s.nextBadge = L10n.string("下一个")
        s.stringNote = { n, note in L10n.string("第 \(n) 弦，\(note)") }
        s.pluckHint = L10n.string("双击发声")
        s.tempoTitle = L10n.string("速度"); s.followMetronome = L10n.string("跟随节拍器")
        s.followingNote = { n in L10n.string("用节拍器的速度（\(n) BPM）") }
        s.slower = L10n.string("减慢"); s.faster = L10n.string("加快")
        s.tempoLabel = { n in L10n.string("速度 \(n) BPM") }
        s.customRow = L10n.string("自定义…"); s.arpeggioEditorTitle = L10n.string("自定义指法")
        s.rhythmEditorTitle = L10n.string("自定义节奏型"); s.rhythmPickerTitle = L10n.string("扫弦节奏型")
        s.arpeggioHelp = { n in L10n.string("输入弦号，1 弦最细（最多 \(n) 弦）。- 或 0 是空拍（不弹，占一个音的时值）；可以用空格或逗号分隔，也可以连着写；R 代表当前和弦的根音弦。") }
        s.rhythmHelp = L10n.string("每个字符一格：B 根音、D 全扫、d 半扫、U 上扫、X 闷音、- 或 . 空拍（D 和 d 分大小写）。空格只用来分组。")
        s.nameLabel = L10n.string("名称")
        s.invalidArpeggio = { n in L10n.string("只能输入 1–\(n) 的弦号、0 或 -（空拍）和字母 R") }
        s.invalidRhythm = L10n.string("只能输入 B、D、d、U、X、- 和 .")
        s.tooManyNotes = { n in L10n.string("最多 \(n) 个音") }
        s.tooManyBeats = { n in L10n.string("最多 \(n) 拍") }
        s.notWholeBeats = { n in L10n.string("格数要是 \(n) 的整数倍") }
        s.limitReached = { n in L10n.string("每种乐器最多保存 \(n) 个") }
        s.save = L10n.string("保存"); s.cancel = L10n.string("取消"); s.delete = L10n.string("删除"); s.edit = L10n.string("编辑")
        s.cellFull = L10n.string("全扫"); s.cellHalf = L10n.string("半扫"); s.cellUp = L10n.string("上扫"); s.cellMute = L10n.string("闷音")
        s.rhythmLegend = L10n.string("B 只拨根音弦；D 从根音弦扫到 1 弦；d 和 U 只扫高音的 3–4 根弦。")
        s.restKey = L10n.string("空拍"); s.backspaceKey = L10n.string("退格")
        s.unitLabel = L10n.string("格子单位"); s.eighthUnit = L10n.string("八分"); s.sixteenthUnit = L10n.string("十六分")
        s.rootStringNote = { n in L10n.string("数字是弦号，5 代表根音弦（当前和弦是 \(n) 弦）") }
        s.bassThird = L10n.string("三度"); s.bassFifth = L10n.string("五度"); s.bassOctave = L10n.string("八度")
        s.barrePosition = { fret in L10n.string("横按 · \(fret) 品") }
        s.fretPosition = { fret in L10n.string("\(fret) 品把位") }
        s.diagramLabel = { name in L10n.string("\(name) 指法") }
        s.bassDiagramLabel = { name in L10n.string("\(name) 贝斯和弦音位置") }
        s.stringMuted = { n in L10n.string("\(n) 弦不弹") }
        s.stringOpen = { n in L10n.string("\(n) 弦空弦") }
        s.stringFretted = { n, f in L10n.string("\(n) 弦 \(f) 品") }
        s.pageLabel = { n, total in L10n.string("第 \(n) 个把位，共 \(total) 个") }
        s.listSeparator = L10n.string("，")
        s.localizesNames = true
        return s
    }

    public static var en: ChordStrings {
        var s = ChordStrings()
        s.title = "Chords"; s.rootHeader = "Root"; s.typeHeader = "Type"; s.tones = "Notes"
        s.play = "Play"; s.stop = "Stop"; s.previous = "Previous voicing"; s.next = "Next voicing"
        s.favorite = "Add to favorites"; s.unfavorite = "Remove from favorites"; s.favoritesHeader = "Favorites"
        s.noFavorites = "No favorites yet"; s.leftHanded = "Left-handed"; s.openPosition = "Open position"
        s.bassHint = "Chord tones in one position"
        s.bassRoot = "Root"; s.bassThird = "3rd"; s.bassFifth = "5th"; s.bassOctave = "Octave"
        s.strumMode = "Strum"; s.arpeggioMode = "Arpeggio"; s.playModeLabel = "Play style"; s.arpeggioTitle = "Arpeggio patterns"
        s.customRow = "Custom…"; s.arpeggioEditorTitle = "Custom pattern"; s.rhythmEditorTitle = "Custom rhythm"
        s.rhythmPickerTitle = "Strumming patterns"
        s.arpeggioHelp = { "Enter string numbers, 1 = thinnest (up to \($0)). - or 0 is a rest (silent, takes one note's time); separate with spaces or commas, or write them together; R means the chord's root string." }
        s.rhythmHelp = "One character per cell: B root, D full strum, d half strum, U up, X muted, - or . rest (D and d are case-sensitive). Spaces only group cells."
        s.nameLabel = "Name"; s.invalidArpeggio = { "Only string numbers 1–\($0), 0 or - (rest) and the letter R are allowed" }
        s.invalidRhythm = "Only B, D, d, U, X, - and . are allowed"
        s.tooManyNotes = { "At most \($0) notes" }; s.tooManyBeats = { "At most \($0) beats" }
        s.notWholeBeats = { "The number of cells must be a multiple of \($0)" }
        s.limitReached = { "Up to \($0) saved per instrument" }
        s.save = "Save"; s.cancel = "Cancel"; s.delete = "Delete"; s.edit = "Edit"
        s.cellFull = "Full"; s.cellHalf = "Half"; s.cellUp = "Up"; s.cellMute = "Mute"
        s.rhythmLegend = "B plays only the root string; D strums from the root string to string 1; d and U strum only the 3–4 treble strings."
        s.restKey = "Rest"; s.backspaceKey = "Backspace"
        s.unitLabel = "Cell unit"; s.eighthUnit = "Eighth"; s.sixteenthUnit = "Sixteenth"
        s.tempoTitle = "Tempo"; s.followMetronome = "Match metronome"
        s.followingNote = { "Using the metronome's tempo (\($0) BPM)" }
        s.slower = "Slower"; s.faster = "Faster"; s.tempoLabel = { "Tempo \($0) BPM" }
        s.queuedNext = { "Next: \($0)" }; s.nextBadge = "Next"
        s.stringNote = { "String \($0), \($1)" }; s.pluckHint = "Double-tap to play"
        s.rootStringNote = { "Numbers are string numbers; 5 stands for the root string (this chord: string \($0))" }
        s.barrePosition = { "Barre · fret \($0)" }
        s.fretPosition = { "Fret \($0)" }
        s.diagramLabel = { "\($0) fingering" }
        s.bassDiagramLabel = { "\($0) bass chord tones" }
        s.stringMuted = { "String \($0) muted" }
        s.stringOpen = { "String \($0) open" }
        s.stringFretted = { "String \($0), fret \($1)" }
        s.pageLabel = { "Position \($0) of \($1)" }
        s.listSeparator = ", "
        s.useEnglishNames = true
        return s
    }

    public func name(_ i: Instrument) -> String {
        localizesNames ? TunerStrings.current.name(i) : (useEnglishNames ? i.englishName : i.name)
    }

    public func name(_ t: Tuning) -> String {
        localizesNames ? TunerStrings.current.name(t) : (useEnglishNames ? t.englishName : t.name)
    }

    public func shortName(_ t: ChordType) -> String {
        if localizesNames { return L10n.lookup(t.shortName) }
        guard useEnglishNames else { return t.shortName }
        switch t.id {
        case ChordType.major.id: return "Maj"
        case ChordType.minor.id: return "Min"
        default: return t.shortName
        }
    }

    /// 分解指法的一行说明；自定义的是用户起的名字（可能为空）。
    public func summary(_ p: ArpeggioPattern) -> String {
        if p.isCustom { return p.summary }
        return localizesNames ? L10n.lookup(p.summary) : (useEnglishNames ? p.englishSummary : p.summary)
    }

    /// 扫弦节奏型的名称；自定义的是用户起的名字（可能为空）。
    public func title(_ r: StrumRhythm) -> String {
        if r.isCustom { return r.title }
        return localizesNames ? L10n.lookup(r.title) : (useEnglishNames ? r.englishTitle : r.title)
    }

    public func name(_ t: ChordType) -> String {
        localizesNames ? L10n.lookup(t.name) : (useEnglishNames ? t.englishName : t.name)
    }

    /// “开放把位”“3 品把位”“横按 · 3 品”。
    public func positionLabel(_ v: ChordVoicing) -> String {
        if v.isOpenPosition { return openPosition }
        return v.barre != nil ? barrePosition(v.minFret) : fretPosition(v.minFret)
    }

    /// 每根弦怎么按，读屏用。
    public func spokenDescription(_ v: ChordVoicing, strings: [InstrumentString]) -> String {
        zip(strings, v.frets).map { s, f in
            f < 0 ? stringMuted(s.number) : (f == 0 ? stringOpen(s.number) : stringFretted(s.number, f))
        }.joined(separator: listSeparator)
    }
}

extension NoteNaming {
    /// 根音名，用惯用拼法（C♯ E♭ F♯ A♭ B♭），随唱名、德语写法变化，例如 "C♯"、"Do♯"、"B"（德语的 B♭）。
    public func rootName(_ chord: Chord) -> String { rootName(pitchClass: chord.root) }
    public func rootName(pitchClass pc: Int) -> String {
        name(pitchClass: pc, useFlats: ChordSpelling.rootUsesFlats(pc))
    }
    /// 完整和弦名，例如 "Cmaj7"、"E♭m"、"Rem"、"Sol7"。大三没有后缀，小三是 m。
    public func chordName(_ chord: Chord) -> String { rootName(chord) + chord.type.symbol }
    /// 和弦名：指定根音音级和类型（类型按钮用）。
    public func chordName(pitchClass pc: Int, type: ChordType) -> String { rootName(pitchClass: pc) + type.symbol }
    /// 组成音，拼法和根音一致，例如 E♭ 大三为 ["E♭", "G", "B♭"]。
    public func toneNames(_ chord: Chord) -> [String] {
        zip(chord.pitchClasses, ChordSpelling.flats(for: chord)).map { name(pitchClass: $0, useFlats: $1) }
    }
    /// 和弦里某个音级的音名（指法图弦下面的字母用）。
    public func toneName(pitchClass pc: Int, in chord: Chord) -> String {
        name(pitchClass: pc, useFlats: ChordSpelling.usesFlat(pitchClass: pc, in: chord))
    }
    /// 根音按钮上的写法：只用常用的一种（C♯ E♭ F♯ A♭ B♭，不再把升降两种并列），
    /// 唱名模式是 Do♯ Mi♭ Fa♯ La♭ Si♭，德语的 B♭ 写作 B。返回只有一个元素的数组（保持旧接口的形状）。
    public func rootButtonNames(pitchClass pc: Int) -> [String] { [rootName(pitchClass: pc)] }
}
