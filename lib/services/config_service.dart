import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class RemoteConfig {
  final String onesignalAppId;
  RemoteConfig({required this.onesignalAppId});
}

class ConfigService {
  static String get configUrl => AppConfig.configEndpoint;

  static Future<RemoteConfig> fetchConfig() async {
    final response = await http
        .get(Uri.parse(configUrl))
        .timeout(
          AppConfig.shortRequestTimeout,
          onTimeout: () => throw Exception('Config fetch timeout'),
        );
    if (response.statusCode != 200) {
      throw Exception('Failed to load config: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return RemoteConfig(onesignalAppId: data['onesignalAppId'] as String);
  }
}
