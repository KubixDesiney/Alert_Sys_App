import 'package:http/http.dart' as http;
import 'dart:convert';

class AIService {
  static const String _workerUrl = 'https://alert-notifier.aziz-nagati01.workers.dev/gemini-proxy';

  Future<String> getResolutionSuggestion({
    required String alertType,
    required String alertDescription,
    required String usine,
    required int convoyeur,
    required int poste,
    List<String> pastResolutions = const [],
  }) async {
    final locationInfo = 'Plant: $usine, Line: $convoyeur, Workstation: $poste';
    final prompt = '''
You are an industrial maintenance assistant. Suggest a resolution for the following alert:

Alert type: $alertType
Description: $alertDescription
Location: $locationInfo

${pastResolutions.isNotEmpty ? 'Past resolutions for the EXACT SAME location and alert type:\n' + pastResolutions.map((r) => '- $r').join('\n') : 'No past resolutions found for this specific location.'}

Provide a concise, actionable resolution suggestion (2-3 bullet points). Focus on the most likely cause and fix. If past resolutions exist, prioritize them.
''';
    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
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
