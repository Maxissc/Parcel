import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'tok-secreto-987';

  test('InstalledAddon.toString no lleva la transportUrl completa', () {
    final addon = InstalledAddon(
      transportUrl: 'https://addon.example/$secret/manifest.json?key=$secret',
      manifest: AddonManifest.fromJson({
        'id': 'a',
        'name': 'Addon',
        'resources': ['catalog'],
      }),
    );
    expect('$addon', isNot(contains(secret)));
    expect('$addon', contains('Addon'));
    expect('$addon', contains('addon.example'));
  });

  test('PlaybackSource.toString muestra solo el host', () {
    final source = PlaybackSource(
      url: 'https://cdn.example/$secret/video.mkv?sig=$secret',
    );
    expect('$source', isNot(contains(secret)));
    expect('$source', contains('cdn.example'));
  });

  test('AddonStream.toString no lleva la URL completa', () {
    final stream = AddonStream.fromJson({
      'url': 'https://debrid.example/$secret/file.mkv',
    });
    expect('$stream', isNot(contains(secret)));
    expect('$stream', contains('debrid.example'));
  });

  test('la FormatException de normalizeManifestUrl no lleva el input', () {
    try {
      normalizeManifestUrl('ftp://host.example/$secret/manifest.json');
      fail('debía tirar FormatException');
    } on FormatException catch (e) {
      expect('$e', isNot(contains(secret)));
      expect('${e.source}', isNot(contains(secret)));
    }
  });
}
