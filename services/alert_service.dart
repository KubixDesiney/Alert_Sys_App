import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/alert_model.dart';

class AlertService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Real-time stream of alerts for a specific plant
  Stream<List<AlertModel>> getAlertsForPlant(String plant) {
    return _db
        .collection('alerts')
        .where('plant', isEqualTo: plant)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AlertModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  // Acknowledge an alert
  Future<void> acknowledgeAlert(String alertId, String supervisorName) async {
    await _db.collection('alerts').doc(alertId).update({
      'status': 'acknowledged',
      'acknowledged': true,
      'acknowledgedBy': supervisorName,
      'acknowledgedAt': DateTime.now().toIso8601String(),
    });
  }

  // Add a comment/note to an alert
  Future<void> addComment(String alertId, String comment) async {
    await _db.collection('alerts').doc(alertId).update({
      'comments': FieldValue.arrayUnion([comment]),
    });
  }

  // Escalate an alert to someone
  Future<void> escalateAlert(String alertId, String escalateTo, String comment) async {
    await _db.collection('alerts').doc(alertId).update({
      'escalated': true,
      'escalatedTo': escalateTo,
      'comments': FieldValue.arrayUnion(['⬆️ Escaladé vers $escalateTo']),
    });
  }

  // Mark alert as resolved
  Future<void> resolveAlert(String alertId, String note) async {
    await _db.collection('alerts').doc(alertId).update({
      'status': 'resolved',
      'resolvedNote': note,
      'resolvedAt': DateTime.now().toIso8601String(),
    });
  }

  // Detach supervisor from alert
  Future<void> detachFromAlert(String alertId) async {
    await _db.collection('alerts').doc(alertId).update({
      'assignedTo': null,
    });
  }
}