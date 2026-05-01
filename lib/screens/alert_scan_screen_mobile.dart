import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/alert_model.dart';
import '../services/work_instruction_service.dart';
import '../theme.dart';
import '../utils/alert_meta.dart';
import 'alert_detail_screen.dart';

/// "Alert Scan" tab — live QR camera on top, workstation alert history below.
///
/// [isActive] is forwarded from the parent PageView so the camera only runs
/// while this page is visible (saves battery and avoids permission prompts
/// on adjacent pages).
class AlertScanScreen extends StatefulWidget {
  final bool isActive;
  const AlertScanScreen({super.key, required this.isActive});

  @override
  State<AlertScanScreen> createState() => _AlertScanScreenState();
}

class _AlertScanScreenState extends State<AlertScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: true,
    cameraResolution: const Size(1920, 1080),
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final WorkInstructionService _service = WorkInstructionService();

  bool _permissionChecked = false;
  bool _cameraGranted = false;
  String? _permissionError;

  _ScannedLocation? _location;
  bool _torchOn = false;
  DateTime? _lastInvalidQrNotice;

  StreamSubscription<List<AlertModel>>? _historySub;
  List<AlertModel> _history = const [];
  bool _historyLoading = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _ensureCamera();
  }

  @override
  void didUpdateWidget(covariant AlertScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _ensureCamera();
    } else if (!widget.isActive && oldWidget.isActive) {
      unawaited(_scannerController.stop());
    }
  }

  @override
  void dispose() {
    _historySub?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  Future<void> _ensureCamera() async {
    if (_permissionChecked && _cameraGranted) return;
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _permissionChecked = true;
      _cameraGranted = status.isGranted;
      _permissionError = status.isPermanentlyDenied
          ? 'Camera permission permanently denied. Open Settings to enable it.'
          : (status.isGranted ? null : 'Camera permission denied.');
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_location != null) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final loc = _ScannedLocation.tryParse(raw);
      if (loc == null) {
        _showInvalidQrNotice();
        continue;
      }
      unawaited(_scannerController.stop());
      setState(() => _location = loc);
      _showScannedNotice(loc);
      _bindHistory(loc);
      return;
    }
  }

  void _showScannedNotice(_ScannedLocation loc) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Station scanned: ${loc.usine} / C${loc.convoyeur} / P${loc.poste}',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showInvalidQrNotice() {
    final now = DateTime.now();
    if (_lastInvalidQrNotice != null &&
        now.difference(_lastInvalidQrNotice!) < const Duration(seconds: 3)) {
      return;
    }
    _lastInvalidQrNotice = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR code detected, but it is not a station QR.'),
        duration: Duration(seconds: 2),
      ),
    );
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
      assetId: loc.assetId,
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

  void _resetScan() {
    _historySub?.cancel();
    _historySub = null;
    setState(() {
      _location = null;
      _history = const [];
      _historyLoading = false;
      _historyError = null;
    });
  }

  Future<void> _toggleTorch() async {
    await _scannerController.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      color: t.scaffold,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(location: _location, onRescan: _resetScan),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _CameraCard(
                permissionChecked: _permissionChecked,
                cameraGranted: _cameraGranted,
                permissionError: _permissionError,
                location: _location,
                torchOn: _torchOn,
                controller: _scannerController,
                onDetect: _onDetect,
                onToggleTorch: _toggleTorch,
                onRescan: _resetScan,
                onRetryPermission: _ensureCamera,
                onOpenSettings: openAppSettings,
                isActive: widget.isActive,
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

// =============================================================================
// QR payload
// =============================================================================
class _ScannedLocation {
  final String? assetId;
  final String usine;
  final int convoyeur;
  final int poste;
  const _ScannedLocation({
    this.assetId,
    required this.usine,
    required this.convoyeur,
    required this.poste,
  });

  static _ScannedLocation? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return _fromMap(Map<Object?, Object?>.from(decoded));
      }
      if (decoded is String && decoded != text) {
        return tryParse(decoded);
      }
    } catch (_) {
      // Not JSON. Continue with URL/address formats below.
    }

    if (text.contains(r'\"')) {
      try {
        final decoded = jsonDecode(text.replaceAll(r'\"', '"'));
        if (decoded is Map) {
          return _fromMap(Map<Object?, Object?>.from(decoded));
        }
      } catch (_) {
        // Not backslash-escaped JSON either.
      }
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
      final fromEncoded =
          _fromAddress(encodedLocation) ?? _fromLocationKey(encodedLocation);
      if (fromEncoded != null) {
        return _ScannedLocation(
          assetId: assetId,
          usine: fromEncoded.usine,
          convoyeur: fromEncoded.convoyeur,
          poste: fromEncoded.poste,
        );
      }
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
    return _ScannedLocation(
      assetId: assetId,
      usine: usine,
      convoyeur: convoyeur,
      poste: poste,
    );
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
    return '$assetPrefix$usine - Conveyor $convoyeur - Post $poste';
  }
}

