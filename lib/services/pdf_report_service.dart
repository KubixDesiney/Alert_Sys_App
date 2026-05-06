import '../models/alert_model.dart';
import '../models/shift_model.dart';
import 'alert_pdf_service.dart';
import 'shift_pdf_service.dart';

/// Thin facade that exposes both PDF report flavors behind one entry point.
/// Lets callers depend on a single class while the underlying templates
/// continue to live in their topic-specific implementations. Shared
/// formatting and palette logic lives in `lib/services/pdf/pdf_common.dart`.
class PdfReportService {
  const PdfReportService._();

  /// Export the current alert list to a landscape A4 PDF and either download
  /// it (web) or open the platform share sheet (mobile).
  static Future<void> exportAlertsReport({
    required List<AlertModel> alerts,
    required String scopeLabel,
    required String timeRangeLabel,
    String Function(String type)? labelType,
  }) {
    return AlertPdfService.exportAndShare(
      alerts: alerts,
      scopeLabel: scopeLabel,
      timeRangeLabel: timeRangeLabel,
      labelType: labelType,
    );
  }

  /// Export an audit-ready shift activity report covering [day]'s window of
  /// the given [shift], including AI Commander actions, supervisor readiness
  /// and the optional handover summary.
  static Future<void> exportShiftReport({
    required ShiftModel shift,
    required DateTime day,
  }) {
    return ShiftPdfService.exportAndShare(shift: shift, day: day);
  }
}
