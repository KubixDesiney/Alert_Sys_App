/// Pure in-memory store for reinforcement-learning score biases.
///
/// [AIScoringEngine] reads from this adjuster after computing the raw score
/// and adds a bias clamped to ±15% of that raw score. The adjuster itself
/// applies no clamping — the engine is responsible for the percentage cap.
///
/// This class has no Firebase dependency; it is injected into the engine and
/// populated by [ScoreReinforcementService] at runtime.
class ScoreAdjuster {
  final Map<String, double> _adjustments = {};

  /// Returns the current bias for [supervisorId], or 0.0 if none recorded.
  double adjustmentFor(String supervisorId) =>
      _adjustments[supervisorId] ?? 0.0;

  /// Stores [value] as the bias for [supervisorId].
  /// Typically called by [ScoreReinforcementService] after recalculating.
  void setAdjustment(String supervisorId, double value) {
    _adjustments[supervisorId] = value;
  }

  /// Bulk-loads a snapshot of adjustments (e.g. from Firebase on startup).
  void loadAll(Map<String, double> snapshot) {
    _adjustments
      ..clear()
      ..addAll(snapshot);
  }

  /// Resets all stored biases — used on logout / test teardown.
  void clear() => _adjustments.clear();

  /// Read-only view for inspection / debugging.
  Map<String, double> get all => Map.unmodifiable(_adjustments);
}
