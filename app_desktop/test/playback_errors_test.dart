import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/playback/playback_errors.dart';

void main() {
  const secret = 'SECRETO';
  const url = 'http://127.0.0.1:7000/no-existe?token=$secret';

  group('redactUrlsInText', () {
    test('deja solo el host de cada dirección', () {
      final out = redactUrlsInText(
        'Failed to open $url. Reintentando https://cdn.example/$secret/v.mkv',
      );
      expect(out, isNot(contains(secret)));
      expect(out, contains('127.0.0.1:7000'));
      expect(out, contains('cdn.example'));
    });

    test('no toca el texto sin direcciones', () {
      expect(redactUrlsInText('sin url acá'), 'sin url acá');
    });
  });

  group('playbackErrorMessage', () {
    test('nunca devuelve la URL ni el token del texto original', () {
      for (final raw in [
        'Failed to open $url.',
        'http: HTTP error 404 Not Found ($url)',
        'HTTP error 403 Forbidden: $url',
        'tcp: Connection refused $url',
        'Exception: $url',
        'Failed to recognize file format. $url',
        'timed out $url',
        'HTTP error 503 $url',
      ]) {
        final message = playbackErrorMessage(raw);
        expect(message, isNot(contains(secret)), reason: raw);
        expect(message, isNot(contains('http')), reason: raw);
        expect(message, isNot(contains('127.0.0.1')), reason: raw);
      }
    });

    test('distingue las causas más comunes', () {
      expect(
        playbackErrorMessage('HTTP error 404 Not Found'),
        'No se encontró el video en el servidor.',
      );
      expect(
        playbackErrorMessage('HTTP error 403 Forbidden'),
        contains('no dejó abrir el video'),
      );
      expect(
        playbackErrorMessage('HTTP error 502 Bad Gateway'),
        'El servidor respondió con un error.',
      );
      expect(
        playbackErrorMessage('Connection refused'),
        'No se pudo conectar con el servidor.',
      );
      expect(
        playbackErrorMessage('Failed to recognize file format.'),
        'Parcel no reconoce el formato de este video.',
      );
      expect(playbackErrorMessage('algo raro'), 'No se pudo abrir el video.');
    });
  });
}
