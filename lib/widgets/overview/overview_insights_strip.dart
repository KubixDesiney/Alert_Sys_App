part of '../../screens/admin_dashboard_screen.dart';

class _Insight {
  final IconData icon;
  final Color color;
  final String text;
  _Insight({required this.icon, required this.color, required this.text});
}

class _InsightsStrip extends StatelessWidget {
  final List<_Insight> insights;
  const _InsightsStrip({required this.insights});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.purple.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 11, color: theme.purple),
                    const SizedBox(width: 4),
                    Text(
                      'INSIGHTS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: theme.purple,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Auto-generated from current data',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...insights.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: i.color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(i.icon, size: 12, color: i.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        i.text,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.text,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
