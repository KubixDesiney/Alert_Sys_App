// Presence state for a supervisor inside a specific shift.
//
// Lives at RTDB path `shift_presence/{shiftId}/{supervisorId}`. The worker
// updates `status`, `lastActiveAt`, and `inactiveSince` from alert activity
// every minute. The supervisor's mobile client writes `confirmedAt` when the
// "Confirm Presence" notification action is tapped.

enum PresenceStatus { active, inactive, absent, pendingConfirm }

class SupervisorPresence {
  final String shiftId;
  final String supervisorId;
  final String name;
  final String factory;
  final PresenceStatus status;

  /// Last time the supervisor claimed, resolved, or otherwise touched an alert.
  final DateTime? lastActiveAt;

  /// When the worker first detected the supervisor as inactive (>1h idle).
  final DateTime? inactiveSince;

  /// When the worker sent the Confirm Presence notification (pending window).
  final DateTime? confirmRequestedAt;

  /// When the pending-confirm window expires (30 min after request).
  final DateTime? confirmExpiresAt;

  /// When the supervisor tapped Confirm Presence.
  final DateTime? confirmedAt;

  /// When the worker recorded the supervisor as joining this shift.
  final DateTime? joinedAt;

  /// How long the supervisor has been in their current status (worker-set).
  final int? statusDurationSeconds;

  const SupervisorPresence({
    required this.shiftId,
    required this.supervisorId,
    required this.name,
    required this.factory,
    required this.status,
    this.lastActiveAt,
    this.inactiveSince,
    this.confirmRequestedAt,
    this.confirmExpiresAt,
    this.confirmedAt,
    this.joinedAt,
    this.statusDurationSeconds,
  });

  static PresenceStatus parseStatus(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'active':
        return PresenceStatus.active;
      case 'inactive':
        return PresenceStatus.inactive;
      case 'absent':
        return PresenceStatus.absent;
      case 'pending_confirm':
      case 'pending':
        return PresenceStatus.pendingConfirm;
      default:
        return PresenceStatus.absent;
    }
  }

  static String statusToString(PresenceStatus s) {
    switch (s) {
      case PresenceStatus.active:
        return 'active';
      case PresenceStatus.inactive:
        return 'inactive';
      case PresenceStatus.absent:
        return 'absent';
      case PresenceStatus.pendingConfirm:
        return 'pending_confirm';
    }
  }

  factory SupervisorPresence.fromMap(
    String shiftId,
    String supervisorId,
    Map<String, dynamic> m,
  ) =>
      SupervisorPresence(
        shiftId: shiftId,
        supervisorId: supervisorId,
        name: (m['name'] ?? '').toString(),
        factory: (m['factory'] ?? '').toString(),
        status: parseStatus(m['status']?.toString()),
        lastActiveAt: _parseDate(m['lastActiveAt']),
        inactiveSince: _parseDate(m['inactiveSince']),
        confirmRequestedAt: _parseDate(m['confirmRequestedAt']),
        confirmExpiresAt: _parseDate(m['confirmExpiresAt']),
        confirmedAt: _parseDate(m['confirmedAt']),
        joinedAt: _parseDate(m['joinedAt']),
        statusDurationSeconds: (m['statusDurationSeconds'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'factory': factory,
        'status': statusToString(status),
        if (lastActiveAt != null) 'lastActiveAt': lastActiveAt!.toIso8601String(),
        if (inactiveSince != null)
          'inactiveSince': inactiveSince!.toIso8601String(),
        if (confirmRequestedAt != null)
          'confirmRequestedAt': confirmRequestedAt!.toIso8601String(),
        if (confirmExpiresAt != null)
          'confirmExpiresAt': confirmExpiresAt!.toIso8601String(),
        if (confirmedAt != null) 'confirmedAt': confirmedAt!.toIso8601String(),
        if (joinedAt != null) 'joinedAt': joinedAt!.toIso8601String(),
        if (statusDurationSeconds != null)
          'statusDurationSeconds': statusDurationSeconds,
      };

  /// Human label for UI badges. Mirrors PDF labels.
  String get statusLabel {
    switch (status) {
      case PresenceStatus.active:
        return 'Active';
      case PresenceStatus.inactive:
        return 'Inactive';
      case PresenceStatus.absent:
        return 'Absent';
      case PresenceStatus.pendingConfirm:
        return 'Awaiting confirmation';
    }
  }

  /// Duration in the current status since the relevant timestamp.
  Duration? get durationInStatus {
    final now = DateTime.now();
    DateTime? anchor;
    switch (status) {
      case PresenceStatus.active:
        anchor = confirmedAt ?? lastActiveAt ?? joinedAt;
      case PresenceStatus.inactive:
        anchor = inactiveSince ?? lastActiveAt;
      case PresenceStatus.absent:
        anchor = joinedAt;
      case PresenceStatus.pendingConfirm:
        anchor = confirmRequestedAt;
    }
    if (anchor == null) return null;
    final diff = now.difference(anchor);
    return diff.isNegative ? Duration.zero : diff;
  }
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
