// Native (Android/iOS) implementation using Vosk + TTS.
// This file is never compiled for web.

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  // The archive extracted into a same-named subdirectory, so the actual
  // model root is one level deeper than the outer folder.

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
  bool _listening = false;

  Stream<String> get commandStream => _commandsController.stream;
  bool get isListening => _listening;

  Future<void> init() async {
    if (_initialized) return;
    try {
      // Manually extract the Vosk model from assets to a temp directory.
      final tempDir = await getTemporaryDirectory();
      final modelDir = Directory('${tempDir.path}/vosk-model');
      if (!modelDir.existsSync()) {
        await _extractModel(modelDir.path);
      }
      final modelPath = modelDir.path;

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
      _initialized = true;
    } catch (e, st) {
      debugPrint('VoiceService.init failed: $e\n$st');
      rethrow;
    }
  }

  /// Hardcoded list of every file in the Vosk model. Copy each one from
  /// Flutter assets into [targetDir], preserving subdirectories.
  Future<void> _extractModel(String targetDir) async {
    const files = [
      'assets/models/vosk-model-small-en-us-0.15/am/final.mdl',
      'assets/models/vosk-model-small-en-us-0.15/conf/mfcc.conf',
      'assets/models/vosk-model-small-en-us-0.15/conf/model.conf',
      'assets/models/vosk-model-small-en-us-0.15/graph/disambig_tid.int',
      'assets/models/vosk-model-small-en-us-0.15/graph/Gr.fst',
      'assets/models/vosk-model-small-en-us-0.15/graph/HCLr.fst',
      'assets/models/vosk-model-small-en-us-0.15/graph/phones/word_boundary.int',
      'assets/models/vosk-model-small-en-us-0.15/ivector/final.dubm',
      'assets/models/vosk-model-small-en-us-0.15/ivector/final.ie',
      'assets/models/vosk-model-small-en-us-0.15/ivector/final.mat',
      'assets/models/vosk-model-small-en-us-0.15/ivector/global_cmvn.stats',
      'assets/models/vosk-model-small-en-us-0.15/ivector/online_cmvn.conf',
      'assets/models/vosk-model-small-en-us-0.15/ivector/splice.conf',
      'assets/models/vosk-model-small-en-us-0.15/README',
    ];

    for (final assetPath in files) {
      final relativePath = assetPath.substring(
        'assets/models/vosk-model-small-en-us-0.15/'.length,
      );
      final targetFile = File('$targetDir/$relativePath');
      await targetFile.parent.create(recursive: true);
      final data = await rootBundle.load(assetPath);
      await targetFile.writeAsBytes(data.buffer.asUint8List());
    }
  }

  Future<void> startListening({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_initialized) await init();
    if (_listening) return;

    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      debugPrint('VoiceService: microphone permission denied');
      await speak('Microphone permission is required.');
      return;
    }

    final speech = _speechService;
    if (speech == null) {
      debugPrint(
          'VoiceService: SpeechService unavailable on $defaultTargetPlatform');
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
