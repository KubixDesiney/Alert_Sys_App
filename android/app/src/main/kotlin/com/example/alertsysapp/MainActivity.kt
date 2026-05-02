package com.example.alertsysapp

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val voiceClaimChannel = "alertsys/voice_claim"
    private val audioChannel = "alertsys/audio"
    private val voiceLockChannel = "alertsys/voice_lock"
    private val voiceLockRequestCode = 9001
    private var voiceWakeLock: PowerManager.WakeLock? = null
    private var lockScreenModeEnabled = false
    private var pendingVoiceLockResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceClaimChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepareLockScreenVoice" -> {
                        runOnUiThread { prepareLockScreenVoice() }
                        result.success(lockScreenState())
                    }
                    "showOnLockScreen" -> {
                        runOnUiThread { setLockScreenFlags(true) }
                        result.success(null)
                    }
                    "clearLockScreen" -> {
                        runOnUiThread { clearLockScreenVoice() }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceLockChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startVoiceLockFlow" -> {
                        pendingVoiceLockResult?.error("CANCELLED", "Superseded by new request", null)
                        pendingVoiceLockResult = result
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 6000
                        startActivityForResult(
                            Intent(this, VoiceLockRecorderActivity::class.java).putExtra(
                                VoiceLockRecorderActivity.EXTRA_TIMEOUT_MS,
                                timeoutMs.coerceIn(1000, 8000)
                            ),
                            voiceLockRequestCode
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "releaseAudioSession" -> {
                        runOnUiThread { releaseAudioSession() }
                        result.success(null)
                    }
                    "recordPcm16" -> {
                        val durationMs = call.argument<Int>("durationMs") ?: 1800
                        val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                        recordPcm16Async(durationMs, sampleRate, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        if (lockScreenModeEnabled) {
            setLockScreenFlags(true)
        }
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == voiceLockRequestCode) {
            val pending = pendingVoiceLockResult ?: return
            pendingVoiceLockResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                pending.success(
                    mapOf(
                        "transcript" to (data.getStringExtra(VoiceLockRecorderActivity.EXTRA_TRANSCRIPT) ?: ""),
                        "alternatives" to (
                            data.getStringArrayListExtra(VoiceLockRecorderActivity.EXTRA_ALTERNATIVES)
                                ?: arrayListOf<String>()
                            ),
                        "audioPath" to (data.getStringExtra(VoiceLockRecorderActivity.EXTRA_AUDIO_PATH) ?: "")
                    )
                )
            } else {
                pending.error("CANCELLED", "Voice lock flow was cancelled", null)
            }
        }
    }

    private fun prepareLockScreenVoice() {
        setLockScreenFlags(true)
        acquireVoiceWakeLock()
        requestKeyguardDismissalIfPossible()
    }

    private fun clearLockScreenVoice() {
        setLockScreenFlags(false)
        releaseVoiceWakeLock()
    }

    private fun setLockScreenFlags(enable: Boolean) {
        lockScreenModeEnabled = enable

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enable)
            setTurnScreenOn(enable)
        } else {
            @Suppress("DEPRECATION")
            if (enable) {
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                )
            } else {
                window.clearFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                )
            }
        }
        if (enable) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireVoiceWakeLock() {
        try {
            releaseVoiceWakeLock()
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            voiceWakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "$packageName:voice_command_wake"
            ).apply {
                setReferenceCounted(false)
                acquire(2 * 60 * 1000L)
            }
        } catch (_: Exception) {
            // Best effort; showWhenLocked/turnScreenOn still cover most devices.
        }
    }

    private fun releaseVoiceWakeLock() {
        try {
            voiceWakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (_: Exception) {
        } finally {
            voiceWakeLock = null
        }
    }

    private fun requestKeyguardDismissalIfPossible() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        try {
            val keyguardManager =
                getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (!keyguardManager.isKeyguardLocked) return

            keyguardManager.requestDismissKeyguard(
                this,
                object : KeyguardManager.KeyguardDismissCallback() {}
            )
        } catch (_: Exception) {
            // Secure locks and some OEM policies refuse dismissal; the activity
            // still stays visible above the keyguard for the voice flow.
        }
    }

    private fun lockScreenState(): Map<String, Boolean> {
        val keyguardManager =
            getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val keyguardLocked = keyguardManager?.isKeyguardLocked ?: false
        val deviceSecure = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            keyguardManager?.isDeviceSecure ?: false
        } else {
            @Suppress("DEPRECATION")
            keyguardManager?.isKeyguardSecure ?: false
        }

        return mapOf(
            "keyguardLocked" to keyguardLocked,
            "deviceSecure" to deviceSecure
        )
    }

    @Suppress("DEPRECATION")
    private fun releaseAudioSession() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                audioManager.clearCommunicationDevice()
            } catch (_: Exception) {
            }
        }
        try {
            audioManager.stopBluetoothSco()
        } catch (_: Exception) {
        }
        try {
            audioManager.isBluetoothScoOn = false
        } catch (_: Exception) {
        }
        try {
            audioManager.mode = AudioManager.MODE_NORMAL
        } catch (_: Exception) {
            // Best-effort cleanup after SpeechRecognizer/TTS sessions.
        }
    }

    private fun recordPcm16Async(
        durationMs: Int,
        sampleRate: Int,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val audio = recordPcm16(durationMs.coerceIn(500, 5000), sampleRate)
                runOnUiThread { result.success(audio) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("AUDIO_RECORD_FAILED", e.message, null)
                }
            }
        }.start()
    }

    @SuppressLint("MissingPermission")
    private fun recordPcm16(durationMs: Int, sampleRate: Int): ByteArray {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Microphone permission is not granted.")
        }

        releaseAudioSession()

        val minBuffer = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuffer <= 0) {
            throw IllegalStateException("AudioRecord buffer is unavailable.")
        }

        val totalBytes = sampleRate * durationMs / 1000 * 2
        val readBuffer = ByteArray(minBuffer)
        val output = ByteArray(totalBytes)
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBuffer * 2
        )

        try {
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                throw IllegalStateException("AudioRecord failed to initialize.")
            }
            recorder.startRecording()
            var offset = 0
            while (offset < totalBytes) {
                val toRead = minOf(readBuffer.size, totalBytes - offset)
                val read = recorder.read(readBuffer, 0, toRead)
                if (read > 0) {
                    System.arraycopy(readBuffer, 0, output, offset, read)
                    offset += read
                } else if (read < 0) {
                    throw IllegalStateException("AudioRecord read failed: $read")
                }
            }
            return output
        } finally {
            try {
                recorder.stop()
            } catch (_: Exception) {
            }
            recorder.release()
            releaseAudioSession()
        }
    }
}
