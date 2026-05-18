import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

import '../models/alert_model.dart';
import '../models/shift_model.dart';
import '../models/supervisor_presence.dart';
import 'pdf/pdf_common.dart';
import 'presence_service.dart';

/// Single timeline action that occurred during a shift window.
class ShiftAction {
  final DateTime at;
  final String
  kind; // created, claimed, resolved, ai_assigned, escalated, handover
  final String alertLabel;
  final String alertType;
  final String factory;
  final String detail;
  final String actor;
  final double? aiConfidence;

  const ShiftAction({
    required this.at,
    required this.kind,
    required this.alertLabel,
    required this.alertType,
    required this.factory,
    required this.detail,
    required this.actor,
    this.aiConfidence,
  });
}

class ShiftReportExportOptions {
  final String? reportName;
  final String factory;
  final Set<String> actionKinds;

  const ShiftReportExportOptions({
    this.reportName,
    this.factory = 'all',
    this.actionKinds = const <String>{},
  });

  bool includes(ShiftAction action) {
    if (factory != 'all' && action.factory != factory) return false;
    if (actionKinds.isNotEmpty && !actionKinds.contains(action.kind)) {
      return false;
    }
    return true;
  }
}

class ShiftPdfService {
  static String _safe(String v) => PdfTextSafe.normalize(v);

