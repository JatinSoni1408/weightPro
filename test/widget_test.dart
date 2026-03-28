import 'package:flutter_test/flutter_test.dart';
import 'package:weight_calculator/main.dart';

void main() {
  testWidgets('shows calculator fields', (tester) async {
    await tester.pumpWidget(const WeightCalculatorApp());

    expect(find.text('Weight Calculator'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('Making Charges'), findsOneWidget);
    expect(find.text('Add 3% GST'), findsOneWidget);
    expect(find.text('0.000 gm'), findsOneWidget);
  });
}
