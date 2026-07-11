import 'ai_service.dart';
import 'alert_actions_service.dart';
import 'alert_service.dart';
import 'alert_stream_service.dart';
import 'app_logger.dart';
import 'auth_service.dart';
import 'collaboration_service.dart';
import 'data/data_store.dart';
import 'data/data_store_factory.dart';
import 'hierarchy_service.dart';
import 'notification_service.dart';
import 'presence_service.dart';
import 'shift_service.dart';

class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator instance = ServiceLocator._();

  late final AppLogger logger;
  late final AlertService alertService;
  late final AlertStreamService alertStreamService;
  late final NotificationService notificationService;
  late final AlertActionsService alertActionsService;
  late final AuthService authService;
  late final HierarchyService hierarchyService;
  late final CollaborationService collaborationService;
  late final AIService aiService;
  late final ShiftService shiftService;
  late final PresenceService presenceService;

  /// Backend-agnostic data layer (Firebase by default; PocketBase when built
  /// with --dart-define=SIAS_BACKEND=pocketbase). The alert lifecycle in
  /// AlertActionsService/AlertStreamService routes through this instance.
  late final DataStore dataStore;

  bool _initialized = false;

  void init() {
    if (_initialized) {
      return;
    }
    _initialized = true;

    logger = const AppLogger();
    authService = AuthService();
    hierarchyService = HierarchyService();
    collaborationService = CollaborationService(logger: logger);
    
    alertService = AlertService(
      hierarchyService: hierarchyService,
      logger: logger,
    );
    aiService = AIService();
    shiftService = ShiftService(logger: logger);
    presenceService = PresenceService(logger: logger);
    dataStore = createDataStore();
    alertStreamService = AlertStreamService(
      alertService: alertService,
      logger: logger,
      dataStore: dataStore,
    );
    notificationService = NotificationService(
      alertService: alertService,
      logger: logger,
    );
    alertActionsService = AlertActionsService(
      alertService: alertService,
      aiService: aiService,
      logger: logger,
      dataStore: dataStore,
    );
  }
}
