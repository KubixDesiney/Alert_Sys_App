import 'dart:io';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

import '../models/alert_model.dart';
import '../models/shift_model.dart';

class _Pal {
  static const navy = PdfColor.fromInt(0xFF0D4A75);
  static const purple = PdfColor.fromInt(0xFF6D28D9);
  static const text = PdfColor.fromInt(0xFF1E293B);
  static const muted = PdfColor.fromInt(0xFF64748B);
  static const subtle = PdfColor.fromInt(0xFF94A3B8);
  static const cardBg = PdfColor.fromInt(0xFFF8FAFC);
  static const stripe = PdfColor.fromInt(0xFFF1F5F9);
  static const green = PdfColor.fromInt(0xFF16A34A);
  static const orange = PdfColor.fromInt(0xFFEA580C);
  static const red = PdfColor.fromInt(0xFFDC2626);
  static const blue = PdfColor.fromInt(0xFF2563EB);
  static const yellow = PdfColor.fromInt(0xFFD97706);
  static const aiPink = PdfColor.fromInt(0xFFC084FC);
}

/// Single timeline action that occurred during a shift window.
class ShiftAction {
  final DateTime at;
  final String kind; // created, claimed, resolved, ai_assigned, escalated, handover
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

class ShiftPdfService {
  static String _safe(String v) => v
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('•', '*')
      .replaceAll('…', '...');

  /// Loads every action that happened during [shift] on [day], builds a
  /// shift report PDF, and either downloads it (web) or shares it.
  static Future<void> exportAndShare({
    required ShiftModel shift,
    required DateTime day,
  }) async {
    final window = _windowFor(shift, day);
    final actions = await _loadActions(shift, window);
    final doc = await _buildDoc(shift: shift, window: window, actions: actions);
    final bytes = await doc.save();
    final filename =
        'alertsys_shift_${_slug(shift.name)}_${_fmtDateFile(day)}.pdf';
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
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'AlertSys shift report — ${shift.name}',
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // DATA LOADING
  // ──────────────────────────────────────────────────────────────────────

  static ({DateTime start, DateTime end}) _windowFor(
      ShiftModel shift, DateTime day) {
    final base = DateTime(day.year, day.month, day.day);
    final start = base.add(Duration(minutes: shift.startMinutes));
    DateTime end = base.add(Duration(minutes: shift.endMinutes));
    if (shift.endMinutes <= shift.startMinutes) {
      end = end.add(const Duration(days: 1));
    }
    return (start: start, end: end);
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
        actions.add(ShiftAction(
          at: alert.timestamp,
          kind: 'created',
          alertLabel: alert.alertLabel,
          alertType: alert.type,
          factory: alert.usine,
          detail: alert.description.isEmpty
              ? 'Alert created at ${alert.usine}, conv ${alert.convoyeur}, line ${alert.poste}'
              : alert.description,
          actor: 'System',
        ));
      }

      if (alert.aiAssigned &&
          alert.aiAssignedAt != null &&
          inWindow(alert.aiAssignedAt)) {
        actions.add(ShiftAction(
          at: alert.aiAssignedAt!,
          kind: 'ai_assigned',
          alertLabel: alert.alertLabel,
          alertType: alert.type,
          factory: alert.usine,
          detail: alert.aiAssignmentReason ?? 'AI commander assignment',
          actor: alert.superviseurName ?? 'AI',
          aiConfidence: alert.aiConfidence,
        ));
      } else if (alert.takenAtTimestamp != null &&
          inWindow(alert.takenAtTimestamp)) {
        actions.add(ShiftAction(
          at: alert.takenAtTimestamp!,
          kind: 'claimed',
          alertLabel: alert.alertLabel,
          alertType: alert.type,
          factory: alert.usine,
          detail:
              'Claimed by ${alert.superviseurName ?? "supervisor"} at ${alert.usine}',
          actor: alert.superviseurName ?? '-',
        ));
      }

      if (alert.resolvedAt != null && inWindow(alert.resolvedAt)) {
        actions.add(ShiftAction(
          at: alert.resolvedAt!,
          kind: 'resolved',
          alertLabel: alert.alertLabel,
          alertType: alert.type,
          factory: alert.usine,
          detail: alert.resolutionReason?.isNotEmpty == true
              ? alert.resolutionReason!
              : 'Resolved',
          actor: alert.superviseurName ?? '-',
        ));
      }

      if (alert.isEscalated &&
          alert.escalatedAt != null &&
          inWindow(alert.escalatedAt)) {
        actions.add(ShiftAction(
          at: alert.escalatedAt!,
          kind: 'escalated',
          alertLabel: alert.alertLabel,
          alertType: alert.type,
          factory: alert.usine,
          detail: 'Escalated as critical',
          actor: 'System',
        ));
      }
    }

