import 'package:flutter/material.dart';
import '../models/alert_model.dart';
import '../services/alert_service.dart';

class AlertProvider extends ChangeNotifier {
  final AlertService _service = AlertService();
  List<AlertModel> _alerts = [];
  bool isLoading = false;
  String _filterSeverity = 'all';
  String _filterType = 'all';
  String _searchQuery = '';

  List<AlertModel> get activeAlerts =>
      _filtered.where((a) => a.status != 'resolved').toList();

  List<AlertModel> get resolvedAlerts =>
      _filtered.where((a) => a.status == 'resolved').toList();

  List<AlertModel> get _filtered {
    return _alerts.where((a) {
      if (_filterSeverity != 'all' && a.severity != _filterSeverity) return false;
      if (_filterType != 'all' && a.type != _filterType) return false;
      if (_searchQuery.isNotEmpty &&
          !a.message.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !a.machine.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  void setFilter(String severity, String type) {
    _filterSeverity = severity;
    _filterType = type;
    notifyListeners();
  }

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // Start listening to real-time alerts from Firestore
  void listenToAlerts(String plant) {
    isLoading = true;
    notifyListeners();
    _service.getAlertsForPlant(plant).listen((alerts) {
      _alerts = alerts;
      isLoading = false;
      notifyListeners();
    });
  }

  Future<void> acknowledge(String id, String supervisorName) async {
    await _service.acknowledgeAlert(id, supervisorName);
  }

  Future<void> addComment(String id, String comment) async {
    await _service.addComment(id, comment);
  }

  Future<void> escalate(String id, String to) async {
    await _service.escalateAlert(id, to, '');
  }

  Future<void> resolve(String id, String note) async {
    await _service.resolveAlert(id, note);
  }

  Future<void> detach(String id) async {
    await _service.detachFromAlert(id);
  }
}