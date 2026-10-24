import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

void main() {
  group('formatPlaybackTime', () {
    test('menos de una hora usa m:ss', () {
      expect(formatPlaybackTime(Duration.zero), '0:00');
      expect(formatPlaybackTime(const Duration(seconds: 7)), '0:07');
      expect(
        formatPlaybackTime(const Duration(minutes: 12, seconds: 5)),
        '12:05',
      );
    });

    test('una hora o más usa h:mm:ss', () {
      expect(
        formatPlaybackTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatPlaybackTime(const Duration(hours: 10)), '10:00:00');
    });

    test('descarta los milisegundos y trata lo negativo como cero', () {
      expect(formatPlaybackTime(const Duration(milliseconds: 59999)), '0:59');
      expect(formatPlaybackTime(const Duration(seconds: -5)), '0:00');
    });
  });

  group('languagesMatch', () {
    test('compara códigos de 2 y de 3 letras', () {
      expect(languagesMatch('es', 'spa'), isTrue);
      expect(languagesMatch('eng', 'en'), isTrue);
      expect(languagesMatch('fre', 'fr'), isTrue);
      expect(languagesMatch('fra', 'fre'), isTrue);
    });

    test('ignora mayúsculas y región', () {
      expect(languagesMatch('ES-AR', 'spa'), isTrue);
      expect(languagesMatch('pt_BR', 'por'), isTrue);
    });

    test('idiomas distintos o ausentes no coinciden', () {
      expect(languagesMatch('es', 'en'), isFalse);
      expect(languagesMatch(null, 'es'), isFalse);
      expect(languagesMatch('', 'es'), isFalse);
    });

    test('un código desconocido solo coincide consigo mismo', () {
      expect(languagesMatch('tlh', 'tlh'), isTrue);
      expect(languagesMatch('tlh', 'es'), isFalse);
    });
  });

  group('pickPreferredTrack', () {
    const tracks = [
      AudioTrack(id: '1', language: 'eng', title: 'Original'),
      AudioTrack(id: '2', language: 'spa'),
      AudioTrack(id: '3', language: 'jpn'),
    ];

    test('respeta el orden de preferencia', () {
      expect(pickPreferredTrack(tracks, ['ja', 'es'])?.id, '3');
      expect(pickPreferredTrack(tracks, ['es', 'ja'])?.id, '2');
    });

    test('salta idiomas que no están', () {
      expect(pickPreferredTrack(tracks, ['de', 'es'])?.id, '2');
    });

    test('devuelve null si nada coincide o no hay preferencias', () {
      expect(pickPreferredTrack(tracks, ['de']), isNull);
      expect(pickPreferredTrack(tracks, const []), isNull);
      expect(pickPreferredTrack(const <AudioTrack>[], ['es']), isNull);
    });
  });
}
