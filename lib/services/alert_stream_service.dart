import 'dart:async';

import 'package:rxdart/rxdart.dart';

import '../models/alert_model.dart';
import 'alert_service.dart';
import 'app_logger.dart';
import 'data/data_store.dart';
import 'data/firebase_data_store.dart';

class AlertStreamService {
  AlertStreamService({
    required AlertService alertService,
    required AppLogger logger,
    DataStore? dataStore,
  }) : _alertService = alertService,
       _logger = logger,
       // Default preserves cloud behaviour: FirebaseDataStore delegates to
       // the same AlertService streams.
       _store = dataStore ?? FirebaseDataStore(alertService: alertService);

  final AlertService _alertService;
  final AppLogger _logger;
  final DataStore _store;

  bool get _isFirebase => _store.backendName == 'firebase';

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
      source: _store.watchAllAlerts(limit: pageSize),
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

    final usineStream = _store.watchAlertsForUsine(usine, limit: pageSize);
    if (currentUserId == null || currentUserId.isEmpty) {
      _start(source: usineStream, onAlerts: onAlerts, onLoading: onLoading);
      return;
    }

    if (!_isFirebase) {
      // On-prem: the store's supervisor stream already covers owner+assistant;
      // collaborator visibility is a v3 item (see data/README.md).
      final mineStream =
          _store.watchAlertsForSupervisor(currentUserId, limit: pageSize);
      _start(
        source: Rx.combineLatest2<List<AlertModel>, List<AlertModel>,
            List<AlertModel>>(
          usineStream,
          mineStream,
          (usineAlerts, mineAlerts) {
            final combined = [...usineAlerts, ...mineAlerts];
            final seen = <String>{};
            return combined.where((a) => seen.add(a.id)).toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          },
        ),
        onAlerts: onAlerts,
        onLoading: onLoading,
        fallback: () => _store.watchAlertsForUsine(usine, limit: pageSize),
      );
      return;
    }

    final assistantStream = _alertService.getAlertsWhereAssistant(
      currentUserId,
      limit: pageSize,
    );
    final supervisorStream = _alertService.getAlertsWhereSupervisor(
      currentUserId,
      limit: pageSize,
    );
    final collaboratorStream = _alertService.getAlertsForCollaborator(
      currentUserId,
    );

    _start(
      source:
          Rx.combineLatest4<
            List<AlertModel>,
            List<AlertModel>,
            List<AlertModel>,
            List<AlertModel>,
            List<AlertModel>
          >(
            usineStream,
            assistantStream,
            supervisorStream,
            collaboratorStream,
            (
              usineAlerts,
              assistantAlerts,
              supervisorAlerts,
              collaboratorAlerts,
            ) {
              final combined = [
                ...usineAlerts,
                ...assistantAlerts,
                ...supervisorAlerts,
                ...collaboratorAlerts,
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

  Future<List<AlertModel>> loadOlderAlerts(
    List<AlertModel> currentAlerts,
  ) async {
    if (currentAlerts.isEmpty) {
      return const [];
    }
    final oldest = currentAlerts.last.timestamp;
    return _store.fetchOlderAlerts(
      usine: _currentUsine,
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

  void dispose() {
    reset();
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
      if (_isFirebase) {
        // Cloud path: queue FCM fan-out rows in RTDB. On-prem the
        // worker-runner owns new-alert fan-out over LAN SSE.
        _alertService.sendNewAlertNotification(
          alert.id,
          alert.type,
          alert.description,
        );
      }
    }
    _previousAlertIds = newIds;
  }
}
