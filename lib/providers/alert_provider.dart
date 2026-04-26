import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/alert_model.dart';
import '../services/alert_service.dart';
import '../services/ai_service.dart';
import 'package:rxdart/rxdart.dart';

class AlertProvider extends ChangeNotifier {
  final AlertService _service = AlertService();
  List<AlertModel> _alerts = [];
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();
  bool isLoading = false;

  Set<String> _previousAlertIds = {};
  final Map<String, DateTime> _lastProcessed = {}; // Deduplication map
  bool _initialized = false;
  StreamSubscription? _alertsSubscription;

  // ----------------------------------------------------------------------
  // Initialization
  // ----------------------------------------------------------------------
  void initForProductionManager() {
    if (_initialized) return;
    _initialized = true;
    isLoading = true;
    notifyListeners();
    _alertsSubscription?.cancel();
    bool firstLoad = true;
    _alertsSubscription = _service.getAllAlerts().listen((alerts) {
      if (firstLoad) {
        _previousAlertIds = alerts.map((a) => a.id).toSet();
        firstLoad = false;
      } else {
        _checkNewAlerts(alerts);
      }
      _alerts = alerts;
      isLoading = false;
      notifyListeners();
    });
    _startClock();
  }

  void init(String usine) {
    _alertsSubscription?.cancel();
    _alerts = [];
    _previousAlertIds.clear();
    _lastProcessed.clear();
    isLoading = true;
    notifyListeners();

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      // Fallback to just usine stream
      bool firstLoad = true;
      _alertsSubscription = _service.getAlertsForUsine(usine).listen((alerts) {
        if (firstLoad) {
          _previousAlertIds = alerts.map((a) => a.id).toSet();
          firstLoad = false;
        } else {
          _checkNewAlerts(alerts);
        }
        _alerts = alerts;
        isLoading = false;
        notifyListeners();
      });
      _startClock();
      return;
    }

    final usineStream = _service.getAlertsForUsine(usine);
    final assistantStream = _service.getAlertsWhereAssistant(currentUserId);

    bool firstLoad = true;
    bool fallbackActivated = false;

    void applyAlerts(List<AlertModel> alerts) {
      if (firstLoad) {
        _previousAlertIds = alerts.map((a) => a.id).toSet();
        firstLoad = false;
      } else {
        _checkNewAlerts(alerts);
      }
      _alerts = alerts;
      isLoading = false;
      notifyListeners();
    }

    void activateFallback(Object error, [StackTrace? stackTrace]) {
      if (fallbackActivated) return;
      fallbackActivated = true;
      debugPrint('AlertProvider combineLatest fallback activated: $error');
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }

