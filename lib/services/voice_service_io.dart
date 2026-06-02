// Voice service for mobile/desktop builds.
//
// Command capture uses speech_to_text for fast platform recognition. Android
// enrollment still uses the native PCM recorder through alertsys/audio so the
// existing speaker enrollment screen can keep collecting samples.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'voice_command_parser.dart';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  static const MethodChannel _audioChannel = MethodChannel('alertsys/audio');

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool _initInFlight = false;
  bool _available = false;
  bool _ttsReady = false;
  bool _listening = false;
  bool _permissionGranted = false;
  String? lastError;

  bool get isAvailable => _available;
  bool get isListening => _listening;
  bool get requiresVoiceEnrollment =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Stream<String> get commandStream => _commandsController.stream;

  Future<void> init() async {
    if (_initialized) return;
    if (_initInFlight) {
      while (_initInFlight && !_initialized) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
      return;
    }

    _initInFlight = true;
    try {
      try {
        final status = await Permission.microphone.status;
        _permissionGranted = status.isGranted;
      } catch (_) {}

      _available = await _speech.initialize(
        onError: (e) {
          lastError = e.errorMsg;
          debugPrint('VoiceService speech error: ${e.errorMsg}');
        },
        onStatus: (s) => debugPrint('VoiceService speech status: $s'),
        debugLogging: false,
        finalTimeout: const Duration(milliseconds: 1200),
        options: [
          stt.SpeechToText.androidAlwaysUseStop,
          stt.SpeechToText.androidNoBluetooth,
        ],
      );

      await _configureFactoryTts();
      _ttsReady = true;
      if (!_available) {
        lastError ??= 'Speech recognition not available on this device.';
      }
    } catch (e, st) {
      _available = false;
      lastError = '$e';
      debugPrint('VoiceService.init failed: $e\n$st');
    } finally {
      _initialized = true;
      _initInFlight = false;
    }
  }

  Future<void> _configureFactoryTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final engines = await _tts.getEngines as List<dynamic>?;
          if (engines != null) {
            final preferred = engines.cast<String>().firstWhere(
              (e) => e.toLowerCase().contains('google'),
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

  Future<String> captureOnce({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final capture = await captureCommandWithAudio(timeout: timeout);
    return capture.transcript;
  }

  Future<VoiceCommandCapture> captureCommandWithAudio({
    Duration timeout = const Duration(seconds: 6),
    Duration endSilence = const Duration(milliseconds: 800),
    int sampleRate = 16000,
    bool forceLockScreen = false,
  }) async {
    if (!_initialized) await init();
    if (!await _ensureMicPermission()) {
      lastError = 'Microphone permission denied.';
      return VoiceCommandCapture.empty(
        sampleRate: sampleRate,
        voiceAlreadyVerified: true,
      );
    }

    if (!_available) {
      _initialized = false;
      await init();
      if (!_available) {
        return VoiceCommandCapture.empty(
          sampleRate: sampleRate,
          voiceAlreadyVerified: true,
        );
      }
    }

    await _releaseAndroidAudioSession();
    return _captureViaSpeechToText(timeout, sampleRate);
  }

  Future<VoiceCommandCapture> _captureViaSpeechToText(
    Duration timeout,
    int sampleRate,
  ) async {
    _listening = true;
    final completer = Completer<void>();
    final alternatives = <String>[];
    String bestTranscript = '';
    double confidence = -1;
    Timer? cutoff;
    Timer? claimFinalGrace;
    Timer? completeClaimGrace;

    void recordTranscript(String text, [double score = -1]) {
      final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleaned.isEmpty) return;
      bestTranscript = cleaned;
      if (!alternatives.contains(cleaned)) alternatives.add(cleaned);
      if (score >= 0) confidence = score;
    }

    void completeAfterClaimGrace() {
      claimFinalGrace?.cancel();
      claimFinalGrace = Timer(const Duration(milliseconds: 2500), () {
        if (!completer.isCompleted) completer.complete();
      });
    }

    void completeAfterStableClaim() {
      completeClaimGrace?.cancel();
      completeClaimGrace = Timer(const Duration(milliseconds: 700), () {
        if (!completer.isCompleted) completer.complete();
      });
    }

    try {
      try {
        if (_speech.isListening) await _speech.stop();
      } catch (_) {}

      await _speech.listen(
        onResult: (r) {
          claimFinalGrace?.cancel();
          completeClaimGrace?.cancel();
          recordTranscript(r.recognizedWords, r.confidence);
          for (final alt in r.alternates) {
            recordTranscript(alt.recognizedWords, alt.confidence);
          }
          final command = VoiceCommandParser.parseBest(alternatives);
          final completeClaim = VoiceCommandParser.claimIsStableForAutoStop(
            command,
          );
          if (r.finalResult && !completer.isCompleted) {
            if (VoiceCommandParser.claimMayBeEarlyPartialDuringCapture(
              command,
            )) {
              completeAfterClaimGrace();
            } else {
              completer.complete();
            }
          } else if (completeClaim && !completer.isCompleted) {
            completeAfterStableClaim();
          }
        },
        listenFor: timeout,
        pauseFor: const Duration(milliseconds: 2500),
        localeId: 'en_US',
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );

      cutoff = Timer(timeout + const Duration(milliseconds: 700), () {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
    } catch (e) {
      lastError = '$e';
      debugPrint('VoiceService._captureViaSpeechToText: $e');
    } finally {
      cutoff?.cancel();
      claimFinalGrace?.cancel();
      completeClaimGrace?.cancel();
      _listening = false;
      try {
        await _speech.stop();
      } catch (_) {}
      await _releaseAndroidAudioSession();
    }

    return VoiceCommandCapture(
      transcript: bestTranscript,
      alternatives: alternatives,
      rawAudio: null,
      sampleRate: sampleRate,
      confidence: confidence,
      voiceAlreadyVerified: true,
    );
  }

  Future<Uint8List?> captureRawAudio({
    Duration duration = const Duration(seconds: 3),
    int sampleRate = 16000,
  }) async {
    if (!await _ensureMicPermission()) return null;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    await _releaseAndroidAudioSession();
    try {
      final audio = await _audioChannel.invokeMethod<Uint8List>('recordPcm16', {
        'durationMs': duration.inMilliseconds,
        'sampleRate': sampleRate,
      });
      return audio;
    } catch (e) {
      debugPrint('VoiceService.captureRawAudio: $e');
      return null;
    } finally {
      await _releaseAndroidAudioSession();
    }
  }

  Future<void> stopListening() async {
    if (_listening) {
      _listening = false;
      try {
        await _speech.stop();
      } catch (e) {
        debugPrint('VoiceService.stopListening: $e');
      }
    }
    await _releaseAndroidAudioSession();
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    if (!_ttsReady) await init();
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _audioChannel.invokeMethod('boostMediaVolume');
        } catch (_) {}
      }
      await _tts.stop();
      await _tts.speak(text);
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
    } catch (_) {}
  }
}

class VoiceCommandCapture {
  final String transcript;
  final List<String> alternatives;
  final Uint8List? rawAudio;
  final int sampleRate;
  final double confidence;
  final bool voiceAlreadyVerified;

  const VoiceCommandCapture({
    required this.transcript,
    this.alternatives = const <String>[],
    required this.rawAudio,
    required this.sampleRate,
    this.confidence = -1,
    this.voiceAlreadyVerified = false,
  });

  const VoiceCommandCapture.empty({
    required this.sampleRate,
    this.voiceAlreadyVerified = false,
  }) : transcript = '',
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
