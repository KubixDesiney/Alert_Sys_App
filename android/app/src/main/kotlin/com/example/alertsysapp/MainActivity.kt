package com.example.alertsysapp

import android.app.Activity
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL_VOICE_LOCK  = "alertsys/voice_lock"
        const val CHANNEL_AUDIO       = "alertsys/audio"
        const val REQUEST_VOICE_LOCK  = 1001
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingVoiceLockResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerVoiceLockChannel(flutterEngine)
        registerAudioChannel(flutterEngine)
    }

    // ── alertsys/voice_lock ──────────────────────────────────────────────

    private fun registerVoiceLockChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_VOICE_LOCK)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startVoiceLockFlow" -> {
                        if (pendingVoiceLockResult != null) {
                            result.error("ALREADY_RUNNING", "Voice lock flow already active", null)
                            return@setMethodCallHandler
                        }
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 6_000
                        pendingVoiceLockResult = result
                        val intent = Intent(this, VoiceLockRecorderActivity::class.java).apply {
                            putExtra(VoiceLockRecorderActivity.EXTRA_TIMEOUT_MS, timeoutMs)
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQUEST_VOICE_LOCK)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_VOICE_LOCK) return
        val pending = pendingVoiceLockResult ?: return
        pendingVoiceLockResult = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            pending.success(
                mapOf(
                    "transcript"   to (data.getStringExtra(VoiceLockRecorderActivity.RESULT_TRANSCRIPT) ?: ""),
                    "alternatives" to (data.getStringArrayListExtra(VoiceLockRecorderActivity.RESULT_ALTERNATIVES)
                        ?: emptyList<String>()),
                    "audioPath"    to (data.getStringExtra(VoiceLockRecorderActivity.RESULT_AUDIO_PATH) ?: ""),
                )
            )
        } else {
            // Cancelled or permission denied – Flutter side gracefully falls back.
            pending.success(null)
        }
    }

    // ── alertsys/audio ───────────────────────────────────────────────────

    private fun registerAudioChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_AUDIO)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recordPcm16" -> {
                        // Returns raw little-endian 16-bit PCM for the TFLite voice-auth model.
                        // Runs on a daemon thread; result is posted back to the main thread.
                        val durationMs = call.argument<Int>("durationMs") ?: 1_800
                        val sampleRate = call.argument<Int>("sampleRate") ?: 16_000
                        Thread {
                            val pcm = recordRawPcm(durationMs, sampleRate)
                            mainHandler.post { result.success(pcm) }
                        }.apply { isDaemon = true; start() }
                    }
                    "boostMediaVolume" -> {
                        val am = getSystemService(AUDIO_SERVICE) as AudioManager
                        am.setStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            am.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                            0,
                        )
                        result.success(null)
                    }
                    "releaseAudioSession" -> {
                        @Suppress("DEPRECATION")
                        (getSystemService(AUDIO_SERVICE) as AudioManager).abandonAudioFocus(null)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun recordRawPcm(durationMs: Int, sampleRate: Int): ByteArray {
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufSize = maxOf(minBuf, 2048)
        val rec = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC, sampleRate,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize * 4,
            )
        } catch (_: Exception) { return ByteArray(0) }

        if (rec.state != AudioRecord.STATE_INITIALIZED) { rec.release(); return ByteArray(0) }

        rec.startRecording()
        val buf = ShortArray(bufSize)
        val out = ByteArrayOutputStream()
        val deadline = System.currentTimeMillis() + durationMs
        while (System.currentTimeMillis() < deadline) {
            val n = rec.read(buf, 0, buf.size)
            if (n <= 0) break
            val bytes = ByteBuffer.allocate(n * 2).order(ByteOrder.LITTLE_ENDIAN)
            repeat(n) { bytes.putShort(buf[it]) }
            out.write(bytes.array(), 0, n * 2)
        }
        rec.stop()
        rec.release()
        return out.toByteArray()
    }
}
