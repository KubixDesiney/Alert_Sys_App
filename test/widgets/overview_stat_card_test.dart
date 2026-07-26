// Widget tests for the admin Overview tab's EliteStatCard — a high-traffic,
// self-contained stat tile with no Firebase/Provider dependency beyond a
// MaterialApp theme, making it a fast, reliable coverage target.
import 'package:alertsysapp/theme.dart';
import 'package:alertsysapp/widgets/overview/overview_stat_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? buildLightTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders label, value and calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(EliteStatCard(
      label: 'Pending',
      value: 12,
      icon: Icons.pending_actions,
      color: Colors.orange,
      accentLt: Colors.orange.shade50,
      spark: const [1, 2, 3, 4],
      trendPct: 5,
      isActive: false,
      onTap: () => tapped = true,
    )));

    expect(find.text('PENDING'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);

    await tester.tap(find.byType(GestureDetector).first);
    expect(tapped, isTrue);
  });

  testWidgets('shows "No 7-day activity" when the spark line is all zeros', (tester) async {
    await tester.pumpWidget(wrap(EliteStatCard(
      label: 'Resolved',
      value: 0,
      icon: Icons.check_circle,
      color: Colors.green,
      accentLt: Colors.green.shade50,
      spark: const [0, 0, 0],
      trendPct: 0,
      isActive: false,
      onTap: () {},
    )));

    expect(find.text('No 7-day activity'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('renders a critical badge only when criticalCount is positive, and it is tappable', (tester) async {
    var criticalTapped = false;
    await tester.pumpWidget(wrap(EliteStatCard(
      label: 'Active',
      value: 3,
      icon: Icons.warning,
      color: Colors.red,
      accentLt: Colors.red.shade50,
      spark: const [1, 2],
      trendPct: -10,
      isActive: true,
      criticalCount: 2,
      onCriticalTap: () => criticalTapped = true,
      onTap: () {},
    )));

    expect(find.text('2 critical'), findsOneWidget);
    await tester.tap(find.text('2 critical'));
    expect(criticalTapped, isTrue);
  });

  testWidgets('omits the critical badge when criticalCount is null or zero', (tester) async {
    await tester.pumpWidget(wrap(EliteStatCard(
      label: 'Active',
      value: 3,
      icon: Icons.warning,
      color: Colors.red,
      accentLt: Colors.red.shade50,
      spark: const [1, 2],
      trendPct: 0,
      isActive: false,
      onTap: () {},
    )));
    expect(find.textContaining('critical'), findsNothing);

    await tester.pumpWidget(wrap(EliteStatCard(
      label: 'Active',
      value: 3,
      icon: Icons.warning,
      color: Colors.red,
      accentLt: Colors.red.shade50,
      spark: const [1, 2],
      trendPct: 0,
      isActive: false,
      criticalCount: 0,
      onTap: () {},
    )));
    expect(find.textContaining('critical'), findsNothing);
  });

  testWidgets('trend badge shows up/down arrows and flat state correctly', (tester) async {
    await tester.pumpWidget(wrap(EliteStatCard(
      label: 'Up',
      value: 5,
      icon: Icons.trending_up,
      color: Colors.blue,
      accentLt: Colors.blue.shade50,
      spark: const [1, 2],
      trendPct: 12.4,
      isActive: false,
      onTap: () {},
    )));
    expect(find.text('12%'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    await tester.pumpWidget(wrap(EliteStatCard(
      label: 'Down',
      value: 5,
      icon: Icons.trending_down,
      color: Colors.blue,
      accentLt: Colors.blue.shade50,
      spark: const [1, 2],
      trendPct: -8.0,
      isActive: false,
      onTap: () {},
    )));
    expect(find.text('8%'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    await tester.pumpWidget(wrap(EliteStatCard(
      label: 'Flat',
      value: 5,
      icon: Icons.trending_flat,
      color: Colors.blue,
      accentLt: Colors.blue.shade50,
      spark: const [1, 2],
      trendPct: 0.1,
      isActive: false,
      onTap: () {},
    )));
    expect(find.text('0%'), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
  });

  testWidgets('renders correctly against the dark theme too', (tester) async {
    await tester.pumpWidget(wrap(
      EliteStatCard(
        label: 'Dark mode',
        value: 7,
        icon: Icons.dark_mode,
        color: Colors.purple,
        accentLt: Colors.purple.shade900,
        spark: const [3, 1, 4],
        trendPct: 2,
        isActive: true,
        onTap: () {},
      ),
      theme: buildDarkTheme(),
    ));
    expect(find.text('DARK MODE'), findsOneWidget);
  });
}
