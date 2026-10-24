import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

const _movie = Duration(seconds: 7200);

/// Cues que arrancan al inicio y cuyo último termina en [lastEnd] segundos.
List<SubtitleCue> _cues(double lastEnd) => [
  const SubtitleCue(
    start: Duration(seconds: 10),
    end: Duration(seconds: 12),
    text: 'Primero',
  ),
  SubtitleCue(
    start: Duration(milliseconds: ((lastEnd - 2) * 1000).round()),
    end: Duration(milliseconds: (lastEnd * 1000).round()),
    text: 'Último',
  ),
];

SubtitleAlignment _estimate(double lastEnd, [Duration? duration = _movie]) =>
    SubtitleAlignment.estimate(_cues(lastEnd), duration);

void main() {
  group('likely', () {
    test('termina entre el 85 % y el 100 % de la duración', () {
      expect(_estimate(7080), SubtitleAlignment.likely);
      expect(_estimate(6500), SubtitleAlignment.likely);
      expect(_estimate(7200), SubtitleAlignment.likely);
    });

    test('los bordes: 85 % exacto y 30 s de margen', () {
      expect(_estimate(7200 * 0.85), SubtitleAlignment.likely);
      expect(_estimate(7200 + 30), SubtitleAlignment.likely);
    });

    test('toma el fin más tardío aunque los cues vengan desordenados', () {
      final cues = _cues(7000).reversed.toList();
      expect(
        SubtitleAlignment.estimate(cues, _movie),
        SubtitleAlignment.likely,
      );
    });
  });

  group('fpsMismatch', () {
    test('25 / 23,976: el subtítulo termina 4,3 % más tarde', () {
      expect(_estimate(7200 * 25 / 23.976), SubtitleAlignment.fpsMismatch);
    });

    test('23,976 / 25 (termina 4,1 % antes) queda como likely: no se distingue '
        'de un subtítulo que termina antes de los créditos', () {
      expect(_estimate(7200 * 23.976 / 25), SubtitleAlignment.likely);
    });

    test('25 / 24 marca otra velocidad; 24 / 25 queda como likely', () {
      expect(_estimate(7200 * 25 / 24), SubtitleAlignment.fpsMismatch);
      expect(_estimate(7200 * 24 / 25), SubtitleAlignment.likely);
    });

    test('tolera ±0,6 % alrededor del cociente', () {
      final ratio = 25 / 23.976;
      expect(_estimate(7200 * ratio * 1.005), SubtitleAlignment.fpsMismatch);
      expect(_estimate(7200 * ratio * 0.995), SubtitleAlignment.fpsMismatch);
      expect(_estimate(7200 * ratio * 1.012), SubtitleAlignment.unlikely);
    });

    test('anda también en una duración corta (un episodio de 25 min)', () {
      const episode = Duration(minutes: 25);
      expect(
        _estimate(1500 * 25 / 23.976, episode),
        SubtitleAlignment.fpsMismatch,
      );
    });
  });

  group('unlikely', () {
    test('termina mucho antes', () {
      expect(_estimate(3000), SubtitleAlignment.unlikely);
      expect(_estimate(7200 * 0.84), SubtitleAlignment.unlikely);
    });

    test('termina bastante después y no es un cociente de fps', () {
      expect(_estimate(7200 + 40), SubtitleAlignment.unlikely);
      expect(_estimate(7200 * 1.5), SubtitleAlignment.unlikely);
    });
  });

  group('unknown', () {
    test('sin duración', () {
      expect(_estimate(7000, null), SubtitleAlignment.unknown);
      expect(_estimate(7000, Duration.zero), SubtitleAlignment.unknown);
    });

    test('sin cues', () {
      expect(
        SubtitleAlignment.estimate(const [], _movie),
        SubtitleAlignment.unknown,
      );
    });
  });
}
