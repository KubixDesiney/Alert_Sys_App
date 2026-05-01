import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import '../models/alert_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../providers/alert_provider.dart';
import 'alert_detail_screen.dart';
import 'package:http/http.dart' as http;
import 'admin_escalation_screen.dart';
import 'hierarchy_screen.dart';
import '../models/hierarchy_model.dart';
import '../services/hierarchy_service.dart';
import '../services/alert_service.dart';
import '../widgets/voice_command_button.dart';
import '../services/ai_assignment_service.dart';
import '../providers/theme_provider.dart';
import '../theme.dart';
import 'alerts_tree_tab.dart';

part 'overview_tab.dart';
part 'supervisors_tab.dart';

// ── Palette ─────────────────────────────────────────────────────────────
const _navy = AppColors.navy;
const _navyLt = AppColors.navyLight;
const _red = AppColors.red;
const _white = AppColors.white;
const _border = AppColors.border;
const _muted = AppColors.muted;
const _text = AppColors.text;
const _green = AppColors.green;
const _greenLt = AppColors.greenLight;
const _orange = AppColors.orange;
const _orangeLt = AppColors.orangeLight;
const _blue = AppColors.blue;
const _blueLt = AppColors.blueLight;

Color _typeColor(String t) => switch (t) {
      'qualite' => const Color(0xFFDC2626),
      'maintenance' => const Color(0xFF2563EB),
      'defaut_produit' => const Color(0xFF16A34A),
      'manque_ressource' => const Color(0xFFD97706),
      _ => const Color(0xFF64748B),
    };

String _typeLabel(String t) => switch (t) {
      'qualite' => 'Quality',
      'maintenance' => 'Maintenance',
      'defaut_produit' => 'Damaged Product',
      'manque_ressource' => 'Resources Deficiency',
      _ => t,
    };

