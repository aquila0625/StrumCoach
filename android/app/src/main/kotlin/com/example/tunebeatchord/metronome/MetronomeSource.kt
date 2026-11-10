package com.example.tunebeatchord.metronome

import com.example.tunebeatchord.audio.AudioSource
import java.util.concurrent.atomic.AtomicReference

/** 音频线程里发出的一个点击，加上它在输出里的绝对采样序号，界面用它对时。 */
class PlayedClick(
    val engineFrame: Long,
    val bar: Int,
    val beatInBar: Int,
    val beatsPerBar: Int,
    val subIndex: Int,
    val subdivision: com.example.tunebeatchord.rhythm.Subdivision,
    val bpm: Double,
    val muted: Boolean,
)

/**
 * 节拍器接进音频输出的一端：每个混音周期让 [ClickRenderer] 渲染一段，并把发出的点击记在一个小环里，
 * 界面线程用 `engine.frameToNanos(click.engineFrame)` 判断“这一下现在响了没有”。
 * 配置通过原子引用交给音频线程，在下一个周期交给调度器（调度器再在下一拍拍头生效）。
 */
class MetronomeSource(sampleRate: Double, initial: MetronomeConfig) : AudioSource {
    private val renderer = ClickRenderer(VoiceBank(sampleRate), initial)
    private val pendingConfig = AtomicReference<MetronomeConfig?>(null)
    @Volatile private var startRequest: MetronomeConfig? = null
    @Volatile private var stopRequested = false
    @Volatile private var running = false
    @Volatile private var tailFrames = 0
    private var scratch = FloatArray(0)

    private val ring = arrayOfNulls<PlayedClick>(RING_SIZE)
    @Volatile private var ringWrites = 0

    /** 训练方案要求的结束点到了（渐进提速选“到目标后停止”）。 */
    @Volatile var finished = false
        private set

    val isRunning: Boolean get() = running

    override val isActive: Boolean get() = running || tailFrames > 0

    fun start(config: MetronomeConfig) {
        finished = false
        stopRequested = false
        startRequest = config
        running = true
    }

    fun stop() {
        stopRequested = true
    }

    fun update(config: MetronomeConfig) {
        pendingConfig.set(config)
    }

    override fun mixInto(out: FloatArray, frames: Int, frameStart: Long) {
        startRequest?.let { startRequest = null; renderer.start(it) }
        pendingConfig.getAndSet(null)?.let { renderer.update(it) }
        if (stopRequested) {
            stopRequested = false
            renderer.stop()
            running = false
            tailFrames = (renderer.sampleRate * 0.8).toInt()
        }
        if (!running && tailFrames <= 0) return
        if (scratch.size < frames) scratch = FloatArray(frames)
        val cursor = renderer.cursor
        renderer.render(scratch, frames) { e ->
            val slot = ringWrites % RING_SIZE
            ring[slot] = PlayedClick(frameStart + (e.sample - cursor), e.bar, e.beatInBar, e.beatsPerBar, e.subIndex, e.subdivision, e.bpm, e.isTrainingMuted)
            ringWrites += 1
        }
        for (i in 0 until frames) out[i] += scratch[i]
        if (running && renderer.scheduler.isFinished) {
            finished = true
            running = false
            tailFrames = (renderer.sampleRate * 0.8).toInt()
        } else if (!running) tailFrames -= frames
    }

    /** 最近发出的点击，新的在后（最多 RING_SIZE 个）。 */
    fun recentClicks(): List<PlayedClick> {
        val writes = ringWrites
        val n = minOf(writes, RING_SIZE)
        return (writes - n until writes).mapNotNull { ring[it % RING_SIZE] }
    }

    private companion object {
        const val RING_SIZE = 32
    }
}
