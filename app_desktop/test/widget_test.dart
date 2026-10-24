import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/main.dart';

void main() {
  testWidgets('monta la app y muestra Parcel', (WidgetTester tester) async {
    await tester.pumpWidget(const ParcelApp());

    expect(find.text('Parcel'), findsWidgets);
  });
}