IconData _typeIcon(String t) => switch (t) {
      'qualite' => Icons.warning_amber_rounded,
      'maintenance' => Icons.build,
      'defaut_produit' => Icons.cancel,
      'manque_ressource' => Icons.inventory_2,
      _ => Icons.notifications_outlined,
    };

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtTs(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _fmtMin(int min) => min < 60 ? '${min}m' : '${min ~/ 60}h ${min % 60}m';

// ═══════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _tab = 0; // 0=Overview  1=Supervisors  2=Alerts
  List<UserModel> _supervisors = [];
  List<AlertModel> _alerts = [];
  bool _loading = true;

  final _db = FirebaseDatabase.instance;
  final _auth = AuthService();

  // Filter state
  String _timeRange = 'all';
  String _selectedUsine = 'all';
  String _filterConvoyeur = 'all';
  String _filterPoste = 'all';
  String _filterType = 'all';
  String _filterStatus = 'all';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  List<AlertModel> _filteredAlerts = [];

  static const String _prefTimeRange = 'overview_time_range';
  static const String _prefUsine = 'overview_usine';

  @override
  void initState() {
    super.initState();
    _loadSavedFilters();
    _loadSupervisors();
    _loadAlerts();
  }

  Future<void> _loadSavedFilters() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _timeRange = prefs.getString(_prefTimeRange) ?? 'all';
      _selectedUsine = prefs.getString(_prefUsine) ?? 'all';
    });
    _applyFilters();
  }

  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefTimeRange, _timeRange);
    await prefs.setString(_prefUsine, _selectedUsine);
  }

  void _applyFilters() {
    if (_alerts.isEmpty) {
      setState(() => _filteredAlerts = []);
      return;
    }
    final now = DateTime.now();
    final filtered = _alerts.where((a) {
      bool timeOk = switch (_timeRange) {
        'today' => a.timestamp.year == now.year &&
            a.timestamp.month == now.month &&
            a.timestamp.day == now.day,
        'week' => a.timestamp.isAfter(now.subtract(const Duration(days: 7))),
        'month' =>
          a.timestamp.year == now.year && a.timestamp.month == now.month,
        'year' => a.timestamp.year == now.year,
        'custom' => (_customStartDate != null && _customEndDate != null)
            ? a.timestamp.isAfter(_customStartDate!) &&
                a.timestamp.isBefore(_customEndDate!)
            : true,
        _ => true,
      };
      if (!timeOk) return false;
      if (_selectedUsine != 'all' && a.usine != _selectedUsine) return false;
      if (_filterConvoyeur != 'all' &&
          a.convoyeur.toString() != _filterConvoyeur) return false;
      if (_filterPoste != 'all' && a.poste.toString() != _filterPoste)
        return false;
      if (_filterType != 'all' && a.type != _filterType) return false;
      if (_filterStatus != 'all' && a.status != _filterStatus) return false;
      return true;
    }).toList();
    setState(() => _filteredAlerts = filtered);
  }

  Future<void> _loadSupervisors() async {
    final list = await _auth.fetchSupervisors();
    if (mounted)
      setState(() {
        _supervisors = list;
        _loading = false;
      });
  }

  void _loadAlerts() {
    _db.ref('alerts').onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data == null) {
        setState(() {
          _alerts = [];
          _filteredAlerts = [];
        });
        return;
      }
      final map = Map<String, dynamic>.from(data as Map);
      final list = map.entries
          .map((e) => AlertModel.fromMap(
              e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() => _alerts = list);
      _applyFilters();
    });
  }

  int get _total => _filteredAlerts.length;
  int get _solved => _filteredAlerts.where((a) => a.status == 'validee').length;
  int get _inProgress =>
      _filteredAlerts.where((a) => a.status == 'en_cours').length;
  int get _pending =>
      _filteredAlerts.where((a) => a.status == 'disponible').length;
  int get _activeSups => _supervisors.where((s) => s.isActive).length;

  String get _timeRangeLabel => switch (_timeRange) {
        'today' => 'Today',
        'week' => 'Last Week',
        'month' => 'This Month',
        'year' => 'This Year',
        'custom' => _customStartDate != null && _customEndDate != null
            ? '${_customStartDate!.day}/${_customStartDate!.month} – '
                '${_customEndDate!.day}/${_customEndDate!.month}'
            : 'Custom',
        _ => 'All time',
      };

  String get _timeRangeSubtitle => switch (_timeRange) {
        'today' => 'Showing today\'s data',
        'week' => 'Showing last 7 days',
        'month' => 'Showing this month',
        'year' => 'Showing this year',
        _ => 'Filtered view',
      };

  Future<void> _logout() async {
    await _auth.logout();
  }

  // ── Alert creation methods (added) ────────────────────────────────────
  // Add an instance of AlertService at the top of the state class
  final AlertService _alertService = AlertService();

  Future<void> _simulateAlert({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    required bool isCritical,
  }) async {
    try {
      await _alertService.createAlertWithHierarchy(
        type: type,
        usine: usine,
        convoyeur: convoyeur,
        poste: poste,
        description: description,
        isCritical: isCritical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Simulated ${_typeLabel(type)} alert on $usine, Conv $convoyeur, Post $poste'),
            backgroundColor: _green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: ${e.toString()}'), backgroundColor: _red),
        );
      }
    }
  }

  // ignore: unused_element
  Future<void> _createSimulatedAlert({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    bool isCritical = false,
  }) async {
    // ✅ 1. Validate against hierarchy before anything else
    final hierarchyService = HierarchyService();
    final isValid =
        await hierarchyService.validateLocation(usine, convoyeur, poste);
    if (!isValid) {
      throw Exception(
          'Invalid location: Factory "$usine", Conveyor $convoyeur, Station $poste does not exist in hierarchy.');
    }

    // ✅ 2. Original alert creation (unchanged)
    final assetId =
        await hierarchyService.getAssetIdForLocation(usine, convoyeur, poste);
    final ref = _db.ref('alerts').push();
    final now = DateTime.now();
    final alertId = ref.key;
    await ref.set({
      'type': type,
      'usine': usine,
      'convoyeur': convoyeur,
      'poste': poste,
      'adresse': '${usine.replaceAll(' ', '_')}_C${convoyeur}_P$poste',
      if (assetId != null) 'assetId': assetId,
      'timestamp': now.toIso8601String(),
      'description': description,
      'status': 'disponible',
      'comments': [],
      'isCritical': isCritical,
      'push_sent': false, // ⬅️ critical for Cloudflare Worker
      'superviseurId': null,
      'superviseurName': null,
      'assistantId': null,
      'assistantName': null,
      'resolutionReason': null,
      'resolvedAt': null,
      'elapsedTime': null,
    });

    // ✅ 3. Manual Cloudflare Worker trigger (unchanged)
    try {
      await http.post(
        Uri.parse('https://alert-notifier.aziz-nagati01.workers.dev'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': type,
          'description': description,
          'alertId': alertId,
        }),
      );
    } catch (e) {
      debugPrint('Manual worker trigger failed: $e');
    }
  }

  // ── Export methods (cross‑platform) ────────────────────────────────────
  Future<void> _exportToCsv() async {
    if (_filteredAlerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No alerts to export'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    List<List<dynamic>> csvData = [
      [
        'ID',
        'Alert #',
        'Type',
        'Usine',
        'Convoyeur',
        'Poste',
        'Adresse',
        'Timestamp',
        'Description',
        'Status',
        'Superviseur',
        'Assistant',
        'Resolution Reason',
        'Elapsed Time (min)',
        'Critical'
      ]
    ];
    for (var alert in _filteredAlerts) {
      csvData.add([
        alert.id,
        alert.alertNumber,
        _typeLabel(alert.type),
        alert.usine,
        alert.convoyeur,
        alert.poste,
        alert.adresse,
        alert.timestamp.toIso8601String(),
        alert.description,
        alert.status,
        alert.superviseurName ?? '',
        alert.assistantName ?? '',
        alert.resolutionReason ?? '',
        alert.elapsedTime ?? '',
        alert.isCritical ? 'Yes' : 'No',
      ]);
    }
    String csv = const ListToCsvConverter().convert(csvData);
    final bytes = utf8.encode(csv);

    if (kIsWeb) {
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download',
            'alerts_export_${DateTime.now().millisecondsSinceEpoch}.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/alerts_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Alert export');
    }
  }

  Future<void> _exportToExcel() async {
    if (_filteredAlerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No alerts to export'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    var excelFile = excel.Excel.createExcel();
    var sheet = excelFile['Alerts'];
    sheet.appendRow([
      excel.TextCellValue('ID'),
      excel.TextCellValue('Alert #'),
      excel.TextCellValue('Type'),
      excel.TextCellValue('Usine'),
      excel.TextCellValue('Convoyeur'),
      excel.TextCellValue('Poste'),
      excel.TextCellValue('Adresse'),
      excel.TextCellValue('Timestamp'),
      excel.TextCellValue('Description'),
      excel.TextCellValue('Status'),
      excel.TextCellValue('Superviseur'),
      excel.TextCellValue('Assistant'),
      excel.TextCellValue('Resolution Reason'),
      excel.TextCellValue('Elapsed Time (min)'),
      excel.TextCellValue('Critical'),
    ]);
    for (var alert in _filteredAlerts) {
      sheet.appendRow([
        excel.TextCellValue(alert.id),
        excel.IntCellValue(alert.alertNumber),
        excel.TextCellValue(_typeLabel(alert.type)),
        excel.TextCellValue(alert.usine),
        excel.IntCellValue(alert.convoyeur),
        excel.IntCellValue(alert.poste),
        excel.TextCellValue(alert.adresse),
        excel.TextCellValue(alert.timestamp.toIso8601String()),
        excel.TextCellValue(alert.description),
        excel.TextCellValue(alert.status),
        excel.TextCellValue(alert.superviseurName ?? ''),
        excel.TextCellValue(alert.assistantName ?? ''),
        excel.TextCellValue(alert.resolutionReason ?? ''),
        excel.IntCellValue(alert.elapsedTime ?? 0),
        excel.TextCellValue(alert.isCritical ? 'Yes' : 'No'),
      ]);
    }
    final fileBytes = excelFile.encode();
    if (fileBytes == null) return;

    if (kIsWeb) {
      final blob = html.Blob([fileBytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download',
            'alerts_export_${DateTime.now().millisecondsSinceEpoch}.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/alerts_export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Alert export');
    }
  }

  Future<void> _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _customStartDate ??
            DateTime.now().subtract(const Duration(days: 7)),
        end: _customEndDate ?? DateTime.now(),
      ),
    );
    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
      });
      _applyFilters();
      _saveFilters();
    } else {
      setState(() => _timeRange = 'week');
    }
  }

  // ignore: unused_element
  Future<void> _assignSupervisor(AlertModel alert) async {
    final supervisors = await _auth.getActiveSupervisors();
    // Filter by alert's factory
    final filtered = supervisors.where((s) => s.usine == alert.usine).toList();
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                const Text('No active supervisors available for this factory')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.person_add, size: 20),
          SizedBox(width: 8),
          Text('Assign Supervisor'),
        ]),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: filtered.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.person, color: _navy),
              title: Text(filtered[i].fullName),
              subtitle: Text(filtered[i].email),
              onTap: () async {
                Navigator.pop(_);
                await _auth.assignSupervisorToAlert(
                    alert.id, filtered[i].id, filtered[i].fullName);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Assigned to ${filtered[i].fullName}'),
                      backgroundColor: _green),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _assignAssistant(AlertModel alert) async {
    final supervisors = await _auth.getActiveSupervisors();
    // Filter by alert's factory
    final filtered = supervisors.where((s) => s.usine == alert.usine).toList();
    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                const Text('No active supervisors available for this factory')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.group_add, size: 20),
          SizedBox(width: 8),
          Text('Assign Assistant'),
        ]),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: filtered.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.person_add, color: _navy),
              title: Text(filtered[i].fullName),
              subtitle: Text(filtered[i].email),
              onTap: () async {
                Navigator.pop(_);
                await _auth.assignAssistantToAlert(
                    alert.id, filtered[i].id, filtered[i].fullName);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Assigned ${filtered[i].fullName} as assistant'),
                      backgroundColor: _green),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _showSimulateDialog() {
    String? selectedFactoryId;
    String? selectedFactoryName;
    String? selectedConveyorId;
    int? selectedConveyorNumber;
    String? selectedStationId;
    int? selectedStationNumber;
    String selectedType = 'qualite';
    String description = '';
    bool isCritical = false;

    List<Factory> factories = [];
    List<Conveyor> conveyors = [];
    List<Station> stations = [];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          // Define updateStations FIRST (before it's called)
          void updateStations() {
            final factory =
                factories.firstWhere((f) => f.id == selectedFactoryId);
            final conveyor = factory.conveyors[selectedConveyorId];
            if (conveyor != null) {
              stations = conveyor.stations.values.toList();
              if (stations.isNotEmpty && selectedStationId == null) {
                selectedStationId = stations.first.id;
                selectedStationNumber =
                    int.tryParse(selectedStationId!.replaceAll('station_', ''));
              }
            } else {
              stations = [];
            }
          }

          // Define updateConveyors (which calls updateStations)
          void updateConveyors() {
            final factory =
                factories.firstWhere((f) => f.id == selectedFactoryId);
            conveyors = factory.conveyors.values.toList();
            if (conveyors.isNotEmpty && selectedConveyorId == null) {
              selectedConveyorId = conveyors.first.id;
              selectedConveyorNumber = conveyors.first.number;
              updateStations(); // now safe
            } else if (conveyors.isEmpty) {
              stations = [];
              selectedStationId = null;
            }
          }

          // Load factories on first build
          if (factories.isEmpty) {
            final hierarchyService = HierarchyService();
            hierarchyService.getFactories().listen((factoriesList) {
              setState(() {
                factories = factoriesList;
                if (factories.isNotEmpty) {
                  selectedFactoryId = factories.first.id;
                  selectedFactoryName = factories.first.name;
                  updateConveyors();
                }
              });
            });
          }

          return AlertDialog(
            title: const Row(children: [
              Icon(Icons.notification_important, size: 20, color: Colors.red),
              SizedBox(width: 8),
              Text('Simulate Custom Alert',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Alert Type',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    items: const [
                      DropdownMenuItem(
                          value: 'qualite',
                          child: Row(children: [
                            Icon(Icons.check_circle_outline, size: 16),
                            SizedBox(width: 8),
                            Text('Quality'),
                          ])),
                      DropdownMenuItem(
                          value: 'maintenance',
                          child: Row(children: [
                            Icon(Icons.handyman, size: 16),
                            SizedBox(width: 8),
                            Text('Maintenance'),
                          ])),
                      DropdownMenuItem(
                          value: 'defaut_produit',
                          child: Row(children: [
                            Icon(Icons.report_problem, size: 16),
                            SizedBox(width: 8),
                            Text('Damaged Product'),
                          ])),
                      DropdownMenuItem(
                          value: 'manque_ressource',
                          child: Row(children: [
                            Icon(Icons.inventory_2, size: 16),
                            SizedBox(width: 8),
                            Text('Resource Shortage'),
                          ])),
                    ],
                    onChanged: (val) => setState(() => selectedType = val!),
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Factory (Usine)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedFactoryName,
                    items: factories
                        .map((f) => DropdownMenuItem(
                            value: f.name, child: Text(f.name)))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedFactoryName = val;
                        selectedFactoryId =
                            factories.firstWhere((f) => f.name == val).id;
                        selectedConveyorId = null;
                        selectedStationId = null;
                        updateConveyors();
                      });
                    },
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Conveyor',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedConveyorId != null
                        ? 'Conveyor ${selectedConveyorNumber}'
                        : null,
                    items: conveyors
                        .map((c) => DropdownMenuItem(
                            value: 'Conveyor ${c.number}',
                            child: Text('Conveyor ${c.number}')))
                        .toList(),
                    onChanged: conveyors.isEmpty
                        ? null
                        : (val) {
                            setState(() {
                              final index = conveyors.indexWhere(
                                  (c) => 'Conveyor ${c.number}' == val);
                              selectedConveyorId = conveyors[index].id;
                              selectedConveyorNumber = conveyors[index].number;
                              selectedStationId = null;
                              updateStations();
                            });
                          },
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Workstation (Poste)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedStationId != null
                        ? 'Station ${selectedStationNumber}'
                        : null,
                    items: stations
                        .map((s) => DropdownMenuItem(
                            value: s.name, child: Text(s.name)))
                        .toList(),
                    onChanged: stations.isEmpty
                        ? null
                        : (val) {
                            setState(() {
                              final station =
                                  stations.firstWhere((s) => s.name == val);
                              selectedStationId = station.id;
                              selectedStationNumber = int.tryParse(
                                  selectedStationId!
                                      .replaceAll('station_', ''));
                            });
                          },
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Description (optional)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    onChanged: (val) => description = val,
                    decoration: const InputDecoration(
                      hintText: 'e.g., Motor overheating (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Mark as Critical',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Switch(
                        value: isCritical,
                        onChanged: (val) => setState(() => isCritical = val),
                        activeColor: Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (selectedFactoryId == null ||
                      selectedConveyorId == null ||
                      selectedStationId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Please select factory, conveyor, and workstation'),
                          backgroundColor: Colors.red),
                    );
                    return;
                  }
                  Navigator.pop(context);
                  _simulateAlert(
                    type: selectedType,
                    usine: selectedFactoryName!,
                    convoyeur: selectedConveyorNumber!,
                    poste: selectedStationNumber!,
                    description: description.trim(),
                    isCritical: isCritical,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: _navy),
                child: const Text('Create Alert',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateSheet() {
    final first = TextEditingController();
    final last = TextEditingController();
    final email = TextEditingController();
    final pass = TextEditingController();
    final phone = TextEditingController();
    String usine = '';
    DateTime hired = DateTime.now();
    String? error;
    bool loading = false;

    List<String> factoryNames = [];
    bool factoriesLoaded = false;

    // Load factories from hierarchy
    final hierarchyService = HierarchyService();
    hierarchyService.getFactories().listen((factories) {
      if (mounted && !factoriesLoaded) {
        factoryNames = factories.map((f) => f.name).toList();
        if (factoryNames.isNotEmpty && usine.isEmpty) {
          usine = factoryNames.first;
        }
        factoriesLoaded = true;
        // Force rebuild of the bottom sheet
        if (mounted) setState(() {});
      }
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                            color: _border,
                            borderRadius: BorderRadius.circular(99)))),
                Row(children: [
                  Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: _navyLt,
                          borderRadius: BorderRadius.circular(10)),
                      child:
                          const Icon(Icons.person_add, color: _navy, size: 20)),
                  const SizedBox(width: 12),
                  const Text('New Supervisor Account',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _navy)),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _SheetField('First Name', first, 'Ahmed')),
                  const SizedBox(width: 10),
                  Expanded(child: _SheetField('Last Name', last, 'Benali')),
                ]),
                _SheetField('Phone', phone, '+213 XX XX XX XX',
                    keyboard: TextInputType.phone),
                _SheetField('Email', email, 'ahmed@sagem.com',
                    keyboard: TextInputType.emailAddress),
                _SheetField('Password', pass, 'Min 6 characters',
                    obscure: true),
                _SheetLabel('Assigned Plant'),
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      color: context.appTheme.scaffold,
                      border: Border.all(color: context.appTheme.border),
                      borderRadius: BorderRadius.circular(9)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: usine.isEmpty ? null : usine,
                      isExpanded: true,
                      hint: const Text('Select a factory'),
                      items: factoryNames
                          .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) => setS(() => usine = v!),
                    ),
                  ),
                ),
                _SheetLabel('Hire Date'),
                GestureDetector(
                  onTap: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: hired,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      builder: (c, child) => Theme(
                          data: ThemeData.light().copyWith(
                              colorScheme:
                                  const ColorScheme.light(primary: _navy)),
                          child: child!),
                    );
                    if (p != null) setS(() => hired = p);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 13),
                    decoration: BoxDecoration(
                        color: context.appTheme.scaffold,
                        border: Border.all(color: context.appTheme.border),
                        borderRadius: BorderRadius.circular(9)),
                    child: Row(children: [
                      const Icon(Icons.calendar_today, size: 16, color: _muted),
                      const SizedBox(width: 8),
                      Text(_fmtDate(hired),
                          style: const TextStyle(fontSize: 14)),
                    ]),
                  ),
                ),
                if (error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        border: Border.all(color: _red),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(error!,
                        style: const TextStyle(color: _red, fontSize: 13)),
                  ),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: loading
                          ? null
                          : () async {
                              if ([first, last, email, pass]
                                  .any((c) => c.text.trim().isEmpty)) {
                                setS(() => error = 'All fields are required.');
                                return;
                              }
                              if (usine.isEmpty) {
                                setS(() => error = 'Please select a factory.');
                                return;
                              }
                              setS(() {
                                loading = true;
                                error = null;
                              });
                              final err = await _auth.createSupervisor(
                                firstName: first.text.trim(),
                                lastName: last.text.trim(),
                                email: email.text.trim(),
                                password: pass.text.trim(),
                                phone: phone.text.trim(),
                                usine: usine,
                                hiredDate: hired,
                              );
                              if (!ctx.mounted) return;
                              if (err != null) {
                                setS(() {
                                  error = err;
                                  loading = false;
                                });
                              } else {
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _loadSupervisors();
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Supervisor created'),
                                          backgroundColor: _green));
                              }
                            },
                      icon: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: _white, strokeWidth: 2))
                          : const Icon(Icons.check, size: 18),
                      label: Text(loading ? 'Creating…' : 'Create Account',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _navy,
                          foregroundColor: _white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(color: _muted))),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(UserModel sup) async {
    await _auth.deleteSupervisor(sup.id);
    await _loadSupervisors();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: const Text('Supervisor removed'), backgroundColor: _red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appTheme.scaffold,
      body: SafeArea(
          child: Column(children: [
        _Header(
          activeSups: _activeSups,
          onLogout: _logout,
          onSimulateAlert: _showSimulateDialog,
        ),
        _PillTabBar(tab: _tab, onSelect: (i) => setState(() => _tab = i)),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _navy))
                : _buildContent()),
      ])),
      floatingActionButton: const VoiceCommandButton(),
    );
  }

  Widget _buildContent() {
    switch (_tab) {
      case 0:
        return _OverviewTab(
          total: _total,
          solved: _solved,
          inProgress: _inProgress,
          pending: _pending,
          alerts: _filteredAlerts,
          timeRange: _timeRange,
          timeRangeLabel: _timeRangeLabel,
          timeRangeSubtitle: _timeRangeSubtitle,
          selectedUsine: _selectedUsine,
          filterConvoyeur: _filterConvoyeur,
          filterPoste: _filterPoste,
          filterType: _filterType,
          filterStatus: _filterStatus,
          onTimeRangeChange: (v) {
            setState(() => _timeRange = v);
            if (v == 'custom')
              _showDateRangePicker();
            else {
              _applyFilters();
              _saveFilters();
            }
          },
          onUsineChange: (v) {
            setState(() => _selectedUsine = v);
            _applyFilters();
            _saveFilters();
          },
          onConvoyeurChange: (v) {
            setState(() => _filterConvoyeur = v);
            _applyFilters();
          },
          onPosteChange: (v) {
            setState(() => _filterPoste = v);
            _applyFilters();
          },
          onTypeChange: (v) {
            setState(() => _filterType = v);
            _applyFilters();
          },
          onStatusChange: (v) {
            setState(() => _filterStatus = v);
            _applyFilters();
          },
          onReset: () {
            setState(() {
              _timeRange = 'week';
              _selectedUsine = 'all';
              _filterConvoyeur = 'all';
              _filterPoste = 'all';
              _filterType = 'all';
              _filterStatus = 'all';
              _customStartDate = null;
              _customEndDate = null;
            });
            _applyFilters();
            _saveFilters();
          },
          onExportCsv: _exportToCsv,
          onExportExcel: _exportToExcel,
          allAlerts: _alerts,
        );
      case 1:
        return _SupervisorsTab(
          supervisors: _supervisors,
          alerts: _alerts,
          onAdd: _showCreateSheet,
          onDelete: _confirmDelete,
          onRefresh: _loadSupervisors,
        );
      case 2:
        return AlertsTreeTab(
          alerts: _alerts,
          onAssignAssistant: _assignAssistant,
        );
      case 3:
        return const AdminEscalationScreen();
      case 4:
        return const HierarchyScreen();
      default:
        return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════
class _Header extends StatefulWidget {
  final int activeSups;
  final VoidCallback onLogout;
  final VoidCallback onSimulateAlert;
  const _Header({
    required this.activeSups,
    required this.onLogout,
    required this.onSimulateAlert,
  });
  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  int _notificationCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _notifSub;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _db.child('notifications/$uid').remove();
      _notifSub = _db.child('notifications/$uid').onValue.listen(
        (event) {
          final data = event.snapshot.value;
          if (data == null) {
            setState(() {
              _notificationCount = 0;
              _notifications = [];
            });
            return;
          }
          final map = Map<String, dynamic>.from(data as Map);
          final list = map.entries.map((e) {
            final m = Map<String, dynamic>.from(e.value as Map);
            m['id'] = e.key;
            return m;
          }).toList();
          final pending = list.where((n) => n['status'] != 'read').toList();
          setState(() {
            _notifications = list;
            _notificationCount = pending.length;
          });
        },
        onError: (error) {
          debugPrint('Notification stream error: $error');
          // Don't crash; just treat as empty
          if (mounted) {
            setState(() {
              _notifications = [];
              _notificationCount = 0;
            });
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  Future<void> _markNotificationAsRead(
    Map<String, dynamic> notification,
    StateSetter setModalState,
    BuildContext modalContext,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final notificationId = notification['id']?.toString();
    if (uid == null || notificationId == null || notificationId.isEmpty) {
      return;
    }

    await _db.child('notifications/$uid/$notificationId').remove();

    if (!mounted || !modalContext.mounted) return;
    setModalState(() {
      _notifications.removeWhere((item) => item['id'] == notificationId);
      _notificationCount =
          _notifications.where((item) => item['status'] != 'read').length;
    });
    setState(() {});
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            final textColor = theme.brightness == Brightness.dark
                ? Colors.white
                : Colors.black87;
            return Container(
              padding: const EdgeInsets.all(16),
              height: 400,
              color: theme.scaffoldBackgroundColor,
              child: Column(
                children: [
                  Text('Notifications',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor)),
                  Divider(color: theme.dividerColor),
                  Expanded(
                    child: _notifications.isEmpty
                        ? Center(
                            child: Text('No notifications',
                                style: TextStyle(color: textColor)))
                        : ListView.builder(
                            itemCount: _notifications.length,
                            itemBuilder: (context, index) {
                              final n = _notifications[index];
                              final notificationType =
                                  (n['type'] ?? '').toString();
                              final isCollabNotification =
                                  notificationType.startsWith('collaboration_');
                              if (n['type'] ==
                                  'ai_cross_factory_recommendation') {
                                final alertId = (n['alertId'] ?? '').toString();
                                final recName =
                                    (n['recommendedSupervisorName'] ?? '')
                                        .toString();
                                final recReason =
                                    (n['reason'] ?? '').toString();

                                Future<void> completeDecision(
                                    {required bool approve}) async {
                                  if (alertId.isEmpty) return;
                                  final current =
                                      FirebaseAuth.instance.currentUser;
                                  final approverId = current?.uid;
                                  final approverName =
                                      current?.email?.split('@').first ??
                                          'Production Manager';

                                  final ok = approve
                                      ? await AIAssignmentService.instance
                                          .approveCrossFactoryRecommendation(
                                          alertId: alertId,
                                          approverId: approverId,
                                          approverName: approverName,
                                        )
                                      : await AIAssignmentService.instance
                                          .declineCrossFactoryRecommendation(
                                          alertId: alertId,
                                          approverId: approverId,
                                          approverName: approverName,
                                        );

                                  await _db
                                      .child(
                                          'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                      .remove();

                                  if (context.mounted) {
                                    setModalState(() {
                                      _notifications.removeWhere(
                                          (item) => item['id'] == n['id']);
                                      _notificationCount = _notifications
                                          .where((x) => x['status'] != 'read')
                                          .length;
                                    });

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(ok
                                            ? (approve
                                                ? 'Recommendation approved'
                                                : 'Recommendation declined')
                                            : 'Recommendation was already processed'),
                                        backgroundColor: ok
                                            ? (approve
                                                ? Colors.green
                                                : Colors.orange)
                                            : Colors.blueGrey,
                                      ),
                                    );
                                  }
                                }

                                return ListTile(
                                  title: Text(
                                    n['message'] ??
                                        'AI cross-factory recommendation',
                                    style: TextStyle(
                                        color:
                                            theme.brightness == Brightness.dark
                                                ? Colors.white
                                                : Colors.black87),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (recName.isNotEmpty)
                                        Text('Recommended: $recName',
                                            style: TextStyle(
                                                color: theme.brightness ==
                                                        Brightness.dark
                                                    ? Colors.white70
                                                    : Colors.black54)),
                                      if (recReason.isNotEmpty)
                                        Text(recReason,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: theme.brightness ==
                                                        Brightness.dark
                                                    ? Colors.white70
                                                    : Colors.black54)),
                                    ],
                                  ),
                                  trailing: SizedBox(
                                    width: 188,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => completeDecision(
                                                approve: false),
                                            icon: const Icon(Icons.close,
                                                size: 14, color: Colors.white),
                                            label: const Text('Decline',
                                                style: TextStyle(fontSize: 11)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFFFB3BA),
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => completeDecision(
                                              approve: true,
                                            ),
                                            icon: const Icon(Icons.check,
                                                size: 14, color: Colors.white),
                                            label: const Text('Approve',
                                                style: TextStyle(fontSize: 11)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  onTap: () async {
                                    await _db
                                        .child(
                                            'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                        .remove();
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AlertDetailScreen(
                                              alertId: alertId),
                                        ),
                                      );
                                    }
                                  },
                                );
                              } else if (n['type'] == 'help_request') {
                                return ListTile(
                                  title: Text(n['message'] ?? 'Help request',
                                      style: TextStyle(
                                          color: theme.brightness ==
                                                  Brightness.dark
                                              ? Colors.white
                                              : Colors.black87)),
                                  subtitle: Text('Tap to accept or refuse',
                                      style: TextStyle(
                                          color: theme.brightness ==
                                                  Brightness.dark
                                              ? Colors.white70
                                              : Colors.black54)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.check_circle,
                                            color: Colors.green),
                                        onPressed: () async {
                                          await Provider.of<AlertProvider>(
                                                  context,
                                                  listen: false)
                                              .acceptHelp(n['alertId'],
                                                  n['helpRequestId']);
                                          await _db
                                              .child(
                                                  'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                              .remove();
                                          if (context.mounted) {
                                            setModalState(() {
                                              _notifications.removeWhere(
                                                  (item) =>
                                                      item['id'] == n['id']);
                                              _notificationCount =
                                                  _notifications
                                                      .where((x) =>
                                                          x['status'] != 'read')
                                                      .length;
                                            });
                                          }
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Help request accepted'),
                                                  backgroundColor:
                                                      Colors.green),
                                            );
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.cancel,
                                            color: Colors.red),
                                        onPressed: () async {
                                          await Provider.of<AlertProvider>(
                                                  context,
                                                  listen: false)
                                              .refuseHelp(n['alertId'],
                                                  n['helpRequestId']);
                                          await _db
                                              .child(
                                                  'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                              .remove();
                                          if (context.mounted) {
                                            setModalState(() {
                                              _notifications.removeWhere(
                                                  (item) =>
                                                      item['id'] == n['id']);
                                              _notificationCount =
                                                  _notifications
                                                      .where((x) =>
                                                          x['status'] != 'read')
                                                      .length;
                                            });
                                          }
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Help request refused'),
                                                  backgroundColor:
                                                      Colors.orange),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              } else if (n['type'] == 'assistance_request') {
                                return ListTile(
                                  title: Text(
                                      n['message'] ?? 'Assistance request',
                                      style: TextStyle(
                                          color: theme.brightness ==
                                                  Brightness.dark
                                              ? Colors.white
                                              : Colors.black87)),
                                  subtitle: Text(n['alertDescription'] ?? '',
                                      style: TextStyle(
                                          color: theme.brightness ==
                                                  Brightness.dark
                                              ? Colors.white70
                                              : Colors.black54)),
                                  trailing: ElevatedButton(
                                    onPressed: () async {
                                      final supervisors = await AuthService()
                                          .getActiveSupervisors();
                                      if (supervisors.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'No active supervisors available')),
                                        );
                                        return;
                                      }
                                      showDialog(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Assign Assistant'),
                                          content: SizedBox(
                                            width: 300,
                                            child: ListView.builder(
                                              shrinkWrap: true,
                                              itemCount: supervisors.length,
                                              itemBuilder: (_, i) => ListTile(
                                                leading: const Icon(
                                                    Icons.person,
                                                    color: _navy),
                                                title: Text(
                                                    supervisors[i].fullName),
                                                subtitle:
                                                    Text(supervisors[i].email),
                                                onTap: () async {
                                                  Navigator.pop(_);
                                                  await AuthService()
                                                      .assignAssistantToAlert(
                                                    n['alertId'],
                                                    supervisors[i].id,
                                                    supervisors[i].fullName,
                                                  );
                                                  await _db
                                                      .child(
                                                          'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                                      .remove();
                                                  if (context.mounted) {
                                                    setModalState(() {
                                                      _notifications
                                                          .removeWhere((item) =>
                                                              item['id'] ==
                                                              n['id']);
                                                      _notificationCount =
                                                          _notifications
                                                              .where((x) =>
                                                                  x['status'] !=
                                                                  'read')
                                                              .length;
                                                    });
                                                  }
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                        content: Text(
                                                            'Assigned ${supervisors[i].fullName} as assistant'),
                                                        backgroundColor:
                                                            Colors.green),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(_),
                                                child: const Text('Cancel')),
                                          ],
                                        ),
                                      );
                                    },
                                    child: const Text('Assign Assistant',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                );
                              } else {
                                return ListTile(
                                  title: Text(n['message'] ?? 'Notification'),
                                  subtitle: Text(n['alertDescription'] ?? ''),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (n['status'] != 'read' &&
                                          isCollabNotification)
                                        OutlinedButton.icon(
                                          onPressed: () async {
                                            await _markNotificationAsRead(
                                                n, setModalState, context);
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      'Collaboration notification marked as read'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          },
                                          icon: const Icon(
                                              Icons.done_all_rounded,
                                              size: 16),
                                          label: const Text('Read',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _navy,
                                            side: BorderSide(
                                                color: theme.dividerColor),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                            minimumSize: const Size(0, 36),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                        )
                                      else if (n['status'] != 'read')
                                        IconButton(
                                          icon: const Icon(Icons.visibility,
                                              size: 18, color: Colors.blue),
                                          onPressed: () async {
                                            await _db
                                                .child(
                                                    'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                                .remove();
                                            if (context.mounted) {
                                              setModalState(() {
                                                _notifications.removeWhere(
                                                    (item) =>
                                                        item['id'] == n['id']);
                                                _notificationCount =
                                                    _notifications
                                                        .where((x) =>
                                                            x['status'] !=
                                                            'read')
                                                        .length;
                                              });
                                            }
                                          },
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.open_in_new,
                                            size: 18, color: _navy),
                                        onPressed: () async {
                                          if (n['status'] != 'read') {
                                            await _db
                                                .child(
                                                    'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                                .remove();
                                          }
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    AlertDetailScreen(
                                                        alertId: n['alertId']),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    if (n['status'] != 'read') {
                                      await _db
                                          .child(
                                              'notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}')
                                          .remove();
                                    }
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AlertDetailScreen(
                                              alertId: n['alertId']),
                                        ),
                                      );
                                    }
                                  },
                                );
                              }
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final isDark = context.isDark;
    return Container(
      color: t.card,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: t.navyLt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.border)),
          child: Center(child: Icon(Icons.factory, size: 22, color: t.navy)),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Production Manager',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: t.navy,
                  letterSpacing: .2)),
          Text('Production Manager - Dashboard',
              style: TextStyle(fontSize: 11, color: t.muted)),
        ]),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.add_alert_outlined, color: t.muted, size: 22),
          tooltip: 'Simulate Alert',
          onPressed: widget.onSimulateAlert,
        ),
        // ── Theme toggle ──
        IconButton(
          icon: Icon(
            isDark ? Icons.light_mode : Icons.dark_mode,
            color: t.muted,
            size: 22,
          ),
          tooltip: isDark ? 'Light mode' : 'Dark mode',
          onPressed: () => context.read<ThemeProvider>().toggle(),
        ),
        // ── Notifications ──
        Stack(children: [
          IconButton(
            icon: Icon(Icons.notifications_none, color: t.muted, size: 24),
            onPressed: _showNotifications,
          ),
          if (_notificationCount > 0)
            Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration:
                      BoxDecoration(color: t.red, shape: BoxShape.circle),
                  child: Center(
                      child: Text('$_notificationCount',
                          style: TextStyle(
                              color: t.card,
                              fontSize: 9,
                              fontWeight: FontWeight.w700))),
                )),
        ]),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed: widget.onLogout,
          icon: Icon(Icons.logout, size: 15, color: t.red),
          label: Text('Sign Out',
              style: TextStyle(
                  color: t.red, fontSize: 13, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
              side: BorderSide(color: t.red),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PILL TAB BAR
// ═══════════════════════════════════════════════════════════════════════════
class _PillTabBar extends StatelessWidget {
  final int tab;
  final void Function(int) onSelect;
  const _PillTabBar({required this.tab, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const tabs = [
      {'icon': Icons.bar_chart, 'label': 'Overview'},
      {'icon': Icons.people, 'label': 'Supervisors'},
      {'icon': Icons.notifications_outlined, 'label': 'Alerts'},
      {'icon': Icons.warning_amber, 'label': 'Escalations'}, // <-- NEW
      {'icon': Icons.account_tree, 'label': 'Hierarchy'}, // NEW
    ];
    final t = context.appTheme;
    return Container(
      color: t.card,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: List.generate(tabs.length, (i) {
          final sel = tab == i;
          final item = tabs[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? t.navy : t.scaffold,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? t.navy : t.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(item['icon'] as IconData,
                      size: 15, color: sel ? Colors.white : t.muted),
                  const SizedBox(width: 6),
                  Text(item['label'] as String,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : t.muted)),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
