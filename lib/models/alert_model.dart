class AlertModel {
  final String id;
  // Short, human-speakable, auto-incrementing number assigned at creation.
  // Voice commands reference this (e.g. "claim alert 1025"). 0 = legacy/unmigrated.
  final int alertNumber;
  final String type;
  final bool isCritical;
  final String? criticalNote; // ✅ NEW
  final String usine;
  final int convoyeur;
  final int poste;
  final String adresse;
  final String? assetId;
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
  final List<Map<String, String>>? collaborators;
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

  bool get hasAlertNumber => alertNumber > 0;

  String get alertLabel {
    if (hasAlertNumber) {
      return '#$alertNumber';
    }
    final shortId = id.length >= 6 ? id.substring(0, 6) : id;
    return '#${shortId.toUpperCase()}';
  }

  AlertModel({
    required this.id,
    this.alertNumber = 0,
    required this.type,
    required this.usine,
    required this.convoyeur,
    required this.poste,
    required this.adresse,
    this.assetId,
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
    this.collaborators,
  });

  factory AlertModel.fromMap(String id, Map<String, dynamic> data) {
    final rawList = data['collaborators'];
    final List<Map<String, String>>? collaboratorsList = rawList != null
        ? (rawList as List<dynamic>)
            .map((e) => Map<String, String>.from(e as Map))
            .toList()
        : null;
    final rawAssetId = data['assetId'] ?? data['asset_id'] ?? data['machineId'];
    final assetId = rawAssetId?.toString().trim();
    return AlertModel(
      id: id,
      alertNumber: (data['alertNumber'] as num?)?.toInt() ?? 0,
      type: data['type'] ?? 'qualite',
      isCritical: data['isCritical'] ?? false,
      criticalNote: data['criticalNote'],
      usine: data['usine'] ?? 'Usine A',
      convoyeur: (data['convoyeur'] as num?)?.toInt() ?? 1,
      poste: (data['poste'] as num?)?.toInt() ?? 1,
      adresse: data['adresse'] ?? data['poste_id'] ?? '',
      assetId: assetId == null || assetId.isEmpty ? null : assetId,
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
      collaborators: collaboratorsList,
    );
  }

  Map<String, dynamic> toMap() => {
        'alertNumber': alertNumber,
        'type': type,
        'isCritical': isCritical,
        'criticalNote': criticalNote,
        'usine': usine,
        'convoyeur': convoyeur,
        'poste': poste,
        'adresse': adresse,
        'assetId': assetId,
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
        'collaborators': collaborators?.map((e) => e).toList(),
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
    String? assetId,
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
    List<Map<String, String>>? collaborators,
  }) =>
      AlertModel(
        id: id,
        alertNumber: alertNumber,
        type: type,
        isCritical: isCritical ?? this.isCritical,
        criticalNote: criticalNote ?? this.criticalNote,
        usine: usine,
        convoyeur: convoyeur,
        poste: poste,
        adresse: adresse,
        assetId: assetId ?? this.assetId,
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
        collaborators: collaborators ?? this.collaborators,
      );
}
