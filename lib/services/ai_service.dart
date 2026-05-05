import 'package:http/http.dart' as http;
import 'dart:convert';

const String _workerBaseUrl = 'https://alert-notifier.aziz-nagati01.workers.dev';

class AIService {
  static String get _workerUrl => '$_workerBaseUrl/ai-proxy';

  static const _typeLabels = {
    'qualite': 'Quality',
    'maintenance': 'Maintenance',
    'defaut_produit': 'Damaged Product',
    'manque_ressource': 'Resource Deficiency',
  };

  Future<String> getResolutionSuggestion({
    required String alertType,
    required String alertDescription,
    required String usine,
    required int convoyeur,
    required int poste,
    List<String> pastResolutions = const [],
  }) async {
    final typeLabel = _typeLabels[alertType] ?? alertType;
    final locationInfo =
        'Factory: $usine, Conveyor line: $convoyeur, Workstation ID: #$poste';
    final prompt = '''
You are an industrial operations assistant. A supervisor needs a resolution suggestion for the following alert:

Alert type: $typeLabel
Description: $alertDescription
Location: $locationInfo

${pastResolutions.isNotEmpty ? 'Past resolutions logged for this alert type at this location:\n' + pastResolutions.map((r) => '- $r').join('\n') : 'No past resolutions on record for this specific location.'}

Provide a concise, actionable resolution suggestion in 2-3 bullet points. Focus on the most likely root cause and immediate fix based on the alert type and description. If past resolutions exist, prioritize the most relevant one.
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
