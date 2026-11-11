package com.example.strumcoach.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaRecorder
import android.os.Process

/**
 * 麦克风收音（单声道 Float）。音频只在内存里即时分析，不保存、不上传。
 * 音源优先用 UNPROCESSED（不带自动增益和降噪，音高和起音更准），不支持时用 MIC。
 * 调用方需要先拿到录音权限。
 */
class MicCapture(val sampleRate: Int = 48_000) {
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false
    @Volatile private var framesRead = 0L

    /** 已经读到的采样总数（从 start 起算）。 */
    val frames: Long get() = framesRead

    /**
     * 开始收音。`onBuffer(buffer, count, firstFrame)` 在收音线程里回调，`buffer` 会被复用，要用就拷走。
     * 返回 false 表示打不开麦克风。
     */
    @SuppressLint("MissingPermission")
    fun start(onBuffer: (FloatArray, Int, Long) -> Unit): Boolean {
        if (running) return true
        val min = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        if (min <= 0) return false
        val size = maxOf(min, sampleRate / 5 * 4)
        fun make(source: Int) = AudioRecord.Builder()
            .setAudioSource(source)
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_FLOAT).setSampleRate(sampleRate).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build())
            .setBufferSizeInBytes(size)
            .build()
        val rec = runCatching { make(MediaRecorder.AudioSource.UNPROCESSED) }.getOrNull()?.takeIf { it.state == AudioRecord.STATE_INITIALIZED }
            ?: runCatching { make(MediaRecorder.AudioSource.MIC) }.getOrNull()?.takeIf { it.state == AudioRecord.STATE_INITIALIZED }
            ?: return false
        record = rec
        framesRead = 0
        running = true
        rec.startRecording()
        thread = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val buffer = FloatArray(sampleRate / 50)      // 20 ms
            while (running) {
                val n = rec.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                if (n <= 0) {
                    if (n < 0) break
                    continue
                }
                val first = framesRead
                framesRead += n
                onBuffer(buffer, n, first)
            }
        }, "mic-capture").also { it.priority = Thread.MAX_PRIORITY; it.start() }
        return true
    }

    /** 第 `frame` 个采样被麦克风收到的时刻（`System.nanoTime` 的时间基）；系统没给时间戳时按读取进度估算。 */
    fun frameToNanos(frame: Long): Long {
        val rec = record ?: return System.nanoTime()
        val ts = AudioTimestamp()
        return if (rec.getTimestamp(ts, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS) {
            ts.nanoTime + ((frame - ts.framePosition) * 1e9 / sampleRate).toLong()
        } else {
            System.nanoTime() - ((framesRead - frame) * 1e9 / sampleRate).toLong()
        }
    }

    fun stop() {
        running = false
        thread?.join(500)
        thread = null
        record?.let { runCatching { it.stop() }; it.release() }
        record = null
    }
}
