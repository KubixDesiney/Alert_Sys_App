import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/alert_model.dart';
import '../services/alert_actions_service.dart';
import '../services/alert_stream_service.dart';
import '../services/notification_service.dart';
import '../services/service_locator.dart';

class AlertProvider extends ChangeNotifier {
  AlertProvider({
    AlertStreamService? alertStreamService,
    AlertActionsService? alertActionsService,
    NotificationService? notificationService,
  })  : _alertStreamService =
            alertStreamService ?? ServiceLocator.instance.alertStreamService,
        _alertActionsService =
            alertActionsService ?? ServiceLocator.instance.alertActionsService,
        _notificationService =
            notificationService ?? ServiceLocator.instance.notificationService;

  final AlertStreamService _alertStreamService;
  final AlertActionsService _alertActionsService;
  final NotificationService _notificationService;

  final int _pageSize = 100;
  final Set<String> _loadedOlderAlertIds = {};
  List<AlertModel> _alerts = [];
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();
  bool isLoading = false;
  bool _initialized = false;
  bool _isLoadingOlder = false;

  void initForProductionManager() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _alertStreamService.initForProductionManager(
      pageSize: _pageSize,
      onLoading: _markLoading,
      onAlerts: _setAlerts,
    );
    _startClock();
  }

  void init(String usine) {
    _initialized = true;
    _alerts = [];
    _loadedOlderAlertIds.clear();
    _alertStreamService.initForSupervisor(
      usine: usine,
      currentUserId: FirebaseAuth.instance.currentUser?.uid,
      pageSize: _pageSize,
      onLoading: _markLoading,
      onAlerts: _setAlerts,
    );
    _startClock();
  }

  Future<void> loadOlderAlerts() async {
    if (_isLoadingOlder) {
      return;
    }
    _isLoadingOlder = true;
    try {
      final older = await _alertStreamService.loadOlderAlerts(_alerts);
      if (older.isEmpty) {
        return;
      }
      final combined = [..._alerts];
      for (final alert in older) {
        if (_loadedOlderAlertIds.add(alert.id) &&
            combined.every((existing) => existing.id != alert.id)) {
          combined.add(alert);
        }
      }
      combined.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _alerts = combined;
      notifyListeners();
    } finally {
      _isLoadingOlder = false;
    }
  }

  void reset() {
    _clockTimer?.cancel();
    _clockTimer = null;
    _alertStreamService.reset();
    _alerts = [];
    isLoading = false;
    _initialized = false;
    _loadedOlderAlertIds.clear();
    notifyListeners();
  }

  Future<List<String>> getPastResolutionsForType(String type, int limit) {
    return _alertActionsService.getPastResolutionsForType(_alerts, type, limit);
  }

  Future<List<String>> getPastResolutionsForLocation({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    int limit = 3,
  }) {
    return _alertActionsService.getPastResolutionsForLocation(
      alerts: _alerts,
      type: type,
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
      limit: limit,
    );
  }

  Future<String> getAiSuggestionForAlert(AlertModel alert) {
    return _alertActionsService.getAiSuggestionForAlert(alert, _alerts);
  }

  void _markLoading() {
    isLoading = true;
    notifyListeners();
  }

  void _setAlerts(List<AlertModel> alerts) {
    _alerts = alerts;
    isLoading = false;
    notifyListeners();
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _currentTime = DateTime.now();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _alertStreamService.reset();
    super.dispose();
  }

  List<AlertModel> get allAlerts => _alerts;
  List<AlertModel> get availableAlerts =>
      _alerts.where((a) => a.status == 'disponible').toList();
  List<AlertModel> get allInProgressAlerts =>
      _alerts.where((a) => a.status == 'en_cours').toList();
  List<AlertModel> get allFixedAlerts =>
      _alerts.where((a) => a.status == 'validee').toList();

  List<AlertModel> inProgressAlerts(String superviseurId) => _alerts
      .where((a) =>
          a.status == 'en_cours' &&
          (a.superviseurId == superviseurId || a.assistantId == superviseurId))
      .toList();

  List<AlertModel> validatedAlerts(String superviseurId) => _alerts
      .where((a) => a.status == 'validee' && a.superviseurId == superviseurId)
      .toList();

  List<AlertModel> assistedAlerts(String superviseurId) {
    return _alerts.where((a) {
      if (a.status != 'validee') {
        return false;
      }
      if (a.assistantId == superviseurId) {
        return true;
      }
      return a.collaborators?.any((c) => c['id'] == superviseurId) ?? false;
    }).toList();
  }

  DateTime get currentTime => _currentTime;
  String get currentSuperviseurId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';
  String get currentSuperviseurName =>
      FirebaseAuth.instance.currentUser?.email?.split('@').first ??
      'Supervisor';

  Future<void> takeAlert(
    String alertId,
    String superviseurId,
    String superviseurName,
  ) {
    return _alertActionsService.takeAlert(
      alerts: _alerts,
      alertId: alertId,
      superviseurId: superviseurId,
      superviseurName: superviseurName,
      updateLocal: _updateLocal,
    );
  }

  Future<void> returnToQueue(String alertId, {String? reason}) {
    return _alertActionsService.returnToQueue(
      alerts: _alerts,
      alertId: alertId,
      reason: reason,
      updateLocal: _updateLocal,
    );
  }

  Future<void> resolveAlert(String alertId, String reason) {
    return _alertActionsService.resolveAlert(
      alerts: _alerts,
      alertId: alertId,
      reason: reason,
      updateLocal: _updateLocal,
    );
  }

  Future<void> addComment(String alertId, String comment) {
    return _alertActionsService.addComment(
      alerts: _alerts,
      alertId: alertId,
      comment: comment,
      currentSuperviseurName: currentSuperviseurName,
      updateLocal: _updateLocal,
    );
  }

  Future<void> toggleCritical(String alertId, bool isCritical, {String? note}) async {
    await _alertActionsService.toggleCritical(
      alertId: alertId,
      isCritical: isCritical,
      note: note,
      updateLocal: _updateLocal,
    );
    await _notificationService.notifyAllUsers(
      alerts: _alerts,
      alertId: alertId,
      isCritical: isCritical,
    );
  }

  Future<void> requestAssistanceForAlert(String alertId) {
    return _notificationService.requestAssistanceForAlert(
      alerts: _alerts,
      alertId: alertId,
      currentUserId: currentSuperviseurId,
      currentSuperviseurName: currentSuperviseurName,
    );
  }

  Future<void> acceptAssistance(String alertId) {
    return _notificationService.acceptAssistance(
      alertId: alertId,
      currentId: currentSuperviseurId,
      currentName: currentSuperviseurName,
      updateLocal: _updateLocal,
    );
  }

  Future<void> acceptHelp(String alertId, String requestId) {
    return _notificationService.acceptHelp(
      alertId: alertId,
      requestId: requestId,
      currentId: currentSuperviseurId,
      currentName: currentSuperviseurName,
      updateLocal: _updateLocal,
    );
  }

  Future<void> refuseHelp(String alertId, String requestId) {
    return _notificationService.refuseHelp(
      alertId: alertId,
      requestId: requestId,
      updateLocal: _updateLocal,
    );
  }

  Future<void> requestHelp(
    String alertId,
    String requesterId,
    String requesterName,
  ) {
    return _notificationService.requestHelp(
      alerts: _alerts,
      alertId: alertId,
      requesterId: requesterId,
      requesterName: requesterName,
    );
  }

  void _updateLocal(String id, AlertModel Function(AlertModel) update) {
    _alerts = _alerts.map((a) => a.id == id ? update(a) : a).toList();
    notifyListeners();
  }

  String getElapsedTime(AlertModel alert) {
    if (alert.takenAtTimestamp == null) {
      return '00:00:00';
    }
    final diff = _currentTime.difference(alert.takenAtTimestamp!);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String formatElapsedTime(int? minutes) {
    if (minutes == null || minutes == 0) {
      return '0 min';
    }
    if (minutes < 60) {
      return '$minutes min';
    }
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}min' : '${h}h';
  }
}
