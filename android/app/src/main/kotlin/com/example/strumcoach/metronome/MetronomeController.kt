package com.example.strumcoach.metronome

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.strumcoach.audio.AudioEngine
import com.example.strumcoach.practice.PracticeLog
import com.example.strumcoach.practice.PracticeRecording
import com.example.strumcoach.rhythm.AccentLevel
import com.example.strumcoach.rhythm.MuteSettings
import com.example.strumcoach.rhythm.PracticeMode
import com.example.strumcoach.rhythm.RampSettings
import com.example.strumcoach.rhythm.RhythmSettings
import com.example.strumcoach.rhythm.Subdivision
import com.example.strumcoach.rhythm.Tempo
import com.example.strumcoach.rhythm.TimeSignature
import com.example.strumcoach.rhythm.TrainingPlan
import com.example.strumcoach.settings.KeyValueStore
import com.example.strumcoach.settings.MemoryStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** 训练页里的选项：渐进提速和静音训练各自的开关与参数。 */
@Serializable
data class TrainingOptions(
    val rampEnabled: Boolean = false,
    val rampStart: Int = 80,
    val rampTarget: Int = 120,
    val rampStep: Int = 2,
    val rampBars: Int = 4,
    val rampEnd: String = RampSettings.EndBehavior.HOLD.id,
    val muteEnabled: Boolean = false,
    /** "bars" 按小节，"random" 随机静音 */
    val muteKind: String = "bars",
    val muteAudible: Int = 2,
    val muteMuted: Int = 1,
    val muteProbability: Double = 0.3,
    val muteSeed: Long = 1,
    val muteKeepsDownbeat: Boolean = true,
    /** 练习计时：今天累计到 `timerMinutes` 分钟时提醒一次（每天一次），可选自动停止。 */
    val timerEnabled: Boolean = false,
    val timerMinutes: Int = 20,
    val timerAutoStop: Boolean = false,
) {
    fun plan(baseBPM: Int): TrainingPlan? {
        val ramp = if (rampEnabled) RampSettings(rampStart, rampTarget, rampStep, rampBars, RampSettings.EndBehavior.fromId(rampEnd)) else null
        val mute = if (muteEnabled) {
            if (muteKind == "bars") MuteSettings.bars(muteAudible, muteMuted)
            else MuteSettings.randomBeats(muteProbability, muteSeed, muteKeepsDownbeat)
        } else null
        return if (ramp == null && mute == null) null else TrainingPlan(baseBPM, ramp, mute)
    }
}

@Serializable
private data class SavedMetronome(
    val bpm: Double = 120.0,
    val beats: Int = 4,
    val unit: Int = 4,
    val accents: List<Int> = emptyList(),
    val subdivision: String = Subdivision.QUARTER.id,
    val tone: String = SoundKind.WOODBLOCK.tone,
    val subdivisionVolume: Float = MetronomeConfig.DEFAULT_SUBDIVISION_VOLUME,
    val training: TrainingOptions = TrainingOptions(),
)

/**
 * 节拍器的界面状态和动作：配置、播放、TAP、训练、练习记录。音频由 [MetronomeSource] 在音频线程里渲染。
 * 当前这一拍的高亮按音频时钟算（`tick`），不靠界面定时器。
 */
