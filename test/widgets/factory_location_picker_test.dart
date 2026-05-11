import 'package:alertsysapp/screens/hierarchy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('factory location picker contains map widget and search bar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FactoryLocationPicker(
          initialSelection: const FactoryLocationSelection(address: ''),
          renderPlatformMap: false,
          onCancel: () {},
          onSave: (_) {},
        ),
      ),
    );

    expect(find.byType(FactoryLocationMap), findsOneWidget);
    expect(
        find.byKey(const Key('factory-location-search-bar')), findsOneWidget);
  });
}
