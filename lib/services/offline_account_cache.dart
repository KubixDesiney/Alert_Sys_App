import 'package:shared_preferences/shared_preferences.dart';

class OfflineAccountCache {
  static const _rolePrefix = 'offline_account_role_';
  static const _usinePrefix = 'offline_account_usine_';

  static bool isValidRole(String? role) =>
      role == 'admin' || role == 'supervisor';

  static Future<void> save({
    required String uid,
    String? role,
    String? usine,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (isValidRole(role)) {
      await prefs.setString('$_rolePrefix$uid', role!);
    }
    final cleanUsine = usine?.trim();
    if (cleanUsine != null && cleanUsine.isNotEmpty) {
      await prefs.setString('$_usinePrefix$uid', cleanUsine);
    }
  }

  static Future<String?> roleFor(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('$_rolePrefix$uid');
    return isValidRole(role) ? role : null;
  }

  static Future<String?> usineFor(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final usine = prefs.getString('$_usinePrefix$uid')?.trim();
    return usine == null || usine.isEmpty ? null : usine;
  }
}
