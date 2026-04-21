import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'login_screen.dart';
import 'alert_detail_screen.dart';
import 'package:http/http.dart' as http;

// ── Palette ─────────────────────────────────────────────────────────────
const _navy    = Color(0xFF0D4A75);
const _navyLt  = Color(0xFFE8F0F8);
const _red     = Color(0xFFDC2626);
const _white   = Colors.white;
const _bg      = Color(0xFFF8FAFC);
const _border  = Color(0xFFE2E8F0);
const _muted   = Color(0xFF94A3B8);
const _text    = Color(0xFF1E293B);
const _green   = Color(0xFF16A34A);
const _greenLt = Color(0xFFDCFCE7);
const _orange  = Color(0xFFEA580C);
const _orangeLt= Color(0xFFFFF7ED);
const _blue    = Color(0xFF2563EB);
const _blueLt  = Color(0xFFEFF6FF);

Color _typeColor(String t) => switch (t) {
  'qualite'          => const Color(0xFFDC2626),
  'maintenance'      => const Color(0xFF2563EB),
  'defaut_produit'   => const Color(0xFF16A34A),
  'manque_ressource' => const Color(0xFFD97706),
  _                  => const Color(0xFF64748B),
};

String _typeLabel(String t) => switch (t) {
  'qualite'          => 'Quality',
  'maintenance'      => 'Maintenance',
  'defaut_produit'   => 'Damaged Product',
  'manque_ressource' => 'Resources Deficiency',
  _                  => t,
};

IconData _typeIcon(String t) => switch (t) {
  'qualite'          => Icons.warning_amber_rounded,
  'maintenance'      => Icons.build_outlined,
  'defaut_produit'   => Icons.cancel_outlined,
  'manque_ressource' => Icons.inventory_2_outlined,
  _                  => Icons.notifications_outlined,
};

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

String _fmtTs(DateTime d) =>
    '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')} '
    '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';

String _fmtMin(int min) =>
    min < 60 ? '${min}m' : '${min ~/ 60}h ${min % 60}m';

