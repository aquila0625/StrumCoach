package com.example.strumcoach.chord

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.strumcoach.audio.AudioEngine
import com.example.strumcoach.audio.ChordSound
import com.example.strumcoach.audio.Voice
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 和弦库的“试听”：把当前和弦的当前把位，按选中的扫弦节奏型一小节一小节地循环扫下去，直到再点一次停止。
 * 每小节开始前才读一次和弦、把位、节奏型和速度，所以演奏中换和弦会在下一小节生效。贝斯没有扫弦：依次弹根音、三度、五度、八度。
 */
class ChordPlayer(
    private val engine: AudioEngine,
    private val sound: ChordSound,
    private val state: ChordLibraryState,
    private val scope: CoroutineScope,
    private val a4: () -> Double,
    private val metronomeBpm: () -> Double,
) {
    var isPlaying by mutableStateOf(false); private set

    private var job: Job? = null
    @Volatile private var barStart = 0.0
    @Volatile private var playingRhythm: StrumRhythm? = null
    @Volatile private var playingBpm = 80.0

    private fun now() = System.nanoTime() / 1e9
    private fun frameAt(seconds: Double) = engine.nanosToFrame((seconds * 1e9).toLong())

    val effectiveBpm: Double get() = if (state.followsMetronome) metronomeBpm() else state.tempo.toDouble()

    fun toggle() = if (isPlaying) stop() else start()

    fun stop() {
        job?.cancel()
        sound.stop()
        isPlaying = false
        playingRhythm = null
    }

    fun start() {
        if (isPlaying) return
        isPlaying = true
        if (state.effectivePlayMode == ChordLibraryState.PlayMode.ARPEGGIO) {
            job = scope.launch { loopArpeggio() }
            return
        }
        job = scope.launch {
            var start = now() + 0.08
            while (isPlaying) {
                val rhythm = state.strumRhythm
                val bpm = effectiveBpm
                val voicing = state.voicing
                val chord = state.chord
                val voice = Voice.fromFamily(state.instrument.family)
                if (voicing != null) {
                    for ((i, t, cell) in rhythm.strokes(bpm)) {
                        sound.play(RhythmStrum.playback(voicing, cell, chord.root, rhythm.velocity(i), voice, a4()), frameAt(start + t))
                    }
                }
                barStart = start; playingRhythm = rhythm; playingBpm = bpm
                start += rhythm.barDuration(bpm)
                delay(((start - now() - 0.12) * 1000).toLong().coerceAtLeast(0))
            }
        }
    }

    /** 分解：把选中的指法一圈一圈地弹下去；每圈开始前才读和弦、把位、指法和速度，所以演奏中换了在下一圈生效。 */
    private suspend fun loopArpeggio() {
        var start = now() + 0.08
        while (isPlaying) {
            val loop = buildArpeggio(state.arpeggioPattern, interval = ArpeggioBuilder.noteInterval(effectiveBpm))
            if (loop == null || loop.cycle <= 0) { isPlaying = false; return }
            sound.play(loop.playback.copy(tail = minOf(1.4, 2 * loop.cycle)), frameAt(start))
            start += loop.cycle
            delay(((start - now() - 0.12) * 1000).toLong().coerceAtLeast(0))
        }
    }

    private fun buildArpeggio(pattern: ArpeggioPattern?, interval: Double): ArpeggioLoop? {
        pattern ?: return null
        val voice = Voice.fromFamily(state.instrument.family)
        return if (state.isBass) {
            if (pattern.isCustom) ArpeggioBuilder.bassCustom(pattern, state.chord, state.tuning, state.bassPositions, voice, a4(), interval)
            else ArpeggioBuilder.bassArpeggio(state.chord, state.tuning, state.bassPositions, voice, a4(), interval)
        } else {
            val v = state.voicing ?: return null
            ArpeggioBuilder.arpeggio(pattern, v, state.chord, state.tuning, voice, a4(), interval)
        }
    }

    /** 编辑自定义指法时试听一圈（只放一遍，不循环）。 */
    fun previewArpeggio(text: String) {
        val parsed = state.validateArpeggio(text)
        if (!parsed.isValid) return
        stop()
        val pattern = ArpeggioPattern(
            ArpeggioPattern.CUSTOM_PREFIX + "preview", state.instrument.family, ArpeggioPattern.Kind.Custom(parsed.steps),
            parsed.normalized, "", "",
        )
        val loop = buildArpeggio(pattern, ArpeggioBuilder.noteInterval(effectiveBpm)) ?: return
        sound.play(loop.playback.copy(tail = 1.4))
    }

    /** 编辑自定义节奏型时试听一小节（当前和弦的第一个把位，只放一遍）。`family` 不是和弦库当前的乐器时用那类乐器的默认定弦。 */
    fun previewRhythm(text: String, cellsPerBeat: Int, family: com.example.strumcoach.tuner.InstrumentFamily = state.instrument.family) {
        val parsed = StrumInput.parse(text, cellsPerBeat)
        if (!parsed.isValid || family !in ChordLibrary.strummableFamilies) return
        val same = family == state.instrument.family
        val v = if (same) state.voicing else ChordLibrary.instruments.firstOrNull { it.family == family }?.let { ChordLibrary.voicings(state.chord, it, it.defaultTuning).firstOrNull() }
        v ?: return
        val rhythm = StrumRhythm.create(StrumRhythm.CUSTOM_PREFIX + "preview", parsed.normalized, cellsPerBeat) ?: return
        stop()
        val voice = Voice.fromFamily(family)
        val bpm = effectiveBpm
        val start = frameAt(now() + 0.05)
        for ((i, t, cell) in rhythm.strokes(bpm)) {
            sound.play(RhythmStrum.playback(v, cell, state.chord.root, rhythm.velocity(i), voice, a4()), start + (t * engineRate()).toLong())
        }
    }

    private fun engineRate() = engine.sampleRate.toDouble()

    /** 此刻正在响（或刚走到）的那一格；没在播放时 null。给格子条高亮用。 */
    fun activeCell(nowSeconds: Double): Int? {
        val r = playingRhythm ?: return null
        if (!isPlaying || nowSeconds < barStart) return null
        return r.cellIndex(nowSeconds - barStart, playingBpm)
    }
}
