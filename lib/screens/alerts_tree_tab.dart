import 'package:flutter/material.dart';

import '../models/alert_model.dart';
import 'alert_tree_visualization.dart';

class AlertsTreeTab extends StatelessWidget {
  final List<AlertModel> alerts;

  const AlertsTreeTab({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    return AlertTreeVisualization(alerts: alerts);
  }
}
