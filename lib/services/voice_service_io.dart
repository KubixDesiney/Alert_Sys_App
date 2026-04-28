import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  static const String _modelAssetPath =
      'assets/models/vosk-model-small-en-us-0.15';
  

  static const List<String> _grammar = [
    'claim alert',
    'resolve alert',
    'escalate alert',
    'with reason',
    'show dashboard',
    'show alerts',
    'show fixed',
    'zero one two three four five six seven eight nine',
    'ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen',
    'twenty thirty forty fifty sixty seventy eighty ninety',
    'hundred thousand',
    '[unk]',
  ];

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  final FlutterTts _tts = FlutterTts();
  final StreamController<String> _commandsController =
      StreamController<String>.broadcast();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  StreamSubscription? _resultSub;
  StreamSubscription? _partialSub;
  bool _initialized = false;
  bool _available = false; // ← new
  bool _listening = false;
  String? lastError;

  /// Whether the voice system is fully ready to use.
  bool get isAvailable => _available;

  Stream<String> get commandStream => _commandsController.stream;
  bool get isListening => _listening;

  Future<void> init() async {
    if (_initialized) return;

    try {
      final modelPath = await ModelLoader().loadFromAssets(_modelAssetPath);
      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
        grammar: _grammar,
      );

      if (defaultTargetPlatform == TargetPlatform.android) {
        _speechService = await _vosk.initSpeechService(_recognizer!);
      }

      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);

      _available = true; // all good
      _initialized = true;
      lastError = null;
    } catch (e, st) {
      debugPrint('VoiceService.init failed (voice disabled): $e\n$st');
      _available = false;
      _initialized = true;
      debugPrint('VoiceService.init failed: $e\n$st');
      lastError = '$e'; // ← store the error
      // DON’T rethrow – the app stays alive, just without voice
    }
  }

  Future<void> startListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_initialized) await init();
    if (!_available) {
      // No native speech – don’t crash
      return;
    }
    if (_listening) return;

    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      await speak('Microphone permission is required.');
      return;
    }

    final speech = _speechService;
    if (speech == null) {
      debugPrint('VoiceService: SpeechService unavailable');
      return;
    }

    await _resultSub?.cancel();
    await _partialSub?.cancel();

    _resultSub = speech.onResult().listen((rawJson) {
      final text = _extractTextField(rawJson);
      if (text.isNotEmpty) _commandsController.add(text);
    });
    _partialSub = speech.onPartial().listen((_) {});

    await speech.start();
    _listening = true;

    Future.delayed(timeout, () {
      if (_listening) stopListening();
    });
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    _listening = false;
    try {
      await _speechService?.stop();
    } catch (e) {
      debugPrint('VoiceService.stopListening: $e');
    }
    await _resultSub?.cancel();
    await _partialSub?.cancel();
    _resultSub = null;
    _partialSub = null;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('VoiceService.speak: $e');
    }
  }

  Future<void> dispose() async {
    await stopListening();
    await _commandsController.close();
    try {
      _recognizer?.dispose();
      _model?.dispose();
      await _tts.stop();
    } catch (_) {}
  }

  static String _extractTextField(String json) {
    final m = RegExp(r'"text"\s*:\s*"([^"]*)"').firstMatch(json);
    return m?.group(1)?.trim() ?? '';
  }
}
