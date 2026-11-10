package com.example.tunebeatchord.metronome

/** TAP 测速：取最近 4 次点按的平均间隔；距上次点按超过 2 秒就重新计算。 */
class TapTempo {
    var resetInterval = 2.0
    var window = 4
    private val _taps = ArrayList<Double>()
    val taps: List<Double> get() = _taps

    /** 记录一次点按，返回算出的 BPM（至少两次点按才有结果），已限制在 20–400。 */
    fun tap(time: Double): Double? {
        val last = _taps.lastOrNull()
        if (last != null && (time - last > resetInterval || time <= last)) _taps.clear()
        _taps.add(time)
        while (_taps.size > window) _taps.removeAt(0)
        if (_taps.size < 2) return null
        val average = (_taps.last() - _taps.first()) / (_taps.size - 1)
        return (60 / average).coerceIn(MetronomeConfig.BPM_RANGE)
    }

    fun reset() = _taps.clear()
}

/** 速度术语，随 BPM 变化。键是简体中文名（也是译文的键）。 */
object TempoTerm {
    private class Entry(val upTo: Double, val zh: String, val it: String)

    private val table = listOf(
        Entry(40.0, "庄板", "Grave"), Entry(60.0, "广板", "Largo"), Entry(66.0, "小广板", "Larghetto"),
        Entry(76.0, "柔板", "Adagio"), Entry(108.0, "行板", "Andante"), Entry(120.0, "中板", "Moderato"),
        Entry(156.0, "快板", "Allegro"), Entry(176.0, "活板", "Vivace"), Entry(200.0, "急板", "Presto"),
        Entry(Double.POSITIVE_INFINITY, "最急板", "Prestissimo"),
    )

    private fun entry(bpm: Double) = table.firstOrNull { bpm < it.upTo } ?: table.last()

    /** 意大利文术语，例如 120 → "Allegro"。区间左闭右开。 */
    fun italian(bpm: Double) = entry(bpm).it

    /** 译文的键（简体中文名），界面用它取当前语言的本地名称。 */
    fun localKey(bpm: Double) = entry(bpm).zh

    /** 完整术语：本地名称 + 意大利文，例如 "快板 Allegro"；没有本地名称或和意大利文相同时只显示意大利文。 */
    fun name(bpm: Double, localName: (String) -> String): String {
        val local = localName(localKey(bpm))
        val it = italian(bpm)
        return if (local.isEmpty() || local == it) it else "$local $it"
    }

}
