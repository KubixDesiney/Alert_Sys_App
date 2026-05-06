import 'package:flutter/material.dart';

import '../../theme.dart';

/// Branded, theme-aware loading indicator. Replaces ad-hoc
/// `CircularProgressIndicator()` usages so size, stroke and color stay
/// consistent across the app.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = 32,
    this.strokeWidth = 3,
    this.label,
    this.color,
  });

  /// Compact 18-pixel variant suitable for buttons / inline contexts.
  const AppLoadingIndicator.small({super.key, this.color, this.label})
      : size = 18,
        strokeWidth = 2;

  /// Centered fullscreen variant with optional label below the spinner.
  const AppLoadingIndicator.fullscreen({super.key, this.label, this.color})
      : size = 40,
        strokeWidth = 3.5;

  final double size;
  final double strokeWidth;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final indicator = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? t.navy),
      ),
    );
    if (label == null) return Center(child: indicator);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: 12),
          Text(label!,
              style: TextStyle(color: t.muted, fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
