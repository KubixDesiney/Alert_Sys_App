import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  static const String _apiKey = 'AIzaSyAQzILti43Tk2JuqHOeYD5crSc_QNkk680';
  
  final GenerativeModel _model = GenerativeModel(
    model: 'gemini-2.5-flash-lite',
    apiKey: _apiKey,
  );

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
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? 'No suggestion available.';
    } catch (e) {
      return 'Error generating suggestion: $e';
    }
  }
}