package com.example.strumcoach.tuner

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.strumcoach.settings.KeyValueStore
import com.example.strumcoach.settings.MemoryStore
import kotlin.math.roundToInt

/** 刚刚调准的一个音（界面据此做一下“已准”动画）。 */
data class TunedEvent(val id: Int, val stringIndex: Int?, val pitch: Pitch)

/**
 * 调音器的状态和逻辑，不碰音频硬件：麦克风的数据从 [ingest] 喂进来（也方便测试），
 * 参考音和提示音通过回调交给外面发声。
 *
 * 流程：检测音高 → 平滑 → 对到目标弦（自动选最近的弦，或手动锁定一根）→ 判定调准（偏差在 ±5 音分内持续 0.5 秒才算，同一根弦只提示一次）。
 */
class TunerModel(
    selection: InstrumentSelection = InstrumentSelection.Default,
    a4: Double = TunerDefaults.A4,
    private val store: KeyValueStore = MemoryStore(),
) {
    var instrument by mutableStateOf(selection.resolve().first); private set
    var tuning by mutableStateOf(selection.resolve().second); private set
    var a4 by mutableStateOf(clampA4(a4)); private set
    var lockedString by mutableStateOf<Int?>(null); private set

    var reading by mutableStateOf<PitchReading?>(null); private set
    var lastReading by mutableStateOf<PitchReading?>(null); private set
    var result by mutableStateOf<TuningResult?>(null); private set
    var tunedStrings by mutableStateOf<Set<Int>>(emptySet()); private set
    var tunedEventCount by mutableIntStateOf(0); private set
    var lastTunedEvent by mutableStateOf<TunedEvent?>(null); private set
    var playingReference by mutableStateOf<Pitch?>(null); private set

    var isRunning by mutableStateOf(false)
    var errorMessage by mutableStateOf<String?>(null)

    /** 调准时是否播“叮咚”。 */
    var tuneChimeEnabled by mutableStateOf(store.getString(KEY_CHIME) != "0")
        private set

    var referenceTimbre by mutableStateOf(ToneTimbreChoice.INSTRUMENT)

    /** 参考音响着的时候暂停检测，免得把参考音当成弦的声音。 */
    var pausesDetectionWhileReferencePlays = true

    // 外部连接
    var clock: () -> Double = { System.nanoTime() / 1e9 }
    /** 播提示音；返回 true 表示真的播了（之后一小段时间忽略检测结果，免得把提示音本身当成弦）。 */
    var playChime: (() -> Boolean)? = null
    var onPlayReference: ((Pitch, Double, ToneTimbreChoice, InstrumentFamily) -> Unit)? = null
    var onStopReference: (() -> Unit)? = null
    var onRetuneReference: ((Double) -> Unit)? = null
    var chimeDuration = 0.45
    var chimeGuardSeconds = 0.6

    val confirmation = TuneConfirmation()
    private val smoother = PitchSmoother()
    private val detector = PitchDetector()
    private var ignoreDetectionUntil = 0.0

    val selection: InstrumentSelection get() = InstrumentSelection(instrument.id, tuning.id)

    /** 麦克风来了一段数据（单声道）。返回当前匹配结果。 */
    fun ingest(samples: FloatArray, sampleRate: Double, count: Int = samples.size): TuningResult? {
        ingest(detector.detect(samples, sampleRate, count))
        return result
    }

    fun ingest(raw: RawPitch?) {
        if (pausesDetectionWhileReferencePlays && playingReference != null) return
        if (ignoreDetectionUntil > 0) {
            // 提示音正在响（或刚响完）：这段时间的检测结果多半是提示音本身，丢掉；窗口结束后从头平滑
            if (clock() < ignoreDetectionUntil) return
            ignoreDetectionUntil = 0.0
            smoother.reset()
            confirmation.restartHold()
        }
        apply(smoother.process(raw, a4))
    }

    /** 直接塞一个结果（预览、测试）。 */
    fun inject(reading: PitchReading?) = apply(reading)

    private fun apply(newReading: PitchReading?) {
        reading = newReading
        if (newReading == null) {
            result = null
            handle(confirmation.update(null, null, clock()), null)
            return
        }
        lastReading = newReading
        val r = tuning.match(newReading, lockedString)
        result = r
        // 弦的序号；半音阶模式下用音名+八度（MIDI 号）
        val key = r.stringIndex ?: r.target.midi
        handle(confirmation.update(key, r.cents, clock()), r)
    }

    private fun handle(event: TuneConfirmation.Event?, r: TuningResult?) {
        when (event) {
            null -> {}
            is TuneConfirmation.Event.Drifted -> if (!tuning.isChromatic) tunedStrings = tunedStrings - event.key
            is TuneConfirmation.Event.Tuned -> {
                val index = if (tuning.isChromatic) null else event.key
                if (index != null) tunedStrings = tunedStrings + index
                tunedEventCount += 1
                lastTunedEvent = TunedEvent(tunedEventCount, index, r?.target ?: Pitch(event.key))
                if (tuneChimeEnabled && playChime?.invoke() == true) ignoreDetectionUntil = clock() + chimeDuration + chimeGuardSeconds
            }
        }
    }

    // 乐器与弦 -----------------------------------------------------------

    fun select(inst: Instrument, t: Tuning? = null) {
        instrument = inst
        tuning = t ?: inst.defaultTuning
        resetForNewTuning()
    }

    fun select(selection: InstrumentSelection) {
        val (i, t) = selection.resolve()
        select(i, t)
    }

    fun select(t: Tuning) {
        if (t !in instrument.tunings) return
        tuning = t
        resetForNewTuning()
    }

    private fun resetForNewTuning() {
        lockedString = null
        tunedStrings = emptySet()
        lastTunedEvent = null
        confirmation.reset()
        smoother.reset()
        reading?.let { apply(PitchReading(it.frequency, it.clarity, a4)) }
    }

    /** 点一根弦锁定，再点一次解锁。 */
    fun lockString(index: Int?) {
        lockedString = if (index == lockedString) null else index
        confirmation.restartHold()
        reading?.let { apply(it) }
    }

    fun clearTunedMarks() {
        tunedStrings = emptySet()
        confirmation.reset()
    }

    // 标准音 -------------------------------------------------------------

    fun updateA4(value: Double) {
        a4 = clampA4(value)
        smoother.reset()
        playingReference?.let { onRetuneReference?.invoke(it.frequency(a4)) }
        reading?.let { apply(PitchReading(it.frequency, it.clarity, a4)) }
    }

    fun adjustA4(delta: Double) = updateA4(a4 + delta)

    // 参考音 -------------------------------------------------------------

    fun toggleReference(pitch: Pitch) = if (playingReference == pitch) stopReference() else playReference(pitch)

    fun playReference(pitch: Pitch) {
        onPlayReference?.invoke(pitch, a4, referenceTimbre, instrument.family)
        playingReference = pitch
        reading = null; result = null
        smoother.reset()
    }

    fun stopReference() {
        if (playingReference == null) return
        onStopReference?.invoke()
        playingReference = null
        smoother.reset()
    }

    /** 拨弦类参考音自然播完了，界面上的“正在发声”跟着结束。 */
    fun referenceEnded() {
        if (playingReference != null) {
            playingReference = null
            smoother.reset()
        }
    }

    fun setTuneChime(enabled: Boolean) {
        tuneChimeEnabled = enabled
        store.putString(KEY_CHIME, if (enabled) "1" else "0")
    }

    /** 停止调音：清掉当前读数和计时（已调准的标记保留）。 */
    fun stop() {
        stopReference()
        ignoreDetectionUntil = 0.0
        smoother.reset()
        confirmation.restartHold()
        reading = null
        result = null
        isRunning = false
    }

    companion object {
        private const val KEY_CHIME = "tuner.chime"
        fun clampA4(v: Double): Double = v.roundToInt().toDouble().coerceIn(TunerDefaults.a4Range)
    }
}

/** 参考音的音色选择（正弦 / 拨弦合成 / 乐器采样）。 */
enum class ToneTimbreChoice { SINE, PLUCK, INSTRUMENT }