// ═══════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int    _tab        = 0;   // 0=Overview  1=Supervisors  2=Alerts
  List<UserModel>  _supervisors = [];
  List<AlertModel> _alerts      = [];
  bool _loading = true;

  final _db   = FirebaseDatabase.instance;
  final _auth = AuthService();

  // Filter state
  String _timeRange      = 'week';
  String _selectedUsine  = 'all';
  String _filterConvoyeur= 'all';
  String _filterPoste    = 'all';
  String _filterType     = 'all';
  String _filterStatus   = 'all';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  List<AlertModel> _filteredAlerts = [];

  static const String _prefTimeRange = 'overview_time_range';
  static const String _prefUsine     = 'overview_usine';

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
      _timeRange     = prefs.getString(_prefTimeRange) ?? 'week';
      _selectedUsine = prefs.getString(_prefUsine)     ?? 'all';
    });
    _applyFilters();
  }

  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefTimeRange, _timeRange);
    await prefs.setString(_prefUsine,     _selectedUsine);
  }

  void _applyFilters() {
    if (_alerts.isEmpty) { setState(() => _filteredAlerts = []); return; }
    final now = DateTime.now();
    final filtered = _alerts.where((a) {
      bool timeOk = switch (_timeRange) {
        'today'  => a.timestamp.year  == now.year  &&
                    a.timestamp.month == now.month &&
                    a.timestamp.day   == now.day,
        'week'   => a.timestamp.isAfter(now.subtract(Duration(days: now.weekday - 1))) &&
                    a.timestamp.isBefore(now.subtract(Duration(days: now.weekday - 1))
                        .add(const Duration(days: 7))),
        'month'  => a.timestamp.year  == now.year && a.timestamp.month == now.month,
        'year'   => a.timestamp.year  == now.year,
        'custom' => (_customStartDate != null && _customEndDate != null)
                    ? a.timestamp.isAfter(_customStartDate!) &&
                      a.timestamp.isBefore(_customEndDate!)
                    : true,
        _        => true,
      };
      if (!timeOk) return false;
      if (_selectedUsine   != 'all' && a.usine                          != _selectedUsine)    return false;
      if (_filterConvoyeur != 'all' && a.convoyeur.toString()           != _filterConvoyeur)  return false;
      if (_filterPoste     != 'all' && a.poste.toString()               != _filterPoste)      return false;
      if (_filterType      != 'all' && a.type                           != _filterType)       return false;
      if (_filterStatus    != 'all' && a.status                         != _filterStatus)     return false;
      return true;
    }).toList();
    setState(() => _filteredAlerts = filtered);
  }

  Future<void> _loadSupervisors() async {
    final list = await _auth.fetchSupervisors();
    if (mounted) setState(() { _supervisors = list; _loading = false; });
  }

  void _loadAlerts() {
    _db.ref('alerts').onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data == null) { setState(() { _alerts = []; _filteredAlerts = []; }); return; }
      final map  = Map<String, dynamic>.from(data as Map);
      final list = map.entries
          .map((e) => AlertModel.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() => _alerts = list);
      _applyFilters();
    });
  }

  int get _total      => _filteredAlerts.length;
  int get _solved     => _filteredAlerts.where((a) => a.status == 'validee').length;
  int get _inProgress => _filteredAlerts.where((a) => a.status == 'en_cours').length;
  int get _pending    => _filteredAlerts.where((a) => a.status == 'disponible').length;
  int get _activeSups => _supervisors.where((s) => s.isActive).length;

  String get _timeRangeLabel => switch (_timeRange) {
    'today'  => 'Today',
    'week'   => 'Last Week',
    'month'  => 'This Month',
    'year'   => 'This Year',
    'custom' => _customStartDate != null && _customEndDate != null
        ? '${_customStartDate!.day}/${_customStartDate!.month} – '
          '${_customEndDate!.day}/${_customEndDate!.month}'
        : 'Custom',
    _        => 'All time',
  };

  String get _timeRangeSubtitle => switch (_timeRange) {
    'today'  => 'Showing today\'s data',
    'week'   => 'Showing last 7 days',
    'month'  => 'Showing this month',
    'year'   => 'Showing this year',
    _        => 'Filtered view',
  };

  Future<void> _logout() async {
    await _auth.logout();
  }

  // ── Alert creation methods (added) ────────────────────────────────────
  Future<void> _simulateAlert({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    required bool isCritical,
  }) async {
    await _createSimulatedAlert(
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
          content: Text('✅ Simulated ${_typeLabel(type)} alert on $usine, Conv $convoyeur, Post $poste'),
          backgroundColor: _green,
        ),
      );
    }
  }

  Future<void> _createSimulatedAlert({
    required String type,
    required String usine,
    required int convoyeur,
    required int poste,
    required String description,
    bool isCritical = false,
  }) async {
    final ref = _db.ref('alerts').push();
    final now = DateTime.now();
    final alertId = ref.key;
    await ref.set({
      'type': type,
      'usine': usine,
      'convoyeur': convoyeur,
      'poste': poste,
      'adresse': '${usine.replaceAll(' ', '_')}_C${convoyeur}_P$poste',
      'timestamp': now.toIso8601String(),
      'description': description,
      'status': 'disponible',
      'comments': [],
      'isCritical': isCritical,
      'push_sent': false,   // ⬅️ critical for Cloudflare Worker
      'superviseurId': null,
      'superviseurName': null,
      'assistantId': null,
      'assistantName': null,
      'resolutionReason': null,
      'resolvedAt': null,
      'elapsedTime': null,
    });

    // Optional: trigger Cloudflare Worker manually (not needed if cron works)
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
        const SnackBar(content: Text('No alerts to export'), backgroundColor: Colors.orange),
      );
      return;
    }

    List<List<dynamic>> csvData = [
      ['ID', 'Type', 'Usine', 'Convoyeur', 'Poste', 'Adresse', 'Timestamp', 'Description', 'Status', 'Superviseur', 'Assistant', 'Resolution Reason', 'Elapsed Time (min)', 'Critical']
    ];
    for (var alert in _filteredAlerts) {
      csvData.add([
        alert.id,
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
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'alerts_export_${DateTime.now().millisecondsSinceEpoch}.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/alerts_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Alert export');
    }
  }

  Future<void> _exportToExcel() async {
    if (_filteredAlerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No alerts to export'), backgroundColor: Colors.orange),
      );
      return;
    }

    var excelFile = excel.Excel.createExcel();
    var sheet = excelFile['Alerts'];
    sheet.appendRow([
      excel.TextCellValue('ID'), excel.TextCellValue('Type'), excel.TextCellValue('Usine'),
      excel.TextCellValue('Convoyeur'), excel.TextCellValue('Poste'), excel.TextCellValue('Adresse'),
      excel.TextCellValue('Timestamp'), excel.TextCellValue('Description'), excel.TextCellValue('Status'),
      excel.TextCellValue('Superviseur'), excel.TextCellValue('Assistant'), excel.TextCellValue('Resolution Reason'),
      excel.TextCellValue('Elapsed Time (min)'), excel.TextCellValue('Critical'),
    ]);
    for (var alert in _filteredAlerts) {
      sheet.appendRow([
        excel.TextCellValue(alert.id),
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
      final blob = html.Blob([fileBytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'alerts_export_${DateTime.now().millisecondsSinceEpoch}.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/alerts_export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
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
        start: _customStartDate ?? DateTime.now().subtract(const Duration(days: 7)),
        end:   _customEndDate   ?? DateTime.now(),
      ),
    );
    if (picked != null) {
      setState(() { _customStartDate = picked.start; _customEndDate = picked.end; });
      _applyFilters(); _saveFilters();
    } else {
      setState(() => _timeRange = 'week');
    }
  }

  Future<void> _assignSupervisor(AlertModel alert) async {
    final supervisors = await _auth.getActiveSupervisors();
    if (supervisors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('👷 No active supervisors available')));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('👷 Assign Supervisor'),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: supervisors.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.person, color: _navy),
              title: Text(supervisors[i].fullName),
              subtitle: Text(supervisors[i].email),
              onTap: () async {
                Navigator.pop(_);
                await _auth.assignSupervisorToAlert(
                    alert.id, supervisors[i].id, supervisors[i].fullName);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('✅ Assigned to ${supervisors[i].fullName}'),
                    backgroundColor: _green));
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_),
              child: const Text('Cancel'))
        ],
      ),
    );
  }

  Future<void> _assignAssistant(AlertModel alert) async {
    final supervisors = await _auth.getActiveSupervisors();
    if (supervisors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('👷 No active supervisors available')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('👷 Assign Assistant'),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: supervisors.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.person_add, color: _navy),
              title: Text(supervisors[i].fullName),
              subtitle: Text(supervisors[i].email),
              onTap: () async {
                Navigator.pop(_);
                await _auth.assignAssistantToAlert(alert.id, supervisors[i].id, supervisors[i].fullName);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Assigned ${supervisors[i].fullName} as assistant'), backgroundColor: _green),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _showSimulateDialog() {
    String selectedType = 'qualite';
    String selectedUsine = 'Usine A';
    int selectedConvoyeur = 1;
    int selectedPoste = 1;
    String description = '';
    bool isCritical = false;

    final List<String> usines = ['Usine A', 'Usine B', 'Usine C', 'Usine D'];
    final List<int> convoyeurs = List.generate(10, (i) => i + 1);
    final List<int> postes = List.generate(10, (i) => i + 1);

    final Map<String, String> typeLabels = {
      'qualite': '⚠️ Quality',
      'maintenance': '🔧 Maintenance',
      'defaut_produit': '🔨 Damaged Product',
      'manque_ressource': '📦 Resource Shortage',
    };

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('🚨 Simulate Custom Alert', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Alert Type', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    items: typeLabels.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    )).toList(),
                    onChanged: (val) => setState(() => selectedType = val!),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Plant (Usine)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedUsine,
                    items: usines.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (val) => setState(() => selectedUsine = val!),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Conveyor Number', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: selectedConvoyeur,
                    items: convoyeurs.map((c) => DropdownMenuItem(value: c, child: Text('Conveyor $c'))).toList(),
                    onChanged: (val) => setState(() => selectedConvoyeur = val!),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Poste (Workstation)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: selectedPoste,
                    items: postes.map((p) => DropdownMenuItem(value: p, child: Text('Post $p'))).toList(),
                    onChanged: (val) => setState(() => selectedPoste = val!),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  const Text('Description (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
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
                      const Text('Mark as Critical', style: TextStyle(fontWeight: FontWeight.w600)),
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
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _simulateAlert(
                    type: selectedType,
                    usine: selectedUsine,
                    convoyeur: selectedConvoyeur,
                    poste: selectedPoste,
                    description: description.trim(),
                    isCritical: isCritical,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: _navy),
                child: const Text('Create Alert', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateSheet() {
    // Original create supervisor sheet (unchanged)
    final first = TextEditingController();
    final last  = TextEditingController();
    final email = TextEditingController();
    final pass  = TextEditingController();
    final phone = TextEditingController();
    String usine   = 'Usine A';
    DateTime hired = DateTime.now();
    String? error;
    bool loading   = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(color: _border,
                        borderRadius: BorderRadius.circular(99)))),
                Row(children: [
                  Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: _navyLt,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.person_add_outlined,
                          color: _navy, size: 20)),
                  const SizedBox(width: 12),
                  const Text('New Supervisor Account',
                      style: TextStyle(fontSize: 18,
                          fontWeight: FontWeight.w700, color: _navy)),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _SheetField('First Name', first, 'Ahmed')),
                  const SizedBox(width: 10),
                  Expanded(child: _SheetField('Last Name',  last,  'Benali')),
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
                  decoration: BoxDecoration(color: _bg,
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(9)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: usine, isExpanded: true,
                      items: ['Usine A','Usine B','Usine C','Usine D']
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
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
                            colorScheme: const ColorScheme.light(primary: _navy)),
                        child: child!),
                    );
                    if (p != null) setS(() => hired = p);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 13),
                    decoration: BoxDecoration(color: _bg,
                        border: Border.all(color: _border),
                        borderRadius: BorderRadius.circular(9)),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 16, color: _muted),
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
                      onPressed: loading ? null : () async {
                        if ([first, last, email, pass]
                            .any((c) => c.text.trim().isEmpty)) {
                          setS(() => error = 'All fields are required.');
                          return;
                        }
                        setS(() { loading = true; error = null; });
                        final err = await _auth.createSupervisor(
                          firstName: first.text.trim(),
                          lastName:  last.text.trim(),
                          email:     email.text.trim(),
                          password:  pass.text.trim(),
                          phone:     phone.text.trim(),
                          usine:     usine,
                          hiredDate: hired,
                        );
                        if (!ctx.mounted) return;
                        if (err != null) {
                          setS(() { error = err; loading = false; });
                        } else {
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadSupervisors();
                          if (mounted) ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                              content: Text('✅ Supervisor created'),
                              backgroundColor: _green));
                        }
                      },
                      icon: loading
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  color: _white, strokeWidth: 2))
                          : const Icon(Icons.check, size: 18),
                      label: Text(loading ? 'Creating…' : 'Create Account',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _navy, foregroundColor: _white,
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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('👷 Supervisor removed'), backgroundColor: _red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: Column(children: [
        _Header(activeSups: _activeSups, onLogout: _logout),
        _PillTabBar(tab: _tab, onSelect: (i) => setState(() => _tab = i)),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _navy))
            : _buildContent()),
      ])),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSimulateDialog,
        backgroundColor: _navy,
        tooltip: 'Simulate Alert',
        child: const Icon(Icons.add_alert),
      ),
    );
  }

  Widget _buildContent() {
    switch (_tab) {
      case 0:
        return _OverviewTab(
          total: _total, solved: _solved,
          inProgress: _inProgress, pending: _pending,
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
            if (v == 'custom') _showDateRangePicker();
            else { _applyFilters(); _saveFilters(); }
          },
          onUsineChange: (v) {
            setState(() => _selectedUsine = v);
            _applyFilters(); _saveFilters();
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
              _timeRange = 'week'; _selectedUsine = 'all';
              _filterConvoyeur = 'all'; _filterPoste = 'all';
              _filterType = 'all'; _filterStatus = 'all';
              _customStartDate = null; _customEndDate = null;
            });
            _applyFilters(); _saveFilters();
          },
          onExportCsv: _exportToCsv,
          onExportExcel: _exportToExcel,
          allAlerts: _alerts,
        );
      case 1:
        return _SupervisorsTab(
          supervisors: _supervisors, alerts: _alerts,
          onAdd: _showCreateSheet, onDelete: _confirmDelete);
      default:
        return _AlertsTab(
          alerts: _alerts,
          onAssign: _assignSupervisor,
          onAssignAssistant: _assignAssistant,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════
class _Header extends StatefulWidget {
  final int activeSups;
  final VoidCallback onLogout;
  const _Header({required this.activeSups, required this.onLogout});
  @override State<_Header> createState() => _HeaderState();
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
      _notifSub = _db.child('notifications/$uid').onValue.listen((event) {
        final data = event.snapshot.value;
        if (data == null) {
          setState(() { _notificationCount = 0; _notifications = []; });
          return;
        }
        final map  = Map<String, dynamic>.from(data as Map);
        final list = map.entries.map((e) {
          final m = Map<String, dynamic>.from(e.value as Map);
          m['id'] = e.key; return m;
        }).toList();
        final pending = list.where((n) => n['status'] != 'read').toList();
        setState(() { _notifications = list; _notificationCount = pending.length; });
      });
    }
  }

  @override
  void dispose() { _notifSub?.cancel(); super.dispose(); }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: 400,
              child: Column(
                children: [
                  const Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  Expanded(
                    child: _notifications.isEmpty
                        ? const Center(child: Text('No notifications'))
                        : ListView.builder(
                            itemCount: _notifications.length,
                            itemBuilder: (context, index) {
                              final n = _notifications[index];
                              if (n['type'] == 'help_request') {
                                return ListTile(
                                  title: Text(n['message'] ?? 'Help request'),
                                  subtitle: const Text('Tap to accept or refuse'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.check_circle, color: Colors.green),
                                        onPressed: () async {
                                          await Provider.of<AlertProvider>(context, listen: false)
                                              .acceptHelp(n['alertId'], n['helpRequestId']);
                                          await _db.child('notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}').remove();
                                          if (context.mounted) {
                                            setModalState(() {
                                              _notifications.removeWhere((item) => item['id'] == n['id']);
                                              _notificationCount = _notifications.where((x) => x['status'] != 'read').length;
                                            });
                                          }
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Help request accepted'), backgroundColor: Colors.green),
                                            );
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.cancel, color: Colors.red),
                                        onPressed: () async {
                                          await Provider.of<AlertProvider>(context, listen: false)
                                              .refuseHelp(n['alertId'], n['helpRequestId']);
                                          await _db.child('notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}').remove();
                                          if (context.mounted) {
                                            setModalState(() {
                                              _notifications.removeWhere((item) => item['id'] == n['id']);
                                              _notificationCount = _notifications.where((x) => x['status'] != 'read').length;
                                            });
                                          }
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Help request refused'), backgroundColor: Colors.orange),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              } else if (n['type'] == 'assistance_request') {
                                return ListTile(
                                  title: Text(n['message'] ?? 'Assistance request'),
                                  subtitle: Text(n['alertDescription'] ?? ''),
                                  trailing: ElevatedButton(
                                    onPressed: () async {
                                      final supervisors = await AuthService().getActiveSupervisors();
                                      if (supervisors.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('No active supervisors available')),
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
                                                leading: const Icon(Icons.person, color: _navy),
                                                title: Text(supervisors[i].fullName),
                                                subtitle: Text(supervisors[i].email),
                                                onTap: () async {
                                                  Navigator.pop(_);
                                                  await AuthService().assignAssistantToAlert(
                                                    n['alertId'],
                                                    supervisors[i].id,
                                                    supervisors[i].fullName,
                                                  );
                                                  await _db.child('notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}').remove();
                                                  if (context.mounted) {
                                                    setModalState(() {
                                                      _notifications.removeWhere((item) => item['id'] == n['id']);
                                                      _notificationCount = _notifications.where((x) => x['status'] != 'read').length;
                                                    });
                                                  }
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('✅ Assigned ${supervisors[i].fullName} as assistant'), backgroundColor: Colors.green),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
                                          ],
                                        ),
                                      );
                                    },
                                    child: const Text('Assign Assistant', style: TextStyle(fontSize: 12)),
                                  ),
                                );
                              } else {
                                return ListTile(
                                  title: Text(n['message'] ?? 'Notification'),
                                  subtitle: Text(n['alertDescription'] ?? ''),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (n['status'] != 'read')
                                        IconButton(
                                          icon: const Icon(Icons.visibility, size: 18, color: Colors.blue),
                                          onPressed: () async {
                                            await _db.child('notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}').remove();
                                            if (context.mounted) {
                                              setModalState(() {
                                                _notifications.removeWhere((item) => item['id'] == n['id']);
                                                _notificationCount = _notifications.where((x) => x['status'] != 'read').length;
                                              });
                                            }
                                          },
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.open_in_new, size: 18, color: _navy),
                                        onPressed: () async {
                                          if (n['status'] != 'read') {
                                            await _db.child('notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}').remove();
                                          }
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => AlertDetailScreen(alertId: n['alertId']),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    if (n['status'] != 'read') {
                                      await _db.child('notifications/${FirebaseAuth.instance.currentUser!.uid}/${n['id']}').remove();
                                    }
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AlertDetailScreen(alertId: n['alertId']),
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
    return Container(
      color: _white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
              color: _navyLt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border)),
          child: const Center(child: Text('🏭', style: TextStyle(fontSize: 22))),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Production Manager',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                  color: _navy, letterSpacing: .2)),
          const Text('admin — Sagem',
              style: TextStyle(fontSize: 11, color: _muted)),
        ]),
        const Spacer(),
        Stack(children: [
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined,
                color: _muted, size: 24),
            onPressed: _showNotifications,
          ),
          if (_notificationCount > 0)
            Positioned(top: 6, right: 6,
              child: Container(
                width: 16, height: 16,
                decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
                child: Center(child: Text('$_notificationCount',
                    style: const TextStyle(color: _white, fontSize: 9,
                        fontWeight: FontWeight.w700))),
              )),
        ]),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout_outlined, size: 15, color: _red),
          label: const Text('Sign Out',
              style: TextStyle(color: _red, fontSize: 13,
                  fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _red),
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
      {'icon': Icons.bar_chart_outlined,      'label': 'Overview'},
      {'icon': Icons.people_alt_outlined,     'label': 'Supervisors'},
      {'icon': Icons.notifications_outlined,  'label': 'Alerts'},
    ];
    return Container(
      color: _white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: List.generate(tabs.length, (i) {
          final sel  = tab == i;
          final item = tabs[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _navy : _white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? _navy : _border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(item['icon'] as IconData,
                      size: 15,
                      color: sel ? _white : _muted),
                  const SizedBox(width: 6),
                  Text(item['label'] as String,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? _white : _muted)),
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
// OVERVIEW TAB (full implementation – already correct, keep as is)
// ═══════════════════════════════════════════════════════════════════════════
class _OverviewTab extends StatefulWidget {
  final int total, solved, inProgress, pending;
  final List<AlertModel> alerts;
  final List<AlertModel> allAlerts;
  final String timeRange, timeRangeLabel, timeRangeSubtitle;
  final String selectedUsine, filterConvoyeur, filterPoste, filterType, filterStatus;
  final void Function(String) onTimeRangeChange;
  final void Function(String) onUsineChange;
  final void Function(String) onConvoyeurChange;
  final void Function(String) onPosteChange;
  final void Function(String) onTypeChange;
  final void Function(String) onStatusChange;
  final VoidCallback onReset;
  final VoidCallback onExportCsv;
  final VoidCallback onExportExcel;

  const _OverviewTab({
    required this.onExportCsv,
    required this.onExportExcel,
    required this.total, required this.solved,
    required this.inProgress, required this.pending,
    required this.alerts, required this.allAlerts,
    required this.timeRange, required this.timeRangeLabel,
    required this.timeRangeSubtitle,
    required this.selectedUsine, required this.filterConvoyeur,
    required this.filterPoste, required this.filterType,
    required this.filterStatus,
    required this.onTimeRangeChange, required this.onUsineChange,
    required this.onConvoyeurChange, required this.onPosteChange,
    required this.onTypeChange, required this.onStatusChange,
    required this.onReset,
  });

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  String? _historyFilter;

  List<AlertModel> get _criticalUnclaimedAlerts {
    return widget.allAlerts.where((a) => a.isCritical && a.status == 'disponible').toList();
  }
  int get _criticalUnclaimedCount => _criticalUnclaimedAlerts.length;

  List<AlertModel> get _displayedAlerts {
    if (_historyFilter == null) return widget.alerts;
    switch (_historyFilter) {
      case 'total': return widget.alerts;
      case 'validated': return widget.alerts.where((a) => a.status == 'validee').toList();
      case 'pending': return widget.alerts.where((a) => a.status != 'validee').toList();
      case 'qualite': return widget.alerts.where((a) => a.type == 'qualite').toList();
      case 'maintenance': return widget.alerts.where((a) => a.type == 'maintenance').toList();
      case 'defaut_produit': return widget.alerts.where((a) => a.type == 'defaut_produit').toList();
      case 'manque_ressource': return widget.alerts.where((a) => a.type == 'manque_ressource').toList();
      default: return widget.alerts;
    }
  }

  void _setHistoryFilter(String? filter) {
    setState(() {
      if (_historyFilter == filter) {
        _historyFilter = null;
      } else {
        _historyFilter = filter;
      }
    });
  }

  Map<String, Map<String, int>> _typeStats() {
    final keys = ['qualite', 'maintenance', 'defaut_produit', 'manque_ressource'];
    return { for (var k in keys) k: {
      'total': widget.alerts.where((a) => a.type == k).length,
      'solved': widget.alerts.where((a) => a.type == k && a.status == 'validee').length,
      'pending': widget.alerts.where((a) => a.type == k && a.status != 'validee').length,
    }};
  }

  List<String> _usines() => ['all', ...widget.allAlerts.map((a) => a.usine).toSet().toList()..sort()];
  List<String> _convoyeurs() => ['all', ...widget.allAlerts.map((a) => a.convoyeur.toString()).toSet().toList()..sort()];
  List<String> _postes() => ['all', ...widget.allAlerts.map((a) => a.poste.toString()).toSet().toList()..sort()];

  String _getAlertDisplayDescription(AlertModel alert) {
    if (alert.description.trim().isNotEmpty) return alert.description;
    switch (alert.type) {
      case 'qualite': return 'Quality issue detected on production line';
      case 'maintenance': return 'Maintenance required on equipment';
      case 'defaut_produit': return 'Damaged product detected';
      case 'manque_ressource': return 'Resource shortage - missing raw materials';
      default: return 'Alert detected';
    }
  }

  void _exportFilteredAlerts(List<AlertModel> alertsToExport) async {
    if (alertsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No alerts to export'), backgroundColor: Colors.orange),
      );
      return;
    }
    List<List<dynamic>> csvData = [
      ['ID', 'Type', 'Usine', 'Convoyeur', 'Poste', 'Adresse', 'Timestamp', 'Description', 'Status', 'Superviseur', 'Assistant', 'Resolution Reason', 'Elapsed Time (min)', 'Critical']
    ];
    for (var alert in alertsToExport) {
      csvData.add([
        alert.id,
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
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'alerts_export_${DateTime.now().millisecondsSinceEpoch}.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/alerts_export_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Alert export');
    }
  }

  void _exportFilteredAlertsExcel(List<AlertModel> alertsToExport) async {
    if (alertsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No alerts to export'), backgroundColor: Colors.orange),
      );
      return;
    }
    var excelFile = excel.Excel.createExcel();
    var sheet = excelFile['Alerts'];
    sheet.appendRow([
      excel.TextCellValue('ID'), excel.TextCellValue('Type'), excel.TextCellValue('Usine'),
      excel.TextCellValue('Convoyeur'), excel.TextCellValue('Poste'), excel.TextCellValue('Adresse'),
      excel.TextCellValue('Timestamp'), excel.TextCellValue('Description'), excel.TextCellValue('Status'),
      excel.TextCellValue('Superviseur'), excel.TextCellValue('Assistant'), excel.TextCellValue('Resolution Reason'),
      excel.TextCellValue('Elapsed Time (min)'), excel.TextCellValue('Critical'),
    ]);
    for (var alert in alertsToExport) {
      sheet.appendRow([
        excel.TextCellValue(alert.id),
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
      final blob = html.Blob([fileBytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'alerts_export_${DateTime.now().millisecondsSinceEpoch}.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/alerts_export_${DateTime.now().millisecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Alert export');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = _typeStats();
    print('Critical unclaimed alerts count: $_criticalUnclaimedCount');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
              Text('Alert Dashboard VV2',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                      color: _text)),
              SizedBox(height: 2),
              Text('Overview and detailed analysis of alerts',
                  style: TextStyle(fontSize: 13, color: _muted)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: _white, border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.filter_alt_outlined, size: 13, color: _navy),
                const SizedBox(width: 4),
                Text(widget.timeRangeLabel,
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w600, color: _navy)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: const Color(0xFFBFDBFE)),
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.filter_alt_outlined, size: 15, color: _blue),
              const SizedBox(width: 6),
              const Text('Active filter:  ',
                  style: TextStyle(fontSize: 12, color: _muted)),
              _FilterChip(label: widget.timeRangeLabel, onRemove: null),
              const SizedBox(width: 6),
              _FilterChip(
                  label: widget.selectedUsine == 'all' ? 'Default' : widget.selectedUsine,
                  onRemove: widget.selectedUsine == 'all' ? null : () => widget.onUsineChange('all')),
              const Spacer(),
              Text(widget.timeRangeSubtitle,
                  style: const TextStyle(fontSize: 11, color: _muted)),
            ]),
          ),
          const SizedBox(height: 20),

          Row(children: [
            Expanded(child: _ClickableStatCard(
                label: 'Total Alerts',
                value: widget.total,
                color: _blue,
                icon: Icons.notifications_outlined,
                iconBg: const Color(0xFFEFF6FF),
                isActive: _historyFilter == 'total',
                onTap: () => _setHistoryFilter('total'),
                showHistoryHint: true,
            )),
            const SizedBox(width: 12),
            Expanded(child: _ClickableStatCard(
                label: 'Validated Alerts',
                value: widget.solved,
                color: _green,
                icon: Icons.check_circle_outline,
                iconBg: _greenLt,
                isActive: _historyFilter == 'validated',
                onTap: () => _setHistoryFilter('validated'),
                showHistoryHint: true,
            )),
            const SizedBox(width: 12),
            Expanded(child: _ClickableStatCard(
                label: 'Pending',
                value: widget.pending,
                color: _orange,
                icon: Icons.pending_outlined,
                iconBg: _orangeLt,
                isActive: _historyFilter == 'pending',
                onTap: () => _setHistoryFilter('pending'),
                showHistoryHint: true,
            )),
          ]),
          const SizedBox(height: 16),

          if (_criticalUnclaimedCount > 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '⚠️ Critical Unclaimed Alerts ($_criticalUnclaimedCount)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'These alerts have been waiting for more than 10 minutes',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._criticalUnclaimedAlerts.map((alert) {
                    final elapsedMinutes = DateTime.now().difference(alert.timestamp).inMinutes;
                    final elapsedText = elapsedMinutes < 60
                        ? '$elapsedMinutes min'
                        : '${elapsedMinutes ~/ 60}h ${elapsedMinutes % 60}m';
                    final displayDescription = _getAlertDisplayDescription(alert);
                    return GestureDetector(
                      onTap: () => _setHistoryFilter(alert.type),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _typeColor(alert.type),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_typeLabel(alert.type)} — $displayDescription',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _text,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${alert.usine} - Line ${alert.convoyeur} - WS ${alert.poste}',
                                    style: const TextStyle(fontSize: 11, color: _muted),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                elapsedText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right, color: _muted, size: 18),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          Row(children: [
            Expanded(child: _ClickableTypeCard(
                type: 'qualite',
                total: ts['qualite']!['total']!,
                solved: ts['qualite']!['solved']!,
                pending: ts['qualite']!['pending']!,
                isActive: _historyFilter == 'qualite',
                onTap: () => _setHistoryFilter('qualite'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _ClickableTypeCard(
                type: 'maintenance',
                total: ts['maintenance']!['total']!,
                solved: ts['maintenance']!['solved']!,
                pending: ts['maintenance']!['pending']!,
                isActive: _historyFilter == 'maintenance',
                onTap: () => _setHistoryFilter('maintenance'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _ClickableTypeCard(
                type: 'defaut_produit',
                total: ts['defaut_produit']!['total']!,
                solved: ts['defaut_produit']!['solved']!,
                pending: ts['defaut_produit']!['pending']!,
                isActive: _historyFilter == 'defaut_produit',
                onTap: () => _setHistoryFilter('defaut_produit'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _ClickableTypeCard(
                type: 'manque_ressource',
                total: ts['manque_ressource']!['total']!,
                solved: ts['manque_ressource']!['solved']!,
                pending: ts['manque_ressource']!['pending']!,
                isActive: _historyFilter == 'manque_ressource',
                onTap: () => _setHistoryFilter('manque_ressource'),
            )),
          ]),
          const SizedBox(height: 24),

          Row(children: [
            Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 16, color: _navy),
              const SizedBox(width: 8),
              Text('Alert History (${_displayedAlerts.length})',
                  style: const TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w700, color: _text)),
            ]),
            const Spacer(),
            _ExportBtn(label: '📄 Export CSV', onTap: () {
              _exportFilteredAlerts(_displayedAlerts);
            }),
            const SizedBox(width: 8),
            _ExportBtn(label: '📊 Export Excel', onTap: () {
              _exportFilteredAlertsExcel(_displayedAlerts);
            }),
          ]),
          const SizedBox(height: 4),
          const Text('Full alert list with filters',
              style: TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _white, border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.filter_list_outlined, size: 16, color: _navy),
                SizedBox(width: 6),
                Text('Filter History',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: _text)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _FilterDropdown(
                    label: 'Plant',
                    value: widget.selectedUsine,
                    items: _usines().map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(v == 'all' ? 'All Plants' : v,
                            style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: widget.onUsineChange)),
                const SizedBox(width: 10),
                Expanded(child: _FilterDropdown(
                    label: 'Conveyor',
                    value: widget.filterConvoyeur,
                    items: _convoyeurs().map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(v == 'all' ? 'All Conveyors' : 'Conv. $v',
                            style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: widget.onConvoyeurChange)),
                const SizedBox(width: 10),
                Expanded(child: _FilterDropdown(
                    label: 'Post',
                    value: widget.filterPoste,
                    items: _postes().map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(v == 'all' ? 'All Posts' : 'Post $v',
                            style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: widget.onPosteChange)),
                const SizedBox(width: 10),
                Expanded(child: _FilterDropdown(
                    label: 'Alert Type',
                    value: widget.filterType,
                    items: [
                      const DropdownMenuItem(value: 'all',
                          child: Text('All Types', style: TextStyle(fontSize: 13))),
                      ...['qualite','maintenance','defaut_produit','manque_ressource']
                          .map((t) => DropdownMenuItem(value: t,
                              child: Text(_typeLabel(t),
                                  style: const TextStyle(fontSize: 13))))
                    ],
                    onChanged: widget.onTypeChange)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _FilterDropdown(
                    label: 'Status',
                    value: widget.filterStatus,
                    items: [
                      const DropdownMenuItem(value: 'all',
                          child: Text('All Statuses', style: TextStyle(fontSize: 13))),
                      const DropdownMenuItem(value: 'disponible',
                          child: Text('Available', style: TextStyle(fontSize: 13))),
                      const DropdownMenuItem(value: 'en_cours',
                          child: Text('In Progress', style: TextStyle(fontSize: 13))),
                      const DropdownMenuItem(value: 'validee',
                          child: Text('Validated', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: widget.onStatusChange)),
                const SizedBox(width: 10),
                Expanded(child: _FilterDropdown(
                    label: 'Time Range',
                    value: widget.timeRange,
                    items: const [
                      DropdownMenuItem(value: 'today',  child: Text('Today',      style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'week',   child: Text('Last Week',  style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'month',  child: Text('This Month', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'year',   child: Text('This Year',  style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'custom', child: Text('Custom',     style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: widget.onTimeRangeChange)),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    widget.onReset();
                    setState(() => _historyFilter = null);
                  },
                  icon: const Icon(Icons.refresh_outlined, size: 15),
                  label: const Text('Reset',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _navy,
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 14),

          if (_displayedAlerts.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(children: const [
                Icon(Icons.check_circle_outline, size: 48, color: _green),
                SizedBox(height: 12),
                Text('No alerts match your filters',
                    style: TextStyle(fontSize: 15, color: _muted)),
              ]),
            )
          else
            ..._displayedAlerts.map((a) => _AlertHistoryRow(alert: a)),
        ],
      ),
    );
  }
}

// ── Helper widgets (same as original) ─────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  const _FilterChip({required this.label, this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
        color: _navy, borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(fontSize: 11, color: _white,
              fontWeight: FontWeight.w600)),
      if (onRemove != null) ...[
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: const Icon(Icons.close, size: 12, color: _white),
        ),
      ],
    ]),
  );
}

class _ExportBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ExportBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
        foregroundColor: _text,
        side: const BorderSide(color: _border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    child: Text(label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

class _FilterDropdown extends StatelessWidget {
  final String label, value;
  final List<DropdownMenuItem<String>> items;
  final void Function(String) onChanged;
  const _FilterDropdown({required this.label, required this.value,
      required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: _muted, letterSpacing: 1)),
      const SizedBox(height: 5),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: _bg,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(8)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value, isExpanded: true,
            style: const TextStyle(fontSize: 13, color: _text),
            dropdownColor: _white,
            items: items,
            onChanged: (v) => onChanged(v!),
          ),
        ),
      ),
    ],
  );
}

class _AlertHistoryRow extends StatelessWidget {
  final AlertModel alert;
  const _AlertHistoryRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final sc = switch (alert.status) {
      'validee'  => _green,
      'en_cours' => _blue,
      _          => _orange,
    };
    final sl = switch (alert.status) {
      'validee'  => 'Validated',
      'en_cours' => 'In Progress',
      _          => 'Available',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _white, border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Color(0x05000000),
              blurRadius: 3, offset: Offset(0, 1))]),
      child: Row(children: [
        Container(width: 9, height: 9,
            decoration: BoxDecoration(color: _typeColor(alert.type),
                shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_typeLabel(alert.type)} — ${alert.description}',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w600, color: _text),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${alert.usine}  ·  Line ${alert.convoyeur}'
              '  ·  Post ${alert.poste}  ·  ${_fmtTs(alert.timestamp)}',
              style: const TextStyle(fontFamily: 'monospace',
                  fontSize: 10, color: _muted)),
          if (alert.superviseurName != null)
            Text('Assigned: ${alert.superviseurName}',
                style: const TextStyle(fontSize: 11, color: _blue)),
        ])),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: sc.withOpacity(.1),
              border: Border.all(color: sc),
              borderRadius: BorderRadius.circular(99)),
          child: Text(sl,
              style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w700, color: sc)),
        ),
      ]),
    );
  }
}

