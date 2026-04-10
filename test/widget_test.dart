import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:radiance/main.dart';
import 'package:radiance/src/services/local_order_store.dart';
import 'package:radiance/src/services/order_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the Radiance desktop shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      RadianceApp(
        repository: const OrderRepository(localStore: LocalOrderStore()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Radiance'), findsWidgets);
    expect(find.text('New Order'), findsOneWidget);
    expect(find.text('Orders Feed'), findsOneWidget);
    expect(find.text('Save order'), findsOneWidget);
  });
}