// =============================================================================
// Header
// =============================================================================
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
                      ? 'Scan a station to view its history'
                      : location.toString(),
                  style: TextStyle(color: t.muted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (location != null)
            IconButton(
              tooltip: 'Rescan',
              onPressed: onRescan,
              icon: Icon(Icons.refresh, color: t.navy),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Camera card
// =============================================================================
class _CameraCard extends StatelessWidget {
  final bool permissionChecked;
  final bool cameraGranted;
  final String? permissionError;
  final _ScannedLocation? location;
  final bool torchOn;
  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final VoidCallback onToggleTorch;
  final VoidCallback onRescan;
  final VoidCallback onRetryPermission;
  final Future<bool> Function() onOpenSettings;
  final bool isActive;

  const _CameraCard({
    required this.permissionChecked,
    required this.cameraGranted,
    required this.permissionError,
    required this.location,
    required this.torchOn,
    required this.controller,
    required this.onDetect,
    required this.onToggleTorch,
    required this.onRescan,
    required this.onRetryPermission,
    required this.onOpenSettings,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final mq = MediaQuery.of(context);
    // Camera takes ~36% of screen height in portrait, capped on tablets.
    final h = (mq.size.height * 0.36).clamp(220.0, 360.0);

    Widget content;
    if (!permissionChecked) {
      content = const Center(
        child: CircularProgressIndicator(),
      );
    } else if (!isActive) {
      content = const Center(
        child: Text(
          'Scanner paused',
          style: TextStyle(color: Colors.white70),
        ),
      );
    } else if (!cameraGranted) {
      content = _PermissionView(
        message: permissionError ?? 'Camera permission required.',
        onRetry: onRetryPermission,
        onOpenSettings: onOpenSettings,
      );
    } else if (location != null) {
      content = _ScannedConfirmation(location: location!, onRescan: onRescan);
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            onDetect: onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Camera error: ${error.errorDetails?.message ?? error.errorCode.name}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const _Reticle(),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _HintBanner(
              text: 'Point the camera at the station QR sticker',
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: _TorchButton(on: torchOn, onTap: onToggleTorch),
          ),
        ],
      );
    }

    return Container(
      height: h,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, c) {
          final side = c.biggest.shortestSide * 0.62;
          return Center(
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2.5),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  final String text;
  const _HintBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const _TorchButton({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            on ? Icons.flash_on : Icons.flash_off,
            color: on ? Colors.amberAccent : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _ScannedConfirmation extends StatelessWidget {
  final _ScannedLocation location;
  final VoidCallback onRescan;
  const _ScannedConfirmation({required this.location, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0D4A75),
            const Color(0xFF0D4A75).withValues(alpha: 0.75),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Station Scanned',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                location.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRescan,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Scan another',
                  style: TextStyle(color: Colors.white),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white70),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
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

class _PermissionView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final Future<bool> Function() onOpenSettings;
  const _PermissionView({
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  child: const Text('Retry'),
                ),
                ElevatedButton(
                  onPressed: () => onOpenSettings(),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// History section
// =============================================================================
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
        title: 'No station scanned',
        message:
            'Point the camera at a station QR code above to load its full alert history.',
      );
    }
    if (error != null) {
      return _PlaceholderState(
        icon: Icons.error_outline,
        title: 'Could not load history',
        message: error!,
      );
    }
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

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
                  message:
                      'No alerts have ever been raised at this station. Once one is created it will appear here.',
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
              decoration: BoxDecoration(
                color: t.navyLt,
                shape: BoxShape.circle,
              ),
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
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
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

// =============================================================================
// Alert card
// =============================================================================
class _AlertHistoryCard extends StatelessWidget {
  final AlertModel alert;
  const _AlertHistoryCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final type = _typeMeta(alert.type, t);
    final status = _statusMeta(alert.status, t);

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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: context.isDark ? 0.25 : 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top accent stripe so the type colour is visible at a glance.
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: type.color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderRow(t, type, status),
                    const SizedBox(height: 8),
                    if (alert.description.isNotEmpty)
                      Text(
                        alert.description,
                        style: TextStyle(
                          color: t.text,
                          fontSize: 13.5,
                          height: 1.35,
                        ),
                      ),
                    const SizedBox(height: 10),
                    _buildMetaWrap(t),
                    if (alert.resolutionReason != null &&
                        alert.resolutionReason!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _ResolutionBlock(
                        reason: alert.resolutionReason!,
                        elapsedMinutes: alert.elapsedTime,
                      ),
                    ],
                    if (alert.comments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 14, color: t.muted),
                          const SizedBox(width: 6),
                          Text(
                            '${alert.comments.length} comment${alert.comments.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(AppTheme t, _Meta type, _Meta status) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              Row(
                children: [
                  Flexible(
                    child: Text(
                      type.label,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (alert.isCritical) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.local_fire_department, size: 14, color: t.red),
                  ],
                  if (alert.aiAssigned) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.auto_awesome, size: 13, color: t.purple),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                alert.alertNumber > 0
                    ? '#${alert.alertNumber} · ${_shortId(alert.id)}'
                    : _shortId(alert.id),
                style: TextStyle(
                  color: t.muted,
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _StatusPill(meta: status),
      ],
    );
  }

  Widget _buildMetaWrap(AppTheme t) {
    final occurred = _MetaItem(
      icon: Icons.event,
      label: _formatDateTime(alert.timestamp),
    );
    final relative = _MetaItem(
      icon: Icons.schedule,
      label: _relativeTime(alert.timestamp),
    );
    final claimed = alert.superviseurName != null
        ? _MetaItem(
            icon: Icons.person,
            label: alert.superviseurName!,
          )
        : null;
    final assistant = alert.assistantName != null
        ? _MetaItem(
            icon: Icons.handshake,
            label: alert.assistantName!,
          )
        : null;
    final taken = alert.takenAtTimestamp != null
        ? _MetaItem(
            icon: Icons.play_circle_outline,
            label: 'Taken ${_formatTime(alert.takenAtTimestamp!)}',
          )
        : null;
    final escalated = alert.isEscalated
        ? _MetaItem(
            icon: Icons.trending_up,
            label: 'Escalated',
            tone: t.orange,
          )
        : null;

    final items = <_MetaItem>[
      occurred,
      relative,
      if (taken != null) taken,
      if (claimed != null) claimed,
      if (assistant != null) assistant,
      if (escalated != null) escalated,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items
          .map((it) => _MetaChip(
                icon: it.icon,
                label: it.label,
                tone: it.tone ?? t.muted,
              ))
          .toList(),
    );
  }

  String _shortId(String id) => id.length <= 8
      ? id
      : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final sameYear = dt.year == now.year;
    final df = sameYear
        ? DateFormat('MMM d, h:mm a')
        : DateFormat('MMM d yyyy, h:mm a');
    return df.format(dt);
  }

  String _formatTime(DateTime dt) => DateFormat('h:mm a').format(dt);

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}

class _MetaItem {
  final IconData icon;
  final String label;
  final Color? tone;
  const _MetaItem({required this.icon, required this.label, this.tone});
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            t.scaffold == t.card ? t.border.withValues(alpha: 0.4) : t.scaffold,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: tone),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tone,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _Meta meta;
  const _StatusPill({required this.meta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: meta.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: meta.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 12, color: meta.color),
          const SizedBox(width: 4),
          Text(
            meta.label,
            style: TextStyle(
              color: meta.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolutionBlock extends StatelessWidget {
  final String reason;
  final int? elapsedMinutes;
  const _ResolutionBlock({required this.reason, required this.elapsedMinutes});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.greenLt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: t.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Resolution',
                      style: TextStyle(
                        color: t.green,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (elapsedMinutes != null && elapsedMinutes! > 0) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.timer_outlined, size: 12, color: t.green),
                      const SizedBox(width: 3),
                      Text(
                        _formatElapsed(elapsedMinutes!),
                        style: TextStyle(
                          color: t.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}min' : '${h}h';
  }
}

// =============================================================================
// Type / status meta — local aliases that defer to lib/utils/alert_meta.dart
// (single source of truth across all screens).
// =============================================================================
typedef _Meta = AlertMeta;

AlertMeta _typeMeta(String type, AppTheme t) => typeMeta(type, t);
AlertMeta _statusMeta(String status, AppTheme t) => statusMeta(status, t);
