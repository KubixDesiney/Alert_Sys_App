import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert_model.dart';
import '../services/work_instruction_service.dart';
import '../theme.dart';
import '../utils/alert_meta.dart';
import 'alert_detail_screen.dart';

class AlertScanScreen extends StatefulWidget {
  final bool isActive;
  const AlertScanScreen({super.key, required this.isActive});

  @override
  State<AlertScanScreen> createState() => _AlertScanScreenState();
}

class _AlertScanScreenState extends State<AlertScanScreen> {
  final WorkInstructionService _service = WorkInstructionService();
  final TextEditingController _qrController = TextEditingController();
  final TextEditingController _factoryController = TextEditingController();
  final TextEditingController _conveyorController = TextEditingController();
  final TextEditingController _stationController = TextEditingController();

  _ScannedLocation? _location;
  StreamSubscription<List<AlertModel>>? _historySub;
  List<AlertModel> _history = const [];
  bool _historyLoading = false;
  String? _historyError;

  @override
  void dispose() {
    _historySub?.cancel();
    _qrController.dispose();
    _factoryController.dispose();
    _conveyorController.dispose();
    _stationController.dispose();
    super.dispose();
  }

  void _useQrText() {
    final loc = _ScannedLocation.tryParse(_qrController.text);
    if (loc == null) {
      _showMessage('That text is not a valid station QR payload.');
      return;
    }
    _selectLocation(loc);
  }

  void _useManualFields() {
    final usine = _factoryController.text.trim();
    final convoyeur = int.tryParse(_conveyorController.text.trim());
    final poste = int.tryParse(_stationController.text.trim());
    if (usine.isEmpty || convoyeur == null || poste == null) {
      _showMessage('Enter a factory, conveyor number, and station number.');
      return;
    }
    _selectLocation(
      _ScannedLocation(usine: usine, convoyeur: convoyeur, poste: poste),
    );
  }

  void _selectLocation(_ScannedLocation loc) {
    setState(() => _location = loc);
    _bindHistory(loc);
    _showMessage(
        'Station loaded: ${loc.usine} / C${loc.convoyeur} / P${loc.poste}');
  }

  void _bindHistory(_ScannedLocation loc) {
    _historySub?.cancel();
    setState(() {
      _historyLoading = true;
      _historyError = null;
      _history = const [];
    });
    _historySub = _service
        .historyAtLocation(
      usine: loc.usine,
      convoyeur: loc.convoyeur,
      poste: loc.poste,
    )
        .listen(
      (alerts) {
        if (!mounted) return;
        setState(() {
          _history = alerts;
          _historyLoading = false;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _historyError = e.toString();
          _historyLoading = false;
        });
      },
    );
  }

