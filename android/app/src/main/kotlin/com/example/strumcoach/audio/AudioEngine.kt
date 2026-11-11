package com.example.strumcoach.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Process
import java.util.concurrent.CopyOnWriteArrayList

/** 往输出里混音的一个来源。`mixInto` 在音频线程调用，不要分配内存、不要阻塞。 */
interface AudioSource {
    /** 现在还有声音要出（节拍器在播、还有没播完的音符）。全部来源都不活跃一小会儿后，输出会自动关掉省电。 */
    val isActive: Boolean

    /** 把 `frames` 个采样加进 `out`；`frameStart` 是 out[0] 在输出里的绝对采样序号。 */
    fun mixInto(out: FloatArray, frames: Int, frameStart: Long)
}

/**
 * 全 App 共用的音频输出：一个低延迟的 `AudioTrack`（单声道、Float）加一条高优先级线程，
 * 线程里循环“把各个来源混进缓冲 → 阻塞写入”。节拍器的精度来自采样计数，不依赖这条线程的定时。
 *
 * 想换成 Oboe：保持这个类的公开接口（`add` / `remove` / `currentFrame` / `frameToNanos`）不变，换掉里面的输出即可。
 */
class AudioEngine(context: Context) {
    private val appContext = context.applicationContext
    val sampleRate: Int
    private val burst: Int
    private val sources = CopyOnWriteArrayList<AudioSource>()
    private val lock = Object()
    private var thread: Thread? = null
    @Volatile private var track: AudioTrack? = null
    @Volatile private var written = 0L
    @Volatile private var stopRequested = false

    init {
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        sampleRate = am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 48_000
        burst = (am.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)?.toIntOrNull() ?: 256).coerceIn(64, 1024)
    }

    /** 已经写进输出的采样总数（也就是下一个要写的采样序号）。输出重启后从 0 重新数。 */
    val currentFrame: Long get() = written

    fun add(source: AudioSource) {
        if (source !in sources) sources.add(source)
        ensureRunning()
    }

    fun remove(source: AudioSource) {
        sources.remove(source)
    }

    /** 输出里第 `frame` 个采样被听到的时刻（`System.nanoTime` 的时间基）。取不到时间戳时按写入进度估算。 */
    fun frameToNanos(frame: Long): Long {
        val t = track ?: return System.nanoTime()
        val ts = AudioTimestamp()
        return if (t.getTimestamp(ts)) {
            ts.nanoTime + ((frame - ts.framePosition) * 1e9 / sampleRate).toLong()
        } else {
            val head = t.playbackHeadPosition.toLong() and 0xFFFFFFFFL
            System.nanoTime() + ((frame - head) * 1e9 / sampleRate).toLong()
        }
    }

    /** 输出时刻 `nanos` 对应的采样序号（`frameToNanos` 的反函数），用来把“某个时刻发声”排到采样上。 */
    fun nanosToFrame(nanos: Long): Long {
        val base = currentFrame
        val delta = nanos - frameToNanos(base)
        return base + (delta * sampleRate / 1e9).toLong()
    }

    @Synchronized
    private fun ensureRunning() {
        if (thread?.isAlive == true && !stopRequested) return
        val old = thread
        if (old != null && old.isAlive) {
            stopRequested = false
            return
        }
        stopRequested = false
        val t = Thread({ run() }, "audio-engine").also { it.priority = Thread.MAX_PRIORITY }
        thread = t
        t.start()
    }

    private fun run() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val min = AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        val audioTrack = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_FLOAT).setSampleRate(sampleRate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(min, burst * 4 * 4))
            .build()
        runCatching { audioTrack.bufferSizeInFrames = maxOf(burst * 3, 1) }
        written = 0
        track = audioTrack
        audioTrack.play()
        val buffer = FloatArray(burst)
        var idleSince = -1L
        try {
            while (!stopRequested) {
                java.util.Arrays.fill(buffer, 0f)
                var anyActive = false
                for (s in sources) {
                    s.mixInto(buffer, burst, written)
                    if (s.isActive) anyActive = true
                }
                for (i in 0 until burst) buffer[i] = buffer[i].coerceIn(-1f, 1f)
                val n = audioTrack.write(buffer, 0, burst, AudioTrack.WRITE_BLOCKING)
                if (n < 0) break
                written += n
                if (anyActive) idleSince = -1L
                else {
                    val now = System.nanoTime()
                    if (idleSince < 0) idleSince = now
                    else if (now - idleSince > 1_500_000_000L) break
                }
            }
        } finally {
            track = null
            runCatching { audioTrack.stop() }
            audioTrack.release()
            written = 0
            synchronized(lock) { }
        }
    }

    fun shutdown() {
        stopRequested = true
        sources.clear()
    }
}
