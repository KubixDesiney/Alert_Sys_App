import 'package:firebase_database/firebase_database.dart';

/// Per-company Guardian configuration, stored under `ai_agents/guardian/*`.
/// Additive: the console reads/writes this; the worker pipeline consumes it.
/// Token fields hold a *reference name* (e.g. ANTHROPIC_API_KEY), never a value.
enum GuardianDeployMode { auto, humanReview }

class GuardianConfig {
  final bool enabled;
  final GuardianDeployMode deployMode;
  final bool autoModelSelect;
  final String modelHigh;
  final String modelMedium;
  final String modelLow;
  final String fixTokenRef;
  final String reviewTokenRef;
  final List<String> skills;
  final String repo;

  const GuardianConfig({
    this.enabled = false,
    this.deployMode = GuardianDeployMode.humanReview,
    this.autoModelSelect = true,
    this.modelHigh = 'claude-opus-4-8',
    this.modelMedium = 'claude-sonnet-4-6',
    this.modelLow = 'claude-haiku-4-5',
    this.fixTokenRef = 'ANTHROPIC_API_KEY',
    this.reviewTokenRef = 'OPENAI_API_KEY',
    this.skills = const [],
    this.repo = '',
  });

  static const empty = GuardianConfig();

  factory GuardianConfig.fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return empty;
    String s(String k, String d) => m[k]?.toString() ?? d;
    final routing = (m['modelRouting'] is Map) ? m['modelRouting'] as Map : const {};
    final skillsRaw = m['skills'];
    return GuardianConfig(
      enabled: m['enabled'] == true,
      deployMode: s('deployMode', 'human') == 'auto'
          ? GuardianDeployMode.auto
          : GuardianDeployMode.humanReview,
      autoModelSelect: m['autoModelSelect'] != false,
      modelHigh: routing['high']?.toString() ?? 'claude-opus-4-8',
      modelMedium: routing['medium']?.toString() ?? 'claude-sonnet-4-6',
      modelLow: routing['low']?.toString() ?? 'claude-haiku-4-5',
      fixTokenRef: s('fixTokenRef', 'ANTHROPIC_API_KEY'),
      reviewTokenRef: s('reviewTokenRef', 'OPENAI_API_KEY'),
      skills: skillsRaw is List ? skillsRaw.map((e) => e.toString()).toList() : const [],
      repo: s('repo', ''),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'deployMode': deployMode == GuardianDeployMode.auto ? 'auto' : 'human',
        'autoModelSelect': autoModelSelect,
        'modelRouting': {'high': modelHigh, 'medium': modelMedium, 'low': modelLow},
        'fixTokenRef': fixTokenRef,
        'reviewTokenRef': reviewTokenRef,
        'skills': skills,
        'repo': repo,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

  GuardianConfig copyWith({
    bool? enabled,
    GuardianDeployMode? deployMode,
    bool? autoModelSelect,
    String? modelHigh,
    String? modelMedium,
    String? modelLow,
    String? fixTokenRef,
    String? reviewTokenRef,
    List<String>? skills,
    String? repo,
  }) =>
      GuardianConfig(
        enabled: enabled ?? this.enabled,
        deployMode: deployMode ?? this.deployMode,
        autoModelSelect: autoModelSelect ?? this.autoModelSelect,
        modelHigh: modelHigh ?? this.modelHigh,
        modelMedium: modelMedium ?? this.modelMedium,
        modelLow: modelLow ?? this.modelLow,
        fixTokenRef: fixTokenRef ?? this.fixTokenRef,
        reviewTokenRef: reviewTokenRef ?? this.reviewTokenRef,
        skills: skills ?? this.skills,
        repo: repo ?? this.repo,
      );
}

class GuardianConfigService {
  GuardianConfigService({FirebaseDatabase? db})
      : _ref = (db ?? FirebaseDatabase.instance).ref('ai_agents/guardian');

  final DatabaseReference _ref;

  Stream<GuardianConfig> watch() => _ref.onValue
      .map((e) => GuardianConfig.fromMap(e.snapshot.value as Map<dynamic, dynamic>?));

  Future<GuardianConfig> fetch() async =>
      GuardianConfig.fromMap((await _ref.get()).value as Map<dynamic, dynamic>?);

  Future<void> save(GuardianConfig c) => _ref.update(c.toMap());
  Future<void> setEnabled(bool v) => _ref.update({'enabled': v});
}
