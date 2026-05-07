// Shift entity used by the Shifts module.
//
// A shift represents a recurring time window in the factory operation.
// Time-of-day is stored in minutes-from-midnight (0..1439). Shifts may wrap
// midnight (start > end), e.g. a night shift from 22:00 → 06:00.

enum ShiftKind { morning, afternoon, night }

class AssignedSupervisor {
  final String id;
  final String name;
  final String factory;
  final String? avatarUrl;
  final bool ready;

  const AssignedSupervisor({
    required this.id,
    required this.name,
    required this.factory,
    this.avatarUrl,
    this.ready = false,
  });

  factory AssignedSupervisor.fromMap(Map<String, dynamic> m) =>
      AssignedSupervisor(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        factory: (m['factory'] ?? '').toString(),
        avatarUrl: m['avatarUrl']?.toString(),
        ready: m['ready'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'factory': factory,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'ready': ready,
      };

  AssignedSupervisor copyWith({bool? ready, String? avatarUrl}) =>
      AssignedSupervisor(
        id: id,
        name: name,
        factory: factory,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        ready: ready ?? this.ready,
      );

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class ShiftModel {
  final String id;
  final String name;

  /// Start time in minutes-from-midnight, 0..1439.
  final int startMinutes;

  /// End time in minutes-from-midnight, 0..1439.
  final int endMinutes;

  final List<AssignedSupervisor> supervisors;

  /// Maximum supervisors allowed in this shift.
  final int maxSupervisors;

  /// AI Shift Commander — when true the Cloudflare worker auto-approves
  /// collaborations and does cross-factory assignment without PM approval.
  final bool aiCommander;

  /// Llama 3.2 (Workers AI binding) is currently the only supported model.
  final String aiModel;

  /// Legacy confidence threshold kept for backward compatibility.
  final double aiConfidence;

  /// Fine-grained commander task controls.
  final bool handleAssignments;
  final bool handleCollaborations;
  final bool handleCrossFactoryTransfer;
  final bool fullControl;

  /// When true, supervisors are randomly drawn from the active pool.
  final bool randomize;

  /// ISO timestamp when the shift was created.
  final DateTime createdAt;

  /// Optional handover summary written by the worker after the shift ends.
  final String? lastHandoverSummary;
  final DateTime? lastHandoverAt;

  /// True if this shift was inserted by `seedDefault*`. Used by UI hints.
  final bool isSeeded;

  ShiftModel({
    required this.id,
    required this.name,
    required this.startMinutes,
    required this.endMinutes,
    required this.supervisors,
    required this.maxSupervisors,
    required this.aiCommander,
    required this.aiModel,
    required this.aiConfidence,
    required this.handleAssignments,
    required this.handleCollaborations,
    required this.handleCrossFactoryTransfer,
    required this.fullControl,
    required this.randomize,
    required this.createdAt,
    this.lastHandoverSummary,
    this.lastHandoverAt,
    this.isSeeded = false,
  });

  ShiftKind get kind {
    final h = startMinutes ~/ 60;
    if (h >= 5 && h < 12) return ShiftKind.morning;
    if (h >= 12 && h < 20) return ShiftKind.afternoon;
    return ShiftKind.night;
  }

  /// Total length in minutes, accounting for overnight wrap-around.
  int get durationMinutes {
    if (endMinutes >= startMinutes) return endMinutes - startMinutes;
    return (1440 - startMinutes) + endMinutes;
  }

  /// `true` when [now] (a wall-clock time) falls inside the shift window.
  bool containsTime(DateTime now) {
    final m = now.hour * 60 + now.minute;
    if (endMinutes >= startMinutes) {
      return m >= startMinutes && m < endMinutes;
    }
    return m >= startMinutes || m < endMinutes;
  }

  /// Returns 0..1 representing how far through the shift `now` is.
  /// Outside the shift window → 0.
  double progress(DateTime now) {
    if (!containsTime(now)) return 0;
    final m = now.hour * 60 + now.minute;
    int elapsed;
    if (endMinutes >= startMinutes) {
      elapsed = m - startMinutes;
    } else {
      elapsed =
          m >= startMinutes ? m - startMinutes : (1440 - startMinutes) + m;
    }
    final total = durationMinutes;
    if (total <= 0) return 0;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// Minutes remaining until the shift ends, or null if it isn't running.
  int? minutesRemaining(DateTime now) {
    if (!containsTime(now)) return null;
    final m = now.hour * 60 + now.minute;
    final endAbs = endMinutes >= startMinutes ? endMinutes : 1440 + endMinutes;
    final mAbs = m >= startMinutes ? m : 1440 + m;
    return endAbs - mAbs;
  }

  static String formatMinutes(int m) {
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  String get timeRangeLabel =>
      '${formatMinutes(startMinutes)} – ${formatMinutes(endMinutes)}';

  factory ShiftModel.fromMap(String id, Map<String, dynamic> m) {
    final hasCommanderTaskConfig = m.containsKey('handleAssignments') ||
        m.containsKey('handleCollaborations') ||
        m.containsKey('handleCrossFactoryTransfer') ||
        m.containsKey('fullControl');
    final supsRaw = m['supervisors'];
    final sups = <AssignedSupervisor>[];
    if (supsRaw is Map) {
      for (final entry in supsRaw.entries) {
        final v = entry.value;
        if (v is Map) {
          final mm = Map<String, dynamic>.from(v);
          mm['id'] = mm['id'] ?? entry.key.toString();
          sups.add(AssignedSupervisor.fromMap(mm));
        }
      }
    } else if (supsRaw is List) {
      for (final v in supsRaw) {
        if (v is Map) {
          sups.add(AssignedSupervisor.fromMap(Map<String, dynamic>.from(v)));
        }
      }
    }
    return ShiftModel(
      id: id,
      name: (m['name'] ?? 'Shift').toString(),
      startMinutes: _coerceInt(m['startMinutes'], 360),
      endMinutes: _coerceInt(m['endMinutes'], 840),
      supervisors: sups,
      maxSupervisors: _coerceInt(m['maxSupervisors'], 3),
      aiCommander: m['aiCommander'] == true,
      aiModel: (m['aiModel'] ?? 'llama-3.2-3b').toString(),
      aiConfidence: _coerceDouble(m['aiConfidence'], 0.65),
      handleAssignments: m['fullControl'] == true ||
          m['handleAssignments'] == true ||
          (!hasCommanderTaskConfig && m['aiCommander'] == true),
      handleCollaborations: m['fullControl'] == true ||
          m['handleCollaborations'] == true ||
          (!hasCommanderTaskConfig && m['aiCommander'] == true),
      handleCrossFactoryTransfer:
          m['fullControl'] == true || m['handleCrossFactoryTransfer'] == true,
      fullControl: m['fullControl'] == true,
      randomize: m['randomize'] == true,
      createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      lastHandoverSummary: m['lastHandoverSummary']?.toString(),
      lastHandoverAt: m['lastHandoverAt'] == null
          ? null
          : DateTime.tryParse(m['lastHandoverAt'].toString()),
      isSeeded: m['isSeeded'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'supervisors': {
          for (final s in supervisors) s.id: s.toMap(),
        },
        'maxSupervisors': maxSupervisors,
        'aiCommander': aiCommander,
        'aiModel': aiModel,
        'aiConfidence': aiConfidence,
        'handleAssignments': handleAssignments,
        'handleCollaborations': handleCollaborations,
        'handleCrossFactoryTransfer': handleCrossFactoryTransfer,
        'fullControl': fullControl,
        'randomize': randomize,
        'createdAt': createdAt.toIso8601String(),
        if (lastHandoverSummary != null)
          'lastHandoverSummary': lastHandoverSummary,
        if (lastHandoverAt != null)
          'lastHandoverAt': lastHandoverAt!.toIso8601String(),
        'isSeeded': isSeeded,
      };

  ShiftModel copyWith({
    String? name,
    int? startMinutes,
    int? endMinutes,
    List<AssignedSupervisor>? supervisors,
    int? maxSupervisors,
    bool? aiCommander,
    String? aiModel,
    double? aiConfidence,
    bool? handleAssignments,
    bool? handleCollaborations,
    bool? handleCrossFactoryTransfer,
    bool? fullControl,
    bool? randomize,
    String? lastHandoverSummary,
    DateTime? lastHandoverAt,
  }) =>
      ShiftModel(
        id: id,
        name: name ?? this.name,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        supervisors: supervisors ?? this.supervisors,
        maxSupervisors: maxSupervisors ?? this.maxSupervisors,
        aiCommander: aiCommander ?? this.aiCommander,
        aiModel: aiModel ?? this.aiModel,
        aiConfidence: aiConfidence ?? this.aiConfidence,
        handleAssignments: handleAssignments ?? this.handleAssignments,
        handleCollaborations: handleCollaborations ?? this.handleCollaborations,
        handleCrossFactoryTransfer:
            handleCrossFactoryTransfer ?? this.handleCrossFactoryTransfer,
        fullControl: fullControl ?? this.fullControl,
        randomize: randomize ?? this.randomize,
        createdAt: createdAt,
        lastHandoverSummary: lastHandoverSummary ?? this.lastHandoverSummary,
        lastHandoverAt: lastHandoverAt ?? this.lastHandoverAt,
        isSeeded: isSeeded,
      );
}

// ---------------------------------------------------------------------------
// ShiftLogEntry — a single AI Commander action written to shift_ai_logs/{id}
// ---------------------------------------------------------------------------

class ShiftLogEntry {
  final String id;
  final String shiftId;
  final DateTime at;

  /// Event kind: assigned, skipped, handover, created, updated, evaluate, …
  final String kind;

  final String? alertLabel;
  final String? supervisorName;
  final String? supervisorId;
  final String? factory;
  final double confidence;
  final String reason;

  const ShiftLogEntry({
    required this.id,
    required this.shiftId,
    required this.at,
    required this.kind,
    this.alertLabel,
    this.supervisorName,
    this.supervisorId,
    this.factory,
    this.confidence = 0,
    required this.reason,
  });

  factory ShiftLogEntry.fromMap(String id, Map<String, dynamic> m) =>
      ShiftLogEntry(
        id: id,
        shiftId: m['shiftId']?.toString() ?? '',
        at: DateTime.tryParse(m['at']?.toString() ?? '') ?? DateTime.now(),
        kind: m['kind']?.toString() ?? 'evaluate',
        alertLabel: m['alertLabel']?.toString(),
        supervisorName: m['supervisorName']?.toString(),
        supervisorId: m['supervisorId']?.toString(),
        factory: m['factory']?.toString(),
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
        reason: m['reason']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'shiftId': shiftId,
        'at': at.toIso8601String(),
        'kind': kind,
        if (alertLabel != null) 'alertLabel': alertLabel,
        if (supervisorName != null) 'supervisorName': supervisorName,
        if (supervisorId != null) 'supervisorId': supervisorId,
        if (factory != null) 'factory': factory,
        'confidence': confidence,
        'reason': reason,
      };
}

int _coerceInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _coerceDouble(dynamic v, double fallback) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}
