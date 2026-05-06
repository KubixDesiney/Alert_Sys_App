import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

import '../models/alert_model.dart';

class _PdfPalette {
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
}

class AlertPdfService {
  static const String _dash = '-';

  static String _dashIfBlank(String? value) {
    final v = (value ?? '').trim();
    return v.isEmpty ? _dash : _safePdfText(v);
  }

  static String _safePdfText(String value) {
    return value
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('−', '-')
        .replaceAll('·', '-')
        .replaceAll('•', '*')
        .replaceAll('…', '...')
        .replaceAll('"', '"')
        .replaceAll('"', '"')
        .replaceAll(''', "'")
        .replaceAll(''', "'");
  }

  static String _truncate(String value, {required int maxChars}) {
    final v = _safePdfText(value).trim();
    if (v.length <= maxChars) return v;
    if (maxChars <= 3) return v.substring(0, maxChars);
    return '${v.substring(0, maxChars - 3)}...';
  }

  static Future<void> exportAndShare({
    required List<AlertModel> alerts,
    required String scopeLabel,
    required String timeRangeLabel,
    String Function(String type)? labelType,
  }) async {
    final doc = await _buildDoc(
      alerts: alerts,
      scopeLabel: scopeLabel,
      timeRangeLabel: timeRangeLabel,
      labelType: labelType ?? _defaultTypeLabel,
    );
    final bytes = await doc.save();
    final filename =
        'alertsys_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
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
      text: 'AlertSys operations report',
    );
  }

  static String _defaultTypeLabel(String type) {
    switch (type) {
      case 'qualite':
        return 'Quality';
      case 'maintenance':
        return 'Maintenance';
      case 'defaut_produit':
        return 'Damaged';
      case 'manque_ressource':
        return 'Resource';
      default:
        return type;
    }
  }

  static Future<pw.Document> _buildDoc({
    required List<AlertModel> alerts,
    required String scopeLabel,
    required String timeRangeLabel,
    required String Function(String) labelType,
  }) async {
    final doc = pw.Document(
      title: 'AlertSys Operations Report',
      author: 'AlertSys',
      creator: 'AlertSys Production Manager',
    );

    final solved = alerts.where((a) => a.status == 'validee').length;
    final inProgress = alerts.where((a) => a.status == 'en_cours').length;
    final pending = alerts.where((a) => a.status == 'disponible').length;
    final critical = alerts.where((a) => a.isCritical).length;
    final total = alerts.length;
    final resolutionRate =
        total == 0 ? 0 : ((solved / total) * 100).round();
    final solvedWithTime = alerts.where(
        (a) => a.status == 'validee' && (a.elapsedTime ?? 0) > 0);
    final avgMin = solvedWithTime.isEmpty
        ? 0
        : (solvedWithTime
                    .map((a) => a.elapsedTime!)
                    .fold<int>(0, (s, e) => s + e) /
                solvedWithTime.length)
            .round();

    final byType = <String, int>{};
    for (final a in alerts) {
      byType[a.type] = (byType[a.type] ?? 0) + 1;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        theme: pw.ThemeData.withFont(),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox.shrink()
            : pw.Column(children: [
                _runningHeader(scopeLabel, timeRangeLabel),
                pw.SizedBox(height: 8),
                _tableHeader(),
              ]),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          _heroBanner(
            scopeLabel: scopeLabel,
            timeRangeLabel: timeRangeLabel,
            total: total,
          ),
          pw.SizedBox(height: 14),
          _kpiStrip(
            total: total,
            pending: pending,
            inProgress: inProgress,
            solved: solved,
            critical: critical,
            avgMin: avgMin,
            resolutionRate: resolutionRate,
          ),
          pw.SizedBox(height: 14),
          if (byType.isNotEmpty)
            _typeBreakdown(byType, total, labelType: labelType),
          pw.SizedBox(height: 14),
          _sectionHeader('Alert Ledger', total),
          pw.SizedBox(height: 6),
          _legendBar(),
          pw.SizedBox(height: 8),
          _tableHeader(),
          _alertsTableWithoutHeader(alerts, labelType: labelType),
          pw.SizedBox(height: 10),
          _watermarkFooter(),
        ],
      ),
    );

    return doc;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HERO BANNER
  // ─────────────────────────────────────────────────────────────────────────

  static pw.Widget _heroBanner({
    required String scopeLabel,
    required String timeRangeLabel,
    required int total,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      color: _PdfPalette.navy,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ALERTSYS - OPERATIONS REPORT',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Production Intelligence Briefing',
            style: pw.TextStyle(
              fontSize: 24,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Audit-grade snapshot of factory floor alerts and supervisor performance.',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              _simpleChip('Plant: $scopeLabel'),
              pw.SizedBox(width: 12),
              _simpleChip('Range: $timeRangeLabel'),
              pw.SizedBox(width: 12),
              _simpleChip('Generated: ${_fmtDate(DateTime.now())}'),
              pw.Spacer(),
              pw.Text(
                'Total Alerts: $total',
                style: pw.TextStyle(
                  fontSize: 16,
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _simpleChip(String label) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const PdfColor(1, 1, 1, 0.15),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KPI STRIP
  // ─────────────────────────────────────────────────────────────────────────

  static pw.Widget _kpiStrip({
    required int total,
    required int pending,
    required int inProgress,
    required int solved,
    required int critical,
    required int avgMin,
    required int resolutionRate,
  }) {
    return pw.Row(children: [
      _kpiCard('Total', '$total', _PdfPalette.navy, _PdfPalette.cardBg),
      _kpiSpacer(),
      _kpiCard(
          'Pending', '$pending', _PdfPalette.orange, _PdfPalette.cardBg),
      _kpiSpacer(),
      _kpiCard(
          'Claimed', '$inProgress', _PdfPalette.blue, _PdfPalette.cardBg),
      _kpiSpacer(),
      _kpiCard('Resolved', '$solved', _PdfPalette.green, _PdfPalette.cardBg),
      _kpiSpacer(),
      _kpiCard(
          'Critical', '$critical', _PdfPalette.red, _PdfPalette.cardBg),
      _kpiSpacer(),
      _kpiCard(
          'Avg fix', avgMin > 0 ? '${avgMin}m' : '-',
          _PdfPalette.purple, _PdfPalette.cardBg),
      _kpiSpacer(),
      _kpiCard('Resolution', '$resolutionRate%', _PdfPalette.yellow,
          _PdfPalette.cardBg),
    ]);
  }

  static pw.Widget _kpiSpacer() => pw.SizedBox(width: 8);

  static pw.Widget _kpiCard(
      String label, String value, PdfColor accent, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 10),
        color: bg,
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
                fontSize: 20,
                color: accent,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TYPE BREAKDOWN BARS
  // ─────────────────────────────────────────────────────────────────────────

  static pw.Widget _typeBreakdown(
    Map<String, int> byType,
    int total, {
    required String Function(String) labelType,
  }) {
    final entries = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.first.value;
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: _PdfPalette.cardBg,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(children: [
            pw.Text(
              'Distribution by alert type',
              style: pw.TextStyle(
                fontSize: 11,
                color: _PdfPalette.text,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Spacer(),
            pw.Text(
              '$total alerts analysed',
              style: pw.TextStyle(
                fontSize: 8,
                color: _PdfPalette.muted,
              ),
            ),
          ]),
          pw.SizedBox(height: 8),
          ...entries.map((e) => _typeBar(
                label: labelType(e.key),
                color: _typeColor(e.key),
                count: e.value,
                fraction: maxVal == 0 ? 0 : e.value / maxVal,
                pctOfTotal:
                    total == 0 ? 0 : (e.value / total * 100).round(),
              )),
        ],
      ),
    );
  }

  static pw.Widget _typeBar({
    required String label,
    required PdfColor color,
    required int count,
    required double fraction,
    required int pctOfTotal,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(children: [
        pw.SizedBox(
          width: 80,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              color: _PdfPalette.text,
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
                flex: (fraction.clamp(0.0, 1.0) * 1000).round(),
                child: pw.Container(
                  height: 12,
                  color: color,
                ),
              ),
              pw.Expanded(
                flex: ((1 - fraction.clamp(0.0, 1.0)) * 1000).round(),
                child: pw.SizedBox(),
              ),
            ]),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.SizedBox(
          width: 70,
          child: pw.Text(
            '$count  ·  $pctOfTotal%',
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 9,
              color: _PdfPalette.text,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ALERTS TABLE
  // ─────────────────────────────────────────────────────────────────────────

  static const List<String> _tableHeaders = [
    'Alert ID',
    'Type',
    'Factory',
    'Conv.',
    'Line',
    'Address',
    'Timestamp',
    'Description',
    'Status',
    'Supervisor',
    'Assistant',
    'Resolution',
    'Elapsed',
    'Critical',
  ];

  static const List<int> _tableFlexes = [6, 8, 8, 3, 3, 8, 8, 18, 6, 8, 8, 12, 5, 5];

  static pw.Widget _tableHeader() {
    final headerCells = <pw.Widget>[];
    for (int i = 0; i < _tableHeaders.length; i++) {
      headerCells.add(
        pw.Expanded(
          flex: _tableFlexes[i],
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4),
            child: pw.Text(
              _tableHeaders[i].toUpperCase(),
              style: pw.TextStyle(
                fontSize: 7,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      );
    }

    return pw.Container(
      color: _PdfPalette.navy,
      padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      child: pw.Row(children: headerCells),
    );
  }

  static pw.Widget _alertsTableWithoutHeader(
    List<AlertModel> alerts, {
    required String Function(String) labelType,
  }) {
    if (alerts.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 32),
        alignment: pw.Alignment.center,
        color: _PdfPalette.cardBg,
        child: pw.Text(
          'No alerts to display.',
          style: pw.TextStyle(fontSize: 11, color: _PdfPalette.muted),
        ),
      );
    }

    final rows = <pw.Widget>[];

    // Data rows
    for (var i = 0; i < alerts.length; i++) {
      final a = alerts[i];
      final bgColor = i.isOdd ? _PdfPalette.stripe : PdfColors.white;
      final cells = _buildAlertRow(a, _tableFlexes, labelType);

      rows.add(
        pw.Container(
          color: bgColor,
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: pw.Row(children: cells),
        ),
      );
    }

    return pw.Column(children: rows);
  }


  static List<pw.Widget> _buildAlertRow(
    AlertModel a,
    List<int> flexes,
    String Function(String) labelType,
  ) {
    final typeColor = _typeColor(a.type);
    final statusColor = _statusColor(a.status);

    final cells = [
      _cellText('${a.alertNumber}', mono: true, weight: pw.FontWeight.bold),
      _typeBadgeCell(_safePdfText(labelType(a.type)), typeColor),
      _cellText(_dashIfBlank(a.usine), weight: pw.FontWeight.bold),
      _cellText('${a.convoyeur}', align: pw.TextAlign.center),
      _cellText('${a.poste}', align: pw.TextAlign.center),
      _cellText(
        _dashIfBlank(a.adresse).isEmpty
            ? '-'
            : _truncate(_dashIfBlank(a.adresse), maxChars: 28),
        mono: true,
        fontSize: 6.4,
      ),
      _cellText(_safePdfText(_fmtDateTime(a.timestamp)), fontSize: 6.4),
      _cellText(
        _dashIfBlank(a.description).isEmpty
            ? '-'
            : _truncate(_dashIfBlank(a.description), maxChars: 110),
        fontSize: 6.7,
        color: _PdfPalette.text,
      ),
      _statusBadgeCell(_statusLabel(a.status), statusColor),
      _cellText(
        _dashIfBlank(a.superviseurName),
        color: (a.superviseurName ?? '').trim().isEmpty
            ? _PdfPalette.subtle
            : _PdfPalette.text,
      ),
      _cellText(
        _dashIfBlank(a.assistantName),
        color: (a.assistantName ?? '').trim().isEmpty
            ? _PdfPalette.subtle
            : _PdfPalette.text,
      ),
      _cellText(
        _dashIfBlank(a.resolutionReason).isEmpty
            ? '-'
            : _truncate(_dashIfBlank(a.resolutionReason), maxChars: 60),
        fontSize: 6.6,
        color: _dashIfBlank(a.resolutionReason).isEmpty
            ? _PdfPalette.subtle
            : _PdfPalette.text,
      ),
      _cellText(
        _safePdfText(_fmtElapsed(a.elapsedTime)),
        align: pw.TextAlign.center,
        weight: pw.FontWeight.bold,
      ),
      a.isCritical
          ? pw.Align(
              alignment: pw.Alignment.center,
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: _PdfPalette.red,
                child: pw.Text(
                  '!',
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            )
          : _cellText('-', align: pw.TextAlign.center, color: _PdfPalette.subtle),
    ];

    return List.generate(
      cells.length,
      (i) => pw.Expanded(
        flex: flexes[i],
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: cells[i],
        ),
      ),
    );
  }

  static pw.Widget _cellText(
    String text, {
    double fontSize = 7,
    PdfColor color = _PdfPalette.text,
    pw.FontWeight? weight,
    pw.TextAlign align = pw.TextAlign.left,
    bool mono = false,
  }) {
    return pw.Text(
      _safePdfText(text),
      textAlign: align,
      maxLines: 2,
      style: pw.TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        font: mono ? pw.Font.courier() : null,
      ),
    );
  }

  static pw.Widget _typeBadgeCell(String label, PdfColor color) {
    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Container(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        color: _withAlpha(color, 0.14),
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 6.5,
            color: color,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static pw.Widget _statusBadgeCell(String label, PdfColor color) {
    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Container(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        color: _withAlpha(color, 0.14),
        child: pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 6.5,
            color: color,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION + LEGEND HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static pw.Widget _sectionHeader(String label, int count) {
    return pw.Row(children: [
      pw.Container(
        width: 4,
        height: 18,
        color: _PdfPalette.navy,
      ),
      pw.SizedBox(width: 8),
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 13,
          color: _PdfPalette.text,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(width: 6),
      pw.Container(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        color: _withAlpha(_PdfPalette.navy, 0.13),
        child: pw.Text(
          '$count entries',
          style: pw.TextStyle(
            fontSize: 8,
            color: _PdfPalette.navy,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    ]);
  }

  static pw.Widget _legendBar() {
    pw.Widget chip(String label, PdfColor color) => pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color: _withAlpha(color, 0.14),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7,
              color: color,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
    return pw.Row(children: [
      pw.Text(
        'STATUS',
        style: pw.TextStyle(
          fontSize: 7,
          color: _PdfPalette.muted,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(width: 8),
      chip('AVAILABLE', _PdfPalette.orange),
      pw.SizedBox(width: 5),
      chip('CLAIMED', _PdfPalette.blue),
      pw.SizedBox(width: 5),
      chip('FIXED', _PdfPalette.green),
      pw.SizedBox(width: 14),
      pw.Text(
        'TYPE',
        style: pw.TextStyle(
          fontSize: 7,
          color: _PdfPalette.muted,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(width: 8),
      chip('Quality', _typeColor('qualite')),
      pw.SizedBox(width: 5),
      chip('Maintenance', _typeColor('maintenance')),
      pw.SizedBox(width: 5),
      chip('Damaged', _typeColor('defaut_produit')),
      pw.SizedBox(width: 5),
      chip('Resource', _typeColor('manque_ressource')),
    ]);
  }

  static pw.Widget _runningHeader(String scope, String range) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: _PdfPalette.cardBg,
      child: pw.Row(children: [
        pw.Text(
          'AlertSys - Operations Report',
          style: pw.TextStyle(
            fontSize: 10,
            color: _PdfPalette.text,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Spacer(),
        pw.Text(
          '$scope · $range',
          style: pw.TextStyle(
            fontSize: 8,
            color: _PdfPalette.muted,
          ),
        ),
      ]),
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: _PdfPalette.cardBg,
      child: pw.Row(children: [
        pw.Text(
          'Page ${ctx.pageNumber}',
          style: pw.TextStyle(
            fontSize: 8,
            color: _PdfPalette.muted,
          ),
        ),
        pw.Spacer(),
        pw.Text(
          'Generated on ${_fmtDate(DateTime.now())}',
          style: pw.TextStyle(
            fontSize: 8,
            color: _PdfPalette.muted,
          ),
        ),
      ]),
    );
  }

  static pw.Widget _watermarkFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      color: _PdfPalette.navy,
      child: pw.Column(
        children: [
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
            'AlertSys · Industrial Alert Intelligence Platform',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STYLE HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static PdfColor _typeColor(String type) {
    switch (type) {
      case 'qualite':
        return _PdfPalette.red;
      case 'maintenance':
        return _PdfPalette.blue;
      case 'defaut_produit':
        return _PdfPalette.green;
      case 'manque_ressource':
        return _PdfPalette.orange;
      default:
        return _PdfPalette.muted;
    }
  }

  static PdfColor _statusColor(String status) {
    switch (status) {
      case 'validee':
        return _PdfPalette.green;
      case 'en_cours':
        return _PdfPalette.blue;
      default:
        return _PdfPalette.orange;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'validee':
        return 'Fixed';
      case 'en_cours':
        return 'Claimed';
      default:
        return 'Available';
    }
  }

  static String _fmtDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year}  ${two(dt.hour)}:${two(dt.minute)}';
  }

  static String _fmtDate(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
  }

  static String _fmtElapsed(int? minutes) {
    if (minutes == null || minutes <= 0) return _dash;
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static PdfColor _withAlpha(PdfColor c, double alpha) {
    return PdfColor(c.red, c.green, c.blue, alpha.clamp(0.0, 1.0));
  }
}
