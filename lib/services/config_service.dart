import 'dart:convert';
import 'package:http/http.dart' as http;

class RemoteConfig {
  final String onesignalAppId;
  RemoteConfig({required this.onesignalAppId});
}

class ConfigService {
  static const String configUrl =
      'https://alert-notifier.aziz-nagati01.workers.dev/'; // Replace with actual worker URL

  static Future<RemoteConfig> fetchConfig() async {
    final response = await http.get(Uri.parse(configUrl)).timeout(
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
