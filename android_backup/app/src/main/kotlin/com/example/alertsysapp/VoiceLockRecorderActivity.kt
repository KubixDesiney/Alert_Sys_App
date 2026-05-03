package com.example.alertsysapp

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Full-screen push-to-talk activity that captures raw 16-bit PCM audio at
 * 16 kHz. Transcription is done on the Dart side via sherpa_onnx (offline
 * Zipformer / Whisper), so this Activity no longer contains any STT code.
 *
 * Benefits of the new split:
 *   - Simpler native code — no speech engine lifecycle, no grammar JSON
 *   - sherpa_onnx ships as a pub.dev package; no Maven AAR dependency
 *   - Same PCM buffer is used for both transcription and speaker verification
 *
 * Returns on RESULT_OK:
 *   EXTRA_AUDIO_PATH — path to the raw PCM file (sampleRate 16000, mono,
 *                      16-bit LE). Caller deletes the file after reading it.
 */
class VoiceLockRecorderActivity : Activity() {

    companion object {
        const val EXTRA_AUDIO_PATH = "audioPath"
        const val EXTRA_TIMEOUT_MS = "timeoutMs"
        // Legacy keys kept for API compatibility — returned as empty strings
        // so the Dart layer does not need a null check.
        const val EXTRA_TRANSCRIPT = "transcript"
        const val EXTRA_ALTERNATIVES = "alternatives"
        const val EXTRA_CONFIDENCE = "confidence"

        private const val DEFAULT_TIMEOUT_MS = 6000L
        private const val SAMPLE_RATE = 16000

        // Stop recording when RMS stays below this for SILENCE_MS; ensures we
        // don't capture minutes of silence on a long timeout.
        private const val SILENCE_RMS_THRESHOLD = 0.010
        private const val SILENCE_MS = 900L
    }

    private var audioRecord: AudioRecord? = null
    private val stopped = AtomicBoolean(false)
    private val audioBuffer = ByteArrayOutputStream(SAMPLE_RATE * 8)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var recordingThread: Thread? = null

    @SuppressLint("MissingPermission")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        val timeoutMs = intent.getIntExtra(
            EXTRA_TIMEOUT_MS,
            DEFAULT_TIMEOUT_MS.toInt()
        ).coerceIn(1000, 8000).toLong()

        startRecording(timeoutMs)
        mainHandler.postDelayed({ stopAndFinish() }, timeoutMs)
        showListeningOverlay()
    }

    @SuppressLint("MissingPermission")
    private fun startRecording(timeoutMs: Long) {
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuffer <= 0) return

        val readSize = maxOf(minBuffer, 1024)
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            readSize * 4
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return
        }

        audioRecord = recorder
        recorder.startRecording()

        val chunk = ByteArray(readSize)
        recordingThread = Thread {
            var lastSpeechMs = System.currentTimeMillis()
            var sawSpeech = false
            val startMs = System.currentTimeMillis()

            while (!stopped.get()) {
                val read = recorder.read(chunk, 0, chunk.size)
                if (read <= 0) continue
                synchronized(audioBuffer) { audioBuffer.write(chunk, 0, read) }

                val rms = computeRms(chunk, read)
                val now = System.currentTimeMillis()
                if (rms > SILENCE_RMS_THRESHOLD) {
                    sawSpeech = true
                    lastSpeechMs = now
                }
                // End-of-utterance: had speech, then silence for SILENCE_MS
                if (sawSpeech &&
                    now - lastSpeechMs > SILENCE_MS &&
                    now - startMs > 800
                ) {
                    mainHandler.post { stopAndFinish() }
                    return@Thread
                }
            }
        }.also {
            it.isDaemon = true
            it.start()
        }
    }

    private fun computeRms(buffer: ByteArray, length: Int): Double {
        if (length < 2) return 0.0
        var sum = 0.0
        var count = 0
        var i = 0
        while (i + 1 < length) {
            val sample = ((buffer[i + 1].toInt() shl 8) or (buffer[i].toInt() and 0xff)).toShort()
            val norm = sample / 32768.0
            sum += norm * norm
            count++
            i += 2
        }
        return if (count == 0) 0.0 else Math.sqrt(sum / count)
    }

    private fun showListeningOverlay() {
        val container = FrameLayout(this).apply {
            setBackgroundColor(0xCC000000.toInt())
        }
        container.addView(
            TextView(this).apply {
                text = "Listening…"
                textSize = 22f
                setTextColor(0xFFFFFFFF.toInt())
            },
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )
        setContentView(container)
    }

    private fun stopAndFinish() {
        if (!stopped.compareAndSet(false, true)) return
        mainHandler.removeCallbacksAndMessages(null)

        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null

        Thread {
            try { recordingThread?.join(300) } catch (_: Exception) {}
            recordingThread = null

            val audioPath = savePcmToFile()
            mainHandler.post {
                val data = Intent().apply {
                    putExtra(EXTRA_TRANSCRIPT, "")
                    putStringArrayListExtra(EXTRA_ALTERNATIVES, arrayListOf())
                    putExtra(EXTRA_AUDIO_PATH, audioPath ?: "")
                    putExtra(EXTRA_CONFIDENCE, -1.0)
                }
                setResult(RESULT_OK, data)
                finish()
            }
        }.start()
    }

    private fun savePcmToFile(): String? {
        return try {
            val bytes: ByteArray
            synchronized(audioBuffer) { bytes = audioBuffer.toByteArray() }
            if (bytes.isEmpty()) return null
            val file = File.createTempFile("voice_cmd_", ".pcm", cacheDir)
            file.writeBytes(bytes)
            file.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (!stopped.getAndSet(true)) {
            mainHandler.removeCallbacksAndMessages(null)
            try { audioRecord?.stop() } catch (_: Exception) {}
            try { audioRecord?.release() } catch (_: Exception) {}
        }
    }
}
