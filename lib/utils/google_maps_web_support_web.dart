import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('google')
external JSAny? get _googleNamespace;

bool get isGoogleMapsJsLoaded {
  final google = _googleNamespace;
  if (google == null) return false;
  return (google as JSObject).has('maps');
}

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
  final normalized = query.trim();
  if (normalized.length < 3) return const [];

  final predictions = await _placePredictions(normalized, limit: limit);
  if (predictions.isNotEmpty) {
    final suggestions = <GoogleMapsWebLocationSuggestion>[];
    for (final prediction in predictions.take(limit)) {
      final suggestion = await _geocodePlaceId(
        _jsString((prediction as JSObject)['place_id']),
        fallbackDisplayName: _jsString(prediction['description']),
      );
      if (suggestion != null) suggestions.add(suggestion);
    }
    if (suggestions.isNotEmpty) return suggestions;
  }

  return _geocodeAddressSuggestions(normalized, limit: limit);
}

Future<String?> googleMapsWebReverseGeocodeCityCountry(
  double lat,
  double lng,
) async {
  final geocoder = _newMapsObject('Geocoder');
  if (geocoder == null) return null;

  final request = {
    'location': {'lat': lat, 'lng': lng},
  }.jsify();
  final results = await _geocode(geocoder, request);
  if (results.isEmpty) return null;
  final first = results.first;
  final cityCountry = _cityCountryFromComponents(first);
  return cityCountry.isEmpty ? null : cityCountry;
}

Future<List<JSAny?>> _placePredictions(
  String query, {
  required int limit,
}) async {
  final places = _placesNamespace();
  if (places == null || !places.has('AutocompleteService')) return const [];
  final constructor = places['AutocompleteService'];
  if (constructor == null) return const [];

  try {
    final service = (constructor as JSFunction).callAsConstructor<JSObject>();
    final completer = Completer<List<JSAny?>>();
    final callback = ((JSAny? predictions, JSAny? status) {
      if (completer.isCompleted) return;
      final statusText = _jsString(status);
      if (statusText != 'OK') {
        completer.complete(const []);
        return;
      }
      completer.complete(_jsArray(predictions).take(limit).toList());
    }).toJS;
    final request = {
      'input': query,
      'types': ['geocode'],
    }.jsify();
    service.callMethodVarArgs<JSAny?>(
      'getPlacePredictions'.toJS,
      [request, callback],
    );
    return completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => const [],
    );
  } catch (_) {
    return const [];
  }
}

Future<GoogleMapsWebLocationSuggestion?> _geocodePlaceId(
  String placeId, {
  required String fallbackDisplayName,
}) async {
  if (placeId.isEmpty) return null;
  final geocoder = _newMapsObject('Geocoder');
  if (geocoder == null) return null;
  final results = await _geocode(geocoder, {'placeId': placeId}.jsify());
  if (results.isEmpty) return null;
  return _suggestionFromGeocoderResult(
    results.first,
    fallbackDisplayName: fallbackDisplayName,
  );
}

Future<List<GoogleMapsWebLocationSuggestion>> _geocodeAddressSuggestions(
  String query, {
  required int limit,
}) async {
  final geocoder = _newMapsObject('Geocoder');
  if (geocoder == null) return const [];
  final results = await _geocode(geocoder, {'address': query}.jsify());
  return results
      .take(limit)
      .map((result) => _suggestionFromGeocoderResult(
            result,
            fallbackDisplayName: query,
          ))
      .whereType<GoogleMapsWebLocationSuggestion>()
      .toList();
}

Future<List<JSObject>> _geocode(JSObject geocoder, JSAny? request) async {
  try {
    final completer = Completer<List<JSObject>>();
    final callback = ((JSAny? results, JSAny? status) {
      if (completer.isCompleted) return;
      final statusText = _jsString(status);
      if (statusText != 'OK') {
        completer.complete(const []);
        return;
      }
      completer.complete(_jsArray(results).whereType<JSObject>().toList());
    }).toJS;
    geocoder.callMethodVarArgs<JSAny?>('geocode'.toJS, [request, callback]);
    return completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => const [],
    );
  } catch (_) {
    return const [];
  }
}

GoogleMapsWebLocationSuggestion? _suggestionFromGeocoderResult(
  JSObject result, {
  required String fallbackDisplayName,
}) {
  final geometry = result['geometry'];
  if (geometry == null) return null;
  final location = (geometry as JSObject)['location'];
  if (location == null) return null;

  try {
    final point = location as JSObject;
    final lat = point.callMethod<JSNumber>('lat'.toJS).toDartDouble;
    final lng = point.callMethod<JSNumber>('lng'.toJS).toDartDouble;
    final displayName =
        _jsString(result['formatted_address']).trim().isNotEmpty
            ? _jsString(result['formatted_address']).trim()
            : fallbackDisplayName;
    final cityCountry = _cityCountryFromComponents(result);
    return GoogleMapsWebLocationSuggestion(
      displayName: displayName,
      cityCountry: cityCountry.isNotEmpty ? cityCountry : displayName,
      lat: lat,
      lng: lng,
    );
  } catch (_) {
    return null;
  }
}

String _cityCountryFromComponents(JSObject result) {
  final components = _jsArray(result['address_components']);
  var city = '';
  var country = '';

  for (final component in components.whereType<JSObject>()) {
    final longName = _jsString(component['long_name']).trim();
    if (longName.isEmpty) continue;
    final types = _jsArray(component['types']).map(_jsString).toSet();
    if (country.isEmpty && types.contains('country')) {
      country = longName;
    }
    if (city.isEmpty &&
        (types.contains('locality') ||
            types.contains('postal_town') ||
            types.contains('administrative_area_level_2') ||
            types.contains('administrative_area_level_1'))) {
      city = longName;
    }
  }

  final parts = <String>[];
  if (city.isNotEmpty) parts.add(city);
  if (country.isNotEmpty && !parts.contains(country)) parts.add(country);
  return parts.join(', ');
}

JSObject? _newMapsObject(String constructorName) {
  final maps = _mapsNamespace();
  if (maps == null || !maps.has(constructorName)) return null;
  final constructor = maps[constructorName];
  if (constructor == null) return null;
  try {
    return (constructor as JSFunction).callAsConstructor<JSObject>();
  } catch (_) {
    return null;
  }
}

JSObject? _mapsNamespace() {
  final google = _googleNamespace;
  if (google == null) return null;
  final googleObject = google as JSObject;
  if (!googleObject.has('maps')) return null;
  final maps = googleObject['maps'];
  return maps == null ? null : maps as JSObject;
}

JSObject? _placesNamespace() {
  final maps = _mapsNamespace();
  if (maps == null || !maps.has('places')) return null;
  final places = maps['places'];
  return places == null ? null : places as JSObject;
}

List<JSAny?> _jsArray(JSAny? value) {
  if (value == null) return const [];
  try {
    return (value as JSArray<JSAny?>).toDart;
  } catch (_) {
    return const [];
  }
}

String _jsString(JSAny? value) {
  if (value == null) return '';
  return value.dartify()?.toString() ?? '';
}
