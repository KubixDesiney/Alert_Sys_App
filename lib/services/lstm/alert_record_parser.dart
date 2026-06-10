import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'lstm_types.dart';

/// Result of ingesting one uploaded file.
class ParsedDataset {
  final List<AlertRecord> records;
  final DatasetSummary summary;
  final List<String> warnings;

  const ParsedDataset({
    required this.records,
    required this.summary,
    required this.warnings,
  });
}

/// Universal alert-history ingester. Accepts CSV, JSON (including Firebase
/// RTDB exports), Excel (.xlsx), SQL dumps (MySQL/MariaDB `INSERT` scripts)
/// and PDF tables, and normalizes everything into [AlertRecord]s ready for
/// LSTM feature engineering.
class AlertRecordParser {
  static const _timestampKeys = {
    'timestamp', 'date', 'datetime', 'created_at', 'createdat', 'time', 'ts',
    'alert_date', 'alertdate', 'occurred_at', 'occurredat', 'event_time',
    'eventtime', 'reported_at', 'horodatage',
  };
  static const _typeKeys = {
    'type', 'alert_type', 'alerttype', 'category', 'categorie', 'issue',
    'issue_type', 'kind', 'nature', 'defect_type',
  };
  static const _usineKeys = {
    'usine', 'factory', 'plant', 'site', 'factory_name', 'factoryname',
    'factory_id', 'factoryid', 'location', 'workshop',
  };
  static const _convoyeurKeys = {
    'convoyeur', 'conveyor', 'line', 'conveyor_number', 'conveyornumber',
    'ligne', 'belt',
  };
  static const _posteKeys = {
    'poste', 'station', 'workstation', 'post', 'station_number',
    'stationnumber', 'position',
  };
  static const _criticalKeys = {
    'iscritical', 'is_critical', 'critical', 'critique', 'severity',
    'priority', 'priorite',
  };

  /// Entry point: dispatches by file extension.
  static Future<ParsedDataset> parse({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv') || lower.endsWith('.txt') || lower.endsWith('.tsv')) {
      return parseCsvText(fileName, _decodeText(bytes));
    }
    if (lower.endsWith('.json')) {
      return parseJsonText(fileName, _decodeText(bytes));
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return parseXlsxBytes(fileName, bytes);
    }
    if (lower.endsWith('.sql') || lower.endsWith('.dump')) {
      return parseSqlText(fileName, _decodeText(bytes));
    }
    if (lower.endsWith('.pdf')) {
      return parsePdfBytes(fileName, bytes);
    }
    throw FormatException(
      'Unsupported file type "$fileName". Supported: CSV, TSV, JSON, XLSX, '
      'SQL dump, PDF.',
    );
  }

  static String _decodeText(Uint8List bytes) {
    // Strip BOMs and fall back through common encodings.
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      // UTF-16 LE
      final codes = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        codes.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(codes);
    }
    try {
      var text = utf8.decode(bytes);
      if (text.startsWith('﻿')) text = text.substring(1);
      return text;
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  // ── CSV ─────────────────────────────────────────────────────────────────

  static ParsedDataset parseCsvText(String fileName, String text) {
    final firstLine = text.split(RegExp(r'\r?\n')).firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        );
    final delimiter = _detectDelimiter(firstLine);
    final rows = CsvToListConverter(
      fieldDelimiter: delimiter,
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(text.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) {
      throw const FormatException('The CSV file is empty.');
    }
    final header = rows.first.map((e) => e.toString()).toList();
    return _fromTable(
      fileName,
      'csv',
      header,
      rows.skip(1).map((r) => r.map((e) => e as dynamic).toList()).toList(),
    );
  }

  static String _detectDelimiter(String line) {
    final candidates = {',': 0, ';': 0, '\t': 0, '|': 0};
    for (final c in candidates.keys) {
      candidates[c] = line.split(c).length - 1;
    }
    var best = ',';
    var bestCount = -1;
    candidates.forEach((k, v) {
      if (v > bestCount) {
        best = k;
        bestCount = v;
      }
    });
    return best;
  }

  // ── JSON ────────────────────────────────────────────────────────────────

  static ParsedDataset parseJsonText(String fileName, String text) {
    final decoded = jsonDecode(text);
    Iterable<Map<String, dynamic>> objects;
    if (decoded is List) {
      objects = decoded.whereType<Map>().map(Map<String, dynamic>.from);
    } else if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      // Firebase export shapes: { alerts: { id: {...} } } or { id: {...} }.
      final alerts = map['alerts'];
      if (alerts is Map) {
        objects = alerts.values.whereType<Map>().map(Map<String, dynamic>.from);
      } else if (map.values.every((v) => v is Map)) {
        objects = map.values.whereType<Map>().map(Map<String, dynamic>.from);
      } else {
        objects = [map];
      }
    } else {
      throw const FormatException('JSON must contain a list or map of alerts.');
    }

    final records = <AlertRecord>[];
    var skipped = 0;
    for (final obj in objects) {
      final normalized = <String, dynamic>{};
      obj.forEach((k, v) => normalized[_normKey(k)] = v);
      final record = _recordFromKeyed(normalized);
      if (record != null) {
        records.add(record);
      } else {
        skipped++;
      }
    }
    return _finish(fileName, 'json', records, records.length + skipped, skipped);
  }

