package com.example.tunebeatchord.audio

import com.example.tunebeatchord.chord.ChordPlayback
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.roundToInt

/** 把一次扫弦（[ChordPlayback]）排到输出的采样上。和弦库试听、扫弦示范共用。 */
class ChordSound(private val engine: AudioEngine, private val bank: SampleBank?) {
    private val mixer = NoteMixer()
    private val cache = ConcurrentHashMap<String, FloatArray>()

    /** 这一刻之后多久放出第一个音（给界面线程到音频线程的传递留余量）。 */
    var leadSeconds = 0.04

    /** 立刻放（`leadSeconds` 之后）。 */
    fun play(playback: ChordPlayback) {
        engine.add(mixer)
        play(playback, engine.currentFrame + (leadSeconds * engine.sampleRate).toLong())
    }

    /** 在输出的第 `startFrame` 个采样放出第一个音。 */
    fun play(playback: ChordPlayback, startFrame: Long) {
        engine.add(mixer)
        val sr = engine.sampleRate.toDouble()
        for (e in playback.events) {
            val hold = e.hold
            val duration = hold?.plus(0.05) ?: playback.tail
            val data = note(playback.voice, e.pitch.frequency(playback.a4), sr, duration)
            mixer.play(
                data, startFrame + (e.time * sr).roundToInt(), e.gain * GAIN,
                holdFrames = hold?.let { (it * sr).toInt() }, fadeFrames = (0.03 * sr).toInt(),
            )
        }
    }

    fun stop() = mixer.stopAll()

    private fun note(voice: Voice, frequency: Double, sr: Double, duration: Double): FloatArray {
        val key = "${voice.id}/${frequency.roundToInt()}/${(frequency * 100).roundToInt() % 100}/${sr.toInt()}/${(duration * 100).roundToInt()}"
        return cache.getOrPut(key) { InstrumentTone.render(bank, voice, frequency, sr, duration, amplitude = 1f) }
    }

    private companion object {
        const val GAIN = 0.9f
    }
}
