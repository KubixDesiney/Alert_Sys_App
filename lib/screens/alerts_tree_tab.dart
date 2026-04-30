import 'package:flutter/material.dart';

import '../models/alert_model.dart';
import 'alert_tree_visualization.dart';

class AlertsTreeTab extends StatelessWidget {
  final List<AlertModel> alerts;
  final Future<void> Function(AlertModel alert)? onAssignAssistant;

  const AlertsTreeTab({
    super.key,
    required this.alerts,
    this.onAssignAssistant,
  });

  @override
  Widget build(BuildContext context) {
    return AlertTreeVisualization(
      alerts: alerts,
      onAssignAssistant: onAssignAssistant,
    );
  }
}
