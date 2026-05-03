export 'predictive_models.dart';

import 'predictive_models.dart';
import 'predictive_intel_stream_service.dart';
import 'predictive_repository.dart';

/// Thin facade that keeps existing call sites stable while the data layer and
/// stream handling are split into dedicated services.
class PredictiveIntelService {
  PredictiveIntelService._()
      : repository = PredictiveRepository(),
        streams = PredictiveIntelStreamService.instance;

  static final PredictiveIntelService instance = PredictiveIntelService._();

  final PredictiveRepository repository;
  final PredictiveIntelStreamService streams;

  Stream<MorningBriefing?> briefingStream() => streams.briefingStream();
  Stream<PredictiveModel?> predictionsStream() => streams.predictionsStream();

  Future<MorningBriefing?> fetchBriefing({bool force = false}) =>
      repository.getBriefing(force: force);

  Future<PredictiveModel?> fetchPredictions({bool force = false}) =>
      repository.getPredictions(force: force);

  Future<AssigneeSuggestion?> suggestAssignee(String alertId) =>
      repository.suggestAssignee(alertId);
}
