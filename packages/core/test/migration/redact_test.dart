import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

void main() {
  group('redactAddonUrl', () {
    test('deja solo el host y descarta ruta, query y credenciales', () {
      final out = redactAddonUrl(
        'https://user:pass@addon.example.com/eyJ0b2tlbiI6InNlY3JldG8ifQ/manifest.json?key=secreto#frag',
      );
      expect(out, 'addon.example.com');
      expect(out, isNot(contains('secreto')));
      expect(out, isNot(contains('eyJ0b2tlbiI6')));
      expect(out, isNot(contains('pass')));
    });

    test('conserva el puerto', () {
      expect(
        redactAddonUrl('http://192.168.0.5:7000/manifest.json'),
        '192.168.0.5:7000',
      );
    });

    test('con nombre, lo antepone al host', () {
      expect(
        redactAddonUrl(
          'https://torrentio.strem.fun/token123/manifest.json',
          name: 'Torrentio',
        ),
        'Torrentio (torrentio.strem.fun)',
      );
    });

    test('acepta stremio://', () {
      expect(
        redactAddonUrl('stremio://addon.example.com/tok/manifest.json'),
        'addon.example.com',
      );
    });

    test('con una URL inválida no devuelve el texto original', () {
      final out = redactAddonUrl('esto-no-es-una-url-con-token-abc123');
      expect(out, isNot(contains('abc123')));
      expect(out, 'URL inválida');
    });
  });

  group('AccountException', () {
    test('toString muestra el mensaje y nunca datos sensibles', () {
      const e = AccountException(
        AccountFailureReason.accountNotFound,
        'No encontramos una cuenta de Stremio con ese email',
      );
      expect(e.toString(), contains('No encontramos'));
    });

    test('LinkCodeExpired es una AccountException con motivo linkExpired', () {
      const e = LinkCodeExpired();
      expect(e, isA<AccountException>());
      expect(e.reason, AccountFailureReason.linkExpired);
      expect(e.message, 'El código venció. Generá uno nuevo.');
    });
  });
}
