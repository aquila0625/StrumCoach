package com.example.tunebeatchord.strum

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.tunebeatchord.audio.AudioEngine
import com.example.tunebeatchord.audio.ChordSound
import com.example.tunebeatchord.audio.MicCapture
import com.example.tunebeatchord.audio.NoteMixer
import com.example.tunebeatchord.audio.Voice
import com.example.tunebeatchord.chord.ChordLibrary
import com.example.tunebeatchord.chord.RhythmStrum
import com.example.tunebeatchord.chord.StrumRhythm
import com.example.tunebeatchord.chord.chordName
import com.example.tunebeatchord.metronome.ClickSynth
import com.example.tunebeatchord.metronome.SoundKind
import com.example.tunebeatchord.practice.PracticeLog
import com.example.tunebeatchord.rhythm.PracticeMode
import com.example.tunebeatchord.rhythm.VoiceLevel
import com.example.tunebeatchord.settings.KeyValueStore
import com.example.tunebeatchord.settings.MemoryStore
import com.example.tunebeatchord.tuner.Instrument
import com.example.tunebeatchord.tuner.NoteNaming
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.roundToInt

/** 一次跟练结束后的结果。 */
class StrumResult(
    val run: PracticeRun,
    val timeline: StrumTimeline,
    val progression: ChordProgression,
    val names: List<String>,
    val report: ProgressionReport?,
) {
    val combined: StrumScore? get() = run.combined
    val score: Int get() = run.averageScore ?: 0
}

/**
 * 扫弦训练：示范（按节奏型把和弦进行扫一遍）、跟练（收音、整段做起音检测、逐下评分）、延迟校准。
 *
 * - 时钟：所有时间都是 `System.nanoTime` 换成秒。示范和耳机里的节拍声按“听到的时刻”排到输出的采样上
 *   （`AudioEngine.nanosToFrame`，已经包含输出延迟）；录音的每个缓冲带它被麦克风收到的时刻（`AudioRecord.getTimestamp`）。
 *   起音时间再减去“延迟校准”的偏差。
 * - 外放时跟练不放任何节拍声（免得麦克风收进去），靠屏幕高亮和倒数引导；检测到耳机才在耳机里放节拍声。
 */
