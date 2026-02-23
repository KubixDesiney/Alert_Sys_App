class AlertModel {
  final String id;
  final String type;        // "Maintenance", "Qualité", "Matière", "Assistance"
  final String severity;    // "critical", "high", "medium", "low"
  final String machine;
  final String plant;
  final String sector;
  final DateTime timestamp;
  final String message;
  final String recommendedAction;
  String status;            // "pending", "acknowledged", "resolved"
  bool acknowledged;
  String? acknowledgedBy;
  DateTime? acknowledgedAt;
  bool escalated;
  String? escalatedTo;
  List<String> comments;
  String? resolvedNote;
  String? assignedTo;

  AlertModel({
    required this.id,
    required this.type,
    required this.severity,
    required this.machine,
    required this.plant,
    required this.sector,
    required this.timestamp,
    required this.message,
    required this.recommendedAction,
    this.status = 'pending',
    this.acknowledged = false,
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.escalated = false,
    this.escalatedTo,
    List<String>? comments,
    this.resolvedNote,
    this.assignedTo,
  }) : comments = comments ?? [];

  // Convert Firestore document → AlertModel object
  factory AlertModel.fromMap(String id, Map<String, dynamic> data) {
    return AlertModel(
      id: id,
      type: data['type'] ?? '',
      severity: data['severity'] ?? 'low',
      machine: data['machine'] ?? '',
      plant: data['plant'] ?? '',
      sector: data['sector'] ?? '',
      timestamp: DateTime.parse(data['timestamp']),
      message: data['message'] ?? '',
      recommendedAction: data['recommendedAction'] ?? '',
      status: data['status'] ?? 'pending',
      acknowledged: data['acknowledged'] ?? false,
      acknowledgedBy: data['acknowledgedBy'],
      acknowledgedAt: data['acknowledgedAt'] != null
          ? DateTime.parse(data['acknowledgedAt'])
          : null,
      escalated: data['escalated'] ?? false,
      escalatedTo: data['escalatedTo'],
      comments: List<String>.from(data['comments'] ?? []),
      resolvedNote: data['resolvedNote'],
      assignedTo: data['assignedTo'],
    );
  }

  // Convert AlertModel → Map to save to Firestore
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'severity': severity,
      'machine': machine,
      'plant': plant,
      'sector': sector,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'recommendedAction': recommendedAction,
      'status': status,
      'acknowledged': acknowledged,
      'acknowledgedBy': acknowledgedBy,
      'acknowledgedAt': acknowledgedAt?.toIso8601String(),
      'escalated': escalated,
      'escalatedTo': escalatedTo,
      'comments': comments,
      'resolvedNote': resolvedNote,
      'assignedTo': assignedTo,
    };
  }
}