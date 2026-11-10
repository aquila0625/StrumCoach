import Foundation

/// 界面文字。`.current` 跟随 App 语言（String Catalog），`.zhHans`、`.en` 是固定的两份（测试、预览用）。
public struct TunerStrings: Sendable {
    public var title = "调音器"
    public var cents = "音分"
    public var inTune = "已准"
    public var flat = "偏低"
    public var sharp = "偏高"
    public var listening = "请弹奏一根弦"
    public var micOff = "正在启动麦克风…"
    public var micDenied = "需要麦克风权限才能调音"
    public var openSettings = "打开设置"
    public var referenceA4 = "标准音"
    public var referencePitch = "参考音（点按发声）"
    public var octave = "八度"
    public var stringsHeader = "弦（点按锁定，再点解锁）"
    public var auto = "自动"
    public var locked = "已锁定"
    public var instrument = "乐器"
    public var tuningLabel = "定弦"
    public var settings = "设置"
    public var gauge = "音分表盘"
    public var noSignal = "无信号"
    public var chimeToggle = "调准提示音"
    public var chimeToggleHint = "调准一根弦时播放“叮咚”提示音"
    /// 弦按钮的读屏文字，例如 "6 弦 E2"。
    public var stringLabel: @Sendable (Int, String) -> String = { "\($0) 弦 \($1)" }
    /// 参考音按钮的读屏文字。
    public var referenceLabel: @Sendable (String) -> String = { "参考音 \($0)" }
    public var useEnglishNames = false
    /// 乐器、定弦名按 String Catalog 翻译（`.current` 打开）。
    public var localizesNames = false

    public init() {}

    public static let zhHans = TunerStrings()

    /// 跟随 App 当前语言（App 内可以切换语言，所以每次重新取）。
    public static var current: TunerStrings { makeCurrent() }

    private static func makeCurrent() -> TunerStrings {
        var s = TunerStrings()
        s.title = L10n.string("调音器"); s.cents = L10n.string("音分"); s.inTune = L10n.string("已准")
        s.flat = L10n.string("偏低"); s.sharp = L10n.string("偏高"); s.listening = L10n.string("请弹奏一根弦")
        s.micOff = L10n.string("正在启动麦克风…"); s.micDenied = L10n.string("需要麦克风权限才能调音")
        s.openSettings = L10n.string("打开设置"); s.referenceA4 = L10n.string("标准音")
        s.referencePitch = L10n.string("参考音（点按发声）"); s.octave = L10n.string("八度")
        s.stringsHeader = L10n.string("弦（点按锁定，再点解锁）"); s.auto = L10n.string("自动")
        s.locked = L10n.string("已锁定"); s.instrument = L10n.string("乐器"); s.tuningLabel = L10n.string("定弦")
        s.settings = L10n.string("设置"); s.gauge = L10n.string("音分表盘"); s.noSignal = L10n.string("无信号")
        s.chimeToggle = L10n.string("调准提示音"); s.chimeToggleHint = L10n.string("调准一根弦时播放“叮咚”提示音")
        s.stringLabel = { number, note in L10n.string("\(number) 弦 \(note)") }
        s.referenceLabel = { note in L10n.string("参考音 \(note)") }
        s.localizesNames = true
        return s
    }

    public static var en: TunerStrings {
        var s = TunerStrings()
        s.title = "Tuner"; s.cents = "cents"; s.inTune = "In tune"; s.flat = "Flat"; s.sharp = "Sharp"
        s.listening = "Play a string"; s.micOff = "Starting microphone…"
        s.micDenied = "Microphone access is needed to tune"; s.openSettings = "Open Settings"
        s.referenceA4 = "Reference"; s.referencePitch = "Reference tone (tap to play)"; s.octave = "Octave"
        s.stringsHeader = "Strings (tap to lock, tap again to unlock)"
        s.auto = "Auto"; s.locked = "Locked"; s.instrument = "Instrument"; s.tuningLabel = "Tuning"
        s.settings = "Settings"; s.gauge = "Cents gauge"; s.noSignal = "No signal"
        s.chimeToggle = "Tuned chime"; s.chimeToggleHint = "Play a “ding-dong” when a string is in tune"
        s.stringLabel = { "String \($0), \($1)" }
        s.referenceLabel = { "Reference tone \($0)" }
        s.useEnglishNames = true
        return s
    }

    public func name(_ i: Instrument) -> String {
        localizesNames ? L10n.lookup(i.name) : (useEnglishNames ? i.englishName : i.name)
    }

    public func name(_ t: Tuning) -> String {
        localizesNames ? L10n.lookup(t.name) : (useEnglishNames ? t.englishName : t.name)
    }
}
