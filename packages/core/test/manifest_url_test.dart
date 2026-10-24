import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeManifestUrl', () {
    test('convierte stremio:// en https://', () {
      expect(
        normalizeManifestUrl('stremio://host.com/x/manifest.json'),
        'https://host.com/x/manifest.json',
      );
    });

    test('completa /manifest.json si falta', () {
      expect(
        normalizeManifestUrl('https://host.com/addon'),
        'https://host.com/addon/manifest.json',
      );
      expect(
        normalizeManifestUrl('https://host.com'),
        'https://host.com/manifest.json',
      );
    });

    test('tolera espacios y barras finales', () {
      expect(
        normalizeManifestUrl('  https://host.com/addon/  '),
        'https://host.com/addon/manifest.json',
      );
      expect(
        normalizeManifestUrl('https://host.com/addon/manifest.json/'),
        'https://host.com/addon/manifest.json',
      );
    });

    test('deja http:// como está y baja a minúsculas el host', () {
      expect(
        normalizeManifestUrl('http://Host.COM/a/manifest.json'),
        'http://host.com/a/manifest.json',
      );
    });

    test('rechaza lo que no es una URL http(s) o stremio', () {
      expect(() => normalizeManifestUrl(''), throwsFormatException);
      expect(() => normalizeManifestUrl('no es url'), throwsFormatException);
      expect(
        () => normalizeManifestUrl('ftp://host.com/manifest.json'),
        throwsFormatException,
      );
    });
  });

  group('transportBaseUrl', () {
    test('quita /manifest.json', () {
      expect(
        transportBaseUrl('https://host.com/x/manifest.json'),
        'https://host.com/x',
      );
      expect(
        transportBaseUrl('https://host.com/manifest.json'),
        'https://host.com',
      );
    });
  });
}
