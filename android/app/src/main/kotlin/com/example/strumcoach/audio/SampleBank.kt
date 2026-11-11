package com.example.strumcoach.audio

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.abs
import kotlin.math.ln

@Serializable
private class EntryDto(
    val file: String,
    val midi: Int,
    val f0: Double,
    val frames: Int,
    val loopStart: Int? = null,
    val loopEnd: Int? = null,
)

@Serializable
private class VoiceDto(val sampleRate: Double, val samples: List<EntryDto>)

@Serializable
private class ManifestDto(val voices: Map<String, VoiceDto>)

/**
 * 内置的真实乐器采样库（授权见 assets/samples/LICENSES.md）：每种乐器每隔 1–3 个半音一个音，
 * 播放时用重采样把它精确调到目标频率。manifest 沿用 iOS 版，文件是转成 OGG 的同一批录音。
 *
 * @param manifestJson assets/samples/manifest.json 的内容
 * @param loader 按文件名读出采样并解码成单声道 Float（返回 null 表示读不到）；App 里读 assets，测试里可以用合成数据
 */
class SampleBank(manifestJson: String, private val loader: (file: String) -> FloatArray?) {
    private val voices: Map<String, VoiceDto> =
        runCatching { Json { ignoreUnknownKeys = true }.decodeFromString<ManifestDto>(manifestJson).voices }.getOrDefault(emptyMap())
    private val cache = object : LinkedHashMap<String, SampleBuffer>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, SampleBuffer>) = size > CACHE_LIMIT
    }

    fun hasSamples(voice: Voice) = voices[voice.id]?.samples?.isNotEmpty() == true

    /** 该乐器所有采样的 (midi, 实测基频)。 */
    fun roots(voice: Voice): List<Pair<Int, Double>> = voices[voice.id]?.samples?.map { it.midi to it.f0 } ?: emptyList()

    /** 离 `frequency` 最近（按音分）的那段采样，已解码。找不到或解码失败返回 null。 */
    @Synchronized
    fun sample(voice: Voice, nearestTo: Double): SampleBuffer? {
        if (nearestTo <= 0) return null
        val manifest = voices[voice.id] ?: return null
        val entry = manifest.samples.minByOrNull { abs(ln(nearestTo / it.f0)) } ?: return null
        cache[entry.file]?.let { return it }
        val decoded = loader(entry.file)?.let { fit(it, entry.frames) } ?: return null
        val hasLoop = entry.loopStart != null && entry.loopEnd != null && entry.loopStart < entry.loopEnd && entry.loopEnd <= decoded.size
        val buffer = SampleBuffer(
            voice, entry.midi, entry.f0, manifest.sampleRate, decoded,
            if (hasLoop) entry.loopStart else null, if (hasLoop) entry.loopEnd else null,
        )
        cache[entry.file] = buffer
        return buffer
    }

    /** 长度对齐到 manifest 里的帧数（编码器会补齐到块长）。 */
    private fun fit(data: FloatArray, frames: Int): FloatArray = if (data.size == frames) data else data.copyOf(frames)

    private companion object {
        const val CACHE_LIMIT = 40
    }
}
