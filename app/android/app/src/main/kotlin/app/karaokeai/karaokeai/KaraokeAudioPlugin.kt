package app.karaokeai.karaokeai

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

/** Bridges Dart (`app.karaokeai/{audio,tts,remote}`) to Android audio APIs. */
class KaraokeAudioPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newCachedThreadPool()
    private var micResult: MethodChannel.Result? = null
    private var session: SingSession? = null
    private var events: EventChannel.EventSink? = null
    private var mediaSession: MediaSession? = null

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val ttsPending = mutableListOf<Pair<String, MethodChannel.Result>>()
    private val ttsResults = HashMap<String, MethodChannel.Result>()

    init {
        MethodChannel(messenger, "app.karaokeai/audio").setMethodCallHandler(::onAudioCall)
        MethodChannel(messenger, "app.karaokeai/tts").setMethodCallHandler(::onTtsCall)
        EventChannel(messenger, "app.karaokeai/remote").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) { events = sink }
            override fun onCancel(args: Any?) { events = null }
        })
    }

    // ---- audio ----
    private fun onAudioCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestMicPermission" -> requestMic(result)
            "currentRoute" -> result.success(SingSession.currentRoute(activity))
            "decodeToWav" -> {
                val src = call.argument<String>("src")!!
                val dst = call.argument<String>("dst")!!
                io.execute {
                    try {
                        AudioDecoder.decodeToWav(src, dst)
                        main.post { result.success(null) }
                    } catch (e: Exception) {
                        main.post { result.error("decode", e.message, null) }
                    }
                }
            }
            "playAndRecord" -> {
                val path = call.argument<String>("path")!!
                val rate = call.argument<Int>("recordRate") ?: 16000
                if (session != null) {
                    result.error("busy", "a session is already running", null)
                    return
                }
                val s = SingSession(activity)
                session = s
                io.execute {
                    try {
                        val pcm = s.run(path, rate)
                        main.post {
                            session = null
                            result.success(mapOf("pcm" to pcm, "sampleRate" to rate))
                        }
                    } catch (e: Exception) {
                        main.post {
                            session = null
                            result.error("audio", e.message, null)
                        }
                    }
                }
            }
            "stop" -> {
                session?.stop()
                result.success(null)
            }
            "startSession" -> {
                activity.startForegroundService(Intent(activity, KaraokeService::class.java))
                startMediaSession()
                result.success(null)
            }
            "endSession" -> {
                activity.stopService(Intent(activity, KaraokeService::class.java))
                mediaSession?.release()
                mediaSession = null
                result.success(null)
            }
            "excludeFromBackup" -> result.success(null) // allowBackup=false in the manifest
            else -> result.notImplemented()
        }
    }

    private fun requestMic(result: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        micResult?.success(false)
        micResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_MIC) return
        micResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        micResult = null
    }

    // ---- remote buttons (BT media keys / steering wheel via AVRCP) ----
    private fun startMediaSession() {
        if (mediaSession != null) return
        val ms = MediaSession(activity, "KaraokeAI")
        ms.setCallback(object : MediaSession.Callback() {
            override fun onSkipToNext() { events?.success("next") }
            override fun onSkipToPrevious() { events?.success("previous") }
            override fun onPlay() { events?.success("playPause") }
            override fun onPause() { events?.success("playPause") }
        })
        ms.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS
                )
                .setState(PlaybackState.STATE_PLAYING, 0, 1f)
                .build()
        )
        ms.isActive = true
        mediaSession = ms
    }

    // ---- text to speech ----
    private fun onTtsCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "speak") {
            result.notImplemented()
            return
        }
        val text = call.argument<String>("text") ?: ""
        ensureTts()
        if (ttsReady) speakNow(text, result) else ttsPending.add(text to result)
    }

    private fun ensureTts() {
        if (tts != null) return
        tts = TextToSpeech(activity) { status ->
            main.post {
                ttsReady = status == TextToSpeech.SUCCESS
                if (ttsReady) {
                    tts?.language = Locale.JAPAN
                    tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(id: String?) {}
                        override fun onDone(id: String?) { finish(id, null) }
                        @Deprecated("Deprecated in Java")
                        override fun onError(id: String?) { finish(id, "tts error") }
                    })
                }
                val pending = ttsPending.toList()
                ttsPending.clear()
                pending.forEach { (t, r) ->
                    if (ttsReady) speakNow(t, r) else r.error("tts", "TextToSpeech unavailable", null)
                }
            }
        }
    }

    private fun finish(id: String?, error: String?) {
        main.post {
            val r = ttsResults.remove(id) ?: return@post
            if (error == null) r.success(null) else r.error("tts", error, null)
        }
    }

    private fun speakNow(text: String, result: MethodChannel.Result) {
        val id = "u${System.nanoTime()}"
        ttsResults[id] = result
        if (tts?.speak(text, TextToSpeech.QUEUE_ADD, null, id) != TextToSpeech.SUCCESS) {
            ttsResults.remove(id)
            result.error("tts", "speak failed", null)
        }
    }

    fun dispose() {
        session?.stop()
        mediaSession?.release()
        tts?.shutdown()
        io.shutdown()
    }

    companion object {
        private const val REQ_MIC = 4242
    }
}