class StrumTrainer(
    private val context: Context,
    private val engine: AudioEngine,
    private val chordSound: ChordSound,
    private val practiceLog: PracticeLog,
    private val store: KeyValueStore = MemoryStore(),
    private val scope: CoroutineScope,
    private val naming: () -> NoteNaming = { NoteNaming.Letters },
    /** 某类乐器的自定义节奏型（和和弦库共用同一份存储）。 */
    private val customRhythms: (com.example.tunebeatchord.tuner.InstrumentFamily) -> List<StrumRhythm> = { emptyList() },
) {
    enum class Phase { IDLE, DEMO, PRACTICE, CALIBRATING }

    var instrument by mutableStateOf(ChordLibrary.strummableInstruments[0]); private set
    var rhythm by mutableStateOf(StrumRhythm.presets(instrument.family)[0]); private set
    var progression by mutableStateOf(ChordProgression.presets[0]); private set
    var bpm by mutableStateOf(80); private set

    /** 练几遍；null = 一直练到点“结束”。 */
    var practiceTarget by mutableStateOf<Int?>(2); private set

    var phase by mutableStateOf(Phase.IDLE); private set
    var timeline by mutableStateOf<StrumTimeline?>(null); private set
    var plan by mutableStateOf<ProgressionPlan?>(null); private set
    var passesDone by mutableStateOf(0); private set
    var lastPass by mutableStateOf<Pair<Int, Int>?>(null); private set
    var scoring by mutableStateOf(false); private set
    var result by mutableStateOf<StrumResult?>(null)
    var message by mutableStateOf<Message?>(null)
    var latencyOffset by mutableStateOf(0.0); private set
    val history = StrumHistory(store)
    val marks = RhythmMarks(store)
    var filter by mutableStateOf(RhythmMarks.Filter.fromId(store.getString(K_FILTER))); private set
    /** 连续 3 次 ≥ 90 分后建议标为“已掌握”的节奏型；界面问一次，答完清掉。 */
    var masterySuggestion by mutableStateOf<StrumRhythm?>(null); private set
    private val progressionStore = ProgressionStore(store)
    var saved by mutableStateOf(progressionStore.loadSaved()); private set

    sealed interface Message {
        data object MicFailed : Message
        data class Calibrated(val ms: Int) : Message
        data class CalibrationFailed(val found: Int) : Message
    }

    private var job: Job? = null
    private var mic: MicCapture? = null
    private val chunks = ArrayList<StrumCaptureChunk>()
    private val clicks = NoteMixer()
    private var strongClick: FloatArray? = null
    private var weakClick: FloatArray? = null

    init {
        store.getString(K_BPM)?.toIntOrNull()?.let { bpm = it.coerceIn(30, 220) }
        store.getString(K_TARGET)?.let { practiceTarget = if (it == "endless") null else it.toIntOrNull() }
        store.getString(K_LATENCY)?.toDoubleOrNull()?.let { latencyOffset = it.coerceIn(-0.2, 0.2) }
        progressionStore.loadCurrent()?.let { progression = it }
        val inst = store.getString(K_INSTRUMENT)?.let { id -> ChordLibrary.strummableInstruments.firstOrNull { it.id == id } }
        if (inst != null) instrument = inst
        rhythm = store.getString(K_RHYTHM)?.let { id -> patterns.firstOrNull { it.id == id } } ?: patterns[0]
    }

    /** 当前乐器能用的节奏型：预设在前，自定义在后。 */
    val patterns: List<StrumRhythm> get() = StrumRhythm.presets(instrument.family) + customRhythms(instrument.family)

    /** 按筛选和标记排好序的节奏型（训练页卡片里滑动的那些）。 */
    val visiblePatterns: List<StrumRhythm> get() = marks.filtered(patterns, filter, instrument.family)

    fun updateFilter(f: RhythmMarks.Filter) { filter = f; store.putString(K_FILTER, f.id) }
    fun isFavorite(r: StrumRhythm) = marks.isFavorite(r.id, instrument.family)
    fun isMastered(r: StrumRhythm) = marks.isMastered(r.id, instrument.family)
    fun setFavorite(on: Boolean, r: StrumRhythm) = marks.setFavorite(on, r.id, instrument.family)
    fun setMastered(on: Boolean, r: StrumRhythm) = marks.setMastered(on, r.id, instrument.family)

    /** 回答“标记为已掌握？”：同意就标，不同意就记下不再问。 */
    fun answerMastery(accept: Boolean) {
        val r = masterySuggestion ?: return
        if (accept) marks.setMastered(true, r.id, instrument.family) else marks.decline(r.id, instrument.family)
        masterySuggestion = null
    }

    // 设置 ---------------------------------------------------------------

    fun select(inst: Instrument) {
        if (inst.id == instrument.id) return
        instrument = inst
        // 当前节奏型不在新乐器的列表里就换成它的默认节奏型
        if (rhythm !in patterns) rhythm = patterns[0]
        store.putString(K_INSTRUMENT, inst.id); store.putString(K_RHYTHM, rhythm.id)
    }

    fun select(r: StrumRhythm) { rhythm = r; store.putString(K_RHYTHM, r.id) }
    fun updateBpm(v: Int) { bpm = v.coerceIn(30, 220); store.putString(K_BPM, bpm.toString()) }
    fun updatePracticeTarget(v: Int?) { practiceTarget = v?.coerceIn(PracticeRun.TARGET_RANGE); store.putString(K_TARGET, v?.toString() ?: "endless") }

    fun updateProgression(p: ChordProgression) { progression = p; progressionStore.saveCurrent(p) }
    fun saveProgression(name: String) { saved = progressionStore.save(progression.copy(name = name.trim().ifEmpty { progression.name })) }
    fun deleteSaved(p: ChordProgression) { saved = saved.filter { it.id != p.id }; progressionStore.storeSaved(saved) }

    // 时钟与出声 ------------------------------------------------------------

    private fun now() = System.nanoTime() / 1e9

    private fun frameAt(seconds: Double) = engine.nanosToFrame((seconds * 1e9).toLong())

    private fun click(strong: Boolean, at: Double) {
        val sr = engine.sampleRate.toDouble()
        val data = if (strong) strongClick ?: ClickSynth.make(SoundKind.WOODBLOCK, VoiceLevel.STRONG, sr).also { strongClick = it }
        else weakClick ?: ClickSynth.make(SoundKind.WOODBLOCK, VoiceLevel.WEAK, sr).also { weakClick = it }
        engine.add(clicks)
        clicks.play(data, frameAt(at), 0.9f)
    }

    /** 有没有戴耳机（有线、蓝牙、USB）：戴了才在耳机里放节拍声。 */
    fun headphonesConnected(): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type in setOf(AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_BLE_HEADSET)
        }
    }

    private fun voice() = Voice.fromFamily(instrument.family)

    /** 一小节里每个要扫的格，用那个小节对应的和弦的第一个把位，排到输出上。 */
    private fun scheduleDemo(tl: StrumTimeline, plan: ProgressionPlan) {
        val voicings = progression.chords.map { c -> ChordLibrary.voicings(c.chord, instrument).firstOrNull() }
        for (s in tl.strokes) {
            val index = plan.chordIndex(s.bar)
            val v = voicings[index] ?: continue
            val chord = progression.chords[index].chord
            val playback = RhythmStrum.playback(v, s.stroke, chord.root, tl.pattern.velocity(s.step), voice())
            chordSound.play(playback, frameAt(s.time))
        }
    }

    // 示范 ---------------------------------------------------------------

    /** 听示范：倒数一小节（木鱼声），把和弦进行扫一遍（最多 8 小节），一直循环到点“停止”。 */
    fun startDemo() {
        if (phase != Phase.IDLE) return
        message = null
        result = null
        val p = ProgressionPlan.of(progression, maxBars = 8)
        plan = p
        phase = Phase.DEMO
        job = scope.launch {
            var tl = StrumTimeline(rhythm, bpm.toDouble(), now() + 0.5 + 60.0 / bpm * rhythm.beatsPerBar, p.bars)
            timeline = tl
            for ((i, t) in tl.countInBeats.withIndex()) click(i == 0, t)
            var first = true
            while (phase == Phase.DEMO) {
                scheduleDemo(tl, p)
                delay(((tl.end - now()) * 1000 - 400).toLong().coerceAtLeast(0))
                if (phase != Phase.DEMO) break
                tl = tl.following()
                timeline = tl
                first = false
            }
            if (first) { /* 没来得及排第二遍就停了 */ }
        }
    }

    fun stopDemo() {
        if (phase != Phase.DEMO) return
        stopAll()
    }

    // 跟练 ---------------------------------------------------------------

    /** 开始跟练：倒数一小节后收音，每遍结束时在后台评分；练够遍数或点“结束”后出结果。调用方先拿到录音权限。 */
    fun startPractice(): Boolean {
        if (phase != Phase.IDLE) return false
        message = null
        result = null
        passesDone = 0
        lastPass = null
        if (!startMic()) { message = Message.MicFailed; return false }
        val p = ProgressionPlan.of(progression, minBars = MIN_PRACTICE_BARS)
        plan = p
        val run = PracticeRun(practiceTarget, p.bars)
        currentRun = run
        phase = Phase.PRACTICE
        val headphones = headphonesConnected()
        val names = progression.chords.map { naming().chordName(it.chord) }
        val startedAtMillis = System.currentTimeMillis()
        job = scope.launch {
            val beat = 60.0 / bpm
            var tl = StrumTimeline(rhythm, bpm.toDouble(), now() + 0.5 + beat * rhythm.beatsPerBar, p.bars)
            val timelines = ArrayList<StrumTimeline>()
            var scheduled = 0
            timeline = tl
            if (headphones) for ((i, t) in tl.countInBeats.withIndex()) click(i == 0, t)
            while (phase == Phase.PRACTICE && run.needsPass(scheduled)) {
                timelines.add(tl); scheduled++
                if (headphones) for (b in 0 until rhythm.beatsPerBar * p.bars) click(b % rhythm.beatsPerBar == 0, tl.start + b * beat)
                timeline = tl
                // 等这一遍结束再多收一会儿，然后评分
                delay(((tl.end + 0.35 - now()) * 1000).toLong().coerceAtLeast(0))
                if (phase != Phase.PRACTICE) break
                val k = timelines.size - 1
                gradePass(run, tl, timelines, k)
                tl = tl.following()
            }
            if (phase == Phase.PRACTICE) finishPractice(run, p, names, startedAtMillis, timelines.firstOrNull())
        }
        return true
    }

    private suspend fun gradePass(run: PracticeRun, tl: StrumTimeline, passTimelines: List<StrumTimeline>, k: Int) {
        scoring = true
        val picked = synchronized(chunks) {
            val rate = mic?.sampleRate?.toDouble() ?: 48_000.0
            chunks.filter { it.time + it.samples.size / rate >= tl.start - 0.5 && it.time <= tl.end + 0.5 }
        }
        val rate = mic?.sampleRate?.toDouble() ?: 48_000.0
        val offset = latencyOffset
        val sensitive = StrumTrainerLogic.bassWindows(tl, offset)
        val onsets = withContext(Dispatchers.Default) { StrumCapture(picked, rate).onsetTimes(sensitive).map { it - offset } }
        val guards = ArrayList<Double>()
        if (k > 0) passTimelines[k - 1].strokes.lastOrNull()?.let { guards.add(it.time) }
        // 下一遍的第一下就在这一遍结束的那一刻
        guards.add(tl.following().strokes.firstOrNull()?.time ?: tl.end)
        val score = StrumScore.grade(tl, onsets, guards)
        run.add(score)
        passesDone = run.passes.size
        lastPass = (k + 1) to score.score
        scoring = false
        synchronized(chunks) { chunks.removeAll { it.time + it.samples.size / rate < tl.end - 1 } }
    }

    /** 结束跟练（点“结束”）：只算已经练完的遍；一遍都没练完就不出成绩。 */
    fun endPractice() {
        if (phase != Phase.PRACTICE) return
        val run = currentRun
        job?.cancel()
        // 取消后在主线程收尾
        stopMic(); chordSound.stop(); clicks.stopAll()
        val p = plan; val tl = timeline
        phase = Phase.IDLE
        timeline = null
        if (run != null && run.passes.isNotEmpty() && p != null && tl != null) publish(run, p, progression.chords.map { naming().chordName(it.chord) }, System.currentTimeMillis(), tl)
    }

    private var currentRun: PracticeRun? = null

    private fun finishPractice(run: PracticeRun, p: ProgressionPlan, names: List<String>, startedAtMillis: Long, tl: StrumTimeline?) {
        stopMic()
        clicks.stopAll()
        phase = Phase.IDLE
        timeline = null
        if (tl != null && run.passes.isNotEmpty()) publish(run, p, names, startedAtMillis, tl)
    }

    private fun publish(run: PracticeRun, p: ProgressionPlan, names: List<String>, startedAtMillis: Long, tl: StrumTimeline) {
        val combined = run.combined ?: return
        val report = if (progression.chords.size > 1 || p.changeBars.isNotEmpty()) ProgressionReport.make(combined, tl, p.repeated(run.passes.size), names) else null
        result = StrumResult(run, tl, progression, names, report)
        val seconds = run.passes.size * p.bars * tl.barDuration
        practiceLog.record(startedAtMillis, seconds, bpm..bpm, PracticeMode.STRUM)
        history.add(StrumHistory.Entry(System.currentTimeMillis(), rhythm.id, progression.label { naming().chordName(it) }, bpm, run.averageScore ?: 0, instrument.family.id))
        if (marks.suggestsMastered(rhythm.id, instrument.family, history.entries)) masterySuggestion = rhythm
    }

    // 延迟校准 -----------------------------------------------------------

    /** 跟着节拍每拍扫一下（8 拍、90 BPM），取偏差的中位数存起来（限制在 ±200 毫秒）。 */
    fun startCalibration(): Boolean {
        if (phase != Phase.IDLE) return false
        message = null
        if (!startMic()) { message = Message.MicFailed; return false }
        phase = Phase.CALIBRATING
        job = scope.launch {
            val beat = 60.0 / 90
            val first = now() + 0.5 + beat * 4
            val beats = (0 until 8).map { first + it * beat }
            timeline = StrumTimeline(StrumRhythm.quarters, 90.0, first, 2)
            for (i in 0 until 4) click(i == 0, first - beat * (4 - i))
            for ((i, t) in beats.withIndex()) click(i % 4 == 0, t)
            delay(((beats.last() + 0.5 - now()) * 1000).toLong().coerceAtLeast(0))
            val rate = mic?.sampleRate?.toDouble() ?: 48_000.0
            val picked = synchronized(chunks) { chunks.toList() }
            val onsets = withContext(Dispatchers.Default) { StrumCapture(picked, rate).onsetTimes() }
            val diffs = beats.mapNotNull { t -> onsets.map { it - t }.filter { abs(it) <= 0.2 }.minByOrNull { abs(it) } }
            stopMic(); clicks.stopAll()
            phase = Phase.IDLE; timeline = null
            if (diffs.size < 4) { message = Message.CalibrationFailed(diffs.size); return@launch }
            val median = diffs.sorted()[diffs.size / 2]
            latencyOffset = median.coerceIn(-0.2, 0.2)
            store.putString(K_LATENCY, latencyOffset.toString())
            message = Message.Calibrated((latencyOffset * 1000).roundToInt())
        }
        return true
    }

    fun resetCalibration() { latencyOffset = 0.0; store.putString(K_LATENCY, "0") }

    // 通用 ---------------------------------------------------------------

    fun stopAll() {
        job?.cancel()
        stopMic(); chordSound.stop(); clicks.stopAll()
        phase = Phase.IDLE
        timeline = null
        scoring = false
    }

    /** 离开页面时调用。 */
    fun leave() {
        if (phase == Phase.PRACTICE) endPractice() else stopAll()
    }

    private fun startMic(): Boolean {
        synchronized(chunks) { chunks.clear() }
        val capture = MicCapture(48_000)
        val ok = capture.start { buffer, count, firstFrame ->
            val time = capture.frameToNanos(firstFrame) / 1e9
            synchronized(chunks) { chunks.add(StrumCaptureChunk(time, buffer.copyOf(count))) }
        }
        if (!ok) return false
        mic = capture
        return true
    }

    private fun stopMic() {
        mic?.stop()
        mic = null
    }

    /** 当前（示范或跟练时）的位置：第几小节第几格；没在播放时 null。 */
    fun position(nowSeconds: Double): Pair<Int, Int>? = timeline?.position(nowSeconds)

    /** 倒数：现在在倒数第几拍（1 起），不在倒数时 null。 */
    fun countIn(nowSeconds: Double): Int? {
        val tl = timeline ?: return null
        if (nowSeconds >= tl.start) return null
        val beats = tl.countInBeats
        val i = beats.indexOfLast { it <= nowSeconds }
        return if (i < 0) null else i + 1
    }

    /** 当前（或最近一遍）时间轴的“现在”，给界面用。 */
    fun clockSeconds() = now()

    companion object {
        const val MIN_PRACTICE_BARS = 4
        private const val K_BPM = "strum.bpm"
        private const val K_TARGET = "strum.practiceTarget"
        private const val K_LATENCY = "strum.latencyOffset"
        private const val K_INSTRUMENT = "strum.instrument"
        private const val K_RHYTHM = "strum.rhythm"
        private const val K_FILTER = "strum.rhythmFilter"
    }
}
