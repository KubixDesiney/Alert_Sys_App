import 'dart:convert';
import 'package:http/http.dart' as http;

import 'worker_auth_config.dart';

class RemoteConfig {
  final String onesignalAppId;
  RemoteConfig({required this.onesignalAppId});
}

class ConfigService {
  static String get configUrl => '${WorkerAuthConfig.baseUrl}/config';

  static Future<RemoteConfig> fetchConfig() async {
    final response = await http
        .get(Uri.parse(configUrl), headers: WorkerAuthConfig.headers())
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw Exception('Config fetch timeout'),
        );
    if (response.statusCode != 200) {
      throw Exception('Failed to load config: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RemoteConfig(onesignalAppId: data['onesignalAppId'] as String);
  }
}
