import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../models/alert_model.dart';
import 'alert_service.dart';
import 'app_logger.dart';

class AlertStreamService {
  AlertStreamService({
    required AlertService alertService,
    required AppLogger logger,
  })  : _alertService = alertService,
        _logger = logger;

  final AlertService _alertService;
  final AppLogger _logger;

  StreamSubscription<List<AlertModel>>? _alertsSubscription;
  final Map<String, DateTime> _lastProcessed = {};
  Set<String> _previousAlertIds = {};
  String? _currentUsine;
  int _pageSize = 100;

  void initForProductionManager({
    int pageSize = 100,
    required void Function(List<AlertModel> alerts) onAlerts,
    required void Function() onLoading,
  }) {
    _pageSize = pageSize;
    _currentUsine = null;
    _start(
      source: _alertService.getAllAlerts(limit: pageSize),
      onAlerts: onAlerts,
      onLoading: onLoading,
    );
  }

  void initForSupervisor({
    required String usine,
    required String? currentUserId,
    int pageSize = 100,
    required void Function(List<AlertModel> alerts) onAlerts,
    required void Function() onLoading,
  }) {
    _pageSize = pageSize;
    _currentUsine = usine;

    final usineStream = _alertService.getAlertsForUsine(usine, limit: pageSize);
    if (currentUserId == null || currentUserId.isEmpty) {
      _start(source: usineStream, onAlerts: onAlerts, onLoading: onLoading);
      return;
    }

    final assistantStream =
        _alertService.getAlertsWhereAssistant(currentUserId, limit: pageSize);
    final supervisorStream =
        _alertService.getAlertsWhereSupervisor(currentUserId, limit: pageSize);

    _start(
      source: Rx.combineLatest3<List<AlertModel>, List<AlertModel>,
          List<AlertModel>, List<AlertModel>>(
        usineStream,
        assistantStream,
        supervisorStream,
        (usineAlerts, assistantAlerts, supervisorAlerts) {
          final combined = [
            ...usineAlerts,
            ...assistantAlerts,
            ...supervisorAlerts,
          ];
          final seen = <String>{};
          return combined.where((a) => seen.add(a.id)).toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        },
      ),
      onAlerts: onAlerts,
      onLoading: onLoading,
      fallback: () => _alertService.getAlertsForUsine(usine, limit: pageSize),
    );
  }

  Future<List<AlertModel>> loadOlderAlerts(List<AlertModel> currentAlerts) async {
    if (currentAlerts.isEmpty) {
      return const [];
    }
    final oldest = currentAlerts.last.timestamp;
    if (_currentUsine == null) {
      return _alertService.fetchOlderAlerts(
        before: oldest,
        limit: _pageSize,
      );
    }
    return _alertService.fetchOlderAlertsForUsine(
      usine: _currentUsine!,
      before: oldest,
      limit: _pageSize,
    );
  }

  void reset() {
    _alertsSubscription?.cancel();
    _alertsSubscription = null;
    _previousAlertIds.clear();
    _lastProcessed.clear();
  }

  void _start({
    required Stream<List<AlertModel>> source,
    required void Function(List<AlertModel> alerts) onAlerts,
    required void Function() onLoading,
    Stream<List<AlertModel>> Function()? fallback,
  }) {
    reset();
    onLoading();
    var firstLoad = true;

    void applyAlerts(List<AlertModel> alerts) {
      if (firstLoad) {
        _previousAlertIds = alerts.map((a) => a.id).toSet();
        firstLoad = false;
      } else {
        _checkNewAlerts(alerts);
      }
      onAlerts(alerts);
    }

    _alertsSubscription = source.listen(
      applyAlerts,
      onError: (error, stackTrace) {
        _logger.warning('Primary alert stream failed', error, stackTrace);
        if (fallback == null) {
          return;
        }
        _alertsSubscription?.cancel();
        _alertsSubscription = fallback().listen(
          applyAlerts,
          onError: (fallbackError, fallbackStackTrace) {
            _logger.error(
              'Fallback alert stream failed',
              fallbackError,
              fallbackStackTrace,
            );
          },
        );
      },
    );
  }

  void _checkNewAlerts(List<AlertModel> newAlerts) {
    final newIds = newAlerts.map((a) => a.id).toSet();
    final addedIds = newIds.difference(_previousAlertIds);
    final now = DateTime.now();

    for (final id in addedIds) {
      final last = _lastProcessed[id];
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        continue;
      }
      _lastProcessed[id] = now;
      final alert = newAlerts.firstWhere((a) => a.id == id);
      _logger.info('New alert detected: ${alert.id} (${alert.type})');
      _alertService.sendNewAlertNotification(
        alert.id,
        alert.type,
        alert.description,
      );
    }
    _previousAlertIds = newIds;
  }
}
