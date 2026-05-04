import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/alert_model.dart';
import '../models/work_instruction.dart';
import '../providers/alert_provider.dart';
import '../services/work_instruction_service.dart';

/// AR-style work-instruction screen.
///
/// Implementation note on "AR": maintained AR plugins for Flutter
/// (`arcore_flutter_plugin`, `ar_flutter_plugin`) are no longer kept in sync
/// with current Flutter / AGP / iOS toolchains. For the supervisor flow
/// described — scan a QR sticker, see overlaid repair steps — the camera
/// passthrough behind a translucent overlay is functionally identical to
/// what the user sees. True spatial AR (plane detection, anchored 3D models)
/// is out of scope here; if needed later, swap [MobileScanner] for an
/// ARView and feed its frame stream into a separate barcode detector.
class ArInstructionScreen extends StatefulWidget {
  const ArInstructionScreen({super.key});

  @override
  State<ArInstructionScreen> createState() => _ArInstructionScreenState();
}

class _ArInstructionScreenState extends State<ArInstructionScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    cameraResolution: const Size(1920, 1080),
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );
  final WorkInstructionService _instructionService = WorkInstructionService();

  bool _cameraPermissionGranted = false;
  bool _permissionChecked = false;
  String? _permissionError;

  // Decoded QR payload.
  _ScannedLocation? _scannedLocation;

  // Live alert stream tied to the scanned location.
  StreamSubscription<AlertModel?>? _alertSub;
  AlertModel? _activeAlert;

  // Instruction loading state.
  bool _loadingInstructions = false;
  WorkInstructions? _instructions;
  String? _instructionsError;

  // Prevents duplicate sheet pushes for the same scan.
  bool _sheetVisible = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------
  Future<void> _requestCameraPermission() async {
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      setState(() {
        _cameraPermissionGranted = status.isGranted;
        _permissionChecked = true;
        _permissionError = status.isPermanentlyDenied
            ? 'Camera permission permanently denied. Open Settings to enable it.'
            : (status.isGranted ? null : 'Camera permission denied.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionChecked = true;
        _cameraPermissionGranted = false;
        _permissionError = 'Could not request camera permission: $e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // QR handling
  // ---------------------------------------------------------------------------
  void _onDetect(BarcodeCapture capture) {
    if (_scannedLocation != null) return; // already locked onto a station
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final loc = _ScannedLocation.tryParse(raw);
      if (loc == null) continue;

      _scannerController.stop();
      setState(() => _scannedLocation = loc);
      _bindToLocation(loc);
      return;
    }
  }

  void _bindToLocation(_ScannedLocation loc) {
    _alertSub?.cancel();
    _alertSub = _instructionService
        .listenToActiveAlertAtLocation(
      usine: loc.usine,
      convoyeur: loc.convoyeur,
      poste: loc.poste,
      assetId: loc.assetId,
    )
        .listen(
      _onAlertChanged,
      onError: (e) {
        if (!mounted) return;
        setState(() => _instructionsError = 'Realtime DB error: $e');
        _showSheet();
      },
    );
    _showSheet();
  }

  Future<void> _onAlertChanged(AlertModel? alert) async {
    if (!mounted) return;
    final previousId = _activeAlert?.id;
    setState(() => _activeAlert = alert);

    if (alert == null) {
      setState(() {
        _instructions = null;
        _instructionsError = null;
        _loadingInstructions = false;
      });
      return;
    }
    if (alert.id == previousId && _instructions != null) return;

    setState(() {
      _loadingInstructions = true;
      _instructionsError = null;
      _instructions = null;
    });
    try {
      final loaded = await _instructionService.fetchInstructions(alert.type);
      if (!mounted) return;
      setState(() {
        _loadingInstructions = false;
        _instructions = loaded;
        _instructionsError = loaded == null
            ? 'No instructions defined for alert type "${alert.type}".'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInstructions = false;
        _instructionsError = 'Failed to load instructions: $e';
      });
    }
  }

  void _resetScan() {
    _alertSub?.cancel();
    _alertSub = null;
    setState(() {
      _scannedLocation = null;
      _activeAlert = null;
      _instructions = null;
      _instructionsError = null;
      _loadingInstructions = false;
      _sheetVisible = false;
    });
    _scannerController.start();
  }

  // ---------------------------------------------------------------------------
  // Bottom sheet
  // ---------------------------------------------------------------------------
  void _showSheet() {
    if (_sheetVisible) return;
    _sheetVisible = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.25,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, controller) => _InstructionSheet(
            scrollController: controller,
            location: _scannedLocation,
            alert: _activeAlert,
            loading: _loadingInstructions,
            instructions: _instructions,
            error: _instructionsError,
            onStepToggled: (step, value) {
              setState(() => step.isCompleted = value);
              // The sheet uses its own StatefulBuilder via parent rebuild,
              // so trigger a rebuild of the modal route as well.
              (sheetContext as Element).markNeedsBuild();
            },
            onResolve: () => _resolveActiveAlert(sheetContext),
            onRescan: () {
              Navigator.of(sheetContext).maybePop();
              _resetScan();
            },
          ),
        );
      },
    ).whenComplete(() => _sheetVisible = false);
  }

  Future<void> _resolveActiveAlert(BuildContext sheetContext) async {
    final alert = _activeAlert;
    if (alert == null) return;
    final provider = context.read<AlertProvider>();
    try {
      await provider.resolveAlert(alert.id, 'Repaired using AR instructions');
      await provider.addComment(alert.id, 'Repaired using AR instructions');
      if (!mounted) return;
      Navigator.of(sheetContext).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert resolved.')),
      );
      _resetScan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('Failed to resolve alert: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('AR Work Instructions'),
        actions: [
          if (_cameraPermissionGranted)
            IconButton(
              tooltip: 'Toggle torch',
              icon: const Icon(Icons.flash_on),
              onPressed: () => _scannerController.toggleTorch(),
            ),
          if (_scannedLocation != null)
            IconButton(
              tooltip: 'Rescan',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _resetScan,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_permissionChecked) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (!_cameraPermissionGranted) {
      return _PermissionDeniedView(
        message: _permissionError ?? 'Camera permission required.',
        onOpenSettings: openAppSettings,
        onRetry: _requestCameraPermission,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Camera error: ${error.errorDetails?.message ?? error.errorCode.name}',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        const _ScannerReticle(),
        if (_scannedLocation == null)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: _HintBanner(
              text: 'Point the camera at the QR sticker on the machine.',
            ),
          ),
        if (_scannedLocation != null)
          Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: _LocationChip(location: _scannedLocation!),
          ),
      ],
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
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final rawAssetId =
          decoded['assetId'] ?? decoded['asset_id'] ?? decoded['machineId'];
      final assetId = rawAssetId?.toString().trim();
      final usine = decoded['usine']?.toString();
      final convoyeur = (decoded['convoyeur'] as num?)?.toInt();
      final poste = (decoded['poste'] as num?)?.toInt();
      if (usine == null || convoyeur == null || poste == null) return null;
      return _ScannedLocation(
        assetId: assetId == null || assetId.isEmpty ? null : assetId,
        usine: usine,
        convoyeur: convoyeur,
        poste: poste,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() {
    final assetPrefix = assetId == null ? '' : '$assetId - ';
    return '$assetPrefix$usine - Conveyor $convoyeur - Post $poste';
  }
}

// =============================================================================
// Overlay widgets
// =============================================================================
class _ScannerReticle extends StatelessWidget {
  const _ScannerReticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide * 0.65;
          return Center(
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(16),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  final _ScannedLocation location;
  const _LocationChip({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              location.toString(),
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  final String message;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  const _PermissionDeniedView({
    required this.message,
    required this.onOpenSettings,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
                ElevatedButton(
                  onPressed: onOpenSettings,
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
// Bottom-sheet content
// =============================================================================
class _InstructionSheet extends StatefulWidget {
  final ScrollController scrollController;
  final _ScannedLocation? location;
  final AlertModel? alert;
  final bool loading;
  final WorkInstructions? instructions;
  final String? error;
  final void Function(WorkInstructionStep step, bool value) onStepToggled;
  final VoidCallback onResolve;
  final VoidCallback onRescan;

  const _InstructionSheet({
    required this.scrollController,
    required this.location,
    required this.alert,
    required this.loading,
    required this.instructions,
    required this.error,
    required this.onStepToggled,
    required this.onResolve,
    required this.onRescan,
  });

  @override
  State<_InstructionSheet> createState() => _InstructionSheetState();
}

class _InstructionSheetState extends State<_InstructionSheet> {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _buildHeader(context),
              const Divider(height: 16),
              Expanded(child: _buildContent(context)),
              if (widget.instructions != null &&
                  widget.instructions!.allCompleted)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ElevatedButton.icon(
                    onPressed: widget.onResolve,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Resolve Alert'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final loc = widget.location;
    final alert = widget.alert;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc == null ? 'No station scanned' : loc.toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (alert != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Alert: ${alert.type} ${alert.alertLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: widget.onRescan,
          icon: const Icon(Icons.qr_code_scanner, size: 18),
          label: const Text('Rescan'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (widget.alert == null && widget.location != null && !widget.loading) {
      return _CenteredMessage(
        icon: Icons.check_circle_outline,
        text: 'No active alerts at this station.',
      );
    }
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        text: widget.error!,
      );
    }
    final instructions = widget.instructions;
    if (instructions == null || instructions.steps.isEmpty) {
      return _CenteredMessage(
        icon: Icons.menu_book_outlined,
        text: 'No instructions defined for this alert.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LinearProgressIndicator(
            value: instructions.steps.isEmpty
                ? 0
                : instructions.completedCount / instructions.steps.length,
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: widget.scrollController,
            itemCount: instructions.steps.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final step = instructions.steps[i];
              return _StepTile(
                step: step,
                onChanged: (v) {
                  setState(() => step.isCompleted = v);
                  widget.onStepToggled(step, v);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  final WorkInstructionStep step;
  final ValueChanged<bool> onChanged;

  const _StepTile({required this.step, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: step.isCompleted,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        '${step.stepNumber}. ${step.description}',
        style: TextStyle(
          decoration: step.isCompleted
              ? TextDecoration.lineThrough
              : TextDecoration.none,
        ),
      ),
      subtitle: step.safetyWarning == null && step.imageUrl == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step.safetyWarning != null)
                    Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            step.safetyWarning!,
                            style: const TextStyle(color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  if (step.imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          step.imageUrl!,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CenteredMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Colors.grey),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