    if (shift.lastHandoverAt != null &&
        !shift.lastHandoverAt!.isBefore(window.start) &&
        shift.lastHandoverAt!.isBefore(
            window.end.add(const Duration(minutes: 30)))) {
      actions.add(ShiftAction(
        at: shift.lastHandoverAt!,
        kind: 'handover',
        alertLabel: '-',
        alertType: '-',
        factory: '-',
        detail: shift.lastHandoverSummary ?? 'AI handover generated',
        actor: 'AI Commander',
      ));
    }

    actions.sort((a, b) => a.at.compareTo(b.at));
    return actions;
  }

  // ──────────────────────────────────────────────────────────────────────
  // PDF BUILD
  // ──────────────────────────────────────────────────────────────────────

  static Future<pw.Document> _buildDoc({
    required ShiftModel shift,
    required ({DateTime start, DateTime end}) window,
    required List<ShiftAction> actions,
  }) async {
    final doc = pw.Document(
      title: 'Shift Report — ${shift.name}',
      author: 'AlertSys',
      creator: 'AlertSys Shift Commander',
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
        theme: pw.ThemeData.withFont(),
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
          _shiftMetaCard(shift),
          pw.SizedBox(height: 14),
          if (byFactory.isNotEmpty) ...[
            _sectionHeader('Alerts by factory', byFactory.length),
            pw.SizedBox(height: 6),
            _barBreakdown(byFactory, _Pal.navy),
            pw.SizedBox(height: 14),
          ],
          if (bySupervisor.isNotEmpty) ...[
            _sectionHeader('Top supervisors (resolutions)', bySupervisor.length),
            pw.SizedBox(height: 6),
            _barBreakdown(bySupervisor, _Pal.green),
            pw.SizedBox(height: 14),
          ],
          if (aiAssigned > 0) ...[
            _sectionHeader('AI Shift Commander actions', aiAssigned),
            pw.SizedBox(height: 6),
            _aiActionsList(
                actions.where((a) => a.kind == 'ai_assigned').toList()),
            pw.SizedBox(height: 14),
          ],
          _sectionHeader('Action timeline', actions.length),
          pw.SizedBox(height: 6),
          _timelineHeader(),
          _timeline(actions),
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

  // ── Hero ─────────────────────────────────────────────────────────────
  static pw.Widget _hero(
    ShiftModel shift,
    ({DateTime start, DateTime end}) window,
    int totalActions,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: const pw.BoxDecoration(color: _Pal.navy),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ALERTSYS - SHIFT REPORT',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            _safe(shift.name),
            style: pw.TextStyle(
              fontSize: 26,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'A complete record of every action that occurred during this shift, '
            'including AI Shift Commander decisions and handover output.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
          ),
          pw.SizedBox(height: 12),
          pw.Row(children: [
            _heroChip('${_kindLabel(shift.kind)} shift'),
            pw.SizedBox(width: 8),
            _heroChip(
                '${_fmtDateTime(window.start)}  ->  ${_fmtDateTime(window.end)}'),
            pw.SizedBox(width: 8),
            if (shift.aiCommander) _heroChip('AI Commander ON'),
            pw.Spacer(),
            pw.Text(
              '$totalActions actions',
              style: pw.TextStyle(
                fontSize: 16,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  static pw.Widget _heroChip(String label) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const PdfColor(1, 1, 1, 0.18),
      child: pw.Text(
        _safe(label),
        style: pw.TextStyle(
          fontSize: 9,
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  // ── KPI strip ────────────────────────────────────────────────────────
  static pw.Widget _kpiStrip({
    required int total,
    required int created,
    required int claimed,
    required int resolved,
    required int aiAssigned,
    required int escalated,
  }) {
    return pw.Row(children: [
      _kpi('Actions', '$total', _Pal.navy),
      _gap(),
      _kpi('Created', '$created', _Pal.orange),
      _gap(),
      _kpi('Claimed', '$claimed', _Pal.blue),
      _gap(),
      _kpi('Resolved', '$resolved', _Pal.green),
      _gap(),
      _kpi('AI calls', '$aiAssigned', _Pal.purple),
      _gap(),
      _kpi('Escalated', '$escalated', _Pal.red),
    ]);
  }

  static pw.Widget _gap() => pw.SizedBox(width: 8);

  static pw.Widget _kpi(String label, String value, PdfColor accent) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 10),
        color: _Pal.cardBg,
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
                fontSize: 22,
                color: accent,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shift meta ───────────────────────────────────────────────────────
  static pw.Widget _shiftMetaCard(ShiftModel shift) {
    final supervisors = shift.supervisors.map((s) => s.name).join(', ');
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _Pal.cardBg,
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _metaRow('Shift kind', _kindLabel(shift.kind)),
                _metaRow(
                    'Capacity', '${shift.supervisors.length}/${shift.maxSupervisors}'),
                _metaRow('Randomized', shift.randomize ? 'Yes' : 'No'),
              ],
            ),
          ),
          pw.SizedBox(width: 24),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _metaRow('AI Commander',
                    shift.aiCommander ? 'Enabled' : 'Disabled'),
                _metaRow('AI model', shift.aiModel),
                _metaRow('Confidence floor',
                    '${(shift.aiConfidence * 100).round()}%'),
              ],
            ),
          ),
          pw.SizedBox(width: 24),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('SUPERVISORS',
                    style: pw.TextStyle(
                      fontSize: 7,
                      color: _Pal.muted,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.8,
                    )),
                pw.SizedBox(height: 4),
                pw.Text(
                  supervisors.isEmpty ? '-' : _safe(supervisors),
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: _Pal.text,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _metaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(children: [
        pw.SizedBox(
          width: 90,
          child: pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7,
              color: _Pal.muted,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            _safe(value),
            style: pw.TextStyle(
              fontSize: 10,
              color: _Pal.text,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ]),
    );
  }

  // ── Bar breakdown ────────────────────────────────────────────────────
  static pw.Widget _barBreakdown(Map<String, int> data, PdfColor color) {
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.first.value;
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: _Pal.cardBg,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: entries
            .map((e) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(children: [
                    pw.SizedBox(
                      width: 110,
                      child: pw.Text(
                        _safe(e.key.isEmpty ? '-' : e.key),
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: _Pal.text,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        height: 12,
                        color: PdfColor.fromHex('#EEF2F7'),
                        child: pw.Row(children: [
                          pw.Expanded(
                            flex:
                                (e.value / maxVal * 1000).round().clamp(1, 1000),
                            child: pw.Container(height: 12, color: color),
                          ),
                          pw.Expanded(
                            flex: (1000 -
                                    (e.value / maxVal * 1000).round())
                                .clamp(0, 999),
                            child: pw.SizedBox(),
                          ),
                        ]),
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
                          color: _Pal.text,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
  }

  // ── AI actions list ──────────────────────────────────────────────────
  static pw.Widget _aiActionsList(List<ShiftAction> ais) {
    return pw.Column(children: [
      for (var i = 0; i < ais.length; i++)
        pw.Container(
          color: i.isOdd ? _Pal.stripe : PdfColors.white,
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                color: _Pal.aiPink,
                child: pw.Text('AI',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                    )),
              ),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                width: 80,
                child: pw.Text(
                  _fmtTime(ais[i].at),
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: _Pal.muted,
                    font: pw.Font.courier(),
                  ),
                ),
              ),
              pw.SizedBox(
                width: 60,
                child: pw.Text(
                  ais[i].alertLabel,
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: _Pal.text,
                    fontWeight: pw.FontWeight.bold,
                    font: pw.Font.courier(),
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  _safe(ais[i].detail),
                  style: const pw.TextStyle(fontSize: 9, color: _Pal.text),
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
                    color: _Pal.purple,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (ais[i].aiConfidence != null) ...[
                pw.SizedBox(width: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  color: _withAlpha(_Pal.purple, 0.14),
                  child: pw.Text(
                    '${(ais[i].aiConfidence! * 100).round()}%',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: _Pal.purple,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    ]);
  }

  // ── Timeline ─────────────────────────────────────────────────────────
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
      color: _Pal.navy,
      padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      child: pw.Row(children: [
        cell('TIME', 5),
        cell('EVENT', 5),
        cell('ALERT', 4),
        cell('TYPE', 5),
        cell('FACTORY', 6),
        cell('DETAIL', 18),
        cell('ACTOR', 8),
      ]),
    );
  }

  static pw.Widget _timeline(List<ShiftAction> actions) {
    if (actions.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 28),
        alignment: pw.Alignment.center,
        color: _Pal.cardBg,
        child: pw.Text('No actions recorded during this shift.',
            style: pw.TextStyle(fontSize: 11, color: _Pal.muted)),
      );
    }
    final rows = <pw.Widget>[];
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      final color = _kindColor(a.kind);
      final bg = i.isOdd ? _Pal.stripe : PdfColors.white;
      pw.Widget cell(String text, int flex,
              {PdfColor? c, bool mono = false}) =>
          pw.Expanded(
            flex: flex,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4),
              child: pw.Text(
                _safe(text),
                maxLines: 3,
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: c ?? _Pal.text,
                  font: mono ? pw.Font.courier() : null,
                ),
              ),
            ),
          );
      rows.add(pw.Container(
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
                      horizontal: 5, vertical: 2),
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
            cell(a.alertType, 5, c: _Pal.muted),
            cell(a.factory, 6),
            cell(a.detail, 18),
            cell(a.actor, 8, c: _Pal.muted),
          ],
        ),
      ));
    }
    return pw.Column(children: rows);
  }

