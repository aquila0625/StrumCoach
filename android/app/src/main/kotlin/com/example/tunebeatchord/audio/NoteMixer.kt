package com.example.tunebeatchord.audio

/**
 * 把一个个预先渲染好的音符，按“输出里的第几个采样”排好时间混进去。和弦试听、扫弦示范、调准提示音都用它。
 * 排的时候在界面线程，混的时候在音频线程，中间用一个很短的锁；音频线程拿不到锁就跳过这一轮（下一轮补上）。
 */
class NoteMixer : AudioSource {
    private class Voice(val data: FloatArray, val start: Long, val gain: Float, val end: Long)

    private val lock = Any()
    private var voices = ArrayList<Voice>()
    @Volatile private var count = 0

    override val isActive: Boolean get() = count > 0

    /**
     * 在输出的第 `startFrame` 个采样开始放 `data`，音量 `gain`；`holdFrames` 不为 null 时，放这么久就在 `fadeFrames` 内淡出（闷音用）。
     */
    fun play(data: FloatArray, startFrame: Long, gain: Float, holdFrames: Int? = null, fadeFrames: Int = 256) {
        val end = if (holdFrames == null) Long.MAX_VALUE else startFrame + holdFrames + fadeFrames
        synchronized(lock) {
            voices.add(Voice(data, startFrame, gain, if (holdFrames == null) Long.MAX_VALUE else end))
            count = voices.size
            fade[voices.last()] = holdFrames?.let { startFrame + it } ?: Long.MAX_VALUE
        }
    }

    private val fade = java.util.IdentityHashMap<Voice, Long>()

    fun stopAll() {
        synchronized(lock) {
            voices.clear(); fade.clear(); count = 0
        }
    }

    override fun mixInto(out: FloatArray, frames: Int, frameStart: Long) {
        if (count == 0) return
        synchronized(lock) {
            val frameEnd = frameStart + frames
            val it = voices.iterator()
            while (it.hasNext()) {
                val v = it.next()
                val fadeStart = fade[v] ?: Long.MAX_VALUE
                if (v.start >= frameEnd) continue
                val from = maxOf(v.start, frameStart)
                val to = minOf(frameEnd, minOf(v.start + v.data.size, v.end))
                for (f in from until to) {
                    var g = v.gain
                    if (f >= fadeStart) {
                        val k = 1f - (f - fadeStart).toFloat() / (v.end - fadeStart).coerceAtLeast(1)
                        g *= k.coerceIn(0f, 1f)
                    }
                    out[(f - frameStart).toInt()] += v.data[(f - v.start).toInt()] * g
                }
                if (frameEnd >= minOf(v.start + v.data.size, v.end)) {
                    it.remove(); fade.remove(v)
                }
            }
            count = voices.size
        }
    }
}
