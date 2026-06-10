import 'package:flutter_test/flutter_test.dart';
import 'package:alertsysapp/services/lstm/alert_record_parser.dart';

void main() {
  group('AlertRecordParser CSV', () {
    test('parses comma CSV with standard headers', () {
      const csv = 'timestamp,type,usine,convoyeur,poste,isCritical\n'
          '2026-01-05T08:30:00Z,qualite,Plant A,1,2,true\n'
          '2026-01-06T09:00:00Z,maintenance,Plant A,1,3,false\n';
      final parsed = AlertRecordParser.parseCsvText('alerts.csv', csv);
      expect(parsed.records.length, 2);
      expect(parsed.records.first.type, 'qualite');
      expect(parsed.records.first.isCritical, isTrue);
      expect(parsed.summary.machineCount, 2);
    });

    test('parses semicolon CSV with synonym headers and dd/MM dates', () {
      const csv = 'Date;Category;Factory;Line;Station;Severity\n'
          '05/01/2026 08:30;Quality;Plant B;3;7;high\n'
          '06/01/2026;Resource shortage;Plant B;3;7;low\n';
      final parsed = AlertRecordParser.parseCsvText('export.csv', csv);
      expect(parsed.records.length, 2);
      expect(parsed.records[0].type, 'qualite');
      expect(parsed.records[0].timestamp.day, 5);
      expect(parsed.records[0].timestamp.month, 1);
      expect(parsed.records[0].isCritical, isTrue);
      expect(parsed.records[1].type, 'manque_ressource');
      expect(parsed.records[0].convoyeur, 3);
    });
  });

  group('AlertRecordParser JSON', () {
    test('parses a JSON list', () {
      const json = '[{"timestamp":"2026-02-01T10:00:00Z","type":"maintenance",'
          '"usine":"Plant C","convoyeur":2,"poste":4,"isCritical":false}]';
      final parsed = AlertRecordParser.parseJsonText('a.json', json);
      expect(parsed.records.single.type, 'maintenance');
    });

    test('parses a Firebase RTDB export shape', () {
      const json = '{"alerts":{"-Nabc":{"timestamp":"2026-02-01T10:00:00Z",'
          '"type":"defaut_produit","usine":"Plant C","convoyeur":1,"poste":1},'
          '"-Nabd":{"timestamp":"2026-02-02T11:00:00Z","type":"qualite",'
          '"usine":"Plant C","convoyeur":1,"poste":1}}}';
      final parsed = AlertRecordParser.parseJsonText('export.json', json);
      expect(parsed.records.length, 2);
      expect(parsed.records.first.timestamp.isBefore(parsed.records.last.timestamp), isTrue);
    });
  });

  group('AlertRecordParser SQL', () {
    test('parses a MySQL dump with column list', () {
      const sql = '''
CREATE TABLE `alerts` (
  `id` int NOT NULL,
  `created_at` datetime,
  `alert_type` varchar(50),
  `factory` varchar(50),
  `conveyor` int,
  `station` int,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;
INSERT INTO `alerts` (`id`, `created_at`, `alert_type`, `factory`, `conveyor`, `station`) VALUES
(1, '2026-03-01 08:00:00', 'quality', 'Plant D', 4, 9),
(2, '2026-03-02 09:30:00', 'maintenance', 'Plant D', 4, 9);
''';
      final parsed = AlertRecordParser.parseSqlText('dump.sql', sql);
      expect(parsed.records.length, 2);
      expect(parsed.records.first.type, 'qualite');
      expect(parsed.records.first.usine, 'Plant D');
      expect(parsed.records.first.convoyeur, 4);
    });

    test('rejects dumps without INSERTs', () {
      expect(
        () => AlertRecordParser.parseSqlText('x.sql', 'SELECT 1;'),
        throwsFormatException,
      );
    });
  });

  group('AlertRecordParser PDF text', () {
    test('parses a spaced table extracted from PDF', () {
      const text = '''
Smart Industrial Alert — Export
Date          Type           Factory    Conveyor   Station
2026-04-01    qualite        Plant E    2          5
2026-04-02    maintenance    Plant E    2          5
''';
      final parsed = AlertRecordParser.parsePdfText('report.pdf', text);
      expect(parsed.records.length, 2);
      expect(parsed.records.first.usine, 'Plant E');
    });
  });

  group('parseFlexibleTimestamp', () {
    test('handles ISO, epoch and European dates', () {
      expect(AlertRecordParser.parseFlexibleTimestamp('2026-01-02T03:04:05Z'),
          isNotNull);
      expect(
          AlertRecordParser.parseFlexibleTimestamp(1767312000000), isNotNull);
      expect(AlertRecordParser.parseFlexibleTimestamp(1767312000), isNotNull);
      final eu = AlertRecordParser.parseFlexibleTimestamp('31/12/2025');
      expect(eu!.day, 31);
      expect(eu.month, 12);
      expect(AlertRecordParser.parseFlexibleTimestamp('garbage'), isNull);
    });
  });

  group('normalizeType', () {
    test('maps synonyms onto canonical types', () {
      expect(AlertRecordParser.normalizeType('Quality issue'), 'qualite');
      expect(AlertRecordParser.normalizeType('MAINTENANCE'), 'maintenance');
      expect(AlertRecordParser.normalizeType('Damaged product'), 'defaut_produit');
      expect(AlertRecordParser.normalizeType('missing stock'), 'manque_ressource');
      expect(AlertRecordParser.normalizeType('Electrical Fault'), 'electrical_fault');
    });
  });
}
