import 'dart:convert';

class LocationAlertScanTarget {
  final String? assetId;
  final String usine;
  final int convoyeur;
  final int poste;

  const LocationAlertScanTarget({
    this.assetId,
    required this.usine,
    required this.convoyeur,
    required this.poste,
  });

  static LocationAlertScanTarget? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return _fromMap(Map<Object?, Object?>.from(decoded));
      if (decoded is String && decoded != text) return tryParse(decoded);
    } catch (_) {}

    if (text.contains(r'\"')) {
      try {
        final decoded = jsonDecode(text.replaceAll(r'\"', '"'));
        if (decoded is Map) {
          return _fromMap(Map<Object?, Object?>.from(decoded));
        }
      } catch (_) {}
    }

    final uri = Uri.tryParse(text);
    if (uri != null) {
      if (uri.queryParameters.isNotEmpty) {
        final fromQuery = _fromMap(uri.queryParameters);
        if (fromQuery != null) return fromQuery;
      }
      if (uri.pathSegments.isNotEmpty) {
        final fromPath = _fromAddress(uri.pathSegments.last);
        if (fromPath != null) return fromPath;
      }
    }
    return _fromAddress(text) ?? _fromLocationKey(text);
  }

  static LocationAlertScanTarget? _fromMap(Map<Object?, Object?> data) {
    final assetId = _firstString(data, const [
      'assetId',
      'asset_id',
      'machineId',
      'machine_id',
    ]);
    final encodedLocation = _firstString(data, const [
      'adresse',
      'address',
      'locationKey',
      'location',
    ]);
    if (encodedLocation != null) {
      final loc =
          _fromAddress(encodedLocation) ?? _fromLocationKey(encodedLocation);
      if (loc != null) {
        return LocationAlertScanTarget(
          assetId: assetId,
          usine: loc.usine,
          convoyeur: loc.convoyeur,
          poste: loc.poste,
        );
      }
    }

    final usine = _firstString(data, const ['usine', 'factory', 'factoryName']);
    final convoyeur = _firstInt(data, const ['convoyeur', 'conveyor']);
    final poste = _firstInt(data, const ['poste', 'station', 'workstation']);
    if (usine == null || convoyeur == null || poste == null) return null;

    return LocationAlertScanTarget(
      assetId: assetId,
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
    );
  }

  static LocationAlertScanTarget? _fromAddress(String raw) {
    final address = Uri.decodeFull(raw).trim();
    final underscoreMatch = RegExp(
      r'^(.+)_C(\d+)_P(\d+)$',
      caseSensitive: false,
    ).firstMatch(address);
    if (underscoreMatch != null) {
      return LocationAlertScanTarget(
        usine: underscoreMatch.group(1)!.replaceAll('_', ' '),
        convoyeur: int.parse(underscoreMatch.group(2)!),
        poste: int.parse(underscoreMatch.group(3)!),
      );
    }

    final dashedMatch = RegExp(
      r'^\s*(.+?)\s*-\s*(?:C|Conv(?:oyeur)?)\s*0*(\d+)\s*-\s*(?:P|Poste?|Station|WS)\s*0*(\d+)\s*$',
      caseSensitive: false,
    ).firstMatch(address);
    if (dashedMatch == null) return null;
    return LocationAlertScanTarget(
      usine: dashedMatch.group(1)!.trim(),
      convoyeur: int.parse(dashedMatch.group(2)!),
      poste: int.parse(dashedMatch.group(3)!),
    );
  }

  static LocationAlertScanTarget? _fromLocationKey(String raw) {
    final parts = raw.split('|').map((e) => e.trim()).toList();
    if (parts.length != 3) return null;
    final convoyeur = int.tryParse(parts[1]);
    final poste = int.tryParse(parts[2]);
    if (parts[0].isEmpty || convoyeur == null || poste == null) return null;
    return LocationAlertScanTarget(
      usine: parts[0],
      convoyeur: convoyeur,
      poste: poste,
    );
  }

  static String? _firstString(Map<Object?, Object?> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static int? _firstInt(Map<Object?, Object?> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toInt();
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) continue;
      final exact = int.tryParse(text);
      if (exact != null) return exact;
      final embeddedNumber = RegExp(r'\d+').firstMatch(text);
      if (embeddedNumber != null) {
        return int.tryParse(embeddedNumber.group(0)!);
      }
    }
    return null;
  }

  @override
  String toString() {
    final assetPrefix = assetId == null ? '' : '$assetId - ';
    return '$assetPrefix$usine / C$convoyeur / P$poste';
  }
}
