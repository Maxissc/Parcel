import 'package:flutter_test/flutter_test.dart';

import '../../tool/dev_addon.dart';

void main() {
  group('parseByteRange', () {
    test('sin Range sirve el archivo entero', () {
      final r = parseByteRange(null, 1000)!;
      expect((r.start, r.end, r.partial), (0, 999, false));
    });

    test('un tramo válido, un tramo abierto y los últimos bytes', () {
      expect(parseByteRange('bytes=10-19', 1000)!.start, 10);
      final open = parseByteRange('bytes=500-', 1000)!;
      expect((open.start, open.end, open.partial), (500, 999, true));
      final tail = parseByteRange('bytes=-100', 1000)!;
      expect((tail.start, tail.end), (900, 999));
    });

    test('un final pasado del archivo se recorta', () {
      final r = parseByteRange('bytes=900-5000', 1000)!;
      expect((r.start, r.end), (900, 999));
      expect(parseByteRange('bytes=-5000', 1000)!.start, 0);
    });

    test('los rangos que no se pueden cumplir dan null (416)', () {
      expect(parseByteRange('bytes=1000-', 1000), isNull);
      expect(parseByteRange('bytes=5000-6000', 1000), isNull);
      expect(parseByteRange('bytes=20-10', 1000), isNull);
      expect(parseByteRange('bytes=-', 1000), isNull);
      expect(parseByteRange('bytes=-0', 1000), isNull);
      expect(parseByteRange('bytes=0-10', 0), isNull);
    });

    test('un encabezado que no es de bytes se ignora', () {
      expect(parseByteRange('items=1-2', 1000)!.partial, isFalse);
    });
  });
}
