import 'package:flutter/material.dart';

import '../../theme.dart';

/// Branded empty / error state. Use across lists, panels and dialogs in place
/// of bespoke `Center(Text('No data'))` layouts.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.iconColor,
    this.action,
    this.compact = false,
  });

  /// Variant for error states — red icon and softer messaging.
  factory AppEmptyState.error({
    Key? key,
    required String title,
    String? message,
    Widget? action,
  }) =>
      _ErrorEmptyState(
          key: key, title: title, message: message, action: action);

  final String title;
  final String? message;
  final IconData icon;
  final Color? iconColor;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final color = iconColor ?? t.muted;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 24, vertical: compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 36 : 56, color: color),
            SizedBox(height: compact ? 8 : 16),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  color: t.muted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorEmptyState extends AppEmptyState {
  const _ErrorEmptyState({
    super.key,
    required super.title,
    super.message,
    super.action,
  }) : super(icon: Icons.error_outline);

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return AppEmptyState(
      title: title,
      message: message,
      icon: Icons.error_outline,
      iconColor: t.red,
      action: action,
    );
  }
}
