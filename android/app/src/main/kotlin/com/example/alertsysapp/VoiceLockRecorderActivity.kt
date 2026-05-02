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
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Minimal full-screen activity that captures raw PCM audio and speech-to-text
 * in parallel. Launched by MainActivity via startActivityForResult; returns
 * { EXTRA_TRANSCRIPT, EXTRA_AUDIO_PATH } on RESULT_OK.
 */
class VoiceLockRecorderActivity : Activity() {

    companion object {
        const val EXTRA_TRANSCRIPT = "transcript"
        const val EXTRA_ALTERNATIVES = "alternatives"
        const val EXTRA_AUDIO_PATH = "audioPath"
        const val EXTRA_TIMEOUT_MS = "timeoutMs"
        private const val DEFAULT_TIMEOUT_MS = 6000L
        private const val SAMPLE_RATE = 16000
    }

    private var audioRecord: AudioRecord? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private val stopped = AtomicBoolean(false)
    private val audioBuffer = ByteArrayOutputStream(SAMPLE_RATE * 8) // ~4 s preallocated
    private val mainHandler = Handler(Looper.getMainLooper())
    private var recordingThread: Thread? = null
    private var bestTranscript = ""
    private val transcriptAlternatives = linkedSetOf<String>()

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

        // 1. Start PCM capture immediately — no UI delay.
        startAudioRecording()

        // 2. Start speech-to-text in parallel.
        startSpeechRecognition()

        // 3. Hard timeout.
        val timeoutMs = intent.getIntExtra(
            EXTRA_TIMEOUT_MS,
            DEFAULT_TIMEOUT_MS.toInt()
        ).coerceIn(1000, 8000).toLong()
        mainHandler.postDelayed({ stopAndFinish(null) }, timeoutMs)

        // 4. Show minimal overlay (recording is already running by this point).
        showListeningOverlay()
    }

    @SuppressLint("MissingPermission")
    private fun startAudioRecording() {
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuffer <= 0) return

        val recorder = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBuffer * 4
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return
        }

        audioRecord = recorder
        recorder.startRecording()

        val readBuf = ByteArray(minBuffer)
        recordingThread = Thread {
            while (!stopped.get()) {
                val read = recorder.read(readBuf, 0, readBuf.size)
                if (read > 0) {
                    synchronized(audioBuffer) { audioBuffer.write(readBuf, 0, read) }
                }
            }
        }.also {
            it.isDaemon = true
            it.start()
        }
    }

    private fun startSpeechRecognition() {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) return

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle) {
                updateBestTranscript(results)
                stopAndFinish(bestTranscript)
            }

            override fun onError(error: Int) =
                stopAndFinish(bestTranscript.ifBlank { null })
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {
                mainHandler.postDelayed({
                    if (!stopped.get()) stopAndFinish(bestTranscript.ifBlank { null })
                }, 700L)
            }
            override fun onPartialResults(partialResults: Bundle?) {
                updateBestTranscript(partialResults)
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US.toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, Locale.US.toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2200L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 400L)
        }
        speechRecognizer?.startListening(intent)
    }

    private fun updateBestTranscript(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        matches
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.forEach { transcriptAlternatives.add(it) }
        val candidate = matches?.firstOrNull()?.trim().orEmpty()
        if (candidate.length >= bestTranscript.length) {
            bestTranscript = candidate
        }
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

    private fun stopAndFinish(transcript: String?) {
        if (!stopped.compareAndSet(false, true)) return
        mainHandler.removeCallbacksAndMessages(null)

        try { speechRecognizer?.stopListening() } catch (_: Exception) {}
        try { speechRecognizer?.destroy() } catch (_: Exception) {}
        speechRecognizer = null

        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null

        Thread {
            try { recordingThread?.join(300) } catch (_: Exception) {}
            recordingThread = null

            val audioPath = savePcmToFile()
            mainHandler.post {
                val data = Intent().apply {
                    putExtra(EXTRA_TRANSCRIPT, transcript ?: "")
                    putStringArrayListExtra(
                        EXTRA_ALTERNATIVES,
                        ArrayList(transcriptAlternatives)
                    )
                    putExtra(EXTRA_AUDIO_PATH, audioPath ?: "")
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
            try { speechRecognizer?.stopListening() } catch (_: Exception) {}
            try { speechRecognizer?.destroy() } catch (_: Exception) {}
            try { audioRecord?.stop() } catch (_: Exception) {}
            try { audioRecord?.release() } catch (_: Exception) {}
        }
    }
}
