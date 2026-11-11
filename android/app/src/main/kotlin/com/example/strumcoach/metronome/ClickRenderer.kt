package com.example.strumcoach.metronome

/**
 * 把调度器发出的点击混成音频。渲染路径不分配内存（除了调度器每个事件产生的小对象）。
 * 音频线程调用 [render]；界面线程只通过 [BeatScheduler] 的 pending 配置交互（由宿主加锁或交换）。
 */
class ClickRenderer(val voices: VoiceBank, config: MetronomeConfig) {
    val sampleRate: Double get() = voices.sampleRate
    var scheduler = BeatScheduler(voices.sampleRate, config)
        private set

    /** 已渲染的采样总数；新一次播放的第一拍就落在这个位置。 */
    var cursor = 0L
        private set

    var masterGain = 0.9f

    private val activeData = arrayOfNulls<FloatArray>(MAX_VOICES)
    private val activeStart = LongArray(MAX_VOICES)
    private val activeGain = FloatArray(MAX_VOICES)
    private var activeCount = 0

    val isRunning: Boolean get() = scheduler.isRunning

    fun start(config: MetronomeConfig) {
        scheduler.update(config)
        scheduler.start(cursor)
    }

    fun stop() = scheduler.stop()
    fun update(config: MetronomeConfig) = scheduler.update(config)

    /** 渲染 `frames` 个采样到 `out`（单声道），期间发出的每个事件回调一次。 */
    fun render(out: FloatArray, frames: Int, onEvent: (ClickEvent) -> Unit = {}) {
        java.util.Arrays.fill(out, 0, frames, 0f)
        val start = cursor
        scheduler.generate(start, frames) { event ->
            onEvent(event)
            if (event.gain > 0) addVoice(voices.buffer(event.sound, event.level), event.sample, event.gain * masterGain)
        }
        var kept = 0
        for (v in 0 until activeCount) {
            val data = activeData[v]!!
            val voiceStart = activeStart[v]
            val gain = activeGain[v]
            val offset = maxOf(0L, voiceStart - start).toInt()
            val source = (start + offset - voiceStart).toInt()
            val n = minOf(frames - offset, data.size - source)
            if (n > 0) for (i in 0 until n) out[offset + i] += data[source + i] * gain
            if (source + maxOf(n, 0) < data.size) {
                activeData[kept] = data; activeStart[kept] = voiceStart; activeGain[kept] = gain
                kept++
            }
        }
        for (i in kept until activeCount) activeData[i] = null
        activeCount = kept
        for (i in 0 until frames) out[i] = out[i].coerceIn(-1f, 1f)
        cursor += frames
    }

    /** 预测接下来 `frames` 个采样里的点击（不改变状态），给界面高亮和触感用。 */
    fun peekClicks(frames: Int, body: (ClickEvent) -> Unit) {
        scheduler.copy().generate(cursor, frames, body)
    }

    fun peekMainBeats(frames: Int, body: (ClickEvent) -> Unit) {
        scheduler.copy().generate(cursor, frames) { if (it.isMainBeat) body(it) }
    }

    private fun addVoice(data: FloatArray, start: Long, gain: Float) {
        if (activeCount == MAX_VOICES) {
            // 槽位满了就丢掉最老的一个。
            for (i in 1 until activeCount) {
                activeData[i - 1] = activeData[i]; activeStart[i - 1] = activeStart[i]; activeGain[i - 1] = activeGain[i]
            }
            activeCount -= 1
        }
        activeData[activeCount] = data; activeStart[activeCount] = start; activeGain[activeCount] = gain
        activeCount += 1
    }

    companion object {
        const val MAX_VOICES = 32
    }
}