class _ClickableStatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color, iconBg;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final bool showHistoryHint;

  const _ClickableStatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.iconBg,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.showHistoryHint = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.1) : _white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? color : _border, width: isActive ? 2 : 1),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2))]),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: _muted,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text('$value',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800,
                    color: color, height: 1)),
            if (showHistoryHint)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  isActive ? 'Click to hide history' : 'Click to show history',
                  style: const TextStyle(fontSize: 9, color: _muted, fontStyle: FontStyle.italic),
                ),
              ),
          ])),
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
        ]),
      ),
    );
  }
}

class _ClickableTypeCard extends StatelessWidget {
  final String type;
  final int total, solved, pending;
  final bool isActive;
  final VoidCallback onTap;

  const _ClickableTypeCard({
    required this.type,
    required this.total,
    required this.solved,
    required this.pending,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(type);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.1) : _white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? color : _border, width: isActive ? 2 : 1),
            boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_typeLabel(type),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: isActive ? color : _text)),
            const Spacer(),
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                  color: color.withOpacity(.1), shape: BoxShape.circle),
              child: Icon(_typeIcon(type), color: color, size: 15),
            ),
          ]),
          const SizedBox(height: 8),
          Text('$total',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                  color: isActive ? color : _text, height: 1)),
          const SizedBox(height: 10),
          Row(children: [
            Row(children: [
              const Icon(Icons.check_circle_outline, size: 13, color: _green),
              const SizedBox(width: 3),
              Text('Validated', style: const TextStyle(fontSize: 10, color: _muted)),
            ]),
            const Spacer(),
            Text('$solved',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: _green)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Row(children: [
              const Icon(Icons.cancel_outlined, size: 13, color: _orange),
              const SizedBox(width: 3),
              Text('Pending', style: const TextStyle(fontSize: 10, color: _muted)),
            ]),
            const Spacer(),
            Text('$pending',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: _orange)),
          ]),
          const SizedBox(height: 6),
          Text(
            isActive ? 'Click to hide history' : 'Click to show history',
            style: const TextStyle(fontSize: 9, color: _muted, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUPERVISORS TAB (unchanged from original – keep as is)
// ═══════════════════════════════════════════════════════════════════════════
class _SupervisorsTab extends StatefulWidget {
  final List<UserModel> supervisors;
  final List<AlertModel> alerts;
  final VoidCallback onAdd;
  final void Function(UserModel) onDelete;
  const _SupervisorsTab({
    required this.supervisors,
    required this.alerts,
    required this.onAdd,
    required this.onDelete,
  });
  @override State<_SupervisorsTab> createState() => _SupervisorsTabState();
}

class _SupervisorsTabState extends State<_SupervisorsTab>
    with SingleTickerProviderStateMixin {
  late TabController _sub;

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _sub.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: _white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Container(
          decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              _SubPill(label: 'Management',  icon: Icons.people_alt_outlined,  index: 0, ctrl: _sub),
              _SubPill(label: 'Performance', icon: Icons.show_chart_outlined,  index: 1, ctrl: _sub),
              _SubPill(label: 'Assignments', icon: Icons.bar_chart_outlined,   index: 2, ctrl: _sub),
            ],
          ),
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _sub,
          children: [
            _ManagementSubTab(
              supervisors: widget.supervisors,
              alerts:      widget.alerts,
              onAdd:       widget.onAdd,
              onDelete:    widget.onDelete,
            ),
            _PerformanceSubTab(
              supervisors: widget.supervisors,
              alerts:      widget.alerts,
            ),
            _AssignmentsSubTab(
              supervisors: widget.supervisors,
            ),
          ],
        ),
      ),
    ]);
  }
}

