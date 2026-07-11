import 'package:alertsysapp/widgets/dashboard/dashboard_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required double textScale, required Brightness brightness}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          bottomNavigationBar: DashboardBottomNav(
            currentIndex: 0,
            onTap: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('bottom nav renders without overflow at 200% text scale',
      (tester) async {
    await tester.pumpWidget(_host(textScale: 2.0, brightness: Brightness.light));
    await tester.pumpAndSettle();
    // A RenderFlex overflow throws a FlutterError in tests — assert none.
    expect(tester.takeException(), isNull);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Locator'), findsOneWidget);
  });

  testWidgets('bottom nav renders at 200% in dark mode without overflow',
      (tester) async {
    await tester.pumpWidget(_host(textScale: 2.0, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom nav tabs expose selected-button semantics',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(textScale: 1.0, brightness: Brightness.light));
    await tester.pumpAndSettle();

    // Each tab is reachable by its accessible label…
    expect(find.bySemanticsLabel('Dashboard'), findsOneWidget);

    // …and the active tab carries the button + selected semantic flags.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Dashboard')),
      containsSemantics(isButton: true, isSelected: true),
    );

    handle.dispose();
  });
}
