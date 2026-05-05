import 'package:http/http.dart' as http;
import 'dart:convert';

const String _workerBaseUrl = 'https://alert-notifier.aziz-nagati01.workers.dev';

class AIService {
  Future<String> getResolutionSuggestion({
    required String alertType,
    required String alertDescription,
    required String usine,
    required int convoyeur,
    required int poste,
    List<String> pastResolutions = const [],
  }) async {
    try {
      // /ai-suggest fetches Firebase history itself and uses Llama 3.2.
      final response = await http.post(
        Uri.parse('$_workerBaseUrl/ai-suggest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': alertType,
          'usine': usine,
          'convoyeur': convoyeur,
          'poste': poste,
          'description': alertDescription,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['suggestion'] ?? 'No suggestion available.';
      }
      return 'Error generating suggestion: HTTP ${response.statusCode}';
    } catch (e) {
      return 'Error generating suggestion: $e';
    }
  }
}