class _SubPill extends StatefulWidget {
  final String       label;
  final IconData     icon;
  final int          index;
  final TabController ctrl;
  const _SubPill({required this.label, required this.icon,
      required this.index, required this.ctrl});
  @override State<_SubPill> createState() => _SubPillState();
}

class _SubPillState extends State<_SubPill> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.ctrl.index == widget.index;
    return Expanded(
      child: GestureDetector(
        onTap: () => widget.ctrl.animateTo(widget.index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              color: sel ? _white : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
              boxShadow: sel ? [const BoxShadow(color: Color(0x18000000),
                  blurRadius: 4, offset: Offset(0, 1))] : []),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.icon, size: 14,
                color: sel ? _navy : _muted),
            const SizedBox(width: 5),
            Text(widget.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: sel ? _navy : _muted)),
          ]),
        ),
      ),
    );
  }
}

class _ManagementSubTab extends StatelessWidget {
  final List<UserModel>  supervisors;
  final List<AlertModel> alerts;
  final VoidCallback     onAdd;
  final void Function(UserModel) onDelete;
  const _ManagementSubTab({required this.supervisors, required this.alerts,
      required this.onAdd, required this.onDelete});

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(children: [
        _Chip('${supervisors.where((s) => s.isActive).length} Active',  _green),
        const SizedBox(width: 8),
        _Chip('${supervisors.where((s) => !s.isActive).length} Absent', _red),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.person_add_outlined, size: 16),
          label: const Text('Add Supervisor',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _navy, foregroundColor: _white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9))),
        ),
      ]),
    ),
    Expanded(
      child: supervisors.isEmpty
          ? _emptySups()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: supervisors.length,
              itemBuilder: (_, i) => _SupervisorCard(
                  supervisor: supervisors[i],
                  alerts:     alerts,
                  onDelete:   () => onDelete(supervisors[i]))),
    ),
  ]);
}

