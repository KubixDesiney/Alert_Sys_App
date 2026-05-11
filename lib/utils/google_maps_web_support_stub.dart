bool get isGoogleMapsJsLoaded => true;

class GoogleMapsWebLocationSuggestion {
  final String displayName;
  final String cityCountry;
  final double lat;
  final double lng;

  const GoogleMapsWebLocationSuggestion({
    required this.displayName,
    required this.cityCountry,
    required this.lat,
    required this.lng,
  });
}

Future<List<GoogleMapsWebLocationSuggestion>> googleMapsWebLocationSuggestions(
  String query, {
  int limit = 6,
}) async {
  return const [];
}

Future<String?> googleMapsWebReverseGeocodeCityCountry(
  double lat,
  double lng,
) async {
  return null;
}
