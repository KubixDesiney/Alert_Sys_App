import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';

import 'lstm_feature_engineer.dart';
import 'lstm_network.dart';
import 'lstm_types.dart';

/// A trained model plus everything inference needs (scaler, window length).
class TrainedLstmModel {
  final LstmNetwork network;
  final FeatureScaler scaler;
  final int seqLen;
  final DateTime? trainedAt;
  final String? datasetName;
  final int sampleCount;
  final double valLoss;
  final double valAccuracy;
  final bool learning;

  const TrainedLstmModel({
    required this.network,
    required this.scaler,
    required this.seqLen,
    this.trainedAt,
    this.datasetName,
    this.sampleCount = 0,
    this.valLoss = 0,
    this.valAccuracy = 0,
    this.learning = false,
  });

  static TrainedLstmModel? fromSnapshotValue(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final weights = map['weights'];
    final scalerJson = map['scaler'];
    if (weights is! String || scalerJson is! String) return null;
    try {
      return TrainedLstmModel(
        network: LstmNetwork.fromJsonString(weights),
        scaler: FeatureScaler.fromJson(
            jsonDecode(scalerJson) as Map<String, dynamic>),
        seqLen: (map['seqLen'] as num?)?.toInt() ?? 14,
        trainedAt: DateTime.tryParse((map['trainedAt'] ?? '').toString()),
        datasetName: map['datasetName']?.toString(),
        sampleCount: (map['sampleCount'] as num?)?.toInt() ?? 0,
        valLoss: (map['valLoss'] as num?)?.toDouble() ?? 0,
        valAccuracy: (map['valAccuracy'] as num?)?.toDouble() ?? 0,
        learning: map['learning'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persists trained LSTM models and training telemetry under `ai_lstm/`.
class LstmModelStore {
  final DatabaseReference _root;

  LstmModelStore({FirebaseDatabase? database})
      : _root = (database ?? FirebaseDatabase.instance).ref('ai_lstm');

  /// Saves the trained network so every Production Manager dashboard can run
  /// on-device inference with identical weights.
  Future<void> saveModel({
    required LstmNetwork network,
    required FeatureScaler scaler,
    required int seqLen,
    required String datasetName,
    required int sampleCount,
    required double valLoss,
    required double valAccuracy,
    required bool learning,
    required List<EpochStat> epochs,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _root.child('model').set({
      'weights': network.toJsonString(),
      'scaler': jsonEncode(scaler.toJson()),
      'inputSize': network.inputSize,
      'hiddenSize': network.hiddenSize,
      'outputSize': network.outputSize,
      'seqLen': seqLen,
      'types': kLstmAlertTypes,
      'trainedAt': now,
      'datasetName': datasetName,
      'sampleCount': sampleCount,
      'valLoss': double.parse(valLoss.toStringAsFixed(6)),
      'valAccuracy': double.parse(valAccuracy.toStringAsFixed(6)),
      'learning': learning,
      'epochsRun': epochs.length,
    });
    await _root.child('history').push().set({
      'trainedAt': now,
      'datasetName': datasetName,
      'sampleCount': sampleCount,
      'valLoss': double.parse(valLoss.toStringAsFixed(6)),
      'valAccuracy': double.parse(valAccuracy.toStringAsFixed(6)),
      'learning': learning,
      'epochsRun': epochs.length,
    });
  }

  /// Mirrors live training telemetry so other admins can watch a run.
  Future<void> writeTrainingStatus({
    required String status,
    required double progress,
    required String message,
    List<EpochStat> epochs = const [],
  }) async {
    try {
      await _root.child('training/latest').set({
        'status': status,
        'progress': double.parse(progress.toStringAsFixed(4)),
        'message': message,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'epochs': epochs
            .skip(epochs.length > 120 ? epochs.length - 120 : 0)
            .map((e) => e.toMap())
            .toList(),
      });
    } catch (_) {
      // Telemetry must never break a training run.
    }
  }

  Future<TrainedLstmModel?> loadModel() async {
    final snap = await _root.child('model').get();
    return TrainedLstmModel.fromSnapshotValue(snap.value);
  }

  /// Live stream of the deployed model (null while none is trained).
  Stream<TrainedLstmModel?> modelStream() => _root
      .child('model')
      .onValue
      .map((event) => TrainedLstmModel.fromSnapshotValue(event.snapshot.value));
}