  // ── Excel ───────────────────────────────────────────────────────────────

  static ParsedDataset parseXlsxBytes(String fileName, Uint8List bytes) {
    final book = xls.Excel.decodeBytes(bytes);
    for (final table in book.tables.values) {
      if (table.rows.isEmpty) continue;
      final header =
          table.rows.first.map((c) => _cellToDynamic(c?.value)?.toString() ?? '').toList();
      if (!_looksLikeHeader(header)) continue;
      final dataRows = <List<dynamic>>[];
      for (final row in table.rows.skip(1)) {
        dataRows.add(row.map((c) => _cellToDynamic(c?.value)).toList());
      }
      return _fromTable(fileName, 'excel', header, dataRows);
    }
    throw const FormatException(
      'No sheet with a recognizable header row (need at least a date and a '
      'type column).',
    );
  }

  static dynamic _cellToDynamic(xls.CellValue? v) {
    if (v == null) return null;
    if (v is xls.TextCellValue) return v.value.toString();
    if (v is xls.IntCellValue) return v.value;
    if (v is xls.DoubleCellValue) return v.value;
    if (v is xls.BoolCellValue) return v.value;
    if (v is xls.DateCellValue) return v.asDateTimeUtc();
    if (v is xls.DateTimeCellValue) return v.asDateTimeUtc();
    return v.toString();
  }

  // ── SQL dump ────────────────────────────────────────────────────────────

  static ParsedDataset parseSqlText(String fileName, String text) {
    // Column list from INSERT … (col, col) VALUES, falling back to the
    // CREATE TABLE definition when the dump omits column names.
    final insertRe = RegExp(
      r'INSERT\s+INTO\s+`?(\w+)`?\s*(?:\(([^)]*)\))?\s*VALUES\s*',
      caseSensitive: false,
    );
    final createRe = RegExp(
      r'CREATE\s+TABLE\s+`?(\w+)`?\s*\(([\s\S]*?)\)\s*(?:ENGINE|;)',
      caseSensitive: false,
    );

    List<String>? createColumns;
    final createMatch = createRe.firstMatch(text);
    if (createMatch != null) {
      createColumns = createMatch
          .group(2)!
          .split('\n')
          .map((l) => l.trim())
          .where((l) =>
              l.isNotEmpty &&
              !RegExp(r'^(PRIMARY|UNIQUE|KEY|CONSTRAINT|FOREIGN|INDEX)',
                      caseSensitive: false)
                  .hasMatch(l))
          .map((l) => l.split(RegExp(r'\s+')).first.replaceAll('`', ''))
          .toList();
    }

    final records = <AlertRecord>[];
    var total = 0;
    var skipped = 0;
    for (final match in insertRe.allMatches(text)) {
      final columns = match.group(2) != null
          ? match
              .group(2)!
              .split(',')
              .map((c) => c.trim().replaceAll('`', '').replaceAll('"', ''))
              .toList()
          : createColumns;
      if (columns == null) continue;

      final tuples = _readSqlTuples(text, match.end);
      for (final tuple in tuples) {
        total++;
        if (tuple.length != columns.length) {
          skipped++;
          continue;
        }
        final keyed = <String, dynamic>{};
        for (var i = 0; i < columns.length; i++) {
          keyed[_normKey(columns[i])] = tuple[i];
        }
        final record = _recordFromKeyed(keyed);
        if (record != null) {
          records.add(record);
        } else {
          skipped++;
        }
      }
    }
    if (total == 0) {
      throw const FormatException(
        'No INSERT statements found. Export your MySQL table as a .sql dump '
        'with data (mysqldump) or as CSV.',
      );
    }
    return _finish(fileName, 'sql', records, total, skipped);
  }

