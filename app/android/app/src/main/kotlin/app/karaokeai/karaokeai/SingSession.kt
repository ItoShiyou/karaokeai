package app.karaokeai.karaokeai

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/** Plays a 16-bit PCM WAV accompaniment while recording the built-in mic (mono 16-bit). */
class SingSession(private val context: Context) {
    @Volatile private var stopRequested = false

    fun stop() {
        stopRequested = true
    }

    /** Blocking. Returns recorded PCM16 LE mono bytes. */
    fun run(path: String, recordRate: Int): ByteArray {
        val wav = WavFile.open(path)
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val chMask = if (wav.channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        val minOut = AudioTrack.getMinBufferSize(wav.sampleRate, chMask, AudioFormat.ENCODING_PCM_16BIT)
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(wav.sampleRate)
                    .setChannelMask(chMask)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setBufferSizeInBytes(minOut * 2)
            .build()

        val minIn = AudioRecord.getMinBufferSize(recordRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.MIC)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(recordRate)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build()
            )
            .setBufferSizeInBytes(minIn * 4)
            .build()
        // Always the phone's own mic, never a Bluetooth (HFP) headset mic.
        am.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
            ?.let { rec.setPreferredDevice(it) }

        val recorded = ByteArrayOutputStream()
        val playbackDone = AtomicBoolean(false)
        val recThread = Thread {
            val buf = ByteArray(minIn)
            var tailBytes = recordRate * 2 * 6 / 10 // 0.6s after playback ends (covers output latency)
            while (true) {
                val n = rec.read(buf, 0, buf.size)
                if (n > 0) {
                    synchronized(recorded) { recorded.write(buf, 0, n) }
                    if (playbackDone.get()) tailBytes -= n
                }
                if (stopRequested || (playbackDone.get() && tailBytes <= 0) || n < 0) break
            }
        }

        try {
            rec.startRecording()
            recThread.start()
            track.play()
            val chunk = ByteArray(4096 * wav.channels)
            val raf = RandomAccessFile(File(path), "r")
            raf.seek(wav.dataOffset)
            var remaining = wav.dataLength
            while (remaining > 0 && !stopRequested) {
                val toRead = minOf(chunk.size.toLong(), remaining).toInt()
                val n = raf.read(chunk, 0, toRead)
                if (n <= 0) break
                track.write(chunk, 0, n) // blocking write paces playback
                remaining -= n
            }
            raf.close()
            if (!stopRequested) track.stop() // drain already-written data
            playbackDone.set(true)
            recThread.join(2000)
        } finally {
            stopRequested = true
            try { rec.stop() } catch (_: IllegalStateException) {}
            rec.release()
            try { track.stop() } catch (_: IllegalStateException) {}
            track.release()
        }
        return synchronized(recorded) { recorded.toByteArray() }
    }

    companion object {
        /** "bluetooth" | "usb" | "wired" | "speaker" for the current output. */
        fun currentRoute(context: Context): String {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val types = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { it.type }.toSet()
            return when {
                types.contains(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) ||
                    (Build.VERSION.SDK_INT >= 31 &&
                        (types.contains(AudioDeviceInfo.TYPE_BLE_HEADSET) ||
                            types.contains(AudioDeviceInfo.TYPE_BLE_SPEAKER))) -> "bluetooth"
                types.any { it == AudioDeviceInfo.TYPE_USB_DEVICE || it == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it == AudioDeviceInfo.TYPE_USB_ACCESSORY } -> "usb"
                types.any { it == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it == AudioDeviceInfo.TYPE_AUX_LINE } -> "wired"
                else -> "speaker"
            }
        }
    }
}

/** Minimal PCM16 WAV locator. */
class WavFile private constructor(
    val sampleRate: Int,
    val channels: Int,
    val dataOffset: Long,
    val dataLength: Long,
) {
    companion object {
        fun open(path: String): WavFile {
            RandomAccessFile(File(path), "r").use { f ->
                val head = ByteArray(minOf(f.length(), 4096L).toInt())
                f.readFully(head)
                val bb = ByteBuffer.wrap(head).order(ByteOrder.LITTLE_ENDIAN)
                require(String(head, 0, 4) == "RIFF" && String(head, 8, 4) == "WAVE") { "not a WAV" }
                var o = 12
                var rate = 0
                var ch = 0
                while (o + 8 <= head.size) {
                    val id = String(head, o, 4)
                    val size = bb.getInt(o + 4).toLong() and 0xFFFFFFFFL
                    if (id == "fmt ") {
                        ch = bb.getShort(o + 10).toInt()
                        rate = bb.getInt(o + 12)
                        require(bb.getShort(o + 22).toInt() == 16) { "need 16-bit PCM" }
                    } else if (id == "data") {
                        val avail = f.length() - (o + 8)
                        return WavFile(rate, ch, (o + 8).toLong(), minOf(size, avail))
                    }
                    o += 8 + size.toInt() + (size.toInt() and 1)
                }
                throw IllegalArgumentException("no data chunk")
            }
        }
    }
}
