import 'data_store.dart';
import 'firebase_data_store.dart';
import 'pocketbase_data_store.dart';

/// Build-time backend selection:
///   --dart-define=SIA_BACKEND=pocketbase
///   --dart-define=SIA_POCKETBASE_URL=https://sia.plant.local
///   --dart-define=SIA_POCKETBASE_TOKEN=...
/// Defaults to Firebase. NOT wired into the app yet — provided so callers can
/// later depend on [DataStore] and flip backends with no logic change.
const String kSiaBackend =
    String.fromEnvironment('SIA_BACKEND', defaultValue: 'firebase');
const String kSiaPocketBaseUrl =
    String.fromEnvironment('SIA_POCKETBASE_URL', defaultValue: '');
const String kSiaPocketBaseToken =
    String.fromEnvironment('SIA_POCKETBASE_TOKEN', defaultValue: '');

DataStore createDataStore() {
  if (kSiaBackend.toLowerCase() == 'pocketbase') {
    return PocketBaseDataStore(
      baseUrl: kSiaPocketBaseUrl,
      token: kSiaPocketBaseToken,
    );
  }
  return FirebaseDataStore();
}
