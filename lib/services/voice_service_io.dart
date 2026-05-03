// Voice service used on mobile/desktop builds.
//
// STT path: speech_to_text plugin — wraps the platform's native
// SpeechRecognizer (Android) / SFSpeechRecognizer (iOS). Starts in
// tens of milliseconds (no Activity launch, no model download), and
// emits results + alternates straight to Dart.
//
// The full-screen lock-screen native flow (VoiceLockRecorderActivity)
// is only used when explicitly requested via `forceLockScreen: true` —
// e.g. when the FCM "Speak command" notification action is fired and
// the device is locked, where we cannot rely on plugin overlays.
//
// Sherpa ONNX is kept as an opportunistic transcription helper for the
// raw-PCM lock-screen path, but is no longer on the critical path.
//
// TTS: flutter_tts configured for factory floor — maximum volume, audio
// focus stealing, prefers Google's neural voice. The native MainActivity
// pumps the media stream to max via boostMediaVolume immediately before
// each speak() so prompts cut through machine noise.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'sherpa_stt_service.dart';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();
  static const MethodChannel _audioChannel = MethodChannel('alertsys/audio');
  static const MethodChannel _voiceLockChannel =
      MethodChannel('alertsys/voice_lock');

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  Timer? _listenCutoff;
  int _listenSession = 0;
  bool _initialized = false;
  bool _initInFlight = false;
  bool _available = false;
  bool _listening = false;
  bool _permissionGranted = false;
  String? lastError;

  bool get isAvailable => _available || SherpaSttService.instance.isReady;
  bool get isListening => _listening;
  bool get voskReady => SherpaSttService.instance.isReady;
  Stream<String> get commandStream => _commandsController.stream;

  /// Initializes the speech recognizer and TTS. Idempotent and safe to call
  /// from app start — runs in the background. Pre-warming this means the
  /// first tap on the mic button starts listening with no perceptible delay.
  Future<void> init() async {
    if (_initialized) return;
    if (_initInFlight) {
      // Wait for the in-flight init to finish.
      while (_initInFlight && !_initialized) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
      return;
    }
    _initInFlight = true;

    try {
      // Best-effort pre-grant of mic permission so the first listen() doesn't
      // race the OS permission dialog.
      try {
        final status = await Permission.microphone.status;
        _permissionGranted = status.isGranted;
      } catch (_) {}

      _available = await _speech.initialize(
        onError: (e) {
          debugPrint('VoiceService onError: ${e.errorMsg}');
          lastError = e.errorMsg;
        },
        onStatus: (s) => debugPrint('VoiceService status: $s'),
        debugLogging: false,
        options: [
          stt.SpeechToText.androidAlwaysUseStop,
          stt.SpeechToText.androidNoBluetooth,
        ],
      );
      await _configureFactoryTts();
      if (!_available) {
        lastError ??= 'Speech recognition not available on this device';
      }

      // Sherpa stays as a *background* warmup so the lock-screen flow can use
      // it later if it happens to be ready, but the in-app path no longer
      // waits on it.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(SherpaSttService.instance.ensureReady().then((ok) {
          if (!ok) {
            debugPrint(
                'VoiceService: sherpa_onnx not ready (using speech_to_text only)');
          }
        }));
      }
    } catch (e, st) {
      debugPrint('VoiceService.init failed: $e\n$st');
      _available = false;
      lastError = '$e';
    } finally {
      _initialized = true;
      _initInFlight = false;
    }
  }

  Future<void> _configureFactoryTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final engines = await _tts.getEngines as List<dynamic>?;
          if (engines != null) {
            final preferred = engines.cast<String>().firstWhere(
                  (e) => e.contains('google'),
                  orElse: () => '',
                );
            if (preferred.isNotEmpty) await _tts.setEngine(preferred);
          }
        } catch (_) {}

        try {
          final voices = await _tts.getVoices as List<dynamic>?;
          if (voices != null) {
            for (final raw in voices) {
              if (raw is! Map) continue;
              final voice = Map<String, String>.from(
                raw.map((k, v) => MapEntry(k.toString(), v.toString())),
              );
              final locale = voice['locale'] ?? '';
              final name = voice['name'] ?? '';
              if (locale.startsWith('en') &&
                  (name.contains('en-us-x-') || name.contains('en-US'))) {
                await _tts.setVoice({'name': name, 'locale': locale});
                break;
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('VoiceService TTS setup failed: $e');
    }
  }

  /// Push-to-talk listener for the in-app FAB. Broadcasts the best transcript
  /// captured during [timeout]. Uses speech_to_text under the hood for
  /// instant start.
  Future<void> startListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_initialized) await init();
    if (!_available || _listening) return;

    if (!await _ensureMicPermission()) {
      await speak('Microphone permission is required.');
      return;
    }

    _listening = true;
    final session = ++_listenSession;
    String bestTranscript = '';
    var emitted = false;

    Future<void> finishListen() async {
      if (emitted || session != _listenSession) return;
      emitted = true;
      final text = bestTranscript.trim();
      if (text.isNotEmpty) _commandsController.add(text);
      await stopListening();
    }

    try {
      await _speech.listen(
        onResult: (r) {
          final text = r.recognizedWords.trim();
          if (text.isNotEmpty) bestTranscript = text;
        },
        listenFor: timeout,
        pauseFor: const Duration(seconds: 4),
        localeId: 'en_US',
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
      _listenCutoff?.cancel();
      _listenCutoff = Timer(
        timeout + const Duration(milliseconds: 200),
        () => unawaited(finishListen()),
      );
    } catch (e) {
      debugPrint('VoiceService.startListening: $e');
      _listening = false;
      await _releaseAndroidAudioSession();
    }
  }

  Future<String> captureOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final capture = await captureCommandWithAudio(timeout: timeout);
    return capture.transcript;
  }

  /// Push-to-talk capture. The default path uses speech_to_text — listen()
  /// starts instantly because the recognizer is pre-initialized in init().
  ///
  /// Set [forceLockScreen] to true to force the legacy native flow
  /// (VoiceLockRecorderActivity) — only used by the FCM voice_claim notif
  /// action when the device is locked, since the plugin can't draw on top
  /// of the keyguard.
  Future<VoiceCommandCapture> captureCommandWithAudio({
    Duration timeout = const Duration(seconds: 6),
    int sampleRate = 16000,
    bool forceLockScreen = false,
  }) async {
    if (!_initialized) await init();
    if (!await _ensureMicPermission()) {
      return VoiceCommandCapture.empty(sampleRate: sampleRate);
    }

    if (forceLockScreen &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return _captureViaLockActivity(timeout, sampleRate);
    }

    return _captureViaSpeechToText(timeout, sampleRate);
  }

  Future<VoiceCommandCapture> _captureViaSpeechToText(
    Duration timeout,
    int sampleRate,
  ) async {
    if (!_available) {
      // One last attempt to bring the recognizer up.
      _initialized = false;
      await init();
      if (!_available) {
        return VoiceCommandCapture.empty(sampleRate: sampleRate);
      }
    }

    _listening = true;
    final completer = Completer<void>();
    final List<String> alternatives = [];
    String bestTranscript = '';
    Timer? cutoff;

    void recordTranscript(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return;
      bestTranscript = trimmed;
      if (!alternatives.contains(trimmed)) alternatives.add(trimmed);
    }

    try {
      // Stop any prior session before starting a new one — protects against
      // back-to-back taps that would otherwise leave the recognizer wedged.
      try {
        if (_speech.isListening) await _speech.stop();
      } catch (_) {}

      await _speech.listen(
        onResult: (r) {
          recordTranscript(r.recognizedWords);
          // speech_to_text exposes alternates via SpeechRecognitionResult —
          // capturing them helps the parser disambiguate "clean" vs "claim".
          for (final alt in r.alternates) {
            recordTranscript(alt.recognizedWords);
          }
          if (r.finalResult && !completer.isCompleted) {
            completer.complete();
          }
        },
        onSoundLevelChange: null,
        listenFor: timeout,
        pauseFor: const Duration(milliseconds: 1200),
        localeId: 'en_US',
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        ),
      );

      // Hard cap so we never hang past the timeout window.
      cutoff = Timer(timeout + const Duration(milliseconds: 600), () {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
    } catch (e) {
      debugPrint('VoiceService._captureViaSpeechToText: $e');
    } finally {
      cutoff?.cancel();
      _listening = false;
      try {
        await _speech.stop();
      } catch (_) {}
      await _releaseAndroidAudioSession();
    }

    return VoiceCommandCapture(
      transcript: bestTranscript,
      alternatives: alternatives,
      // speech_to_text doesn't expose raw PCM; biometric is gracefully
      // skipped by the dispatcher when rawAudio is null and the user is
      // already authenticated to the app.
      rawAudio: null,
      sampleRate: sampleRate,
      confidence: -1,
    );
  }

  Future<VoiceCommandCapture> _captureViaLockActivity(
    Duration timeout,
    int sampleRate,
  ) async {
    _listening = true;
    try {
      final result = await _voiceLockChannel.invokeMapMethod<String, dynamic>(
        'startVoiceLockFlow',
        {'timeoutMs': timeout.inMilliseconds},
      );
      if (result == null) {
        return VoiceCommandCapture.empty(sampleRate: sampleRate);
      }

      Uint8List? rawAudio;
      final audioPath = result['audioPath']?.toString() ?? '';
      if (audioPath.isNotEmpty) {
        final file = File(audioPath);
        try {
          rawAudio = await file.readAsBytes();
        } catch (e) {
          debugPrint('VoiceService: audio read failed: $e');
        } finally {
          try {
            await file.delete();
          } catch (_) {}
        }
      }

      // Try sherpa for transcription if it's ready; otherwise fall back to
      // an empty transcript and let the re-prompt loop handle the retry.
      String transcript = '';
      final List<String> alternatives = [];
      if (rawAudio != null && SherpaSttService.instance.isReady) {
        transcript = await SherpaSttService.instance
            .transcribe(rawAudio, sampleRate: sampleRate);
        if (transcript.isNotEmpty) alternatives.add(transcript);
      }

      return VoiceCommandCapture(
        transcript: transcript,
        alternatives: alternatives,
        rawAudio: rawAudio,
        sampleRate: sampleRate,
        confidence: -1,
      );
    } catch (e) {
      debugPrint('VoiceService._captureViaLockActivity: $e');
      return VoiceCommandCapture.empty(sampleRate: sampleRate);
    } finally {
      _listening = false;
      await _releaseAndroidAudioSession();
    }
  }

  Future<Uint8List?> captureRawAudio({
    Duration duration = const Duration(milliseconds: 1800),
    int sampleRate = 16000,
  }) async {
    if (!await _ensureMicPermission()) return null;
    await _releaseAndroidAudioSession();
    try {
      final audio = await _audioChannel.invokeMethod<Uint8List>(
        'recordPcm16',
        {'durationMs': duration.inMilliseconds, 'sampleRate': sampleRate},
      );
      return audio;
    } catch (e) {
      debugPrint('VoiceService.captureRawAudio: $e');
      return null;
    } finally {
      await _releaseAndroidAudioSession();
    }
  }

  Future<void> stopListening() async {
    _listenSession++;
    _listenCutoff?.cancel();
    _listenCutoff = null;
    if (!_listening) return;
    _listening = false;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('VoiceService.stopListening: $e');
    }
    await _releaseAndroidAudioSession();
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _audioChannel.invokeMethod('boostMediaVolume');
        } catch (_) {}
      }
      await _tts.stop();
      await _tts.speak(text, focus: true);
    } catch (e) {
      debugPrint('VoiceService.speak: $e');
    } finally {
      await _releaseAndroidAudioSession();
    }
  }

  Future<void> dispose() async {
    await stopListening();
    await _commandsController.close();
    try {
      await _tts.stop();
    } catch (_) {}
    SherpaSttService.instance.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    if (_permissionGranted) return true;
    try {
      final status = await Permission.microphone.request();
      _permissionGranted = status.isGranted;
      return _permissionGranted;
    } catch (e) {
      debugPrint('VoiceService permission error: $e');
      return false;
    }
  }

  Future<void> _releaseAndroidAudioSession() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _audioChannel.invokeMethod('releaseAudioSession');
    } catch (e) {
      debugPrint('VoiceService audio cleanup failed: $e');
    }
  }
}

class VoiceCommandCapture {
  final String transcript;
  final List<String> alternatives;
  final Uint8List? rawAudio;
  final int sampleRate;
  final double confidence;

  const VoiceCommandCapture({
    required this.transcript,
    this.alternatives = const <String>[],
    required this.rawAudio,
    required this.sampleRate,
    this.confidence = -1,
  });

  const VoiceCommandCapture.empty({required this.sampleRate})
      : transcript = '',
        alternatives = const <String>[],
        rawAudio = null,
        confidence = -1;

  Iterable<String> get transcripts sync* {
    if (transcript.trim().isNotEmpty) yield transcript.trim();
    for (final alternative in alternatives) {
      final text = alternative.trim();
      if (text.isNotEmpty && text != transcript.trim()) yield text;
    }
  }
}
