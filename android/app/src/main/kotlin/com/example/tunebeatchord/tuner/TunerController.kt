package com.example.tunebeatchord.tuner

import android.os.Handler
import android.os.Looper
import com.example.tunebeatchord.audio.AudioEngine
import com.example.tunebeatchord.audio.MicCapture
import com.example.tunebeatchord.audio.NoteMixer
import com.example.tunebeatchord.audio.ReferenceTone
import com.example.tunebeatchord.audio.SampleBank
import com.example.tunebeatchord.audio.TuneChime

/**
 * 把 [TunerModel] 接到真实的麦克风和扬声器上：收音线程里按固定步长跑音高检测，结果交回主线程；
 * 参考音和“叮咚”提示音走全 App 共用的音频输出。调用方需要先拿到录音权限。
 */
class TunerController(private val engine: AudioEngine, private val bank: () -> SampleBank?, val model: TunerModel) {
    private val main = Handler(Looper.getMainLooper())
    private var mic: MicCapture? = null
    private val reference by lazy { ReferenceTone(engine, bank()) }
    private val chimeMixer = NoteMixer()
    private var chime: FloatArray? = null

    init {
        model.chimeDuration = TuneChime.DURATION
        model.playChime = {
            val data = chime ?: TuneChime.render(engine.sampleRate.toDouble()).also { chime = it }
            engine.add(chimeMixer)
            chimeMixer.play(data, engine.currentFrame + (0.03 * engine.sampleRate).toLong(), 1f)
            true
        }
        model.onPlayReference = { pitch, a4, timbre, family -> reference.play(pitch, a4, timbre, family) }
        model.onStopReference = { reference.stop() }
        model.onRetuneReference = { reference.retune(it) }
    }

    /** 开始收音；打不开麦克风时返回 false 并写 `model.errorMessage`。 */
    fun start(): Boolean {
        if (model.isRunning) return true
        val capture = MicCapture(48_000)
        val detector = PitchDetector()
        val window = PitchDetector.recommendedFrameLength(capture.sampleRate.toDouble())
        val ring = FloatArray(window)
        var filled = 0
        var head = 0                                       // 环形缓冲里下一个要写的位置，也就是最旧的采样
        var sinceDetect = 0
        val hop = capture.sampleRate * 30 / 1000          // 每 30 毫秒检测一次
        val frame = FloatArray(window)
        val ok = capture.start { buffer, count, _ ->
            for (i in 0 until count) {
                ring[head] = buffer[i]
                head = (head + 1) % window
            }
            filled = minOf(window, filled + count)
            sinceDetect += count
            if (filled >= window && sinceDetect >= hop) {
                sinceDetect = 0
                System.arraycopy(ring, head, frame, 0, window - head)
                System.arraycopy(ring, 0, frame, window - head, head)
                val raw = detector.detect(frame, capture.sampleRate.toDouble())
                main.post { if (model.isRunning) model.ingest(raw) }
            }
        }
        if (!ok) {
            model.errorMessage = "mic"
            return false
        }
        mic = capture
        model.errorMessage = null
        model.isRunning = true
        return true
    }

    fun stop() {
        mic?.stop()
        mic = null
        model.stop()
    }
}