  void _reset() {
    _historySub?.cancel();
    _historySub = null;
    setState(() {
      _location = null;
      _history = const [];
      _historyLoading = false;
      _historyError = null;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      color: t.scaffold,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(location: _location, onRescan: _reset),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _WebScanCard(
                qrController: _qrController,
                factoryController: _factoryController,
                conveyorController: _conveyorController,
                stationController: _stationController,
                location: _location,
                onUseQr: _useQrText,
                onUseManual: _useManualFields,
                onReset: _reset,
              ),
            ),
            Expanded(
              child: _HistorySection(
                location: _location,
                loading: _historyLoading,
                error: _historyError,
                history: _history,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannedLocation {
  final String usine;
  final int convoyeur;
  final int poste;
  const _ScannedLocation({
    required this.usine,
    required this.convoyeur,
    required this.poste,
  });

  static _ScannedLocation? tryParse(String raw) {
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
        if (decoded is Map)
          return _fromMap(Map<Object?, Object?>.from(decoded));
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

  static _ScannedLocation? _fromMap(Map<Object?, Object?> data) {
    final encodedLocation = _firstString(data, const [
      'adresse',
      'address',
      'locationKey',
      'location',
    ]);
    if (encodedLocation != null) {
      final loc =
          _fromAddress(encodedLocation) ?? _fromLocationKey(encodedLocation);
      if (loc != null) return loc;
    }
    final usine = _firstString(data, const [
      'usine',
      'factory',
      'factoryName',
      'plant',
      'site',
    ]);
    final convoyeur = _firstInt(data, const [
      'convoyeur',
      'conveyor',
      'conveyorNumber',
      'line',
      'lineNumber',
    ]);
    final poste = _firstInt(data, const [
      'poste',
      'post',
      'station',
      'stationNumber',
      'workstation',
      'workstationNumber',
    ]);
    if (usine == null || convoyeur == null || poste == null) return null;
    return _ScannedLocation(usine: usine, convoyeur: convoyeur, poste: poste);
  }

  static _ScannedLocation? _fromAddress(String raw) {
    final address = Uri.decodeFull(raw).trim();
    final match = RegExp(r'^(.+)_C(\d+)_P(\d+)$', caseSensitive: false)
        .firstMatch(address);
    if (match == null) return null;
    return _ScannedLocation(
      usine: match.group(1)!.replaceAll('_', ' '),
      convoyeur: int.parse(match.group(2)!),
      poste: int.parse(match.group(3)!),
    );
  }

  static _ScannedLocation? _fromLocationKey(String raw) {
    final parts = raw.split('|').map((p) => p.trim()).toList();
    if (parts.length != 3 || parts.any((p) => p.isEmpty)) return null;
    final convoyeur = int.tryParse(parts[1]);
    final poste = int.tryParse(parts[2]);
    if (convoyeur == null || poste == null) return null;
    return _ScannedLocation(
        usine: parts[0], convoyeur: convoyeur, poste: poste);
  }

  static String? _firstString(Map<Object?, Object?> data, List<String> keys) {
    for (final key in keys) {
      final text = data[key]?.toString().trim();
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
      if (embeddedNumber != null) return int.tryParse(embeddedNumber.group(0)!);
    }
    return null;
  }

  @override
  String toString() => '$usine - Conveyor $convoyeur - Post $poste';
}

class _Header extends StatelessWidget {
  final _ScannedLocation? location;
  final VoidCallback onRescan;
  const _Header({required this.location, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.navyLt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.qr_code_scanner, color: t.navy, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alert Scan',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  location == null
                      ? 'Web mode: paste QR text or enter the station'
                      : location.toString(),
                  style: TextStyle(color: t.muted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (location != null)
            IconButton(
              tooltip: 'Reset',
              onPressed: onRescan,
              icon: Icon(Icons.refresh, color: t.navy),
            ),
        ],
      ),
    );
  }
}

class _WebScanCard extends StatelessWidget {
  final TextEditingController qrController;
  final TextEditingController factoryController;
  final TextEditingController conveyorController;
  final TextEditingController stationController;
  final _ScannedLocation? location;
  final VoidCallback onUseQr;
  final VoidCallback onUseManual;
  final VoidCallback onReset;

  const _WebScanCard({
    required this.qrController,
    required this.factoryController,
    required this.conveyorController,
    required this.stationController,
    required this.location,
    required this.onUseQr,
    required this.onUseManual,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.web_asset, color: t.navy, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Web Station Lookup',
                  style: TextStyle(
                    color: t.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (location != null)
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reset'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: qrController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'QR payload or station link',
              prefixIcon: Icon(Icons.qr_code_2),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => onUseQr(),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onUseQr,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Load QR'),
            ),
          ),
          const Divider(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final fields = [
                Expanded(
                  flex: compact ? 0 : 2,
                  child: TextField(
                    controller: factoryController,
                    decoration: const InputDecoration(
                      labelText: 'Factory',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: conveyorController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Conveyor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: stationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Station',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ];
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final field in fields) ...[
                      field,
                      const SizedBox(height: 10),
                    ],
                    FilledButton.icon(
                      onPressed: onUseManual,
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('Load History'),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  fields[0],
                  const SizedBox(width: 10),
                  fields[1],
                  const SizedBox(width: 10),
                  fields[2],
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: onUseManual,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Load History'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final _ScannedLocation? location;
  final bool loading;
  final String? error;
  final List<AlertModel> history;

  const _HistorySection({
    required this.location,
    required this.loading,
    required this.error,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (location == null) {
      return _PlaceholderState(
        icon: Icons.qr_code_scanner,
        title: 'No station loaded',
        message: 'Paste a station QR payload or enter a station manually.',
      );
    }
    if (error != null) {
      return _PlaceholderState(
        icon: Icons.error_outline,
        title: 'Could not load history',
        message: error!,
      );
    }
    if (loading) return const Center(child: CircularProgressIndicator());

    final resolvedCount = history.where((a) => a.status == 'validee').length;
    final activeCount = history.length - resolvedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: t.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Workstation History',
                  style: TextStyle(
                    color: t.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (history.isNotEmpty) ...[
                _MiniBadge(
                  icon: Icons.bolt,
                  label: '$activeCount active',
                  color: t.orange,
                  bg: t.orangeLt,
                ),
                const SizedBox(width: 6),
                _MiniBadge(
                  icon: Icons.verified,
                  label: '$resolvedCount fixed',
                  color: t.green,
                  bg: t.greenLt,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: history.isEmpty
              ? _PlaceholderState(
                  icon: Icons.inbox,
                  title: 'No alerts yet',
                  message: 'No alerts have been recorded at this station.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _AlertHistoryCard(alert: history[i]),
                ),
        ),
      ],
    );
  }
}

class _PlaceholderState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _PlaceholderState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration:
                  BoxDecoration(color: t.navyLt, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: t.navy),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: t.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertHistoryCard extends StatelessWidget {
  final AlertModel alert;
  const _AlertHistoryCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final type = typeMeta(alert.type, t);
    final status = statusMeta(alert.status, t);
    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlertDetailScreen(alertId: alert.id),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: type.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(type.icon, color: type.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${DateFormat('MMM d, h:mm a').format(alert.timestamp)} - ${alert.description}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: status.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
