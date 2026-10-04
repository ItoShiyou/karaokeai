package app.karaokeai.karaokeai

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Decodes any MediaCodec-supported file (mp3/m4a/aac/flac/ogg/...) to a 16-bit PCM WAV. */
object AudioDecoder {
    fun decodeToWav(src: String, dst: String) {
        val extractor = MediaExtractor()
        extractor.setDataSource(src)
        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if ((f.getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) {
                trackIndex = i
                format = f
                break
            }
        }
        if (trackIndex < 0 || format == null) {
            extractor.release()
            throw IllegalArgumentException("no audio track")
        }
        extractor.selectTrack(trackIndex)
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()

        var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var floatPcm = false

        val out = RandomAccessFile(File(dst), "rw")
        out.setLength(0)
        out.write(ByteArray(44)) // header placeholder
        var dataBytes = 0L
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        try {
            while (!outputDone) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val buf = codec.getInputBuffer(inIdx)!!
                        val n = extractor.readSampleData(buf, 0)
                        if (n < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, n, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = codec.outputFormat
                        sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        floatPcm = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == android.media.AudioFormat.ENCODING_PCM_FLOAT
                    }
                    outIdx >= 0 -> {
                        val buf = codec.getOutputBuffer(outIdx)!!
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        if (info.size > 0) {
                            dataBytes += writePcm16(out, buf, floatPcm)
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }
            writeWavHeader(out, sampleRate, channels, dataBytes)
        } finally {
            out.close()
            codec.stop()
            codec.release()
            extractor.release()
        }
    }

    private fun writePcm16(out: RandomAccessFile, buf: ByteBuffer, isFloat: Boolean): Long {
        buf.order(ByteOrder.LITTLE_ENDIAN)
        if (!isFloat) {
            val bytes = ByteArray(buf.remaining())
            buf.get(bytes)
            out.write(bytes)
            return bytes.size.toLong()
        }
        val n = buf.remaining() / 4
        val bytes = ByteArray(n * 2)
        for (i in 0 until n) {
            val v = (buf.getFloat().coerceIn(-1f, 1f) * 32767f).toInt()
            bytes[i * 2] = (v and 0xFF).toByte()
            bytes[i * 2 + 1] = ((v shr 8) and 0xFF).toByte()
        }
        out.write(bytes)
        return bytes.size.toLong()
    }

    fun writeWavHeader(out: RandomAccessFile, sampleRate: Int, channels: Int, dataBytes: Long) {
        val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        h.put("RIFF".toByteArray()).putInt((36 + dataBytes).toInt())
        h.put("WAVE".toByteArray()).put("fmt ".toByteArray()).putInt(16)
        h.putShort(1).putShort(channels.toShort()).putInt(sampleRate)
        h.putInt(sampleRate * channels * 2).putShort((channels * 2).toShort()).putShort(16)
        h.put("data".toByteArray()).putInt(dataBytes.toInt())
        out.seek(0)
        out.write(h.array())
    }
}
