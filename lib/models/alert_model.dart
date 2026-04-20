
class AlertModel {
  final String id;
  final String type;
  final bool isCritical;
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
    this.assistantId,
    this.assistantName,
    this.helpRequestId,
    this.helpRequesterId,
    this.helpRequesterName,
    this.isCritical = false,
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
      status: data['status'] ?? 'disponible',
      superviseurId: data['superviseurId'],
      superviseurName: data['superviseurName'],
      takenAtTimestamp: data['takenAtTimestamp'] != null ? _parseDate(data['takenAtTimestamp']) : null,
      elapsedTime: (data['elapsedTime'] as num?)?.toInt(),
      comments: List<String>.from(data['comments'] ?? []),
      resolutionReason: data['resolutionReason'],
      resolvedAt: data['resolvedAt'] != null ? _parseDate(data['resolvedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'isCritical': isCritical,
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
    'status': status,
    'superviseurId': superviseurId,
    'superviseurName': superviseurName,
    'takenAtTimestamp': takenAtTimestamp?.toIso8601String(),
    'elapsedTime': elapsedTime,
    'comments': comments,
    'resolutionReason': resolutionReason,
    'resolvedAt': resolvedAt?.toIso8601String(),
  };

  static DateTime _parseDate(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) { try { return DateTime.parse(raw); } catch (_) {} }
    return DateTime.now();
  }

  AlertModel copyWith({
    String? status,
    bool? isCritical,
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
    bool clearSuperviseur = false,
    bool clearTakenAt = false,
  }) => AlertModel(
    id: id,
    type: type,
    isCritical: isCritical ?? this.isCritical,
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
    status: status ?? this.status,
    superviseurId: clearSuperviseur ? null : (superviseurId ?? this.superviseurId),
    superviseurName: clearSuperviseur ? null : (superviseurName ?? this.superviseurName),
    takenAtTimestamp: clearTakenAt ? null : (takenAtTimestamp ?? this.takenAtTimestamp),
    elapsedTime: elapsedTime ?? this.elapsedTime,
    comments: comments ?? this.comments,
    resolutionReason: resolutionReason ?? this.resolutionReason,
    resolvedAt: resolvedAt ?? this.resolvedAt,
  );
}