  /// Reads `(v, v, …), (…)…;` value tuples starting at [start], respecting
  /// quoted strings and escapes.
  static List<List<String?>> _readSqlTuples(String text, int start) {
    final tuples = <List<String?>>[];
    var i = start;
    while (i < text.length) {
      while (i < text.length && (text[i] == ' ' || text[i] == '\n' || text[i] == '\r' || text[i] == ',')) {
        i++;
      }
      if (i >= text.length || text[i] != '(') break;
      i++;
      final values = <String?>[];
      final buf = StringBuffer();
      var inQuote = false;
      var quoteChar = "'";
      var sawQuote = false;
      while (i < text.length) {
        final ch = text[i];
        if (inQuote) {
          if (ch == '\\' && i + 1 < text.length) {
            buf.write(text[i + 1]);
            i += 2;
            continue;
          }
          if (ch == quoteChar) {
            if (i + 1 < text.length && text[i + 1] == quoteChar) {
              buf.write(quoteChar);
              i += 2;
              continue;
            }
            inQuote = false;
            i++;
            continue;
          }
          buf.write(ch);
          i++;
          continue;
        }
        if (ch == "'" || ch == '"') {
          inQuote = true;
          sawQuote = true;
          quoteChar = ch;
          i++;
          continue;
        }
        if (ch == ',' || ch == ')') {
          final raw = buf.toString().trim();
          values.add(!sawQuote && raw.toUpperCase() == 'NULL' ? null : raw);
          buf.clear();
          sawQuote = false;
          i++;
          if (ch == ')') break;
          continue;
        }
        buf.write(ch);
        i++;
      }
      tuples.add(values);
      // Stop at statement end.
      while (i < text.length && (text[i] == ' ' || text[i] == '\n' || text[i] == '\r')) {
        i++;
      }
      if (i < text.length && text[i] == ';') break;
    }
    return tuples;
  }

  // ── PDF ─────────────────────────────────────────────────────────────────

  static ParsedDataset parsePdfBytes(String fileName, Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();
    return parsePdfText(fileName, text);
  }

  static ParsedDataset parsePdfText(String fileName, String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Attempt 1: a delimited table with a header line.
    for (var i = 0; i < lines.length; i++) {
      final cells = _splitPdfLine(lines[i]);
      if (cells.length >= 2 && _looksLikeHeader(cells)) {
        final dataRows = <List<dynamic>>[];
        for (final line in lines.skip(i + 1)) {
          final row = _splitPdfLine(line);
          if (row.length >= 2) dataRows.add(row);
        }
        try {
          final parsed = _fromTable(fileName, 'pdf', cells, dataRows);
          if (parsed.records.isNotEmpty) return parsed;
        } on FormatException {
          // fall through to the heuristic scan
        }
        break;
      }
    }

    // Attempt 2: heuristic per-line scan — find a date plus a type keyword.
    final dateRe = RegExp(
        r'(\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?)?|\d{1,2}/\d{1,2}/\d{4}(?: \d{2}:\d{2}(?::\d{2})?)?)');
    final records = <AlertRecord>[];
    var skipped = 0;
    for (final line in lines) {
      final dateMatch = dateRe.firstMatch(line);
      if (dateMatch == null) continue;
      final ts = parseFlexibleTimestamp(dateMatch.group(0));
      if (ts == null) {
        skipped++;
        continue;
      }
      final type = _findTypeKeyword(line);
      if (type == null) {
        skipped++;
        continue;
      }
      final conv = RegExp(r'(?:conv\w*|line|ligne)\s*[:#]?\s*(\d+)',
              caseSensitive: false)
          .firstMatch(line);
      final poste = RegExp(r'(?:poste|station|post)\s*[:#]?\s*(\d+)',
              caseSensitive: false)
          .firstMatch(line);
      final usine = RegExp(r'(?:usine|factory|plant|site)\s*[:#]?\s*([\w\- ]+?)(?:\s{2,}|$|[,;|])',
              caseSensitive: false)
          .firstMatch(line);
      records.add(AlertRecord(
        timestamp: ts,
        type: type,
        usine: usine?.group(1)?.trim() ?? 'Factory',
        convoyeur: int.tryParse(conv?.group(1) ?? '') ?? 0,
        poste: int.tryParse(poste?.group(1) ?? '') ?? 0,
        isCritical: RegExp(r'critic|critique', caseSensitive: false).hasMatch(line),
      ));
    }
    if (records.isEmpty) {
      throw const FormatException(
        'Could not find an alert table in this PDF. Export the data as CSV '
        'or Excel for best results.',
      );
    }
    return _finish(fileName, 'pdf', records, records.length + skipped, skipped);
  }

