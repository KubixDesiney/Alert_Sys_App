import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:alertsysapp/models/alert_model.dart';
import 'package:alertsysapp/models/shift_model.dart';
import 'package:alertsysapp/models/supervisor_presence.dart';
import 'package:alertsysapp/services/alert_pdf_service.dart';
import 'package:alertsysapp/services/pdf/pdf_common.dart';
import 'package:alertsysapp/services/shift_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF report theme renders Unicode report text', () async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: await PdfFontTheme.load(),
        build: (_) => pw.Text(
          'Shift \u00B7 R\u00E9solu \u2014 '
          '\u0645\u062A\u0627\u0628\u0639\u0629 '
          '\u0627\u0644\u0625\u0646\u062A\u0627\u062C',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      ),
    );

    final bytes = await doc.save();

    expect(bytes, isNotEmpty);
  });

  test('PDF report services do not force built-in non-Unicode fonts', () {
    final reportSources = [
      File('lib/services/alert_pdf_service.dart'),
      File('lib/services/shift_pdf_service.dart'),
    ];

    for (final source in reportSources) {
      final text = source.readAsStringSync();
      expect(text, isNot(contains('Font.courier')));
      expect(text, isNot(contains('Font.helvetica')));
      expect(text, isNot(contains('Font.times')));
    }
  });

  test('alert report saves without built-in PDF font warnings', () async {
    final printed = <String>[];
    final alerts = List.generate(
      80,
      (i) => AlertModel(
        id: 'a$i',
        alertNumber: 1001 + i,
        type: i.isEven ? 'qualite' : 'maintenance',
        usine: 'Usine \u00C9lite',
        convoyeur: (i % 3) + 1,
        poste: (i % 5) + 1,
        adresse: 'Ligne \u00B7 A$i',
        timestamp: DateTime(2026, 5, 18, 8, 30).add(Duration(minutes: i)),
        description:
            'Contr\u00F4le qualit\u00E9 \u2014 '
            '\u0645\u062A\u0627\u0628\u0639\u0629 '
            '\u0627\u0644\u0625\u0646\u062A\u0627\u062C',
        status: i.isEven ? 'validee' : 'en_cours',
        superviseurName: 'Amine R\u00E9solu',
        elapsedTime: 42,
        resolutionReason: i.isEven
            ? 'R\u00E9glage termin\u00E9 \u2014 '
                  '\u062A\u0645 \u0627\u0644\u0625\u0635\u0644\u0627\u062D'
            : null,
        resolvedAt: i.isEven ? DateTime(2026, 5, 18, 9, 12) : null,
      ),
    );

    await _capturePrints(printed, () async {
      final doc = await AlertPdfService.buildDocumentForTesting(
        alerts: alerts,
        scopeLabel: 'Toutes les usines',
        timeRangeLabel: 'Aujourd\u2019hui',
        labelType: (type) => 'Qualit\u00E9',
        reportName: 'Rapport op\u00E9rations \u2014 SIA',
      );

      await doc.save();
    });

    expect(_fontWarnings(printed), isEmpty);
  });

  test('shift report saves without built-in PDF font warnings', () async {
    final printed = <String>[];
    final day = DateTime(2026, 5, 18);
    final actions = List.generate(90, (i) {
      final kind = switch (i % 3) {
        0 => 'created',
        1 => 'ai_assigned',
        _ => 'resolved',
      };
      return ShiftAction(
        at: DateTime(2026, 5, 18, 8, 0).add(Duration(minutes: i)),
        kind: kind,
        alertLabel: '#${1001 + i}',
        alertType: 'qualit\u00E9',
        factory: 'Usine \u00C9lite',
        detail: kind == 'ai_assigned'
            ? 'Assign\u00E9 automatiquement \u2014 '
                  '\u062A\u0645 \u0627\u0644\u062A\u0648\u062C\u064A\u0647'
            : 'Contr\u00F4le qualit\u00E9 \u2014 '
                  '\u0645\u062A\u0627\u0628\u0639\u0629 '
                  '\u0627\u0644\u0625\u0646\u062A\u0627\u062C',
        actor: kind == 'created' ? 'Syst\u00E8me' : 'Oussema R\u00E9solu',
        aiConfidence: kind == 'ai_assigned' ? 0.91 : null,
      );
    });
    final shift = ShiftModel(
      id: 'shift-1',
      name: '\u00C9quipe matin \u2014 \u0645\u062A\u0627\u0628\u0639\u0629',
      startMinutes: 6 * 60,
      endMinutes: 14 * 60,
      supervisors: const [
        AssignedSupervisor(
          id: 'sup-1',
          name: 'Oussema R\u00E9solu',
          factory: 'Usine \u00C9lite',
          ready: true,
        ),
      ],
      maxSupervisors: 3,
      aiCommander: true,
      aiModel: 'llama-3.2-3b',
      aiConfidence: 0.65,
      handleAssignments: true,
      handleCollaborations: true,
      handleCrossFactoryTransfer: false,
      fullControl: false,
      randomize: false,
      createdAt: day,
      lastHandoverSummary:
          'Passage de consignes \u2014 '
          '\u0645\u062A\u0627\u0628\u0639\u0629 '
          '\u0627\u0644\u0625\u0646\u062A\u0627\u062C '
          '\u0645\u0633\u062A\u0642\u0631\u0629',
      lastHandoverAt: DateTime(2026, 5, 18, 14, 0),
    );

    await _capturePrints(printed, () async {
      final doc = await ShiftPdfService.buildDocumentForTesting(
        shift: shift,
        day: day,
        actions: actions,
        presence: [
          SupervisorPresence(
            shiftId: 'shift-1',
            supervisorId: 'sup-1',
            name: 'Oussema R\u00E9solu',
            factory: 'Usine \u00C9lite',
            status: PresenceStatus.active,
            lastActiveAt: DateTime(2026, 5, 18, 9, 0),
          ),
        ],
      );

      await doc.save();
    });

    expect(_fontWarnings(printed), isEmpty);
  });
}

Future<void> _capturePrints(
  List<String> printed,
  Future<void> Function() body,
) {
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
}

List<String> _fontWarnings(List<String> printed) {
  return printed.where((line) => line.contains('no Unicode support')).toList();
}
