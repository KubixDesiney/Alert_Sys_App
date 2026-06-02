// Web voice service backed by the browser Web Speech API.
//
// Web cannot run the Android voice-enrollment path in this app, so this
// implementation is text-only and marks captures as already verified for
// dispatcher purposes. It is for in-dashboard testing and browser push-to-talk
// use.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final FlutterTts _tts = FlutterTts();
  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  JSObject? _activeRecognition;
  bool _initialized = false;
  bool _listening = false;
  bool _ttsReady = false;

  String? lastError;

  bool get isAvailable => _recognitionConstructor() != null;
  bool get isListening => _listening;
  bool get requiresVoiceEnrollment => false;
  Stream<String> get commandStream => _commandsController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (!isAvailable) {
      lastError =
          'Browser speech recognition is unavailable. Use Chrome or Edge.';
      return;
    }
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _ttsReady = true;
    } catch (_) {
      // Speech recognition is the important part on web. Browser TTS support
      // varies, so a TTS setup failure should not disable commands.
      _ttsReady = false;
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
    if (_listening) return VoiceCommandCapture.empty(sampleRate: sampleRate);

    final constructor = _recognitionConstructor();
    if (constructor == null) {
      lastError =
          'Browser speech recognition is unavailable. Use Chrome or Edge.';
      return VoiceCommandCapture.empty(sampleRate: sampleRate);
    }

    final completer = Completer<VoiceCommandCapture>();
    Timer? timeoutTimer;

    void complete(VoiceCommandCapture capture) {
      if (!completer.isCompleted) {
        completer.complete(capture);
      }
    }

    JSObject? recognition;
    try {
      recognition = constructor.callAsConstructor<JSObject>();
      _activeRecognition = recognition;

      recognition['lang'] = 'en-US'.toJS;
      recognition['continuous'] = false.toJS;
      recognition['interimResults'] = false.toJS;
      recognition['maxAlternatives'] = 3.toJS;

      recognition['onresult'] = ((JSAny? event) {
        final alternatives = _extractAlternatives(event);
        final transcript = alternatives.isEmpty ? '' : alternatives.first;
        complete(
          VoiceCommandCapture(
            transcript: transcript,
            alternatives: alternatives,
            rawAudio: null,
            sampleRate: sampleRate,
            confidence: -1,
            voiceAlreadyVerified: true,
          ),
        );
        if (recognition != null) _stopRecognition(recognition);
      }).toJS;

      recognition['onerror'] = ((JSAny? event) {
        lastError = _speechErrorMessage(event);
        complete(
          VoiceCommandCapture.empty(
            sampleRate: sampleRate,
            voiceAlreadyVerified: true,
          ),
        );
      }).toJS;

      recognition['onend'] = (() {
        complete(
          VoiceCommandCapture.empty(
            sampleRate: sampleRate,
            voiceAlreadyVerified: true,
          ),
        );
      }).toJS;

      _listening = true;
      recognition.callMethod<JSAny?>('start'.toJS);

      timeoutTimer = Timer(timeout, () {
        if (recognition != null) _stopRecognition(recognition);
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          complete(
            VoiceCommandCapture.empty(
              sampleRate: sampleRate,
              voiceAlreadyVerified: true,
            ),
          );
        });
      });

      return await completer.future;
    } catch (e) {
      lastError = 'Browser microphone capture failed: $e';
      return VoiceCommandCapture.empty(
        sampleRate: sampleRate,
        voiceAlreadyVerified: true,
      );
    } finally {
      timeoutTimer?.cancel();
      _listening = false;
      if (recognition != null && identical(_activeRecognition, recognition)) {
        _activeRecognition = null;
      }
    }
  }

  Future<Uint8List?> captureRawAudio({
    Duration duration = const Duration(milliseconds: 1800),
    int sampleRate = 16000,
  }) async {
    return null;
  }

  Future<void> stopListening() async {
    final recognition = _activeRecognition;
    if (recognition != null) {
      try {
        recognition.callMethod<JSAny?>('abort'.toJS);
      } catch (_) {}
    }
    _activeRecognition = null;
    _listening = false;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    if (!_initialized) await init();
    if (!_ttsReady) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopListening();
    await _commandsController.close();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  JSFunction? _recognitionConstructor() {
    final global = globalContext;
    for (final name in const ['SpeechRecognition', 'webkitSpeechRecognition']) {
      try {
        if (global.has(name)) {
          final value = global.getProperty<JSFunction?>(name.toJS);
          if (value != null) return value;
        }
      } catch (_) {}
    }
    return null;
  }

  void _stopRecognition(JSObject recognition) {
    try {
      recognition.callMethod<JSAny?>('stop'.toJS);
    } catch (_) {}
  }

  List<String> _extractAlternatives(JSAny? rawEvent) {
    final out = <String>[];
    try {
      if (rawEvent == null) return out;
      final event = rawEvent as JSObject;
      final results = event.getProperty<JSObject?>('results'.toJS);
      if (results == null) return out;

      final resultIndex =
          event.getProperty<JSNumber?>('resultIndex'.toJS)?.toDartInt ?? 0;
      final resultsLength =
          results.getProperty<JSNumber?>('length'.toJS)?.toDartInt ?? 0;
      for (var i = resultIndex; i < resultsLength; i++) {
        final result = results.getProperty<JSObject?>(i.toJS);
        if (result == null) continue;
        final altLength =
            result.getProperty<JSNumber?>('length'.toJS)?.toDartInt ?? 0;
        for (var j = 0; j < altLength; j++) {
          final alternative = result.getProperty<JSObject?>(j.toJS);
          if (alternative == null) continue;
          final raw = alternative
              .getProperty<JSString?>('transcript'.toJS)
              ?.toDart;
          final text = raw?.trim().toLowerCase().replaceAll(
            RegExp(r'\s+'),
            ' ',
          );
          if (text != null && text.isNotEmpty && !out.contains(text)) {
            out.add(text);
          }
        }
      }
    } catch (_) {}
    return out;
  }

  String _speechErrorMessage(JSAny? rawEvent) {
    try {
      if (rawEvent == null) return 'Browser speech recognition failed.';
      final event = rawEvent as JSObject;
      final error = event.getProperty<JSString?>('error'.toJS)?.toDart;
      switch (error) {
        case 'not-allowed':
        case 'service-not-allowed':
          return 'Microphone permission was blocked by the browser.';
        case 'no-speech':
          return 'No speech was detected.';
        case 'audio-capture':
          return 'No microphone was found by the browser.';
      }
      if (error != null && error.isNotEmpty) return error;
    } catch (_) {}
    return 'Browser speech recognition failed.';
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
