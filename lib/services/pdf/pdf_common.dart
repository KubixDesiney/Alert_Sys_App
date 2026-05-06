import 'package:pdf/pdf.dart';

/// Shared color palette used by every PDF export. Centralizing here removes
/// the per-service `_Pal` / `_PdfPalette` duplication.
class PdfPalette {
  const PdfPalette._();

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

/// Replaces unicode glyphs that the bundled PDF font can't render.
class PdfTextSafe {
  const PdfTextSafe._();

  /// Full normalization (used by AlertPdf): em/en/minus/middle dot, smart
  /// quotes, ellipsis, bullet.
  static String normalize(String value) {
    return value
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('−', '-')
        .replaceAll('·', '-')
        .replaceAll('•', '*')
        .replaceAll('…', '...')
        .replaceAll('"', '"')
        .replaceAll('"', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");
  }

  static String truncate(String value, {required int maxChars}) {
    final v = normalize(value).trim();
    if (v.length <= maxChars) return v;
    if (maxChars <= 3) return v.substring(0, maxChars);
    return '${v.substring(0, maxChars - 3)}...';
  }
}

/// Date / time / elapsed-minutes formatters used in PDF rendering.
class PdfFmt {
  const PdfFmt._();

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `dd/MM/yyyy  HH:mm`
  static String dateTime(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}  ${_two(d.hour)}:${_two(d.minute)}';

  /// `dd/MM/yyyy`
  static String date(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// `HH:mm:ss`
  static String time(DateTime d) =>
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

  /// `yyyyMMdd` — safe for filenames.
  static String dateFile(DateTime d) =>
      '${d.year}${_two(d.month)}${_two(d.day)}';

  /// `5m`, `2h`, `2h 15m`, or '-' when null/zero.
  static String elapsed(int? minutes, {String dashIfBlank = '-'}) {
    if (minutes == null || minutes <= 0) return dashIfBlank;
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// Lowercases, replaces non-alphanumerics with `_`, trims leading/trailing
  /// underscores. Safe for use in filenames.
  static String slug(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}

/// Color tokens for shift-action timeline kinds.
PdfColor pdfActionColor(String kind) {
  switch (kind) {
    case 'created':
      return PdfPalette.orange;
    case 'claimed':
      return PdfPalette.blue;
    case 'resolved':
      return PdfPalette.green;
    case 'ai_assigned':
      return PdfPalette.purple;
    case 'escalated':
      return PdfPalette.red;
    case 'handover':
      return PdfPalette.aiPink;
    default:
      return PdfPalette.muted;
  }
}

PdfColor pdfWithAlpha(PdfColor c, double alpha) =>
    PdfColor(c.red, c.green, c.blue, alpha.clamp(0.0, 1.0));
