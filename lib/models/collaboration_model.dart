class CollaborationRequest {
  final String id;
  final String alertId;
  final String requesterId;
  final String requesterName;
  final List<String> targetSupervisorIds;
  final List<String> targetSupervisorNames;
  final String message;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime timestamp;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final bool requiresPMApproval;
  final bool pmApproved;
  final bool cancelsOriginalAlert;
  final String? usine;
  final int? convoyeur;
  final int? poste;
  final String? alertType;
  final String? alertDescription;

  CollaborationRequest({
    required this.id,
    required this.alertId,
    required this.requesterId,
    required this.requesterName,
    required this.targetSupervisorIds,
    required this.targetSupervisorNames,
    required this.message,
    required this.status,
    required this.timestamp,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.requiresPMApproval = true,
    this.pmApproved = false,
    this.cancelsOriginalAlert = false,
    this.usine,
    this.convoyeur,
    this.poste,
    this.alertType,
    this.alertDescription,
  });

  factory CollaborationRequest.fromMap(String id, Map<String, dynamic> map) {
    return CollaborationRequest(
      id: id,
      alertId: map['alertId'] ?? '',
      requesterId: map['requesterId'] ?? '',
      requesterName: map['requesterName'] ?? '',
      targetSupervisorIds: List<String>.from(map['targetSupervisorIds'] ?? []),
      targetSupervisorNames: List<String>.from(map['targetSupervisorNames'] ?? []),
      message: map['message'] ?? '',
      status: map['status'] ?? 'pending',
      timestamp: DateTime.parse(map['timestamp'] ?? DateTime.now().toIso8601String()),
      approvedBy: map['approvedBy'],
      approvedAt: map['approvedAt'] != null ? DateTime.parse(map['approvedAt']) : null,
      rejectedBy: map['rejectedBy'],
      rejectedAt: map['rejectedAt'] != null ? DateTime.parse(map['rejectedAt']) : null,
      requiresPMApproval: map['requiresPMApproval'] ?? true,
      pmApproved: map['pmApproved'] ?? false,
      cancelsOriginalAlert: map['cancelsOriginalAlert'] ?? false,
      usine: map['usine'],
      convoyeur: map['convoyeur'],
      poste: map['poste'],
      alertType: map['alertType'],
      alertDescription: map['alertDescription'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alertId': alertId,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'targetSupervisorIds': targetSupervisorIds,
      'targetSupervisorNames': targetSupervisorNames,
      'message': message,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
      'approvedBy': approvedBy,
      'approvedAt': approvedAt?.toIso8601String(),
      'rejectedBy': rejectedBy,
      'rejectedAt': rejectedAt?.toIso8601String(),
      'requiresPMApproval': requiresPMApproval,
      'pmApproved': pmApproved,
      'cancelsOriginalAlert': cancelsOriginalAlert,
      'usine': usine,
      'convoyeur': convoyeur,
      'poste': poste,
      'alertType': alertType,
      'alertDescription': alertDescription,
    };
  }
}

class EscalationSettings {
  final Map<String, EscalationThreshold> thresholds;

  EscalationSettings({required this.thresholds});

  factory EscalationSettings.fromMap(Map<String, dynamic> map) {
    final thresholds = <String, EscalationThreshold>{};
    map.forEach((key, value) {
      if (value is Map) {
        thresholds[key] = EscalationThreshold.fromMap(Map<String, dynamic>.from(value));
      }
    });
    return EscalationSettings(thresholds: thresholds);
  }

  factory EscalationSettings.defaultSettings() {
    return EscalationSettings(
      thresholds: {
        'qualite': EscalationThreshold(
          type: 'qualite',
          unclaimedMinutes: 15,
          claimedMinutes: 30,
        ),
        'maintenance': EscalationThreshold(
          type: 'maintenance',
          unclaimedMinutes: 20,
          claimedMinutes: 45,
        ),
        'defaut_produit': EscalationThreshold(
          type: 'defaut_produit',
          unclaimedMinutes: 25,
          claimedMinutes: 40,
        ),
        'manque_ressource': EscalationThreshold(
          type: 'manque_ressource',
          unclaimedMinutes: 30,
          claimedMinutes: 60,
        ),
      },
    );
  }

  Map<String, dynamic> toMap() {
    return thresholds.map((key, value) => MapEntry(key, value.toMap()));
  }
}

class EscalationThreshold {
  final String type;
  final int unclaimedMinutes;
  final int claimedMinutes;

  EscalationThreshold({
    required this.type,
    required this.unclaimedMinutes,
    required this.claimedMinutes,
  });

  factory EscalationThreshold.fromMap(Map<String, dynamic> map) {
    return EscalationThreshold(
      type: map['type'] ?? '',
      unclaimedMinutes: map['unclaimedMinutes'] ?? 0,
      claimedMinutes: map['claimedMinutes'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'unclaimedMinutes': unclaimedMinutes,
      'claimedMinutes': claimedMinutes,
    };
  }

  EscalationThreshold copyWith({
    String? type,
    int? unclaimedMinutes,
    int? claimedMinutes,
  }) {
    return EscalationThreshold(
      type: type ?? this.type,
      unclaimedMinutes: unclaimedMinutes ?? this.unclaimedMinutes,
      claimedMinutes: claimedMinutes ?? this.claimedMinutes,
    );
  }
}
