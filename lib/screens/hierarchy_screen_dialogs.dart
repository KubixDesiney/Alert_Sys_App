part of 'hierarchy_screen.dart';

class _StationDeleteDialog extends StatelessWidget {
  final String stationName;
  final String stationId;
  final int stationNumber;
  final String stationAddress;
  final String assetId;
  final String factoryName;
  final String factoryId;
  final int conveyorNumber;
  final String conveyorId;

  const _StationDeleteDialog({
    required this.stationName,
    required this.stationId,
    required this.stationNumber,
    required this.stationAddress,
    required this.assetId,
    required this.factoryName,
    required this.factoryId,
    required this.conveyorNumber,
    required this.conveyorId,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final preservedAssetLabel =
        assetId.isEmpty ? 'No Asset ID linked yet' : assetId;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      t.red.withValues(alpha: 0.14),
                      t.orange.withValues(alpha: 0.12),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: t.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: t.red.withValues(alpha: 0.22)),
                      ),
                      child: Icon(
                        Icons.delete_forever_outlined,
                        color: t.red,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delete Station',
                            style: TextStyle(
                              color: t.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'This removes the station from the hierarchy while keeping the asset record archived in the database.',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      tooltip: 'Close',
                      icon: Icon(Icons.close, color: t.muted),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.scaffold,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: t.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stationName,
                            style: TextStyle(
                              color: t.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$factoryName  •  Conveyor $conveyorNumber  •  Post $stationNumber',
                            style: TextStyle(
                              color: t.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _DeleteDetailRow(
                              label: 'Factory',
                              value: '$factoryName ($factoryId)'),
                          _DeleteDetailRow(
                            label: 'Conveyor',
                            value: 'Conveyor $conveyorNumber ($conveyorId)',
                          ),
                          _DeleteDetailRow(
                            label: 'Station',
                            value: '$stationName ($stationId)',
                          ),
                          _DeleteDetailRow(
                            label: 'Address',
                            value: stationAddress,
                          ),
                          _DeleteDetailRow(
                            label: 'Asset Record',
                            value: preservedAssetLabel,
                            emphasize: assetId.isNotEmpty,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: t.red.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: t.red,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              assetId.isEmpty
                                  ? 'The hierarchy entry will be removed immediately.'
                                  : 'Asset $assetId will stay under /assets with its last known location and deletion metadata.',
                              style: TextStyle(
                                color: t.text,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                decoration: BoxDecoration(
                  color: t.scaffold,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.red,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete Station'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _DeleteDetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                color: t.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: emphasize ? t.navy : t.text,
                fontSize: 12.5,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _StationActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

class _StationQrDialog extends StatefulWidget {
  final String stationName;
  final String factoryName;
  final int conveyorNumber;
  final int stationNumber;
  final String assetId;
  final String payload;
  final VoidCallback onRelink;

  const _StationQrDialog({
    required this.stationName,
    required this.factoryName,
    required this.conveyorNumber,
    required this.stationNumber,
    required this.assetId,
    required this.payload,
    required this.onRelink,
  });

  @override
  State<_StationQrDialog> createState() => _StationQrDialogState();
}

class _StationQrDialogState extends State<_StationQrDialog> {
  bool _downloading = false;
  bool _printing = false;

  Future<void> _downloadPng() async {
    setState(() => _downloading = true);
    try {
      final bytes = await _renderQrPng(widget.payload);
      final name = 'qr_${widget.assetId}';
      await FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        ext: 'png',
        mimeType: MimeType.png,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('QR saved as $name.png')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Download failed: ${UserFriendlyError.message(e)}')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _printQr() async {
    setState(() => _printing = true);
    try {
      final bytes = await _renderQrPng(widget.payload);
      final doc = pw.Document();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Image(image, width: 300, height: 300),
                pw.SizedBox(height: 16),
                pw.Text(
                  widget.stationName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  '${widget.factoryName} · Conveyor ${widget.conveyorNumber} · Post ${widget.stationNumber}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Print failed: ${UserFriendlyError.message(e)}')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 4, color: t.navy),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.navyLt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.qr_code_2, color: t.navy, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Station QR Code',
                            style: TextStyle(
                              color: t.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.stationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: Icon(Icons.close, color: t.muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: t.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: widget.payload,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            gapless: false,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF0F172A),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _QrMetaChip(
                              icon: Icons.precision_manufacturing_outlined,
                              label: widget.assetId),
                          _QrMetaChip(
                              icon: Icons.factory, label: widget.factoryName),
                          _QrMetaChip(
                              icon: Icons.linear_scale,
                              label: 'Conveyor ${widget.conveyorNumber}'),
                          _QrMetaChip(
                              icon: Icons.settings,
                              label: 'Post ${widget.stationNumber}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onRelink,
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Relink Asset ID'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.scaffold,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: t.border),
                        ),
                        child: SelectableText(
                          widget.payload,
                          style: TextStyle(
                            color: t.text,
                            fontSize: 12,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  color: t.scaffold,
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _printing ? null : _printQr,
                        icon: _printing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print, size: 16),
                        label: const Text('Print QR'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _downloading ? null : _downloadPng,
                        icon: _downloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download, size: 16),
                        label: const Text('Download PNG'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _QrMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: t.navyLt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.navy.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.navy),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: t.navy,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class FactoryLocationSelection {
  final double? lat;
  final double? lng;
  final String address;

  const FactoryLocationSelection({
    this.lat,
    this.lng,
    required this.address,
  });

  bool get hasCoordinates => lat != null && lng != null;

  FactoryLocationSelection copyWith({
    double? lat,
    double? lng,
    String? address,
    bool clearCoordinates = false,
  }) {
    return FactoryLocationSelection(
      lat: clearCoordinates ? null : lat ?? this.lat,
      lng: clearCoordinates ? null : lng ?? this.lng,
      address: address ?? this.address,
    );
  }
}

class _LocationSearchSuggestion {
  final String displayName;
  final String cityCountry;
  final LatLng point;

  const _LocationSearchSuggestion({
    required this.displayName,
    required this.cityCountry,
    required this.point,
  });
}

class FactoryLocationPicker extends StatefulWidget {
  final FactoryLocationSelection initialSelection;
  final VoidCallback onCancel;
  final ValueChanged<FactoryLocationSelection> onSave;
  final bool renderPlatformMap;

  const FactoryLocationPicker({
    super.key,
    required this.initialSelection,
    required this.onCancel,
    required this.onSave,
    this.renderPlatformMap = true,
  });

  @override
  State<FactoryLocationPicker> createState() => _FactoryLocationPickerState();
}

class _FactoryLocationPickerState extends State<FactoryLocationPicker> {
  static const LatLng _defaultTarget = LatLng(33.5731, -7.5898);

  late final TextEditingController _searchController;
  GoogleMapController? _mapController;
  LatLng? _selectedLatLng;
  String _address = '';
  String? _error;
  Timer? _searchDebounce;
  List<_LocationSearchSuggestion> _suggestions = [];
  bool _searching = false;
  bool _loadingSuggestions = false;

  @override
  void initState() {
    super.initState();
    _address = widget.initialSelection.address;
    _searchController = TextEditingController(text: _address);
    if (widget.initialSelection.hasCoordinates) {
      _selectedLatLng = LatLng(
        widget.initialSelection.lat!,
        widget.initialSelection.lng!,
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  LatLng get _cameraTarget => _selectedLatLng ?? _defaultTarget;

  Set<Marker> get _markers {
    final point = _selectedLatLng;
    if (point == null) return {};
    return {
      Marker(
        markerId: const MarkerId('factory-location-pin'),
        position: point,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Selected location',
          snippet: _displayLocationLabel,
        ),
      ),
    };
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _suggestions = [];
    });
    try {
      final suggestion = await _bestLocationSuggestion(query);
      if (suggestion == null) {
        setState(() => _error = 'Address not found');
        return;
      }
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(suggestion.point, 15),
      );
      await _selectSuggestion(suggestion, animate: false);
    } catch (e) {
      setState(() => _error = 'Could not search address');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<_LocationSearchSuggestion?> _bestLocationSuggestion(
      String query) async {
    final suggestions = await _fetchLocationSuggestions(query, limit: 1);
    if (suggestions.isNotEmpty) return suggestions.first;

    try {
      final locations = await geo.locationFromAddress(query);
      if (locations.isNotEmpty) {
        final first = locations.first;
        final point = LatLng(first.latitude, first.longitude);
        final cityCountry =
            await _reverseGeocodeCityCountry(point) ?? query.trim();
        return _LocationSearchSuggestion(
          displayName: query.trim(),
          cityCountry: cityCountry,
          point: point,
        );
      }
    } catch (_) {}

    return null;
  }

  Future<List<_LocationSearchSuggestion>> _fetchLocationSuggestions(
    String query, {
    int limit = 6,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 3) return [];
    final googleSuggestions = await googleMapsWebLocationSuggestions(
      normalized,
      limit: limit,
    );
    if (googleSuggestions.isNotEmpty) {
      return googleSuggestions
          .map(
            (suggestion) => _LocationSearchSuggestion(
              displayName: suggestion.displayName,
              cityCountry: suggestion.cityCountry,
              point: LatLng(suggestion.lat, suggestion.lng),
            ),
          )
          .toList();
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'addressdetails': '1',
        'limit': '$limit',
        'q': normalized,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      if (data is! List) return [];
      final suggestions = <_LocationSearchSuggestion>[];
      for (final item in data) {
        if (item is! Map) continue;
        final map = Map<Object?, Object?>.from(item);
        final lat = double.tryParse(map['lat']?.toString() ?? '');
        final lon = double.tryParse(map['lon']?.toString() ?? '');
        if (lat == null || lon == null) continue;
        final address = map['address'] is Map
            ? Map<Object?, Object?>.from(map['address'] as Map)
            : const <Object?, Object?>{};
        final cityCountry = _cityCountryFromAddressMap(address);
        suggestions.add(
          _LocationSearchSuggestion(
            displayName: map['display_name']?.toString() ?? query.trim(),
            cityCountry: cityCountry.isNotEmpty ? cityCountry : normalized,
            point: LatLng(lat, lon),
          ),
        );
      }
      return suggestions;
    } catch (_) {
      return [];
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _loadingSuggestions = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = true;
        _error = null;
      });
      final suggestions = await _fetchLocationSuggestions(query);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _suggestions = suggestions;
        _loadingSuggestions = false;
      });
    });
  }

  Future<void> _selectSuggestion(
    _LocationSearchSuggestion suggestion, {
    bool animate = true,
  }) async {
    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    if (animate) {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(suggestion.point, 15),
      );
    }
    if (!mounted) return;
    setState(() {
      _selectedLatLng = suggestion.point;
      _address = suggestion.cityCountry;
      _searchController.text = suggestion.cityCountry;
      _suggestions = [];
      _error = null;
    });
  }

  Future<void> _dropPin(LatLng point) async {
    setState(() {
      _selectedLatLng = point;
      _error = null;
      _suggestions = [];
    });
    final formatted = await _reverseGeocodeCityCountry(point);
    if (!mounted) return;
    setState(() {
      _address = formatted ?? _fallbackLocationLabel();
      _searchController.text = _address;
    });
  }

  Future<void> _dropPinFromScreenOffset(Offset offset) async {
    final controller = _mapController;
    if (controller == null) return;
    final point = await controller.getLatLng(
      ScreenCoordinate(x: offset.dx.round(), y: offset.dy.round()),
    );
    await _dropPin(point);
  }

  void _clearPin() {
    if (_selectedLatLng == null) return;
    setState(() {
      _selectedLatLng = null;
      _error = null;
    });
  }

  Future<String?> _reverseGeocodeCityCountry(LatLng point) async {
    final googleFormatted = await googleMapsWebReverseGeocodeCityCountry(
      point.latitude,
      point.longitude,
    );
    if (googleFormatted != null && googleFormatted.trim().isNotEmpty) {
      return googleFormatted.trim();
    }

    try {
      final marks =
          await geo.placemarkFromCoordinates(point.latitude, point.longitude);
      if (marks.isNotEmpty) {
        final formatted = _formatPlacemark(marks.first);
        if (formatted.isNotEmpty) return formatted;
      }
    } catch (_) {}

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'json',
        'addressdetails': '1',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map || data['address'] is! Map) return null;
      final address = Map<Object?, Object?>.from(data['address'] as Map);
      final formatted = _cityCountryFromAddressMap(address);
      return formatted.isEmpty ? null : formatted;
    } catch (_) {
      return null;
    }
  }

  String _formatPlacemark(geo.Placemark mark) {
    String city = '';
    for (final candidate in [
      mark.locality,
      mark.subAdministrativeArea,
      mark.administrativeArea,
    ]) {
      final normalized = (candidate ?? '').trim();
      if (normalized.isNotEmpty) {
        city = normalized;
        break;
      }
    }
    final country = (mark.country ?? '').trim();
    final parts = <String>[];
    if (city.isNotEmpty) parts.add(city);
    if (country.isNotEmpty && !parts.contains(country)) parts.add(country);
    return parts.join(', ');
  }

  String _cityCountryFromAddressMap(Map<Object?, Object?> address) {
    final city = [
      address['city'],
      address['town'],
      address['village'],
      address['municipality'],
      address['county'],
      address['state'],
    ]
        .map((value) => (value ?? '').toString().trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final country = (address['country'] ?? '').toString().trim();
    final parts = <String>[];
    if (city.isNotEmpty) parts.add(city);
    if (country.isNotEmpty && !parts.contains(country)) parts.add(country);
    return parts.join(', ');
  }

  String _fallbackLocationLabel() {
    final typed = _searchController.text.trim();
    return typed.isNotEmpty ? typed : 'Selected location';
  }

  String get _displayLocationLabel {
    final address = _address.trim();
    if (address.isNotEmpty) return address;
    return _selectedLatLng == null ? 'No location selected' : 'Selected location';
  }

  void _save() {
    final point = _selectedLatLng;
    widget.onSave(
      FactoryLocationSelection(
        lat: point?.latitude,
        lng: point?.longitude,
        address: _address.trim().isNotEmpty
            ? _address.trim()
            : _searchController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final point = _selectedLatLng;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Factory Location'),
          actions: [
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('factory-location-search-bar'),
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _searchAddress(),
                      decoration: const InputDecoration(
                        labelText: 'Search address',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _searching ? null : _searchAddress,
                    icon: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    tooltip: 'Search',
                  ),
                  if (point != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _clearPin,
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear location',
                    ),
                  ],
                ],
              ),
            ),
            if (_loadingSuggestions)
              const LinearProgressIndicator(minHeight: 2),
            if (_suggestions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        suggestion.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        suggestion.cityCountry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectSuggestion(suggestion),
                    );
                  },
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!,
                      style: const TextStyle(color: _red, fontSize: 12)),
                ),
              ),
            Expanded(
              child: FactoryLocationMap(
                key: const Key('factory-location-map'),
                initialTarget: _cameraTarget,
                markers: _markers,
                renderPlatformMap: widget.renderPlatformMap,
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                onLongPress: _dropPin,
                onTap: _dropPin,
                onSecondaryTap: _dropPinFromScreenOffset,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Text(
                _displayLocationLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FactoryLocationMap extends StatelessWidget {
  final LatLng initialTarget;
  final Set<Marker> markers;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<LatLng> onLongPress;
  final ValueChanged<LatLng> onTap;
  final Future<void> Function(Offset offset) onSecondaryTap;
  final bool renderPlatformMap;

  const FactoryLocationMap({
    super.key,
    required this.initialTarget,
    required this.markers,
    required this.onMapCreated,
    required this.onLongPress,
    required this.onTap,
    required this.onSecondaryTap,
    this.renderPlatformMap = true,
  });

  @override
  Widget build(BuildContext context) {
    final showLiveMap = renderPlatformMap && isGoogleMapsJsLoaded;
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton) {
          unawaited(onSecondaryTap(event.localPosition));
        }
      },
      child: showLiveMap
          ? GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: 12,
              ),
              markers: markers,
              onMapCreated: onMapCreated,
              onLongPress: onLongPress,
              onTap: onTap,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
            )
          : ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    renderPlatformMap
                        ? 'Interactive map unavailable on web. Search for an address or load the Google Maps JavaScript API to enable map preview.'
                        : 'Map preview disabled for this build.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
    );
  }
}
