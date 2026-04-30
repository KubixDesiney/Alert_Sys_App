/// Work instruction data model for AR step-by-step repair flow.
///
/// Mirrors the Firebase Realtime Database node:
///   /work_instructions/{alertType}
///       /steps/{index}
///           stepNumber, description, imageUrl?, safetyWarning?

class WorkInstructionStep {
  final int stepNumber;
  final String description;
  final String? imageUrl;
  final String? safetyWarning;
  bool isCompleted;

  WorkInstructionStep({
    required this.stepNumber,
    required this.description,
    this.imageUrl,
    this.safetyWarning,
    this.isCompleted = false,
  });

  factory WorkInstructionStep.fromMap(Map<String, dynamic> map) {
    return WorkInstructionStep(
      stepNumber: (map['stepNumber'] as num?)?.toInt() ?? 0,
      description: (map['description'] ?? '').toString(),
      imageUrl: map['imageUrl']?.toString(),
      safetyWarning: map['safetyWarning']?.toString(),
      isCompleted: map['isCompleted'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'stepNumber': stepNumber,
        'description': description,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (safetyWarning != null) 'safetyWarning': safetyWarning,
        'isCompleted': isCompleted,
      };
}

class WorkInstructions {
  final String alertType;
  final List<WorkInstructionStep> steps;

  WorkInstructions({required this.alertType, required this.steps});

  bool get allCompleted =>
      steps.isNotEmpty && steps.every((s) => s.isCompleted);

  int get completedCount => steps.where((s) => s.isCompleted).length;

  /// Builds a [WorkInstructions] from the raw value at
  /// `/work_instructions/{alertType}`.
  ///
  /// Accepts either of these RTDB shapes:
  ///   { "steps": [ {…}, {…} ] }                  // list-style
  ///   { "steps": { "0": {…}, "1": {…} } }        // map-style (RTDB common)
  factory WorkInstructions.fromMap(
    String alertType,
    Map<String, dynamic> map,
  ) {
    final raw = map['steps'];
    final List<WorkInstructionStep> parsed = [];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          parsed.add(
            WorkInstructionStep.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }
    } else if (raw is Map) {
      raw.forEach((_, v) {
        if (v is Map) {
          parsed.add(
            WorkInstructionStep.fromMap(Map<String, dynamic>.from(v)),
          );
        }
      });
    }

    parsed.sort((a, b) => a.stepNumber.compareTo(b.stepNumber));
    return WorkInstructions(alertType: alertType, steps: parsed);
  }

  Map<String, dynamic> toMap() => {
        'alertType': alertType,
        'steps': steps.map((s) => s.toMap()).toList(),
      };
}