class MetronomeController(
    private val engine: AudioEngine?,
    private val store: KeyValueStore = MemoryStore(),
    private val log: PracticeLog = PracticeLog(),
    private val clockNanos: () -> Long = System::nanoTime,
    private val wallClockMillis: () -> Long = System::currentTimeMillis,
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val source = MetronomeSource(engine?.sampleRate?.toDouble() ?: 48_000.0, MetronomeConfig.Default)

    var config by mutableStateOf(MetronomeConfig.Default); private set
    var options by mutableStateOf(TrainingOptions()); private set
    var isPlaying by mutableStateOf(false); private set

    /** 正在响的那一拍（小节内序号）和切分点；没在播放时是 -1。 */
    var currentBeat by mutableStateOf(-1); private set
    var currentSub by mutableStateOf(-1); private set

    /** 播放时实际的 BPM（开了渐进提速时会变）。 */
    var liveBpm by mutableStateOf(120.0); private set
    var liveBar by mutableStateOf(0); private set

    /** 计时：播放时累计的秒数（点“计时”按钮清零）。 */
    var elapsedSeconds by mutableStateOf(0); private set

    /** 最近一次自动停止的原因，界面显示一句提示后清掉。 */
    var notice by mutableStateOf<Notice?>(null)

    /** 今天累计练了多少秒：今天已记录的练习 + 正在播放的这一段。 */
    var todaySeconds by mutableStateOf(0); private set
    private var todayBaseline = 0.0

    /** 今天的练习目标达成时回调一次（震动用）。 */
    var onGoalReached: (() -> Unit)? = null

    /** 每个主拍响起时回调一次（跟拍震动用）。参数是小节内第几拍。 */
    var onMainBeat: ((Int) -> Unit)? = null
    private var lastMainKey = -1L

    enum class Notice { RAMP_FINISHED, TIMER_REACHED_STOPPED, TIMER_REACHED }

    private val tapTempo = TapTempo()
    private var startedAtMillis = 0L
    private var startedAtNanos = 0L
    private var minBpmSeen = 120
    private var maxBpmSeen = 120

    init {
        load()
        refreshToday()
        liveBpm = config.bpm
        engine?.let { /* 来源在第一次播放时才接进去 */ }
    }

    val bpm: Double get() = config.bpm
    val rampControlsTempo: Boolean get() = config.training?.ramp != null

    // 配置 -------------------------------------------------------------

    private fun apply(newConfig: MetronomeConfig) {
        config = newConfig
        if (isPlaying) source.update(newConfig)
        save()
    }

    private fun rebuild(base: MetronomeConfig = config) {
        val plan = options.plan(base.bpm.toInt())
        apply(base.copy(training = plan, clearTraining = plan == null))
    }

    fun setBpm(value: Double) {
        if (rampControlsTempo) return
        val v = value.coerceIn(MetronomeConfig.BPM_RANGE)
        rebuild(config.copy(bpm = v))
        noteBpm(v)
    }

    fun nudgeBpm(delta: Int) = setBpm(Math.round(config.bpm) + delta.toDouble())

    /** TAP 测速：返回算出来的 BPM（至少两次点按才有）。 */
    fun tap(): Double? {
        if (rampControlsTempo) return null
        val bpm = tapTempo.tap(clockNanos() / 1e9)?.let { Math.round(it).toDouble() }
        if (bpm != null) setBpm(bpm)
        return bpm
    }

    fun cycleAccent(beat: Int) {
        if (beat !in 0 until config.accents.count) return
        apply(config.copy(accents = config.accents.with(beat, config.accents[beat].cycled)))
    }

    fun setTimeSignature(ts: TimeSignature, preset: AccentPreset = AccentPreset.GROUPED) = apply(config.withTimeSignature(ts, preset))
    fun setAccentPreset(preset: AccentPreset) = apply(config.copy(accents = preset.pattern(config.timeSignature)))
    fun setSubdivision(sub: Subdivision) = apply(config.copy(subdivision = sub))
    fun setSubdivisionVolume(v: Float) = apply(config.copy(subdivisionVolume = v.coerceIn(0f, 1f)))
    fun setSound(sound: SoundKind) = apply(config.copy(sound = sound))

    fun updateOptions(transform: (TrainingOptions) -> TrainingOptions) {
        options = transform(options)
        rebuild()
    }

    // 播放 -------------------------------------------------------------

    fun start() {
        val e = engine ?: return
        if (isPlaying) return
        notice = null
        refreshToday()
        lastMainKey = -1L
        e.add(source)
        source.start(config)
        isPlaying = true
        timerCarry = elapsedSeconds.toDouble()
        timerBaseNanos = clockNanos()
        startedAtMillis = wallClockMillis()
        startedAtNanos = clockNanos()
        val bpm = config.training?.bpm(0) ?: config.bpm.toInt()
        minBpmSeen = bpm; maxBpmSeen = bpm
        liveBpm = bpm.toDouble()
    }

    /** 停止；播了 30 秒以上会记一次练习。`reason` 不为 null 时界面显示对应的提示。 */
    fun stop(reason: Notice? = null) {
        if (!isPlaying) return
        source.stop()
        isPlaying = false
        currentBeat = -1; currentSub = -1
        val seconds = (clockNanos() - startedAtNanos) / 1e9
        val plan = config.training
        val range = if (plan?.ramp != null) plan.bpmRange(liveBar) else minBpmSeen..maxBpmSeen
        log.record(startedAtMillis, seconds, range, plan?.mode ?: PracticeMode.FREE)
        refreshToday()
        if (reason != null) notice = reason
    }

    fun toggle() = if (isPlaying) stop() else start()

    /** 每一帧调用：更新当前拍高亮，处理“到目标后停止”。 */
    fun tick(nowNanos: Long) {
        val e = engine ?: return
        if (!isPlaying) return
        if (source.finished) {
            stop(Notice.RAMP_FINISHED); return
        }
        val secs = timerCarry + (nowNanos - timerBaseNanos) / 1e9
        if (secs.toInt() != elapsedSeconds) elapsedSeconds = secs.toInt()
        updateToday((nowNanos - startedAtNanos) / 1e9)
        var best: PlayedClick? = null
        for (c in source.recentClicks()) if (e.frameToNanos(c.engineFrame) <= nowNanos) best = c
        if (best != null) {
            if (best.subIndex == 0 && !best.muted) {
                val key = best.bar.toLong() * 100 + best.beatInBar
                if (key != lastMainKey) { lastMainKey = key; onMainBeat?.invoke(best.beatInBar) }
            }
            currentBeat = best.beatInBar
            currentSub = best.subIndex
            liveBpm = best.bpm
            liveBar = best.bar
            noteBpm(best.bpm)
        }
    }

    /** 今天已记录的练习总秒数（不含正在播放的这一段）；换了一天就从 0 开始。 */
    private fun refreshToday() {
        val zone = java.time.ZoneId.systemDefault()
        val start = java.time.Instant.ofEpochMilli(wallClockMillis()).atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
        todayBaseline = log.sessions.filter { !it.startedAt.isBefore(start) && PracticeRecording.shouldRecord(it.duration) }.sumOf { it.duration }
        if (!isPlaying) todaySeconds = todayBaseline.toInt()
    }

    /** 播放中每帧调用：`played` 是这一段已播的秒数。累计到目标就提醒（每天一次），可选自动停止。 */
    internal fun updateToday(played: Double) {
        val today = (todayBaseline + played).toInt()
        if (today == todaySeconds) return
        todaySeconds = today
        val o = options
        if (!o.timerEnabled || today < o.timerMinutes * 60) return
        val day = java.time.Instant.ofEpochMilli(wallClockMillis()).atZone(java.time.ZoneId.systemDefault()).toLocalDate().toString()
        if (store.getString(KEY_GOAL_DAY) == day) return
        store.putString(KEY_GOAL_DAY, day)
        onGoalReached?.invoke()
        if (o.timerAutoStop) stop(Notice.TIMER_REACHED_STOPPED) else notice = Notice.TIMER_REACHED
    }

    fun resetTimer() {
        elapsedSeconds = 0
        timerCarry = 0.0
        timerBaseNanos = clockNanos()
    }

    private var timerBaseNanos = 0L
    private var timerCarry = 0.0

    private fun noteBpm(bpm: Double) {
        val b = Math.round(bpm).toInt()
        minBpmSeen = minOf(minBpmSeen, b); maxBpmSeen = maxOf(maxBpmSeen, b)
    }

    // 存取 -------------------------------------------------------------

    private fun save() {
        val c = config
        store.putString(KEY, json.encodeToString(SavedMetronome(
            c.bpm, c.timeSignature.beatsPerBar, c.timeSignature.beatUnit, c.accents.array.map { it.raw },
            c.subdivision.id, c.sound.tone, c.subdivisionVolume, options,
        )))
    }

    private fun load() {
        val saved = store.getString(KEY)?.let { runCatching { json.decodeFromString<SavedMetronome>(it) }.getOrNull() } ?: return
        // 早先的版本把练习计时的分钟数默认存成 0（表示关）：读到小于 5 的值就回到 20 分钟
        options = saved.training.let { if (it.timerMinutes < 5) it.copy(timerMinutes = 20) else it }
        val ts = TimeSignature.of(saved.beats, saved.unit)
        val accents = RhythmSettings.normalized(saved.accents.map { AccentLevel.fromRaw(it.coerceIn(0, 3)) }, ts)
            .let { if (saved.accents.isEmpty()) AccentPreset.GROUPED.accents(ts) else it }
        val base = MetronomeConfig(saved.bpm, ts, AccentPattern(accents), Subdivision.fromId(saved.subdivision),
            saved.subdivisionVolume, SoundKind.fromTone(saved.tone))
        val plan = options.plan(base.bpm.toInt())
        config = base.copy(training = plan)
    }

    private companion object {
        const val KEY_GOAL_DAY = "practice.goalDay"
        const val KEY = "metronome.config"
        @Suppress("unused") val tempoRange = Tempo.range
    }
}
