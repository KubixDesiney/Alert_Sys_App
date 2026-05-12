String? normalizePredictiveFactory(String? factory) {
  final value = factory?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.toLowerCase() == 'all') return null;
  return value;
}

String? predictiveFactorySlug(String? factory) {
  final scope = normalizePredictiveFactory(factory);
  if (scope == null) return null;
  final slug = scope
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  return slug.isEmpty ? null : slug;
}

String predictiveBriefingPath(String? factory) {
  final slug = predictiveFactorySlug(factory);
  if (slug == null) return 'ai_briefing/latest';
  return 'ai_briefing/factory/$slug/latest';
}

String predictivePredictionsPath(String? factory) {
  final slug = predictiveFactorySlug(factory);
  if (slug == null) return 'ai_predictions/latest';
  return 'ai_predictions/factory/$slug/latest';
}
