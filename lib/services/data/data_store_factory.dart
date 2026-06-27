import 'data_store.dart';
import 'firebase_data_store.dart';
import 'pocketbase_data_store.dart';

/// Build-time backend selection:
///   --dart-define=SIAS_BACKEND=pocketbase
///   --dart-define=SIAS_POCKETBASE_URL=https://sias.plant.local
///   --dart-define=SIAS_POCKETBASE_TOKEN=...
/// Defaults to Firebase. NOT wired into the app yet — provided so callers can
/// later depend on [DataStore] and flip backends with no logic change.
const String kSiaBackend =
    String.fromEnvironment('SIAS_BACKEND', defaultValue: 'firebase');
const String kSiaPocketBaseUrl =
    String.fromEnvironment('SIAS_POCKETBASE_URL', defaultValue: '');
const String kSiaPocketBaseToken =
    String.fromEnvironment('SIAS_POCKETBASE_TOKEN', defaultValue: '');

DataStore createDataStore() {
  if (kSiaBackend.toLowerCase() == 'pocketbase') {
    return PocketBaseDataStore(
      baseUrl: kSiaPocketBaseUrl,
      token: kSiaPocketBaseToken,
    );
  }
  return FirebaseDataStore();
}