  static List<String> _splitPdfLine(String line) {
    for (final sep in [RegExp(r'\s{2,}'), RegExp(r'\t'), RegExp(r'[;|]')]) {
      final parts = line.split(sep).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 3) return parts;
    }
    return [line];
  }

  // ── Shared table → records pipeline ─────────────────────────────────────

  static bool _looksLikeHeader(List<String> cells) {
    final normalized = cells.map(_normKey).toSet();
    final hasDate = normalized.any(_timestampKeys.contains);
    final hasType = normalized.any(_typeKeys.contains);
    return hasDate && hasType;
  }

  static ParsedDataset _fromTable(
    String fileName,
    String kind,
    List<String> header,
    List<List<dynamic>> rows,
  ) {
    final idx = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      idx[_normKey(header[i])] = i;
    }
    int? find(Set<String> keys) {
      for (final k in keys) {
        if (idx.containsKey(k)) return idx[k];
      }
      return null;
    }

    final tsIdx = find(_timestampKeys);
    if (tsIdx == null) {
      throw FormatException(
        'No timestamp/date column found. Headers seen: ${header.join(', ')}',
      );
    }
    final typeIdx = find(_typeKeys);
    final usineIdx = find(_usineKeys);
    final convIdx = find(_convoyeurKeys);
    final posteIdx = find(_posteKeys);
    final critIdx = find(_criticalKeys);

    dynamic at(List<dynamic> row, int? i) =>
        i == null || i >= row.length ? null : row[i];

    final records = <AlertRecord>[];
    var skipped = 0;
    for (final row in rows) {
      if (row.every((c) => c == null || c.toString().trim().isEmpty)) continue;
      final ts = parseFlexibleTimestamp(at(row, tsIdx));
      if (ts == null) {
        skipped++;
        continue;
      }
      records.add(AlertRecord(
        timestamp: ts,
        type: normalizeType(at(row, typeIdx)?.toString()),
        usine: at(row, usineIdx)?.toString().trim().isNotEmpty == true
            ? at(row, usineIdx).toString().trim()
            : 'Factory',
        convoyeur: _asInt(at(row, convIdx)),
        poste: _asInt(at(row, posteIdx)),
        isCritical: _asCritical(at(row, critIdx)),
      ));
    }
    return _finish(fileName, kind, records, rows.length, skipped);
  }

  static ParsedDataset _finish(
    String fileName,
    String kind,
    List<AlertRecord> records,
    int totalRows,
    int skipped,
  ) {
    if (records.isEmpty) {
      throw FormatException(
        'No usable alert rows were found in "$fileName" '
        '($totalRows rows scanned).',
      );
    }
    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final typeCounts = <String, int>{};
    final factoryCounts = <String, int>{};
    final machines = <String>{};
    for (final r in records) {
      typeCounts[r.type] = (typeCounts[r.type] ?? 0) + 1;
      factoryCounts[r.usine] = (factoryCounts[r.usine] ?? 0) + 1;
      machines.add(r.machineKey);
    }
    final warnings = <String>[];
    if (skipped > 0) {
      warnings.add('$skipped rows skipped (missing or unparseable fields).');
    }
    final unknownShare =
        (typeCounts['unknown'] ?? 0) / records.length;
    if (unknownShare > 0.5) {
      warnings.add(
        'More than half the rows have unrecognized alert types — type-level '
        'forecasts will be weak.',
      );
    }
    return ParsedDataset(
      records: records,
      warnings: warnings,
      summary: DatasetSummary(
        sourceName: fileName,
        sourceKind: kind,
        totalRows: totalRows,
        parsedRows: records.length,
        skippedRows: skipped,
        typeCounts: typeCounts,
        factoryCounts: factoryCounts,
        firstTimestamp: records.first.timestamp,
        lastTimestamp: records.last.timestamp,
        machineCount: machines.length,
      ),
    );
  }

  static AlertRecord? _recordFromKeyed(Map<String, dynamic> keyed) {
    dynamic firstOf(Set<String> keys) {
      for (final k in keys) {
        if (keyed.containsKey(k) && keyed[k] != null) return keyed[k];
      }
      return null;
    }

    final ts = parseFlexibleTimestamp(firstOf(_timestampKeys));
    if (ts == null) return null;
    final usineRaw = firstOf(_usineKeys)?.toString().trim();
    return AlertRecord(
      timestamp: ts,
      type: normalizeType(firstOf(_typeKeys)?.toString()),
      usine: usineRaw == null || usineRaw.isEmpty ? 'Factory' : usineRaw,
      convoyeur: _asInt(firstOf(_convoyeurKeys)),
      poste: _asInt(firstOf(_posteKeys)),
      isCritical: _asCritical(firstOf(_criticalKeys)),
    );
  }

  static String _normKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Maps free-form type labels onto the four canonical types the network
  /// predicts; anything else is kept as a sanitized label (it still counts
  /// toward totals and days-since-failure features).
  static String normalizeType(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t.isEmpty) return 'unknown';
    if (t.contains('qual')) return 'qualite';
    if (t.contains('mainten') || t.contains('entretien')) return 'maintenance';
    if (t.contains('defaut') || t.contains('defect') || t.contains('damag') ||
        t.contains('produit') || t.contains('product')) {
      return 'defaut_produit';
    }
    if (t.contains('ressource') || t.contains('resource') ||
        t.contains('shortage') || t.contains('manque') || t.contains('stock')) {
      return 'manque_ressource';
    }
    return t.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
  }

  static bool _asCritical(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v >= 1;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'oui' ||
        s == 'critical' || s == 'critique' || s == 'high' || s == 'haute';
  }

  /// Parses ISO strings, epoch seconds/millis, `dd/MM/yyyy`, `MM/dd/yyyy`
  /// and Excel serial dates.
  static DateTime? parseFlexibleTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is num) return _fromNumericDate(raw);

    final s = raw.toString().trim().replaceAll('"', '').replaceAll("'", '');
    if (s.isEmpty) return null;

    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;

    final asNum = num.tryParse(s);
    if (asNum != null) return _fromNumericDate(asNum);

    // dd/MM/yyyy or MM/dd/yyyy with optional time.
    final m = RegExp(
            r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$')
        .firstMatch(s);
    if (m != null) {
      var a = int.parse(m.group(1)!);
      var b = int.parse(m.group(2)!);
      final year = int.parse(m.group(3)!);
      // Disambiguate: if the first component cannot be a month, it's a day.
      int day, month;
      if (a > 12) {
        day = a;
        month = b;
      } else if (b > 12) {
        day = b;
        month = a;
      } else {
        day = a;
        month = b; // assume dd/MM (European convention used by the plant)
      }
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return DateTime(
        year,
        month,
        day,
        int.tryParse(m.group(4) ?? '') ?? 0,
        int.tryParse(m.group(5) ?? '') ?? 0,
        int.tryParse(m.group(6) ?? '') ?? 0,
      );
    }
    return null;
  }

  static DateTime? _fromNumericDate(num value) {
    final v = value.toDouble();
    if (v > 1000000000000) {
      // epoch milliseconds
      return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    }
    if (v > 1000000000) {
      // epoch seconds
      return DateTime.fromMillisecondsSinceEpoch((v * 1000).toInt(), isUtc: true);
    }
    if (v > 20000 && v < 80000) {
      // Excel serial date (days since 1899-12-30)
      final ms = ((v - 25569) * 86400000).round();
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    return null;
  }

  static String? _findTypeKeyword(String line) {
    final l = line.toLowerCase();
    if (l.contains('qual')) return 'qualite';
    if (l.contains('mainten')) return 'maintenance';
    if (l.contains('defaut') || l.contains('defect') || l.contains('damag')) {
      return 'defaut_produit';
    }
    if (l.contains('ressource') || l.contains('resource') || l.contains('shortage') || l.contains('manque')) {
      return 'manque_ressource';
    }
    return null;
  }
}