class _PerformanceSubTab extends StatefulWidget {
  final List<UserModel>  supervisors;
  final List<AlertModel> alerts;
  const _PerformanceSubTab({required this.supervisors, required this.alerts});
  @override State<_PerformanceSubTab> createState() => _PerformanceSubTabState();
}

class _PerformanceSubTabState extends State<_PerformanceSubTab> {
  UserModel? _selected;
  String     _chartRange = '7days';

  List<AlertModel> get _supAlerts => _selected == null
      ? []
      : widget.alerts
          .where((a) => a.superviseurId == _selected!.id)
          .toList();

  List<AlertModel> get _solved =>
      _supAlerts.where((a) => a.status == 'validee').toList();

  int? get _avgMin {
    final w = _solved.where((a) => a.elapsedTime != null).toList();
    if (w.isEmpty) return null;
    return w.fold(0, (s, a) => s + (a.elapsedTime ?? 0)) ~/ w.length;
  }

  List<_ChartPoint> _buildChartPoints() {
    final days = _chartRange == '7days' ? 7 : 30;
    final now  = DateTime.now();
    return List.generate(days, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: days - 1 - i));
      final next = day.add(const Duration(days: 1));
      final count = _solved
          .where((a) => a.timestamp.isAfter(day) && a.timestamp.isBefore(next))
          .length;
      return _ChartPoint(day: day, value: count.toDouble());
    });
  }

  Map<String, int> _factoryDist() {
    final m = <String, int>{};
    for (var a in _solved) {
      m[a.usine] = (m[a.usine] ?? 0) + 1;
    }
    return m;
  }

  Map<String, _TypeStats> _typeStats() {
    final types = ['qualite','maintenance','defaut_produit','manque_ressource'];
    return { for (var t in types) t: _TypeStats(
      validated:    _supAlerts.where((a) => a.type == t && a.status == 'validee').length,
      notValidated: _supAlerts.where((a) => a.type == t && a.status != 'validee').length,
    )};
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Supervisor Performance',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
                color: _text)),
        const SizedBox(height: 2),
        const Text('Analyse alert validations per supervisor',
            style: TextStyle(fontSize: 13, color: _muted)),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _white,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Select a supervisor',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: _text)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: _bg,
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(9)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<UserModel>(
                  isExpanded: true,
                  value: _selected,
                  hint: const Text('Choose a supervisor…',
                      style: TextStyle(color: _muted, fontSize: 14)),
                  dropdownColor: _white,
                  items: widget.supervisors.map((s) => DropdownMenuItem(
                    value: s,
                    child: Row(children: [
                      const Icon(Icons.person_outlined,
                          size: 16, color: _navy),
                      const SizedBox(width: 8),
                      Text(s.fullName,
                          style: const TextStyle(fontSize: 14, color: _text)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: _navyLt,
                            borderRadius: BorderRadius.circular(99)),
                        child: Text(s.usine,
                            style: const TextStyle(fontSize: 11,
                                color: _navy, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  )).toList(),
                  onChanged: (v) => setState(() => _selected = v),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        if (_selected == null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60),
            alignment: Alignment.center,
            child: Column(children: [
              Container(
                width: 64, height: 64,
                decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                child: const Icon(Icons.person_search_outlined,
                    size: 32, color: _muted),
              ),
              const SizedBox(height: 14),
              const Text('Choose a supervisor',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w600, color: _muted)),
              const SizedBox(height: 4),
              const Text('Select a supervisor above to see their statistics',
                  style: TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),

        if (_selected != null) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: _white,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x06000000),
                        blurRadius: 4, offset: Offset(0, 2))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fixed Alerts',
                          style: TextStyle(fontSize: 12, color: _muted)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text('${_solved.length}',
                            style: const TextStyle(fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: _navy, height: 1)),
                        const Spacer(),
                        Container(
                          width: 48, height: 48,
                          decoration: const BoxDecoration(
                              color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                          child: const Icon(Icons.check_circle_outline,
                              color: _blue, size: 24),
                        ),
                      ]),
                      const Divider(height: 20, color: _border),
                      const Text('Distribution by Factory:',
                          style: TextStyle(fontSize: 11, color: _muted)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8,
                          children: _factoryDist().entries.map((e) =>
                            Container(
                              padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
                              decoration: BoxDecoration(
                                  color: _navyLt,
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.bar_chart_outlined,
                                    size: 14, color: _navy),
                                const SizedBox(width: 6),
                                Column(crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(e.key,
                                          style: const TextStyle(fontSize: 11,
                                              color: _navy, fontWeight: FontWeight.w600)),
                                      Text('${e.value}',
                                          style: const TextStyle(fontSize: 16,
                                              fontWeight: FontWeight.w800, color: _navy)),
                                    ]),
                              ]),
                            )
                          ).toList()),
                    ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: _white,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x06000000),
                        blurRadius: 4, offset: Offset(0, 2))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Average Time',
                          style: TextStyle(fontSize: 12, color: _muted)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: Text(
                              _avgMin == null ? '—' : _fmtMin(_avgMin!),
                              style: const TextStyle(fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: _green, height: 1)),
                        ),
                        Container(
                          width: 48, height: 48,
                          decoration: const BoxDecoration(
                              color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                          child: const Icon(Icons.timer_outlined,
                              color: _green, size: 24),
                        ),
                      ]),
                    ]),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          Row(children: ['qualite','maintenance','defaut_produit','manque_ressource']
              .map((t) {
            final ts   = _typeStats()[t]!;
            final clr  = _typeColor(t);
            final tot  = ts.validated + ts.notValidated;
            final pct  = tot == 0 ? 0 : (ts.validated / tot * 100).round();
            return Expanded(child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: _white,
                    border: Border.all(color: clr.withOpacity(.25)),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color(0x06000000),
                        blurRadius: 3, offset: Offset(0, 2))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(_typeLabel(t),
                            style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600, color: clr))),
                        Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                              color: clr.withOpacity(.1), shape: BoxShape.circle),
                          child: Icon(Icons.check_circle_outline,
                              color: clr, size: 16),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text('$tot',
                          style: TextStyle(fontSize: 26,
                              fontWeight: FontWeight.w800, color: clr, height: 1)),
                      const SizedBox(height: 10),
                      _PerfStatRow(label: 'Validated',     value: ts.validated,    color: _green),
                      const SizedBox(height: 3),
                      _PerfStatRow(label: 'Not validated', value: ts.notValidated, color: _orange),
                      const SizedBox(height: 6),
                      Text('$pct% validated',
                          style: const TextStyle(fontSize: 10, color: _muted)),
                    ]),
              ),
            ));
          }).toList()),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _white,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x06000000),
                    blurRadius: 4, offset: Offset(0, 2))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 15, color: _navy),
                const SizedBox(width: 8),
                const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Evolution of Validations',
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w700, color: _text)),
                  Text('Number of alerts validated per day',
                      style: TextStyle(fontSize: 11, color: _muted)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: _bg,
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(8)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _chartRange,
                      style: const TextStyle(fontSize: 12, color: _text),
                      dropdownColor: _white,
                      items: const [
                        DropdownMenuItem(value: '7days',
                            child: Text('Last 7 days')),
                        DropdownMenuItem(value: '30days',
                            child: Text('Last 30 days')),
                      ],
                      onChanged: (v) => setState(() => _chartRange = v!),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: _LineChart(points: _buildChartPoints()),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 28, height: 2, color: _navy),
                const SizedBox(width: 6),
                const Icon(Icons.circle, size: 7, color: _navy),
                const SizedBox(width: 6),
                const Text('Validations',
                    style: TextStyle(fontSize: 11, color: _muted)),
              ]),
            ]),
          ),
          const SizedBox(height: 20),

          Row(children: [
            const Icon(Icons.check_circle_outline, size: 16, color: _green),
            const SizedBox(width: 6),
            Text('Validated Alerts (${_solved.length})',
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w700, color: _text)),
          ]),
          const SizedBox(height: 2),
          Text('Detailed list of alerts validated by ${_selected!.fullName}',
              style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 12),
          if (_solved.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              alignment: Alignment.center,
              child: const Text('No validated alerts yet',
                  style: TextStyle(fontSize: 14, color: _muted)),
            )
          else
            ..._solved.map((a) => _ValidatedAlertRow(alert: a)),
        ],
      ]),
    );
  }
}

