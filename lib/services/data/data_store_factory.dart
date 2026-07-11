import 'data_store.dart';
import 'firebase_data_store.dart';
import 'pocketbase_data_store.dart';

/// Build-time backend selection:
///   --dart-define=SIAS_BACKEND=pocketbase
///   --dart-define=SIAS_POCKETBASE_URL=https://sias.plant.local
///   --dart-define=SIAS_POCKETBASE_TOKEN=...   (optional service token; the
///     signed-in user's session token from PocketBaseAuthService wins)
/// Defaults to Firebase. `ServiceLocator.init()` builds the app-wide instance
/// and hands it to AlertActionsService / AlertStreamService.
const String kSiaBackend =
    String.fromEnvironment('SIAS_BACKEND', defaultValue: 'firebase');
const String kSiaPocketBaseUrl =
    String.fromEnvironment('SIAS_POCKETBASE_URL', defaultValue: '');
const String kSiaPocketBaseToken =
    String.fromEnvironment('SIAS_POCKETBASE_TOKEN', defaultValue: '');

/// True when the app was built for the on-prem PocketBase backend. Callers use
/// this to skip Firebase-only side paths (FirebaseAuth identity, FCM worker
/// triggers, RTDB notification fan-out) without changing Firebase behaviour.
bool get isPocketBaseBackend => kSiaBackend.toLowerCase() == 'pocketbase';

DataStore createDataStore() {
  if (isPocketBaseBackend) {
    return PocketBaseDataStore(
      baseUrl: kSiaPocketBaseUrl,
      token: kSiaPocketBaseToken,
    );
  }
  return FirebaseDataStore();
}
