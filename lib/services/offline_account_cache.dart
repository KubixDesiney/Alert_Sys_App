import 'package:shared_preferences/shared_preferences.dart';

class OfflineAccountCache {
  static const _rolePrefix = 'offline_account_role_';
  static const _usinePrefix = 'offline_account_usine_';

  /// Canonical lowercase role name, or null when unknown.
  static String? normalizeRole(String? role) {
    final r = role?.trim().toLowerCase();
    if (r == 'admin' || r == 'supervisor' || r == 'superadmin') return r;
    return null;
  }

  static bool isValidRole(String? role) => normalizeRole(role) != null;

  static Future<void> save({
    required String uid,
    String? role,
    String? usine,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeRole(role);
    if (normalized != null) {
      await prefs.setString('$_rolePrefix$uid', normalized);
    }
    final cleanUsine = usine?.trim();
    if (cleanUsine != null && cleanUsine.isNotEmpty) {
      await prefs.setString('$_usinePrefix$uid', cleanUsine);
    }
  }

  static Future<String?> roleFor(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('$_rolePrefix$uid');
    return normalizeRole(role);
  }

  static Future<String?> usineFor(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final usine = prefs.getString('$_usinePrefix$uid')?.trim();
    return usine == null || usine.isEmpty ? null : usine;
  }
}