class _PerfStatRow extends StatelessWidget {
  final String label; final int value; final Color color;
  const _PerfStatRow({required this.label, required this.value,
      required this.color});
  @override Widget build(BuildContext context) =>
      Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(fontSize: 10, color: _muted))),
        Text('$value',
            style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: color)),
      ]);
}

class _TypeStats {
  final int validated, notValidated;
  const _TypeStats({required this.validated, required this.notValidated});
}

class _ValidatedAlertRow extends StatelessWidget {
  final AlertModel alert;
  const _ValidatedAlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final clr = _typeColor(alert.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _white,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: clr.withOpacity(.1),
              borderRadius: BorderRadius.circular(6)),
          child: Text(_typeLabel(alert.type),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: clr)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(
            '${alert.usine} — C${alert.convoyeur} — P${alert.poste}',
            style: const TextStyle(fontSize: 12, color: _text))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              color: _greenLt, borderRadius: BorderRadius.circular(99)),
          child: Text('Validated',
              style: const TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w700, color: _green)),
        ),
      ]),
    );
  }
}

class _ChartPoint {
  final DateTime day;
  final double   value;
  const _ChartPoint({required this.day, required this.value});
}

class _LineChart extends StatelessWidget {
  final List<_ChartPoint> points;
  const _LineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(points: points),
      size: const Size(double.infinity, 200),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_ChartPoint> points;
  _LineChartPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad   = 36.0;
    const rightPad  = 16.0;
    const topPad    = 10.0;
    const bottomPad = 28.0;

