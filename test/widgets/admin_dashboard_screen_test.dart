import 'package:alertsysapp/providers/theme_provider.dart';
import 'package:alertsysapp/screens/admin_dashboard_screen.dart';
import 'package:alertsysapp/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AdminDashboardScreen renders top-level tabs', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const AdminDashboardScreen(),
        ),
      ),
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Supervisors'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Escalations'), findsOneWidget);
    expect(find.text('Hierarchy'), findsOneWidget);
  });
}
