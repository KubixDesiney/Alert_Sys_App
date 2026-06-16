part of 'admin_escalation_screen.dart';

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _service = CollaborationService();
  EscalationSettings? _settings;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _service.getEscalationSettings();
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;
    setState(() => _saving = true);
    await _service.saveEscalationSettings(_settings!);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: context.appTheme.green,
        ),
      );
    }
  }

  void _updateThreshold(String type, int unclaimed, int claimed) {
    if (_settings == null) return;
    final newThresholds = Map<String, EscalationThreshold>.from(
      _settings!.thresholds,
    );
    newThresholds[type] = EscalationThreshold(
      type: type,
      unclaimedMinutes: unclaimed,
      claimedMinutes: claimed,
    );
    setState(() {
      _settings = EscalationSettings(thresholds: newThresholds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.navy));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings, color: t.navy, size: 20),
              const SizedBox(width: 8),
              Text(
                'Escalation Time Thresholds',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: t.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure default time limits before alerts are escalated to your attention',
            style: TextStyle(fontSize: 12, color: t.muted),
          ),
          const SizedBox(height: 16),
          // Info Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: t.isDark
                    ? [t.yellowLt.withOpacity(0.4), t.yellowLt.withOpacity(0.2)]
                    : [t.yellowLt, t.yellowLt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.yellow.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: t.yellow, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'How Escalation Works:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: t.isDark
                            ? const Color(0xFFFFE0A0)
                            : const Color(0xFF78350F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildInfoBullet(
                  t,
                  'Unclaimed Alert Threshold: Time before an unclaimed alert is escalated',
                ),
                _buildInfoBullet(
                  t,
                  'Claimed Alert Threshold: Time a supervisor has to fix a claimed alert before escalation',
                ),
                _buildInfoBullet(
                  t,
                  'Escalated alerts appear in the "Escalated Alerts" section for immediate attention',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Threshold cards
          _ThresholdCard(
            type: 'qualite',
            label: 'Quality Issues',
            color: t.red,
            bgColor: t.redLt,
            icon: Icons.warning_amber_rounded,
            threshold: _settings!.thresholds['qualite']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('qualite', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'maintenance',
            label: 'Maintenance',
            color: t.blue,
            bgColor: t.blueLt,
            icon: Icons.build_circle,
            threshold: _settings!.thresholds['maintenance']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('maintenance', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'defaut_produit',
            label: 'Damaged Product',
            color: t.green,
            bgColor: t.greenLt,
            icon: Icons.cancel,
            threshold: _settings!.thresholds['defaut_produit']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('defaut_produit', unclaimed, claimed),
          ),
          const SizedBox(height: 16),
          _ThresholdCard(
            type: 'manque_ressource',
            label: 'Resource Deficiency',
            color: t.orange,
            bgColor: t.orangeLt,
            icon: Icons.inventory_2,
            threshold: _settings!.thresholds['manque_ressource']!,
            onUpdate: (unclaimed, claimed) =>
                _updateThreshold('manque_ressource', unclaimed, claimed),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _saving
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Settings',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBullet(AppTheme t, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 11,
              color: t.isDark
                  ? const Color(0xFFFFE0A0)
                  : const Color(0xFF78350F),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: t.isDark
                    ? const Color(0xFFFFF3CC)
                    : const Color(0xFF78350F),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThresholdCard extends StatefulWidget {
  final String type, label;
  final Color color, bgColor;
  final IconData icon;
  final EscalationThreshold threshold;
  final Function(int unclaimed, int claimed) onUpdate;

  const _ThresholdCard({
    required this.type,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.threshold,
    required this.onUpdate,
  });

  @override
  State<_ThresholdCard> createState() => _ThresholdCardState();
}

class _ThresholdCardState extends State<_ThresholdCard> {
  late TextEditingController _unclaimedController;
  late TextEditingController _claimedController;

  @override
  void initState() {
    super.initState();
    _unclaimedController = TextEditingController(
      text: widget.threshold.unclaimedMinutes.toString(),
    );
    _claimedController = TextEditingController(
      text: widget.threshold.claimedMinutes.toString(),
    );
  }

  @override
  void dispose() {
    _unclaimedController.dispose();
    _claimedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    // Dark mode: add subtle inner gradient to the card for depth
    final cardDecoration = BoxDecoration(
      gradient: t.isDark
          ? LinearGradient(
              colors: [widget.bgColor, widget.bgColor.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      color: t.isDark ? null : widget.bgColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: widget.color.withOpacity(0.3)),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icon, color: widget.color, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: widget.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unclaimed Alert Threshold',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: t.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.border),
                              boxShadow: t.isDark
                                  ? [
                                      BoxShadow(
                                        color: widget.color.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: TextField(
                              controller: _unclaimedController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: t.text,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                              onChanged: (value) {
                                final unclaimed = int.tryParse(value) ?? 0;
                                final claimed =
                                    int.tryParse(_claimedController.text) ?? 0;
                                widget.onUpdate(unclaimed, claimed);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'minutes',
                          style: TextStyle(fontSize: 11, color: widget.color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Alert escalates if not claimed within this time',
                      style: TextStyle(
                        fontSize: 10,
                        color: widget.color.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Claimed Alert Threshold',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: t.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: t.border),
                              boxShadow: t.isDark
                                  ? [
                                      BoxShadow(
                                        color: widget.color.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: TextField(
                              controller: _claimedController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: t.text,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                              onChanged: (value) {
                                final unclaimed =
                                    int.tryParse(_unclaimedController.text) ??
                                    0;
                                final claimed = int.tryParse(value) ?? 0;
                                widget.onUpdate(unclaimed, claimed);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'minutes',
                          style: TextStyle(fontSize: 11, color: widget.color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Alert escalates if claimed but not fixed within this time',
                      style: TextStyle(
                        fontSize: 10,
                        color: widget.color.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: widget.color.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: t.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.bgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Unclaimed',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: t.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('→', style: TextStyle(fontSize: 10, color: t.muted)),
                    const SizedBox(width: 6),
                    Text(
                      'Escalates after ${_unclaimedController.text} min',
                      style: TextStyle(fontSize: 10, color: widget.color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.bgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Claimed',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: t.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('→', style: TextStyle(fontSize: 10, color: t.muted)),
                    const SizedBox(width: 6),
                    Text(
                      'Escalates after ${_claimedController.text} min without fix',
                      style: TextStyle(fontSize: 10, color: widget.color),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
