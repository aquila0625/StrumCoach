package com.example.tunebeatchord.chord

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.tunebeatchord.audio.AudioEngine
import com.example.tunebeatchord.audio.ChordSound
import com.example.tunebeatchord.audio.Voice
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
        if (state.isBass || !state.supportsStrum) {
            playBassOrSingle()
            job = scope.launch { delay(2500); isPlaying = false }
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

    private fun playBassOrSingle() {
        val voice = Voice.fromFamily(state.instrument.family)
        if (state.isBass) {
            val p = state.bassPositions ?: return
            val root = p.anchor?.pitch ?: return
            val third = p.markers(BassPositions.Role.THIRD).firstOrNull()?.pitch
            val fifth = p.markers(BassPositions.Role.FIFTH).firstOrNull()?.pitch
            val notes = listOfNotNull(root, third, fifth, root.transposed(12))
            sound.play(ChordPlayback(notes.mapIndexed { i, pitch -> PluckEvent(i * 0.45, i, pitch, 0.5f) }, voice, a4(), 1.5))
        } else {
            val v = state.voicing ?: return
            sound.play(RhythmStrum.playback(v, StrumCell.DOWN, state.chord.root, 1f, voice, a4()))
        }
    }

    /** 此刻正在响（或刚走到）的那一格；没在播放时 null。给格子条高亮用。 */
    fun activeCell(nowSeconds: Double): Int? {
        val r = playingRhythm ?: return null
        if (!isPlaying || nowSeconds < barStart) return null
        return r.cellIndex(nowSeconds - barStart, playingBpm)
    }
}
