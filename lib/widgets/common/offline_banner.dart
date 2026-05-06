import 'package:flutter/material.dart';

import '../../theme.dart';

/// Thin banner shown when the device is offline. Wiring to a real
/// connectivity stream lives in Phase 5; for now this widget is a
/// presentational primitive that callers control via [isOffline].
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.isOffline,
    this.message = 'You are offline. Changes will sync when reconnected.',
  });

  final bool isOffline;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: !isOffline
          ? const SizedBox.shrink()
          : Material(
              color: t.orange,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