  // ── Handover ─────────────────────────────────────────────────────────
  static pw.Widget _handoverCard(ShiftModel shift) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _withAlpha(_Pal.purple, 0.06),
        border: pw.Border.all(color: _Pal.purple, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              color: _Pal.purple,
              child: pw.Text('AI HANDOVER',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  )),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              shift.lastHandoverAt == null
                  ? ''
                  : 'Generated ${_fmtDateTime(shift.lastHandoverAt!)}',
              style: pw.TextStyle(fontSize: 8, color: _Pal.muted),
            ),
          ]),
          pw.SizedBox(height: 8),
          pw.Text(
            _safe(shift.lastHandoverSummary ?? ''),
            style: pw.TextStyle(
              fontSize: 10,
              color: _Pal.text,
              lineSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────
  static pw.Widget _sectionHeader(String label, int count) {
    return pw.Row(children: [
      pw.Container(width: 4, height: 18, color: _Pal.navy),
      pw.SizedBox(width: 8),
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 13,
          color: _Pal.text,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(width: 6),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        color: _withAlpha(_Pal.navy, 0.13),
        child: pw.Text(
          '$count',
          style: pw.TextStyle(
            fontSize: 8,
            color: _Pal.navy,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    ]);
  }

  static pw.Widget _runningHeader(
      ShiftModel shift, ({DateTime start, DateTime end}) window) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: _Pal.cardBg,
      child: pw.Row(children: [
        pw.Text(
          'AlertSys - Shift Report - ${_safe(shift.name)}',
          style: pw.TextStyle(
            fontSize: 10,
            color: _Pal.text,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Spacer(),
        pw.Text(
          '${_fmtDateTime(window.start)}  ->  ${_fmtDateTime(window.end)}',
          style: pw.TextStyle(fontSize: 8, color: _Pal.muted),
        ),
      ]),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: _Pal.cardBg,
      child: pw.Row(children: [
        pw.Text('Page ${ctx.pageNumber}',
            style: pw.TextStyle(fontSize: 8, color: _Pal.muted)),
        pw.Spacer(),
        pw.Text('Generated on ${_fmtDateTime(DateTime.now())}',
            style: pw.TextStyle(fontSize: 8, color: _Pal.muted)),
      ]),
    );
  }

  static pw.Widget _watermark() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      color: _Pal.navy,
      child: pw.Column(children: [
        pw.Text(
          'CONFIDENTIAL - INTERNAL USE',
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'AlertSys * Shift Commander Briefing',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
        ),
      ]),
    );
  }

  static PdfColor _kindColor(String kind) {
    switch (kind) {
      case 'created':
        return _Pal.orange;
      case 'claimed':
        return _Pal.blue;
      case 'resolved':
        return _Pal.green;
      case 'ai_assigned':
        return _Pal.purple;
      case 'escalated':
        return _Pal.red;
      case 'handover':
        return _Pal.aiPink;
      default:
        return _Pal.muted;
    }
  }

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
        return 'Afternoon';
      case ShiftKind.night:
        return 'Night';
    }
  }

  static String _fmtDateTime(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _fmtTime(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  static String _fmtDateFile(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}';
  }

  static String _slug(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static PdfColor _withAlpha(PdfColor c, double alpha) {
    return PdfColor(c.red, c.green, c.blue, alpha.clamp(0.0, 1.0));
  }
}
