package com.example.strumcoach.audio

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** 把 assets/samples 里的 OGG 解码成单声道 Float（用系统的 MediaExtractor + MediaCodec，不带第三方库）。 */
class AssetSampleLoader(private val context: Context) {
    fun manifestJson(): String = context.assets.open("samples/manifest.json").bufferedReader().use { it.readText() }

    fun load(file: String): FloatArray? = runCatching { decode("samples/$file") }.getOrNull()

    private fun decode(path: String): FloatArray? {
        val extractor = MediaExtractor()
        val afd = context.assets.openFd(path)
        try {
            extractor.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            extractor.selectTrack(0)
            val format = extractor.getTrackFormat(0)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            val codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()
            val pcm = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floatOutput = false
            while (!outputDone) {
                if (!inputDone) {
                    val index = codec.dequeueInputBuffer(10_000)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val out = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    out >= 0 -> {
                        val buffer = codec.getOutputBuffer(out)!!
                        val bytes = ByteArray(info.size)
                        buffer.position(info.offset)
                        buffer.get(bytes)
                        pcm.write(bytes)
                        codec.releaseOutputBuffer(out, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                    out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = codec.outputFormat
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floatOutput = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == android.media.AudioFormat.ENCODING_PCM_FLOAT
                    }
                }
            }
            codec.stop(); codec.release()
            val raw = ByteBuffer.wrap(pcm.toByteArray()).order(ByteOrder.LITTLE_ENDIAN)
            val bytesPerSample = if (floatOutput) 4 else 2
            val frames = raw.remaining() / (bytesPerSample * channels)
            val result = FloatArray(frames)
            for (i in 0 until frames) {
                // 两个声道一样（转码时双声道复制的），取第一个声道
                result[i] = if (floatOutput) raw.getFloat(i * channels * 4) else raw.getShort(i * channels * 2) / 32768f
            }
            return result
        } finally {
            extractor.release()
            afd.close()
        }
    }
}