      _alertsSubscription?.cancel();
      _alertsSubscription = _service.getAlertsForUsine(usine).listen(
        applyAlerts,
        onError: (fallbackError, fallbackStack) {
          debugPrint('AlertProvider fallback stream error: $fallbackError');
          if (fallbackStack != null) {
            debugPrint(fallbackStack.toString());
          }
        },
      );
    }

    _alertsSubscription =
        Rx.combineLatest2<List<AlertModel>, List<AlertModel>, List<AlertModel>>(
      usineStream,
      assistantStream,
      (usineAlerts, assistantAlerts) {
        final combined = [...usineAlerts, ...assistantAlerts];
        // Remove duplicates by id
        final seen = <String>{};
        final unique = combined.where((a) => seen.add(a.id)).toList();
        return unique;
      },
    ).listen(
      applyAlerts,
      onError: activateFallback,
    );
    _startClock();
  }

  void reset() {
    _clockTimer?.cancel();
    _clockTimer = null;
    _alertsSubscription?.cancel();
    _alertsSubscription = null;
    _alerts = [];
    isLoading = false;
    _previousAlertIds.clear();
    _lastProcessed.clear();
    _initialized = false;
    notifyListeners();
  }

  // ----------------------------------------------------------------------
  // New alert detection with debug prints
  // ----------------------------------------------------------------------
  void _checkNewAlerts(List<AlertModel> newAlerts) {
    final newIds = newAlerts.map((a) => a.id).toSet();
    final addedIds = newIds.difference(_previousAlertIds);
    final now = DateTime.now();

    for (var id in addedIds) {
      if (_lastProcessed.containsKey(id)) {
        final last = _lastProcessed[id]!;
        if (now.difference(last) < const Duration(seconds: 2)) {
          print('⏩ Skipping duplicate alert $id (already processed)');
          continue;
        }
      }
      _lastProcessed[id] = now;
      final alert = newAlerts.firstWhere((a) => a.id == id);

      print(
          '📢 New alert detected: ${alert.id} (${alert.type}) – creating in-app notifications');

      // Create in-app Firebase notifications (OneSignal pushes handled by Worker)
      _service.sendNewAlertNotification(
          alert.id, alert.type, alert.description);
    }
    _previousAlertIds = newIds;
  }

  Future<List<String>> getPastResolutionsForType(String type, int limit) async {
    final similar = _alerts
        .where((a) =>
            a.type == type &&
            a.status == 'validee' &&
            a.resolutionReason != null)
        .toList()
      ..sort((a, b) => b.resolvedAt!.compareTo(a.resolvedAt!));
    return similar.take(limit).map((a) => a.resolutionReason!).toList();
  }

  Future<List<String>> getPastResolutionsForLocation({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    int limit = 3,
  }) async {
    final similar = _alerts
        .where((a) =>
            a.type == type &&
            a.status == 'validee' &&
            a.resolutionReason != null &&
            a.usine == usine &&
            a.convoyeur == convoyeur &&
            a.poste == poste)
        .toList()
      ..sort((a, b) => b.resolvedAt!.compareTo(a.resolvedAt!));
    return similar.take(limit).map((a) => a.resolutionReason!).toList();
  }

  Future<String> getAiSuggestionForAlert(AlertModel alert) async {
    final pastResolutions = await getPastResolutionsForLocation(
      type: alert.type,
      usine: alert.usine,
      convoyeur: alert.convoyeur,
      poste: alert.poste,
      limit: 3,
    );
    final aiService = AIService();
    return await aiService.getResolutionSuggestion(
      alertType: alert.type,
      alertDescription: alert.description,
      usine: alert.usine,
      convoyeur: alert.convoyeur,
      poste: alert.poste,
      pastResolutions: pastResolutions,
    );
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
    _alertsSubscription?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------------------
  // Getters
  // ----------------------------------------------------------------------
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

  /// Alerts where this supervisor was the assistant (not the main claimant).
  List<AlertModel> assistedAlerts(String superviseurId) => _alerts
      .where((a) => a.status == 'validee' && a.assistantId == superviseurId)
      .toList();

  DateTime get currentTime => _currentTime;
  String get currentSuperviseurId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';
  String get currentSuperviseurName =>
      FirebaseAuth.instance.currentUser?.email?.split('@').first ??
      'Supervisor';

  // ----------------------------------------------------------------------
  // Actions
  // ----------------------------------------------------------------------
  Future<void> takeAlert(
      String alertId, String superviseurId, String superviseurName) async {
    // Check if this supervisor already has an in-progress alert
    final existingInProgress = _alerts
        .any((a) => a.status == 'en_cours' && a.superviseurId == superviseurId);
    if (existingInProgress) {
      // Optionally throw an exception or show a snackbar; here we'll just return an error state
      throw Exception(
          'You already have an alert in progress. Please resolve it before claiming a new one.');
    }
    _updateLocal(
        alertId,
        (a) => a.copyWith(
              status: 'en_cours',
              superviseurId: superviseurId,
              superviseurName: superviseurName,
              takenAtTimestamp: DateTime.now(),
            ));
    await _service.takeAlert(alertId, superviseurId, superviseurName);
  }

  Future<void> returnToQueue(String alertId, {String? reason}) async {
    final alert = _alerts.firstWhere((a) => a.id == alertId);
    final supervisorName = alert.superviseurName ?? 'A supervisor';
    _updateLocal(
        alertId,
        (a) => a.copyWith(
              status: 'disponible',
              clearSuperviseur: true,
              clearTakenAt: true,
            ));
    await _service.returnToQueue(alertId, reason: reason);
    await _service.notifyAdminsAboutSuspend(alertId, supervisorName, reason);
  }

  Future<void> resolveAlert(String alertId, String reason) async {
    final alert = _alerts.firstWhere((a) => a.id == alertId);
    final elapsed = alert.takenAtTimestamp != null
        ? DateTime.now().difference(alert.takenAtTimestamp!).inMinutes
        : 0;
    _updateLocal(
        alertId,
        (a) => a.copyWith(
              status: 'validee',
              elapsedTime: elapsed,
              resolutionReason: reason,
              resolvedAt: DateTime.now(),
            ));

    // If an assistant helped, credit them with "Assisted" label
    await _service.resolveAlert(
      alertId,
      reason,
      elapsed,
      assistingSupervisorId: alert.superviseurId,
      assistingSupervisorName: alert.superviseurName,
    );
  }

  Future<void> addComment(String alertId, String comment) async {
    final newComment =
        '[${_formatTime(DateTime.now())}] ${currentSuperviseurName}: $comment';
    final alert = _alerts.firstWhere((a) => a.id == alertId);
    final updatedComments = [...alert.comments, newComment];
    _updateLocal(alertId, (a) => a.copyWith(comments: updatedComments));
    await _service.addComment(alertId, newComment);
  }

  Future<void> toggleCritical(String alertId, bool isCritical,
      {String? note}) async {
    _updateLocal(
        alertId, (a) => a.copyWith(isCritical: isCritical, criticalNote: note));
    await _service.toggleCritical(alertId, isCritical);
    if (note != null) {
      await _service.setCriticalNote(
          alertId, note); // you need to add this method in AlertService
    }
    await _notifyAllUsers(alertId, isCritical);
  }

  Future<void> requestAssistanceForAlert(String alertId) async {
    final alert = _alerts.firstWhere((a) => a.id == alertId);
    if (alert.superviseurId == null) return;
    final users = await _service.getAllUsers();
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    for (var entry in users.entries) {
      final userId = entry.key;
      if (userId == currentUserId) continue;
      final userData = entry.value as Map;
      final role = userData['role'] ?? 'supervisor';
      if (role == 'supervisor' || role == 'admin') {
        final notification = {
          'type': 'assistance_request',
          'alertId': alertId,
          'alertType': alert.type,
          'alertDescription': alert.description,
          'requesterName': currentSuperviseurName,
          'message':
              '🆘 ${currentSuperviseurName} needs assistance on alert: ${alert.type}',
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
        };
        await _service.sendHelpRequest(userId, notification);
      }
    }
  }

  Future<void> acceptAssistance(String alertId) async {
    final currentId = FirebaseAuth.instance.currentUser!.uid;
    final currentName =
        FirebaseAuth.instance.currentUser!.email!.split('@').first;
    await _service.acceptHelpRequest(alertId, '', currentId, currentName);
    _updateLocal(
        alertId,
        (a) => a.copyWith(
              assistantId: currentId,
              assistantName: currentName,
              helpRequestId: null,
            ));
  }

  Future<void> acceptHelp(String alertId, String requestId) async {
    final currentId = FirebaseAuth.instance.currentUser!.uid;
    final currentName =
        FirebaseAuth.instance.currentUser!.email!.split('@').first;
    await _service.acceptHelpRequest(
        alertId, requestId, currentId, currentName);
    _updateLocal(
        alertId,
        (a) => a.copyWith(
              assistantId: currentId,
              assistantName: currentName,
              helpRequestId: null,
            ));
  }

  Future<void> refuseHelp(String alertId, String requestId) async {
    await _service.refuseHelpRequest(alertId, requestId);
    _updateLocal(alertId, (a) => a.copyWith(helpRequestId: null));
  }

  Future<void> requestHelp(
      String alertId, String requesterId, String requesterName) async {
    final alert = _alerts.firstWhere((a) => a.id == alertId);
    if (alert.superviseurId == null) return;
    await _service.createHelpRequest(
        alertId, requesterId, requesterName, alert.superviseurId!);
  }

  Future<void> _notifyAllUsers(String alertId, bool isCritical,
      [String? customMessage]) async {
    final alert = _alerts.firstWhere((a) => a.id == alertId);
    final users = await _service.getAllUsers();
    for (var entry in users.entries) {
      final userId = entry.key;
      final userData = entry.value as Map;
      if (userData['role'] == 'admin' || userData['role'] == 'supervisor') {
        final message = customMessage ??
            (isCritical
                ? 'Alert marked as CRITICAL: ${alert.type}'
                : 'Alert critical flag removed: ${alert.type}');
        final notification = {
          'alertId': alertId,
          'alertType': alert.type,
          'alertDescription': alert.description,
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
        };
        await _service.sendHelpRequest(userId, notification);
      }
    }
  }

  void _updateLocal(String id, AlertModel Function(AlertModel) update) {
    _alerts = _alerts.map((a) => a.id == id ? update(a) : a).toList();
    notifyListeners();
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String getElapsedTime(AlertModel alert) {
    if (alert.takenAtTimestamp == null) return '00:00:00';
    final diff = _currentTime.difference(alert.takenAtTimestamp!);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String formatElapsedTime(int? minutes) {
    if (minutes == null || minutes == 0) return '0 min';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}min' : '${h}h';
  }
}
