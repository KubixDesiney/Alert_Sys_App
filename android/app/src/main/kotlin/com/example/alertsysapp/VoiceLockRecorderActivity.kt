package com.example.alertsysapp

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.core.content.ContextCompat
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Translucent, lock-screen-capable activity that captures a voice command from
 * the microphone, saves it as a 16 kHz mono WAV, and returns the file path to
 * MainActivity via setResult(). The Flutter side (FcmService / VoiceLockService)
 * then hands the file to Sherpa for offline transcription.
 *
 * Manifest requirements (already declared):
 *   android:showWhenLocked="true"   – displays above the keyguard
 *   android:turnScreenOn="true"     – wakes the screen on launch
 *   android:theme="@android:style/Theme.Translucent.NoTitleBar.Fullscreen"
 *   android:noHistory="true"
 */
class VoiceLockRecorderActivity : Activity() {

    companion object {
        const val EXTRA_TIMEOUT_MS    = "timeoutMs"
        const val RESULT_TRANSCRIPT   = "transcript"
        const val RESULT_ALTERNATIVES = "alternatives"
        const val RESULT_AUDIO_PATH   = "audioPath"

        private const val SAMPLE_RATE = 16_000
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val finished    = AtomicBoolean(false)

    @Volatile private var isRecording = false
    private var audioRecord: AudioRecord? = null
    private var recordThread: Thread?     = null
    private var audioFile: File?          = null

    private lateinit var statusLabel: TextView
    private lateinit var pulsingDot: View
    private var dotScale  = 1f
    private var dotGrowing = true

    // ─── Lifecycle ───────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val timeoutMs = intent.getIntExtra(EXTRA_TIMEOUT_MS, 6_000)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            // No mic permission – surface RESULT_CANCELED so Flutter falls back to
            // VoiceClaimScreen without blocking.
            setResult(Activity.RESULT_CANCELED)
            finish()
            return
        }

        buildUi()
        startPulsing()
        startCapture()
        mainHandler.postDelayed({ finishWithResult() }, timeoutMs.toLong())
    }

    override fun onBackPressed() = finishWithResult()

    override fun onDestroy() {
        // Defensive cleanup if the OS kills the activity before finishWithResult().
        isRecording = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        super.onDestroy()
    }

    // ─── UI ──────────────────────────────────────────────────────────────────

    private fun buildUi() {
        val dp = resources.displayMetrics.density

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.argb(185, 8, 8, 18))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding((32 * dp).toInt(), (40 * dp).toInt(), (32 * dp).toInt(), (40 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(Color.argb(238, 18, 18, 38))
                cornerRadius = 24 * dp
            }
        }
        card.layoutParams = FrameLayout.LayoutParams(
            (280 * dp).toInt(),
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER,
        )

        val dotSize = (22 * dp).toInt()
        pulsingDot = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(220, 220, 50, 50))
            }
            layoutParams = LinearLayout.LayoutParams(dotSize, dotSize).apply {
                bottomMargin = (20 * dp).toInt()
            }
        }

        statusLabel = TextView(this).apply {
            text = "Listening…"
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = (8 * dp).toInt() }
        }

        val hintLabel = TextView(this).apply {
            text = "Speak your command"
            setTextColor(Color.argb(170, 200, 200, 230))
            textSize = 13f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = (28 * dp).toInt() }
        }

        val cancelBtn = Button(this).apply {
            text = "Cancel"
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                setColor(Color.argb(90, 120, 120, 160))
                cornerRadius = 12 * dp
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                (40 * dp).toInt(),
            )
            setOnClickListener { finishWithResult() }
        }

        card.addView(pulsingDot)
        card.addView(statusLabel)
        card.addView(hintLabel)
        card.addView(cancelBtn)
        root.addView(card)
        setContentView(root)
    }

    private fun startPulsing() {
        val pulse = object : Runnable {
            override fun run() {
                if (isFinishing) return
                dotScale = if (dotGrowing) {
                    (dotScale + 0.05f).also { if (it >= 1.35f) dotGrowing = false }
                } else {
                    (dotScale - 0.05f).also { if (it <= 0.65f) dotGrowing = true }
                }
                pulsingDot.scaleX = dotScale
                pulsingDot.scaleY = dotScale
                mainHandler.postDelayed(this, 50)
            }
        }
        mainHandler.post(pulse)
    }

    // ─── Audio capture ───────────────────────────────────────────────────────

    private fun startCapture() {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufSize = maxOf(minBuf, 4096)

        val rec = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC, SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, bufSize * 4,
            )
        } catch (_: Exception) { return }

        if (rec.state != AudioRecord.STATE_INITIALIZED) { rec.release(); return }

        audioFile   = File(filesDir, "vl_${System.currentTimeMillis()}.wav")
        audioRecord = rec
        isRecording = true
        rec.startRecording()

        recordThread = Thread {
            val shortBuf = ShortArray(bufSize)
            val pcm      = ByteArrayOutputStream()

            while (isRecording) {
                val n = rec.read(shortBuf, 0, shortBuf.size)
                if (n <= 0) break
                val bytes = ByteBuffer.allocate(n * 2).order(ByteOrder.LITTLE_ENDIAN)
                repeat(n) { bytes.putShort(shortBuf[it]) }
                pcm.write(bytes.array(), 0, n * 2)
            }
            writeWav(pcm.toByteArray())
        }.apply { isDaemon = true; start() }
    }

    private fun writeWav(pcm: ByteArray) {
        val file = audioFile ?: return
        try {
            FileOutputStream(file).use { out ->
                // Standard 44-byte WAV/RIFF header: 16 kHz, mono, 16-bit PCM.
                val hdr = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
                    put("RIFF".toByteArray(Charsets.US_ASCII))
                    putInt(pcm.size + 36)                  // ChunkSize
                    put("WAVE".toByteArray(Charsets.US_ASCII))
                    put("fmt ".toByteArray(Charsets.US_ASCII))
                    putInt(16)                             // Subchunk1Size (PCM)
                    putShort(1.toShort())                  // AudioFormat: PCM
                    putShort(1.toShort())                  // NumChannels: mono
                    putInt(SAMPLE_RATE)                    // SampleRate
                    putInt(SAMPLE_RATE * 2)                // ByteRate
                    putShort(2.toShort())                  // BlockAlign
                    putShort(16.toShort())                 // BitsPerSample
                    put("data".toByteArray(Charsets.US_ASCII))
                    putInt(pcm.size)                       // Subchunk2Size
                }
                out.write(hdr.array())
                out.write(pcm)
            }
        } catch (_: Exception) {}
    }

    // ─── Result delivery ─────────────────────────────────────────────────────

    private fun finishWithResult() {
        if (!finished.compareAndSet(false, true)) return

        // Stop the recording loop so the thread can flush and write the WAV.
        isRecording = false
        audioRecord?.stop()
        // Briefly join on the main thread so the file is complete before the
        // path is delivered to Flutter. In practice this resolves in < 100 ms
        // (the thread only needs to drain its buffer and write a small WAV).
        try { recordThread?.join(900) } catch (_: InterruptedException) {}
        audioRecord?.release()
        audioRecord = null

        // Remove both the timeout callback and the pulse-animation runnables.
        mainHandler.removeCallbacksAndMessages(null)

        setResult(
            Activity.RESULT_OK,
            Intent().apply {
                putExtra(RESULT_TRANSCRIPT, "")
                putStringArrayListExtra(RESULT_ALTERNATIVES, arrayListOf())
                putExtra(RESULT_AUDIO_PATH, audioFile?.absolutePath ?: "")
            },
        )
        finish()
    }
}
