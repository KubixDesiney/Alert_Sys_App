import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/connectivity_service.dart';
import '../../theme.dart';

/// Thin banner shown when the device is offline. Two ways to use it:
///
/// * Without args (`OfflineBanner.live()`) — subscribes to the
///   [ConnectivityService] in the Provider tree and renders automatically.
/// * `OfflineBanner(isOffline: ...)` — caller-controlled for tests/preview.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.isOffline,
    this.message,
  });

  /// Reactive variant. Drop at the top of any [Scaffold] body.
  factory OfflineBanner.live({Key? key, String? message}) =
      _LiveOfflineBanner;

  final bool isOffline;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final text = message ??
        'You are offline. Changes will sync when reconnected.';
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
                          text,
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

class _LiveOfflineBanner extends OfflineBanner {
  const _LiveOfflineBanner({super.key, super.message}) : super(isOffline: true);

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService?>();
    if (connectivity == null) return const SizedBox.shrink();
    return OfflineBanner(isOffline: connectivity.isOffline, message: message);
  }
}