    final chartW = size.width  - leftPad  - rightPad;
    final chartH = size.height - topPad   - bottomPad;

    final maxVal = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final yMax   = maxVal < 1 ? 1.0 : maxVal;
    final n      = points.length;

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = topPad + chartH * (1 - i / 4);
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + chartW, y), gridPaint);
      final textPainter = TextPainter(
        text: TextSpan(
            text: (yMax * i / 4).toStringAsFixed(0),
            style: const TextStyle(fontSize: 9,
                color: Color(0xFF94A3B8))),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas,
          Offset(0, y - textPainter.height / 2));
    }

    Offset pos(int i) {
      final x = leftPad + (n == 1 ? chartW / 2 : i / (n - 1) * chartW);
      final y = topPad + chartH * (1 - (points[i].value / yMax));
      return Offset(x, y);
    }

    final fillPath = Path();
    fillPath.moveTo(leftPad, topPad + chartH);
    for (int i = 0; i < n; i++) {
      fillPath.lineTo(pos(i).dx, pos(i).dy);
    }
    fillPath.lineTo(pos(n - 1).dx, topPad + chartH);
    fillPath.close();

    canvas.drawPath(fillPath,
        Paint()..shader = LinearGradient(
          colors: [_navy.withOpacity(.15), _navy.withOpacity(.01)],
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH)));

    final linePaint = Paint()
      ..color = _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final linePath = Path()..moveTo(pos(0).dx, pos(0).dy);
    for (int i = 1; i < n; i++) {
      final p0 = pos(i - 1);
      final p1 = pos(i);
      final cx = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(linePath, linePaint);

    final dotPaint  = Paint()..color = _navy;
    final dotBorder = Paint()
      ..color = _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final dateSteps = n <= 10 ? 1 : (n / 7).ceil();

    for (int i = 0; i < n; i++) {
      final p = pos(i);
      canvas.drawCircle(p, 4, dotPaint);
      canvas.drawCircle(p, 4, dotBorder);

      if (i % dateSteps == 0 || i == n - 1) {
        final d = points[i].day;
        final label = '${d.day} ${_monthAbbr(d.month)}';
        final tp = TextPainter(
          text: TextSpan(text: label,
              style: const TextStyle(fontSize: 9,
                  color: Color(0xFF94A3B8))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(p.dx - tp.width / 2,
                topPad + chartH + 6));
      }
    }
  }

  String _monthAbbr(int m) {
    const abbr = ['', 'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    return abbr[m];
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.points != points;
}

class _AssignmentsSubTab extends StatelessWidget {
  final List<UserModel> supervisors;
  const _AssignmentsSubTab({required this.supervisors});

  Map<String, List<UserModel>> _byUsine() {
    final usines = ['Usine A', 'Usine B', 'Usine C', 'Usine D'];
    final m = { for (var u in usines) u : <UserModel>[] };
    for (var s in supervisors) {
      m.putIfAbsent(s.usine, () => []).add(s);
    }
    return m;
  }

  static const _cities = {
    'Usine A': 'Plant A',
    'Usine B': 'Plant B',
    'Usine C': 'Plant C',
    'Usine D': 'Plant D',
  };

  @override
  Widget build(BuildContext context) {
    final grouped = _byUsine();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Supervisor Assignments',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
                color: _text)),
        const SizedBox(height: 2),
        const Text('Assign supervisors to plants for alert monitoring',
            style: TextStyle(fontSize: 13, color: _muted)),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: _white,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x06000000),
                  blurRadius: 4, offset: Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.bar_chart_outlined, size: 16, color: _navy),
              const SizedBox(width: 8),
              const Text('Assignments by Plant',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: _text)),
            ]),
            const SizedBox(height: 4),
            const Text('See supervisors assigned to each plant',
                style: TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 16),

            ...grouped.entries.map((e) {
              final usine = e.key;
              final sups  = e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _bg,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(usine,
                          style: const TextStyle(fontSize: 15,
                              fontWeight: FontWeight.w700, color: _text)),
                      const SizedBox(height: 2),
                      Text(_cities[usine] ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: _muted)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                          color: sups.isEmpty
                              ? const Color(0xFFF1F5F9)
                              : _navyLt,
                          borderRadius: BorderRadius.circular(99)),
                      child: Text(
                          sups.isEmpty
                              ? '0 supervisors'
                              : '${sups.length} supervisor${sups.length > 1 ? 's' : ''}',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: sups.isEmpty ? _muted : _navy)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  if (sups.isEmpty)
                    const Text('No supervisor assigned',
                        style: TextStyle(
                            fontSize: 12, color: _muted,
                            fontStyle: FontStyle.italic))
                  else
                    Wrap(spacing: 8, runSpacing: 8,
                        children: sups.map((s) => _SupChip(sup: s)).toList()),
                ]),
              );
            }),
          ]),
        ),
      ]),
    );
  }
}