  /// Loads every action that happened during [shift] on [day], builds a
  /// shift report PDF, and either downloads it (web) or shares it.
  static Future<void> exportAndShare({
    required ShiftModel shift,
    required DateTime day,
    ShiftReportExportOptions options = const ShiftReportExportOptions(),
  }) async {
    final window = _windowFor(shift, day);
    final actions = (await _loadActions(
      shift,
      window,
    )).where(options.includes).toList();
    final presence = await _loadPresence(shift);
    final doc = await _buildDoc(
      shift: shift,
      window: window,
      actions: actions,
      presence: presence,
      reportName: options.reportName,
    );
    final bytes = await doc.save();
    final baseName = (options.reportName ?? '').trim().isEmpty
        ? shift.name
        : options.reportName!.trim();
    final slug = _slug(baseName);
    final filename =
        'SIA_shift_${slug.isEmpty ? "report" : slug}_${_fmtDateFile(day)}.pdf';
    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'SIA shift report - ${shift.name}');
  }

  @visibleForTesting
  static Future<pw.Document> buildDocumentForTesting({
    required ShiftModel shift,
    required DateTime day,
    required List<ShiftAction> actions,
    required List<SupervisorPresence> presence,
    String? reportName,
  }) {
    return _buildDoc(
      shift: shift,
      window: _windowFor(shift, day),
      actions: actions,
      presence: presence,
      reportName: reportName,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATA LOADING
  // ─────────────────────────────────────────────────────────────────────────

  static ({DateTime start, DateTime end}) _windowFor(
    ShiftModel shift,
    DateTime day,
  ) {
    final base = DateTime(day.year, day.month, day.day);
    final start = base.add(Duration(minutes: shift.startMinutes));
    DateTime end = base.add(Duration(minutes: shift.endMinutes));
    if (shift.endMinutes <= shift.startMinutes) {
      end = end.add(const Duration(days: 1));
    }
    return (start: start, end: end);
  }

  static Future<List<SupervisorPresence>> _loadPresence(
    ShiftModel shift,
  ) async {
    try {
      return await PresenceService().fetchPresenceOnce(shift.id);
    } catch (_) {
      return const <SupervisorPresence>[];
    }
  }

  static Future<List<ShiftAction>> _loadActions(
    ShiftModel shift,
    ({DateTime start, DateTime end}) window,
  ) async {
    final db = FirebaseDatabase.instance.ref('alerts');
    final snap = await db.get();
    final raw = snap.value;
    final actions = <ShiftAction>[];
    if (raw is! Map) return actions;

    bool inWindow(DateTime? t) =>
        t != null && !t.isBefore(window.start) && t.isBefore(window.end);

    for (final entry in raw.entries) {
      final v = entry.value;
      if (v is! Map) continue;
      final m = Map<String, dynamic>.from(v);
      AlertModel alert;
      try {
        alert = AlertModel.fromMap(entry.key.toString(), m);
      } catch (_) {
        continue;
      }

      if (inWindow(alert.timestamp)) {
        actions.add(
          ShiftAction(
            at: alert.timestamp,
            kind: 'created',
            alertLabel: alert.alertLabel,
            alertType: alert.type,
            factory: alert.usine,
            detail: alert.description.isEmpty
                ? 'Alert created at ${alert.usine}, conv ${alert.convoyeur}, line ${alert.poste}'
                : alert.description,
            actor: 'System',
          ),
        );
      }

      if (alert.aiAssigned &&
          alert.aiAssignedAt != null &&
          inWindow(alert.aiAssignedAt)) {
        actions.add(
          ShiftAction(
            at: alert.aiAssignedAt!,
            kind: 'ai_assigned',
            alertLabel: alert.alertLabel,
            alertType: alert.type,
            factory: alert.usine,
            detail: alert.aiAssignmentReason ?? 'AI commander assignment',
            actor: alert.superviseurName ?? 'AI',
            aiConfidence: alert.aiConfidence,
          ),
        );
      } else if (alert.takenAtTimestamp != null &&
          inWindow(alert.takenAtTimestamp)) {
        actions.add(
          ShiftAction(
            at: alert.takenAtTimestamp!,
            kind: 'claimed',
            alertLabel: alert.alertLabel,
            alertType: alert.type,
            factory: alert.usine,
            detail:
                'Claimed by ${alert.superviseurName ?? "supervisor"} at ${alert.usine}',
            actor: alert.superviseurName ?? '-',
          ),
        );
      }

      if (alert.resolvedAt != null && inWindow(alert.resolvedAt)) {
        actions.add(
          ShiftAction(
            at: alert.resolvedAt!,
            kind: 'resolved',
            alertLabel: alert.alertLabel,
            alertType: alert.type,
            factory: alert.usine,
            detail: alert.resolutionReason?.isNotEmpty == true
                ? alert.resolutionReason!
                : 'Resolved',
            actor: alert.superviseurName ?? '-',
          ),
        );
      }

      if (alert.isEscalated &&
          alert.escalatedAt != null &&
          inWindow(alert.escalatedAt)) {
        actions.add(
          ShiftAction(
            at: alert.escalatedAt!,
            kind: 'escalated',
            alertLabel: alert.alertLabel,
            alertType: alert.type,
            factory: alert.usine,
            detail: 'Escalated as critical',
            actor: 'System',
          ),
        );
      }
    }

    if (shift.lastHandoverAt != null &&
        !shift.lastHandoverAt!.isBefore(window.start) &&
        shift.lastHandoverAt!.isBefore(
          window.end.add(const Duration(minutes: 30)),
        )) {
      actions.add(
        ShiftAction(
          at: shift.lastHandoverAt!,
          kind: 'handover',
          alertLabel: '-',
          alertType: '-',
          factory: '-',
          detail: shift.lastHandoverSummary ?? 'AI handover generated',
          actor: 'AI Commander',
        ),
      );
    }

    actions.sort((a, b) => a.at.compareTo(b.at));
    return actions;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PDF BUILD
  // ─────────────────────────────────────────────────────────────────────────

  static Future<pw.Document> _buildDoc({
    required ShiftModel shift,
    required ({DateTime start, DateTime end}) window,
    required List<ShiftAction> actions,
    required List<SupervisorPresence> presence,
    String? reportName,
  }) async {
    final resolvedReportName = (reportName ?? '').trim().isEmpty
        ? 'Shift Report - ${shift.name}'
        : reportName!.trim();
    final pdfTheme = await PdfFontTheme.load();
    final doc = pw.Document(
      theme: pdfTheme,
      title: resolvedReportName,
      author: 'Smart Industrial Alert - SIA',
      creator: 'Smart Industrial Alert - SIA Shift Commander',
    );

    final created = actions.where((a) => a.kind == 'created').length;
    final claimed = actions.where((a) => a.kind == 'claimed').length;
    final resolved = actions.where((a) => a.kind == 'resolved').length;
    final aiAssigned = actions.where((a) => a.kind == 'ai_assigned').length;
    final escalated = actions.where((a) => a.kind == 'escalated').length;

    final byFactory = <String, int>{};
    for (final a in actions.where((x) => x.kind == 'created')) {
      byFactory[a.factory] = (byFactory[a.factory] ?? 0) + 1;
    }
    final bySupervisor = <String, int>{};
    for (final a in actions.where((x) => x.kind == 'resolved')) {
      bySupervisor[a.actor] = (bySupervisor[a.actor] ?? 0) + 1;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        theme: pdfTheme,
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox.shrink()
            : _runningHeader(shift, window),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          _hero(shift, window, actions.length),
          pw.SizedBox(height: 14),
          _kpiStrip(
            total: actions.length,
            created: created,
            claimed: claimed,
            resolved: resolved,
            aiAssigned: aiAssigned,
            escalated: escalated,
          ),
          pw.SizedBox(height: 14),
          _shiftMetaCard(shift, resolvedReportName),
          pw.SizedBox(height: 14),
          _sectionHeader('Supervisor presence', shift.supervisors.length),
          pw.SizedBox(height: 6),
          _presenceTable(shift, presence),
          pw.SizedBox(height: 14),
          if (byFactory.isNotEmpty) ...[
            _sectionHeader('Alerts by factory', byFactory.length),
            pw.SizedBox(height: 6),
            _barBreakdown(byFactory, PdfPalette.navy),
            pw.SizedBox(height: 14),
          ],
          if (bySupervisor.isNotEmpty) ...[
            _sectionHeader(
              'Top supervisors (resolutions)',
              bySupervisor.length,
            ),
            pw.SizedBox(height: 6),
            _barBreakdown(bySupervisor, PdfPalette.green),
            pw.SizedBox(height: 14),
          ],
          if (aiAssigned > 0) ...[
            _sectionHeader('AI Shift Commander actions', aiAssigned),
            pw.SizedBox(height: 6),
            ..._aiActionsList(
              actions.where((a) => a.kind == 'ai_assigned').toList(),
            ),
            pw.SizedBox(height: 14),
          ],
          _sectionHeader('Action timeline', actions.length),
          pw.SizedBox(height: 6),
          _timelineHeader(),
          ..._timeline(actions),
          if (shift.lastHandoverSummary != null) ...[
            pw.SizedBox(height: 14),
            _handoverCard(shift),
          ],
          pw.SizedBox(height: 12),
          _watermark(),
        ],
      ),
    );

    return doc;
  }

  // ── Hero ────────────────────────────────────────────────────────────────
  // Light theme: white card on a thin navy accent stripe. No giant purple
  // background — the previous design made the text unreadable.
  static pw.Widget _hero(
    ShiftModel shift,
    ({DateTime start, DateTime end}) window,
    int totalActions,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Thin navy accent rail.
          pw.Container(width: 6, height: 150, color: PdfPalette.navy),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Text(
                        'SIA - SHIFT REPORT',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfPalette.navy,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.4,
                        ),
                      ),
                      pw.Spacer(),
                      _heroChip(
                        _kindLabel(shift.kind),
                        color: _kindColorByKind(shift.kind),
                      ),
                      pw.SizedBox(width: 6),
                      if (shift.aiCommander)
                        _heroChip('AI Commander', color: PdfPalette.blue),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    _safe(shift.name),
                    style: pw.TextStyle(
                      fontSize: 22,
                      color: PdfPalette.text,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${_fmtDateTime(window.start)}  ->  ${_fmtDateTime(window.end)}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfPalette.muted,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'A complete record of every action that occurred during '
                    'this shift, including supervisor presence, AI Shift '
                    'Commander decisions and handover output.',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfPalette.muted,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    children: [
                      _kpi(
                        'Actions',
                        '$totalActions',
                        PdfPalette.navy,
                        compact: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _heroChip(String label, {PdfColor? color}) {
    final c = color ?? PdfPalette.navy;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: pw.BoxDecoration(
        color: _withAlpha(c, 0.12),
        border: pw.Border.all(color: c, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(
        _safe(label),
        style: pw.TextStyle(
          fontSize: 8,
          color: c,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // ── KPI strip ───────────────────────────────────────────────────────────
  static pw.Widget _kpiStrip({
    required int total,
    required int created,
    required int claimed,
    required int resolved,
    required int aiAssigned,
    required int escalated,
  }) {
    return pw.Row(
      children: [
        _kpi('Actions', '$total', PdfPalette.navy),
        _gap(),
        _kpi('Created', '$created', PdfPalette.orange),
        _gap(),
        _kpi('Claimed', '$claimed', PdfPalette.blue),
        _gap(),
        _kpi('Resolved', '$resolved', PdfPalette.green),
        _gap(),
        _kpi('AI calls', '$aiAssigned', PdfPalette.navy),
        _gap(),
        _kpi('Escalated', '$escalated', PdfPalette.red),
      ],
    );
  }

  static pw.Widget _gap() => pw.SizedBox(width: 8);

  static pw.Widget _kpi(
    String label,
    String value,
    PdfColor accent, {
    bool compact = false,
  }) {
    final body = pw.Container(
      padding: pw.EdgeInsets.fromLTRB(
        10,
        compact ? 6 : 9,
        10,
        compact ? 8 : 10,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _withAlpha(accent, 0.4)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7,
              color: accent,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: compact ? 18 : 22,
              color: PdfPalette.text,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    return compact ? body : pw.Expanded(child: body);
  }

  // ── Shift meta ──────────────────────────────────────────────────────────
  // AI model row removed — the PM doesn't need to know which Llama variant
  // backs the commander.
  static pw.Widget _shiftMetaCard(ShiftModel shift, String reportName) {
    final supervisors = shift.supervisors.map((s) => s.name).join(', ');
    final commanderTasks = shift.fullControl
        ? 'Full control'
        : [
            if (shift.handleAssignments) 'Assignments',
            if (shift.handleCollaborations) 'Collaborations',
            if (shift.handleCrossFactoryTransfer) 'Cross-factory transfer',
          ].join(', ');
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _safe(reportName),
            style: pw.TextStyle(
              fontSize: 12,
              color: PdfPalette.text,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _metaBox('Shift kind', _kindLabel(shift.kind)),
              pw.SizedBox(width: 8),
              _metaBox(
                'Capacity',
                '${shift.supervisors.length}/${shift.maxSupervisors}',
              ),
              pw.SizedBox(width: 8),
              _metaBox(
                'AI Commander',
                shift.aiCommander ? 'Enabled' : 'Disabled',
              ),
              pw.SizedBox(width: 8),
              _metaBox('Randomized', shift.randomize ? 'Yes' : 'No'),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _metaBox(
                'Tasks',
                commanderTasks.isEmpty ? 'None selected' : commanderTasks,
                flex: 2,
              ),
              pw.SizedBox(width: 8),
              _metaBox(
                'Supervisors',
                supervisors.isEmpty ? '-' : supervisors,
                flex: 3,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _metaBox(String label, String value, {int flex = 1}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: pw.BoxDecoration(
          color: PdfPalette.cardBg,
          border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 6.5,
                color: PdfPalette.muted,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _safe(value),
              maxLines: 2,
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfPalette.text,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Supervisor presence table ──────────────────────────────────────────
  // Active = green, Inactive = orange, Absent = red. Each row also shows how
  // long the supervisor has been in that status.
  static pw.Widget _presenceTable(
    ShiftModel shift,
    List<SupervisorPresence> presence,
  ) {
    if (shift.supervisors.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Text(
          'No supervisors assigned to this shift.',
          style: const pw.TextStyle(fontSize: 10, color: PdfPalette.muted),
        ),
      );
    }
    final byId = {for (final p in presence) p.supervisorId: p};

    pw.Widget header() => pw.Container(
      color: PdfPalette.navy,
      padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      child: pw.Row(
        children: [
          _cellHeader('SUPERVISOR', flex: 6),
          _cellHeader('FACTORY', flex: 5),
          _cellHeader('PRESENCE', flex: 4),
          _cellHeader('DURATION', flex: 4),
          _cellHeader('LAST ACTIVITY', flex: 5),
        ],
      ),
    );

    final rows = <pw.Widget>[];
    for (var i = 0; i < shift.supervisors.length; i++) {
      final sup = shift.supervisors[i];
      final p = byId[sup.id];
      final status = p?.status ?? PresenceStatus.absent;
      final statusLabel = _presenceLabel(status);
      final statusColor = _presenceColor(status);
      final duration = p?.durationInStatus;
      final durationLabel = duration == null ? '-' : _humanDuration(duration);
      final lastActive = p?.lastActiveAt;
      final lastActiveLabel = lastActive == null ? '-' : _fmtTime(lastActive);

      pw.Widget cell(
        String text,
        int flex, {
        PdfColor? color,
        bool bold = false,
      }) => pw.Expanded(
        flex: flex,
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Text(
            _safe(text),
            maxLines: 2,
            style: pw.TextStyle(
              fontSize: 9,
              color: color ?? PdfPalette.text,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      );

      rows.add(
        pw.Container(
          color: i.isOdd ? PdfPalette.stripe : PdfColors.white,
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              cell(sup.name, 6, bold: true),
              cell(
                sup.factory.isEmpty ? '-' : sup.factory,
                5,
                color: PdfPalette.muted,
              ),
              pw.Expanded(
                flex: 4,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _withAlpha(statusColor, 0.16),
                      border: pw.Border.all(color: statusColor, width: 0.6),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(3),
                      ),
                    ),
                    child: pw.Text(
                      statusLabel.toUpperCase(),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: statusColor,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
              cell(durationLabel, 4, color: PdfPalette.text, bold: true),
              cell(lastActiveLabel, 5, color: PdfPalette.muted),
            ],
          ),
        ),
      );
    }

    final activeCount = shift.supervisors
        .where((s) => byId[s.id]?.status == PresenceStatus.active)
        .length;
    final inactiveCount = shift.supervisors
        .where((s) => byId[s.id]?.status == PresenceStatus.inactive)
        .length;
    final absentCount = shift.supervisors.length - activeCount - inactiveCount;

    return pw.Column(
      children: [
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(children: [header(), ...rows]),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _legend('Active', PdfPalette.green, activeCount),
            pw.SizedBox(width: 8),
            _legend('Inactive', PdfPalette.orange, inactiveCount),
            pw.SizedBox(width: 8),
            _legend('Absent', PdfPalette.red, absentCount),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cellHeader(String label, {required int flex}) =>
      pw.Expanded(
        flex: flex,
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        ),
      );

  static pw.Widget _legend(String label, PdfColor color, int count) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: pw.BoxDecoration(
        color: _withAlpha(color, 0.10),
        border: pw.Border.all(color: color, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(
        '$label · $count',
        style: pw.TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  // ── Bar breakdown ───────────────────────────────────────────────────────
  static pw.Widget _barBreakdown(Map<String, int> data, PdfColor color) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.first.value;
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: entries
            .map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 110,
                      child: pw.Text(
                        _safe(e.key.isEmpty ? '-' : e.key),
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfPalette.text,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        height: 12,
                        color: PdfColor.fromHex('#EEF2F7'),
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              flex: (e.value / maxVal * 1000).round().clamp(
                                1,
                                1000,
                              ),
                              child: pw.Container(height: 12, color: color),
                            ),
                            pw.Expanded(
                              flex: (1000 - (e.value / maxVal * 1000).round())
                                  .clamp(0, 999),
                              child: pw.SizedBox(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.SizedBox(
                      width: 28,
                      child: pw.Text(
                        '${e.value}',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfPalette.text,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── AI actions list ─────────────────────────────────────────────────────
  static List<pw.Widget> _aiActionsList(List<ShiftAction> ais) {
    return [
      for (var i = 0; i < ais.length; i++)
        pw.Container(
          color: i.isOdd ? PdfPalette.stripe : PdfColors.white,
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                color: PdfPalette.navy,
                child: pw.Text(
                  'AI',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                width: 80,
                child: pw.Text(
                  _fmtTime(ais[i].at),
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfPalette.muted,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 60,
                child: pw.Text(
                  ais[i].alertLabel,
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfPalette.text,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  _safe(ais[i].detail),
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfPalette.text,
                  ),
                ),
              ),
              pw.SizedBox(width: 6),
              pw.SizedBox(
                width: 80,
                child: pw.Text(
                  '-> ${_safe(ais[i].actor)}',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfPalette.navy,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (ais[i].aiConfidence != null) ...[
                pw.SizedBox(width: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  color: _withAlpha(PdfPalette.navy, 0.14),
                  child: pw.Text(
                    '${(ais[i].aiConfidence! * 100).round()}%',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfPalette.navy,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  // ── Timeline ────────────────────────────────────────────────────────────
  static pw.Widget _timelineHeader() {
    pw.Widget cell(String label, int flex) => pw.Expanded(
      flex: flex,
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4),
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 7,
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
    return pw.Container(
      color: PdfPalette.navy,
      padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      child: pw.Row(
        children: [
          cell('TIME', 5),
          cell('EVENT', 5),
          cell('ALERT', 4),
          cell('TYPE', 5),
          cell('FACTORY', 6),
          cell('DETAIL', 18),
          cell('ACTOR', 8),
        ],
      ),
    );
  }

  static List<pw.Widget> _timeline(List<ShiftAction> actions) {
    if (actions.isEmpty) {
      return [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 28),
          alignment: pw.Alignment.center,
          color: PdfColors.white,
          child: pw.Text(
            'No actions recorded during this shift.',
            style: const pw.TextStyle(fontSize: 11, color: PdfPalette.muted),
          ),
        ),
      ];
    }
    final rows = <pw.Widget>[];
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      final color = _kindColor(a.kind);
      final bg = i.isOdd ? PdfPalette.stripe : PdfColors.white;
      pw.Widget cell(String text, int flex, {PdfColor? c, bool mono = false}) =>
          pw.Expanded(
            flex: flex,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4),
              child: pw.Text(
                _safe(text),
                maxLines: 3,
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: c ?? PdfPalette.text,
                  letterSpacing: mono ? 0.2 : null,
                ),
              ),
            ),
          );
      rows.add(
        pw.Container(
          color: bg,
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              cell(_fmtTime(a.at), 5, mono: true),
              pw.Expanded(
                flex: 5,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    color: _withAlpha(color, 0.14),
                    child: pw.Text(
                      _kindLabelText(a.kind).toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 7,
                        color: color,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              cell(a.alertLabel, 4, mono: true),
              cell(a.alertType, 5, c: PdfPalette.muted),
              cell(a.factory, 6),
              cell(a.detail, 18),
              cell(a.actor, 8, c: PdfPalette.muted),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  // ── Handover ────────────────────────────────────────────────────────────
  // Light handover card (no purple flood) — readable on any printer.
  static pw.Widget _handoverCard(ShiftModel shift) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfPalette.navy, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                color: PdfPalette.navy,
                child: pw.Text(
                  'AI HANDOVER',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                shift.lastHandoverAt == null
                    ? ''
                    : 'Generated ${_fmtDateTime(shift.lastHandoverAt!)}',
                style: const pw.TextStyle(fontSize: 8, color: PdfPalette.muted),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            _safe(shift.lastHandoverSummary ?? ''),
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfPalette.text,
              lineSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  static pw.Widget _sectionHeader(String label, int count) {
    return pw.Row(
      children: [
        pw.Container(width: 4, height: 18, color: PdfPalette.navy),
        pw.SizedBox(width: 8),
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 13,
            color: PdfPalette.text,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: pw.BoxDecoration(
            color: _withAlpha(PdfPalette.navy, 0.10),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          ),
          child: pw.Text(
            '$count',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfPalette.navy,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _runningHeader(
    ShiftModel shift,
    ({DateTime start, DateTime end}) window,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0')),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'SIA - Shift Report - ${_safe(shift.name)}',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfPalette.text,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            '${_fmtDateTime(window.start)}  ->  ${_fmtDateTime(window.end)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfPalette.muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0')),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'Page ${ctx.pageNumber}',
            style: const pw.TextStyle(fontSize: 8, color: PdfPalette.muted),
          ),
          pw.Spacer(),
          pw.Text(
            'Generated on ${_fmtDateTime(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfPalette.muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _watermark() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfPalette.navy, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: PdfPalette.navy,
            child: pw.Text(
              'CONFIDENTIAL',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            'Smart Industrial Alert - SIA Shift Commander Briefing',
            style: const pw.TextStyle(fontSize: 9, color: PdfPalette.text),
          ),
        ],
      ),
    );
  }

  static PdfColor _kindColor(String kind) => pdfActionColor(kind);

  static String _kindLabelText(String kind) {
    switch (kind) {
      case 'created':
        return 'Created';
      case 'claimed':
        return 'Claimed';
      case 'resolved':
        return 'Resolved';
      case 'ai_assigned':
        return 'AI Assign';
      case 'escalated':
        return 'Escalated';
      case 'handover':
        return 'Handover';
      default:
        return kind;
    }
  }

  static String _kindLabel(ShiftKind k) {
    switch (k) {
      case ShiftKind.morning:
        return 'Morning';
      case ShiftKind.afternoon:
        return 'Evening';
      case ShiftKind.night:
        return 'Night';
    }
  }

  static PdfColor _kindColorByKind(ShiftKind k) {
    switch (k) {
      case ShiftKind.morning:
        return PdfPalette.yellow;
      case ShiftKind.afternoon:
        return PdfPalette.orange;
      case ShiftKind.night:
        return PdfPalette.navy;
    }
  }

  static String _presenceLabel(PresenceStatus s) {
    switch (s) {
      case PresenceStatus.active:
        return 'Active';
      case PresenceStatus.inactive:
        return 'Inactive';
      case PresenceStatus.absent:
        return 'Absent';
      case PresenceStatus.pendingConfirm:
        return 'Awaiting';
    }
  }

  static PdfColor _presenceColor(PresenceStatus s) {
    switch (s) {
      case PresenceStatus.active:
        return PdfPalette.green;
      case PresenceStatus.inactive:
        return PdfPalette.orange;
      case PresenceStatus.absent:
        return PdfPalette.red;
      case PresenceStatus.pendingConfirm:
        return PdfPalette.blue;
    }
  }

  static String _humanDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String _fmtDateTime(DateTime d) => PdfFmt.dateTime(d);
  static String _fmtTime(DateTime d) => PdfFmt.time(d);
  static String _fmtDateFile(DateTime d) => PdfFmt.dateFile(d);
  static String _slug(String name) => PdfFmt.slug(name);
  static PdfColor _withAlpha(PdfColor c, double alpha) =>
      pdfWithAlpha(c, alpha);
}
