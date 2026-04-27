class AlertModel {
  final String id;
  final String type;
  final bool isCritical;
  final String? criticalNote; // ✅ NEW
  final String usine;
  final int convoyeur;
  final int poste;
  final String adresse;
  final DateTime timestamp;
  final String description;
  final String? assistantId;
  final String? assistantName;
  final String? helpRequestId;
  final String? helpRequesterId;
  final String? helpRequesterName;
  final String? collaborationRequestId; // ✅ NEW
  final bool isEscalated;
  final DateTime? escalatedAt;
  final bool? wasAssisted; // ✅ NEW - Track if this alert was assisted
  final String? assistedBySupervisorId; // ✅ NEW - Who supervised the assist
  final String? assistedBySupervisorName; // ✅ NEW - Name of supervisor
  final bool aiAssigned;
  final String? aiAssignmentReason;
  final double? aiConfidence;
  final DateTime? aiAssignedAt;
  final bool aiRecommendationPending;
  final String? aiRecommendationStatus;
  final String? aiRecommendedSupervisorId;
  final String? aiRecommendedSupervisorName;
  final String? aiRecommendationReason;
  String status;
  String? superviseurId;
  String? superviseurName;
  DateTime? takenAtTimestamp;
  int? elapsedTime;
  final List<String> comments;
  String? resolutionReason;
  DateTime? resolvedAt;

  AlertModel({
    required this.id,
    required this.type,
    required this.usine,
    required this.convoyeur,
    required this.poste,
    required this.adresse,
    required this.timestamp,
    required this.description,
    this.isEscalated = false,
    this.escalatedAt,
    this.assistantId,
    this.assistantName,
    this.helpRequestId,
    this.helpRequesterId,
    this.helpRequesterName,
    this.collaborationRequestId,
    this.isCritical = false,
    this.criticalNote,
    this.wasAssisted = false,
    this.assistedBySupervisorId,
    this.assistedBySupervisorName,
    this.aiAssigned = false,
    this.aiAssignmentReason,
    this.aiConfidence,
    this.aiAssignedAt,
    this.aiRecommendationPending = false,
    this.aiRecommendationStatus,
    this.aiRecommendedSupervisorId,
    this.aiRecommendedSupervisorName,
    this.aiRecommendationReason,
    this.status = 'disponible',
    this.superviseurId,
    this.superviseurName,
    this.takenAtTimestamp,
    this.elapsedTime,
    this.comments = const [],
    this.resolutionReason,
    this.resolvedAt,
  });

  factory AlertModel.fromMap(String id, Map<String, dynamic> data) {
    return AlertModel(
      id: id,
      type: data['type'] ?? 'qualite',
      isCritical: data['isCritical'] ?? false,
      criticalNote: data['criticalNote'],
      usine: data['usine'] ?? 'Usine A',
      convoyeur: (data['convoyeur'] as num?)?.toInt() ?? 1,
      poste: (data['poste'] as num?)?.toInt() ?? 1,
      adresse: data['adresse'] ?? data['poste_id'] ?? '',
      timestamp: _parseDate(data['timestamp']),
      description: data['description'] ?? data['message'] ?? '',
      assistantId: data['assistantId'],
      assistantName: data['assistantName'],
      helpRequestId: data['helpRequestId'],
      helpRequesterId: data['helpRequesterId'],
      helpRequesterName: data['helpRequesterName'],
      collaborationRequestId: data['collaborationRequestId'],
      status: data['status'] ?? 'disponible',
      superviseurId: data['superviseurId'],
      superviseurName: data['superviseurName'],
      takenAtTimestamp: data['takenAtTimestamp'] != null
          ? _parseDate(data['takenAtTimestamp'])
          : null,
      elapsedTime: (data['elapsedTime'] as num?)?.toInt(),
      comments: List<String>.from(data['comments'] ?? []),
      resolutionReason: data['resolutionReason'],
      resolvedAt:
          data['resolvedAt'] != null ? _parseDate(data['resolvedAt']) : null,
      isEscalated: data['isEscalated'] ?? false,
      escalatedAt:
          data['escalatedAt'] != null ? _parseDate(data['escalatedAt']) : null,
      wasAssisted: data['wasAssisted'] ?? false,
      assistedBySupervisorId: data['assistedBySupervisorId'],
      assistedBySupervisorName: data['assistedBySupervisorName'],
      aiAssigned: data['aiAssigned'] == true,
      aiAssignmentReason: data['aiAssignmentReason'],
      aiConfidence: (data['aiConfidence'] as num?)?.toDouble(),
      aiAssignedAt: data['aiAssignedAt'] != null
          ? _parseDate(data['aiAssignedAt'])
          : null,
      aiRecommendationPending: data['aiRecommendationPending'] == true,
      aiRecommendationStatus: data['aiRecommendationStatus'],
      aiRecommendedSupervisorId: data['aiRecommendedSupervisorId'],
      aiRecommendedSupervisorName: data['aiRecommendedSupervisorName'],
      aiRecommendationReason: data['aiRecommendationReason'],
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'isCritical': isCritical,
        'criticalNote': criticalNote,
        'usine': usine,
        'convoyeur': convoyeur,
        'poste': poste,
        'adresse': adresse,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'assistantId': assistantId,
        'assistantName': assistantName,
        'helpRequestId': helpRequestId,
        'helpRequesterId': helpRequesterId,
        'helpRequesterName': helpRequesterName,
        'collaborationRequestId': collaborationRequestId,
        'status': status,
        'superviseurId': superviseurId,
        'superviseurName': superviseurName,
        'takenAtTimestamp': takenAtTimestamp?.toIso8601String(),
        'elapsedTime': elapsedTime,
        'comments': comments,
        'resolutionReason': resolutionReason,
        'resolvedAt': resolvedAt?.toIso8601String(),
        'isEscalated': isEscalated,
        'escalatedAt': escalatedAt?.toIso8601String(),
        'aiAssigned': aiAssigned,
        'aiAssignmentReason': aiAssignmentReason,
        'aiConfidence': aiConfidence,
        'aiAssignedAt': aiAssignedAt?.toIso8601String(),
        'aiRecommendationPending': aiRecommendationPending,
        'aiRecommendationStatus': aiRecommendationStatus,
        'aiRecommendedSupervisorId': aiRecommendedSupervisorId,
        'aiRecommendedSupervisorName': aiRecommendedSupervisorName,
        'aiRecommendationReason': aiRecommendationReason,
      };

  static DateTime _parseDate(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    return DateTime.now();
  }

  AlertModel copyWith({
    String? status,
    bool? isCritical,
    String? criticalNote,
    String? superviseurId,
    String? superviseurName,
    DateTime? takenAtTimestamp,
    int? elapsedTime,
    List<String>? comments,
    String? resolutionReason,
    DateTime? resolvedAt,
    String? assistantId,
    String? assistantName,
    String? helpRequestId,
    String? helpRequesterId,
    String? helpRequesterName,
    String? collaborationRequestId,
    bool clearSuperviseur = false,
    bool clearTakenAt = false,
    bool? isEscalated,
    DateTime? escalatedAt,
    bool? aiAssigned,
    String? aiAssignmentReason,
    double? aiConfidence,
    DateTime? aiAssignedAt,
    bool? aiRecommendationPending,
    String? aiRecommendationStatus,
    String? aiRecommendedSupervisorId,
    String? aiRecommendedSupervisorName,
    String? aiRecommendationReason,
  }) =>
      AlertModel(
        id: id,
        type: type,
        isCritical: isCritical ?? this.isCritical,
        criticalNote: criticalNote ?? this.criticalNote,
        usine: usine,
        convoyeur: convoyeur,
        poste: poste,
        adresse: adresse,
        timestamp: timestamp,
        description: description,
        assistantId: assistantId ?? this.assistantId,
        assistantName: assistantName ?? this.assistantName,
        helpRequestId: helpRequestId ?? this.helpRequestId,
        helpRequesterId: helpRequesterId ?? this.helpRequesterId,
        helpRequesterName: helpRequesterName ?? this.helpRequesterName,
        collaborationRequestId:
            collaborationRequestId ?? this.collaborationRequestId,
        status: status ?? this.status,
        superviseurId:
            clearSuperviseur ? null : (superviseurId ?? this.superviseurId),
        superviseurName:
            clearSuperviseur ? null : (superviseurName ?? this.superviseurName),
        takenAtTimestamp:
            clearTakenAt ? null : (takenAtTimestamp ?? this.takenAtTimestamp),
        elapsedTime: elapsedTime ?? this.elapsedTime,
        comments: comments ?? this.comments,
        resolutionReason: resolutionReason ?? this.resolutionReason,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        isEscalated: isEscalated ?? this.isEscalated,
        escalatedAt: escalatedAt ?? this.escalatedAt,
        aiAssigned: aiAssigned ?? this.aiAssigned,
        aiAssignmentReason: aiAssignmentReason ?? this.aiAssignmentReason,
        aiConfidence: aiConfidence ?? this.aiConfidence,
        aiAssignedAt: aiAssignedAt ?? this.aiAssignedAt,
        aiRecommendationPending:
            aiRecommendationPending ?? this.aiRecommendationPending,
        aiRecommendationStatus:
            aiRecommendationStatus ?? this.aiRecommendationStatus,
        aiRecommendedSupervisorId:
            aiRecommendedSupervisorId ?? this.aiRecommendedSupervisorId,
        aiRecommendedSupervisorName:
            aiRecommendedSupervisorName ?? this.aiRecommendedSupervisorName,
        aiRecommendationReason:
            aiRecommendationReason ?? this.aiRecommendationReason,
      );
}
