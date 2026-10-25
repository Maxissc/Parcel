import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/shared/media_labels.dart';

void main() {
  test('quedan minutos, redondeando para arriba', () {
    expect(
      remainingLabel(const Duration(minutes: 50), const Duration(minutes: 38)),
      'Quedan 12 min',
    );
    expect(
      remainingLabel(
        const Duration(minutes: 50),
        const Duration(minutes: 38, seconds: 1),
      ),
      'Quedan 12 min',
    );
  });

  test('con más de una hora usa horas y minutos', () {
    expect(
      remainingLabel(const Duration(minutes: 125), const Duration(minutes: 60)),
      'Quedan 1 h 05 min',
    );
  });

  test('sin nada para ver no hay texto', () {
    expect(
      remainingLabel(const Duration(minutes: 50), const Duration(minutes: 50)),
      isNull,
    );
  });
}
