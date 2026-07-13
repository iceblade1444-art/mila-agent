package app.milaai.mila

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private val audioLock = Any()

    @Volatile
    private var audioTrack: AudioTrack? = null

    @Volatile
    private var playbackGeneration = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PCM_PLAYER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 24000
                    val generation = nextPlaybackGeneration()
                    audioExecutor.execute {
                        try {
                            if (generation == playbackGeneration) {
                                startPlayer(sampleRate)
                            }
                            runOnUiThread { result.success(null) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error("PCM_START_FAILED", error.message, null)
                            }
                        }
                    }
                }

                "write" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) {
                        result.error("PCM_INVALID_DATA", "Expected PCM byte array", null)
                    } else {
                        val generation = playbackGeneration
                        audioExecutor.execute {
                            if (generation == playbackGeneration) {
                                audioTrack?.write(bytes, 0, bytes.size, AudioTrack.WRITE_BLOCKING)
                            }
                        }
                        result.success(null)
                    }
                }

                "clear" -> {
                    queueClearPlayer()
                    result.success(null)
                }

                "stop" -> {
                    queueStopPlayer { result.success(null) }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startPlayer(sampleRate: Int) {
        synchronized(audioLock) {
            releaseTrack()

            val minimum = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            check(minimum > 0) { "Unsupported PCM output configuration" }

            val attributes = AudioAttributes.Builder()
                .setUsage(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        AudioAttributes.USAGE_ASSISTANT
                    } else {
                        AudioAttributes.USAGE_MEDIA
                    },
                )
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val builder = AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(format)
                .setBufferSizeInBytes(max(minimum * 2, sampleRate / 2))
                .setTransferMode(AudioTrack.MODE_STREAM)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            }
            audioTrack = builder.build().also { track ->
                check(track.state == AudioTrack.STATE_INITIALIZED) {
                    "Android AudioTrack could not be initialized"
                }
                track.play()
            }
        }
    }

    @Synchronized
    private fun nextPlaybackGeneration(): Int {
        playbackGeneration += 1
        return playbackGeneration
    }

    private fun queueClearPlayer() {
        val generation = nextPlaybackGeneration()
        audioExecutor.execute {
            if (generation == playbackGeneration) {
                synchronized(audioLock) {
                    audioTrack?.let { track ->
                        try {
                            track.pause()
                            track.flush()
                            track.play()
                        } catch (_: IllegalStateException) {
                            // The track may already be stopping during teardown.
                        }
                    }
                }
            }
        }
    }

    private fun queueStopPlayer(onComplete: (() -> Unit)? = null) {
        val generation = nextPlaybackGeneration()
        audioExecutor.execute {
            if (generation == playbackGeneration) {
                synchronized(audioLock) { releaseTrack() }
            }
            if (onComplete != null) {
                runOnUiThread { onComplete() }
            }
        }
    }

    private fun releaseTrack() {
        audioTrack?.let { track ->
            try {
                track.pause()
                track.flush()
                track.stop()
            } catch (_: IllegalStateException) {
                // Releasing an uninitialized or already stopped track is harmless.
            }
            track.release()
        }
        audioTrack = null
    }

    override fun onDestroy() {
        nextPlaybackGeneration()
        audioExecutor.execute {
            synchronized(audioLock) { releaseTrack() }
        }
        audioExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val PCM_PLAYER_CHANNEL = "app.milaai.mila/pcm_player"
    }
}
