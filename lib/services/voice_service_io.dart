// Voice service used on mobile/desktop builds.
//
// Primary STT path (Android): audio captured by VoiceLockRecorderActivity
// (native AudioRecord), PCM bytes returned to Dart, transcribed by
// SherpaSttService (sherpa_onnx offline Zipformer). No Kotlin STT code.
//
// Fallback path: speech_to_text plugin for non-Android platforms and for
// the brief window before the sherpa_onnx model finishes downloading on a
// fresh install.
//
// TTS: flutter_tts configured for factory floor — maximum volume, audio
// focus stealing, slower rate, prefers the highest-quality available engine.
// The native MainActivity also pumps the media stream to max via
// `boostMediaVolume` immediately before each speak() so prompts cut through
// machine noise even if the user has the system slider down.

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
  bool _available = false;
  bool _listening = false;
  String? lastError;

  bool get isAvailable => _available || SherpaSttService.instance.isReady;
  bool get isListening => _listening;
  bool get voskReady => SherpaSttService.instance.isReady;
  Stream<String> get commandStream => _commandsController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Start sherpa_onnx warmup in parallel with the legacy STT init.
    // First launch downloads ~17 MB; subsequent launches are instant.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(SherpaSttService.instance.ensureReady().then((ok) {
        if (!ok) debugPrint('VoiceService: sherpa_onnx not ready, using fallback STT');
      }));
    }

    try {
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
      if (!_available && !SherpaSttService.instance.isReady) {
        lastError ??= 'Speech recognition not available on this device';
      }
    } catch (e, st) {
      debugPrint('VoiceService.init failed: $e\n$st');
      _available = false;
      lastError = '$e';
    }
  }

  /// Tunes flutter_tts for factory-floor playback:
  ///   - Volume = 1.0 (max).
  ///   - Rate = 0.45 (slower and clearer over PA-style ambient audio).
  ///   - Pitch = 1.0 (default — pitch shifts hurt intelligibility in noise).
  ///   - Awaits speech completion so re-prompts do not overlap.
  ///   - Prefers Google's neural TTS engine when present.
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
  /// captured during [timeout]. Uses the legacy speech_to_text path here
  /// because the FAB targets a continuous-listening UX where partial results
  /// are expected; the push-to-talk notification flow uses captureCommandWithAudio.
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
    if (!_initialized) await init();
    if (!_available) return '';
    if (!await _ensureMicPermission()) return '';

    final completer = Completer<String>();
    _listening = true;
    Timer? cutoff;
    String bestTranscript = '';

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
      cutoff = Timer(timeout + const Duration(milliseconds: 600), () {
        if (!completer.isCompleted) completer.complete(bestTranscript.trim());
      });
      return await completer.future;
    } catch (e) {
      debugPrint('VoiceService.captureOnce: $e');
      return '';
    } finally {
      cutoff?.cancel();
      _listening = false;
      try {
        await _speech.stop();
      } catch (_) {}
      await _releaseAndroidAudioSession();
    }
  }

  /// Full push-to-talk capture for the notification-driven claim flow.
  ///
  /// 1. VoiceLockRecorderActivity (native) captures raw PCM via AudioRecord —
  ///    the most noise-robust Android audio source for voice use cases.
  /// 2. SherpaSttService (sherpa_onnx Dart) transcribes the PCM offline.
  /// 3. The same PCM bytes are returned for speaker verification.
  ///
  /// Falls back to speech_to_text when sherpa_onnx is still downloading
  /// (first launch only).
  Future<VoiceCommandCapture> captureCommandWithAudio({
    Duration timeout = const Duration(seconds: 6),
    int sampleRate = 16000,
  }) async {
    if (!_initialized) await init();
    if (!await _ensureMicPermission()) {
      return VoiceCommandCapture.empty(sampleRate: sampleRate);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _listening = true;
      try {
        // If sherpa_onnx is still downloading, wait up to 3 s before falling
        // back to the legacy SpeechRecognizer path.
        if (!SherpaSttService.instance.isReady) {
          await SherpaSttService.instance
              .ensureReady()
              .timeout(const Duration(seconds: 3), onTimeout: () => false);
        }

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

        // Transcribe with sherpa_onnx if ready, otherwise return empty and
        // let the re-prompt loop in voice_claim_screen handle the retry.
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
        debugPrint('VoiceService.captureCommandWithAudio: $e');
      } finally {
        _listening = false;
        await _releaseAndroidAudioSession();
      }
    }

    // Non-Android fallback (web/desktop dev builds).
    final transcript = await captureOnce(timeout: timeout);
    return VoiceCommandCapture(
      transcript: transcript,
      alternatives:
          transcript.trim().isEmpty ? const <String>[] : [transcript.trim()],
      rawAudio: null,
      sampleRate: sampleRate,
      confidence: -1,
    );
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

  /// Speaks [text] at maximum volume. Pumps the media stream to max
  /// immediately before speaking so the prompt is audible over factory noise
  /// even when the device volume slider has been turned down.
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
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
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
      if (text.isNotEmpty) yield text;
    }
  }
}
