package com.example.tunebeatchord.audio

import com.example.tunebeatchord.tuner.InstrumentFamily
import com.example.tunebeatchord.tuner.Pitch
import com.example.tunebeatchord.tuner.ToneTimbreChoice

/** 调音器的参考音：持续发声直到停止；拨弦类每隔一会儿重新拨一次。 */
class ReferenceTone(private val engine: AudioEngine, private val bank: SampleBank?) : AudioSource {
    private val synth = ToneSynth(engine.sampleRate.toDouble())
    private val lock = Any()
    @Volatile private var active = false
    /** 每次 play 加一；“播完了”的通知带上它，界面据此判断是不是当前这一次。 */
    @Volatile var generation = 0L
        private set

    /** 拨弦类采样自然播完时在音频线程回调一次（参数是那一次的 generation）。 */
    var onEnded: ((Long) -> Unit)? = null

    override val isActive: Boolean get() = active || synth.isSounding

    fun play(pitch: Pitch, a4: Double, timbre: ToneTimbreChoice, family: InstrumentFamily) {
        val f = pitch.frequency(a4)
        synchronized(lock) {
            synth.stop()
            synth.frequency = f
            synth.timbre = when (timbre) {
                ToneTimbreChoice.SINE -> ToneTimbre.SINE
                ToneTimbreChoice.PLUCK -> ToneTimbre.PLUCK
                ToneTimbreChoice.INSTRUMENT -> ToneTimbre.INSTRUMENT
            }
            synth.load(if (timbre == ToneTimbreChoice.INSTRUMENT) bank?.sample(Voice.fromFamily(family), f) else null)
            synth.start()
            active = true
            generation++
        }
        engine.add(this)
    }

    fun retune(frequency: Double) = synchronized(lock) { synth.retune(frequency) }

    fun stop() = synchronized(lock) { synth.stop(); active = false }

    private var scratch = FloatArray(0)

    override fun mixInto(out: FloatArray, frames: Int, frameStart: Long) {
        if (!isActive) return
        if (scratch.size < frames) scratch = FloatArray(frames)
        synchronized(lock) { synth.render(scratch, frames) }
        for (i in 0 until frames) out[i] += scratch[i]
        if (!synth.isSounding && active) {
            active = false
            onEnded?.invoke(generation)
        }
    }
}
