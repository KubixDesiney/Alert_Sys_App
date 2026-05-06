import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/alert_model.dart';
import '../../providers/alert_provider.dart';

/// Live "elapsed since claim" indicator. Watches [AlertProvider] so it ticks
/// in step with the dashboard's 1-second clock without holding its own timer.
class ElapsedTimer extends StatelessWidget {
  final AlertModel alert;
  final AlertProvider provider;

  const ElapsedTimer({
    super.key,
    required this.alert,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<AlertProvider>();
    final elapsed = provider.getElapsedTime(alert);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        border: Border.all(color: const Color(0xFF93C5FD)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, size: 15, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Elapsed time: $elapsed',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D4ED8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