class _SupChip extends StatelessWidget {
  final UserModel sup;
  const _SupChip({required this.sup});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
        color: _navy, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.person_outline, size: 13, color: _white),
      const SizedBox(width: 6),
      Text(sup.fullName,
          style: const TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600, color: _white)),
    ]),
  );
}

Widget _emptySups() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: const [
      Icon(Icons.people_outline, size: 52, color: _muted),
      SizedBox(height: 12),
      Text('No supervisors yet',
          style: TextStyle(fontSize: 16,
              fontWeight: FontWeight.w600, color: _muted)),
      SizedBox(height: 6),
      Text('Tap "Add Supervisor" to create an account',
          style: TextStyle(fontSize: 12, color: _muted)),
    ]));

class _SupervisorCard extends StatefulWidget {
  final UserModel supervisor;
  final List<AlertModel> alerts;
  final VoidCallback onDelete;
  const _SupervisorCard({required this.supervisor, required this.alerts,
      required this.onDelete});
  @override State<_SupervisorCard> createState() => _SupervisorCardState();
}

class _SupervisorCardState extends State<_SupervisorCard> {
  bool _expanded = false;
  Future<void> _showModifyDialog(BuildContext context) async {
    // (original modify dialog logic)
  }

  @override
  Widget build(BuildContext context) {
    final sup     = widget.supervisor;
    final solved  = widget.alerts
        .where((a) => a.status == 'validee' && a.superviseurId == sup.id)
        .toList();
    final inProg  = widget.alerts
        .where((a) => a.status == 'en_cours' && a.superviseurId == sup.id)
        .length;
    final withTime= solved.where((a) => a.elapsedTime != null).toList();
    final avgMin  = withTime.isEmpty ? null
        : withTime.fold(0, (s, a) => s + (a.elapsedTime ?? 0)) ~/ withTime.length;
    final sc = sup.isActive ? _green : _red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: _white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
          boxShadow: const [BoxShadow(color: Color(0x0A000000),
              blurRadius: 4, offset: Offset(0, 1))]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Container(width: 48, height: 48,
                  decoration: BoxDecoration(color: _navyLt,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Center(
                      child: Text('👷', style: TextStyle(fontSize: 24)))),
              Positioned(bottom: 0, right: 0,
                  child: Container(width: 12, height: 12,
                      decoration: BoxDecoration(color: sc,
                          shape: BoxShape.circle,
                          border: Border.all(color: _white, width: 2)))),
            ]),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(sup.fullName,
                    style: const TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700, color: _navy))),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: sc.withOpacity(.1),
                      border: Border.all(color: sc),
                      borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 5, height: 5,
                        decoration: BoxDecoration(
                            color: sc, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(sup.isActive ? 'Active' : 'Absent',
                        style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w700, color: sc)),
                  ]),
                ),
              ]),
              const SizedBox(height: 2),
              Text(sup.email,
                  style: const TextStyle(fontSize: 11, color: _muted)),
              Row(children: [
                const Icon(Icons.phone_outlined, size: 12, color: _muted),
                const SizedBox(width: 3),
                Text(sup.phone.isEmpty ? 'No phone' : sup.phone,
                    style: const TextStyle(fontSize: 11, color: _muted)),
                const SizedBox(width: 10),
                const Icon(Icons.factory_outlined, size: 12, color: _muted),
                const SizedBox(width: 3),
                Text(sup.usine,
                    style: const TextStyle(fontSize: 11, color: _muted)),
              ]),
              if (sup.hiredDate != null)
                Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 12, color: _muted),
                  const SizedBox(width: 3),
                  Text('Hired: ${_fmtDate(sup.hiredDate!)}',
                      style: const TextStyle(fontSize: 11, color: _muted)),
                ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _MiniChip(Icons.check_circle_outline,
                    '${solved.length} fixed', _green),
                _MiniChip(Icons.timer_outlined,
                    '$inProg in progress', _blue),
                if (avgMin != null)
                  _MiniChip(Icons.av_timer_outlined,
                      'Avg ${_fmtMin(avgMin)}', _orange),
              ]),
            ])),
            Column(children: [
              if (solved.isNotEmpty)
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: _navy),
                ),
              IconButton(
                onPressed: () => _showModifyDialog(context),
                icon: const Icon(Icons.edit_outlined, color: _navy, size: 20),
                tooltip: 'Modify Supervisor',
              ),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline, color: _red, size: 20),
              ),
            ]),
          ]),
        ),
        if (_expanded && solved.isNotEmpty) ...[
          Divider(height: 1, color: _border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FIXED CASES HISTORY',
                    style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _muted, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                ...solved.map((a) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Container(width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: _typeColor(a.type),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${_typeLabel(a.type)} — ${a.description}',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w600, color: _navy),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text('${a.usine} · Line ${a.convoyeur} · Post ${a.poste}',
                          style: const TextStyle(
                              fontSize: 10, color: _muted)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                          a.elapsedTime != null
                              ? _fmtMin(a.elapsedTime!)
                              : '-',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _green)),
                    ),
                  ]),
                )),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label; final Color color;
  const _Chip(this.label, this.color);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

class _MiniChip extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _MiniChip(this.icon, this.label, this.color);
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(.08),
        border: Border.all(color: color.withOpacity(.4)),
        borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

class _SheetField extends StatelessWidget {
  final String label, hint;
  final TextEditingController ctrl;
  final bool obscure;
  final TextInputType keyboard;
  const _SheetField(this.label, this.ctrl, this.hint,
      {this.obscure = false, this.keyboard = TextInputType.text});

  @override Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SheetLabel(label),
      TextField(
        controller: ctrl, obscureText: obscure, keyboardType: keyboard,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint, hintStyle: const TextStyle(color: _muted),
          filled: true, fillColor: _bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: _border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: _navy, width: 1.5)),
        ),
      ),
      const SizedBox(height: 14),
    ],
  );
}

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            color: _muted, letterSpacing: 1.3)),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// ALERTS TAB
// ═══════════════════════════════════════════════════════════════════════════
class _AlertsTab extends StatelessWidget {
  final List<AlertModel> alerts;
  final void Function(AlertModel) onAssign;
  final void Function(AlertModel) onAssignAssistant;
  const _AlertsTab({
    required this.alerts,
    required this.onAssign,
    required this.onAssignAssistant,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 52, color: _green),
            SizedBox(height: 12),
            Text('No alerts', style: TextStyle(fontSize: 16, color: _muted)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: alerts.length,
      itemBuilder: (_, i) => _AlertRow(
        alert: alerts[i],
        onAssign: alerts[i].status == 'disponible' ? () => onAssign(alerts[i]) : null,
        onAssignAssistant: alerts[i].status == 'en_cours' ? () => onAssignAssistant(alerts[i]) : null,
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final AlertModel alert;
  final VoidCallback? onAssign;
  final VoidCallback? onAssignAssistant;
  const _AlertRow({
    required this.alert,
    this.onAssign,
    this.onAssignAssistant,
  });

  @override
  Widget build(BuildContext context) {
    final sc = switch (alert.status) {
      'validee'  => _green,
      'en_cours' => _blue,
      _          => _orange,
    };
    final sl = switch (alert.status) {
      'validee'  => '✅ Fixed',
      'en_cours' => '⏳ In Progress',
      _          => '📋 Available',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Row(children: [
        Container(width: 10, height: 10,
            decoration: BoxDecoration(color: _typeColor(alert.type), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_typeLabel(alert.type)} — ${alert.description}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('📍 ${alert.usine}  ·  Line ${alert.convoyeur}  ·  Post ${alert.poste}  ·  ${_fmtTs(alert.timestamp)}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: _muted)),
            if (alert.superviseurName != null)
              Text('👤 Assigned: ${alert.superviseurName}', style: const TextStyle(fontSize: 11, color: _blue)),
          ]),
        ),
        const SizedBox(width: 8),
        if (onAssign != null)
          ElevatedButton.icon(
            onPressed: onAssign,
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text('Assign', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy, foregroundColor: _white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        if (onAssignAssistant != null)
          OutlinedButton.icon(
            onPressed: onAssignAssistant,
            icon: const Icon(Icons.group_add, size: 16),
            label: const Text('Assign Assistant', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _blue),
              foregroundColor: _blue,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        if (onAssign == null && onAssignAssistant == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: sc.withOpacity(.1),
              border: Border.all(color: sc),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(sl, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sc)),
          ),
      ]),
    );
  }
}