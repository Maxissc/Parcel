import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Map<String, dynamic> _manifest({
  Object? resources,
  Object? types = const ['movie', 'series'],
  Object? idPrefixes,
  Object? catalogs,
}) => {
  'id': 'org.test',
  'name': 'Test',
  'version': '1.0.0',
  'description': 'd',
  'resources': resources ?? ['stream'],
  'types': types,
  'idPrefixes': ?idPrefixes,
  'catalogs': ?catalogs,
};

void main() {
  group('parseo de manifests reales', () {
    test('Cinemeta', () {
      final m = AddonManifest.fromJson(fixture('cinemeta_manifest.json'));
      expect(m.id, 'com.linvo.cinemeta');
      expect(m.name, 'Cinemeta');
      expect(m.version, '3.0.14');
      expect(m.types, ['movie', 'series']);
      expect(m.idPrefixes, ['tt']);
      expect(m.resources.map((r) => r.name), [
        'catalog',
        'meta',
        'addon_catalog',
      ]);
      expect(m.catalogs, isNotEmpty);
      final top = m.catalogs.first;
      expect(top.type, 'movie');
      expect(top.id, 'top');
      expect(top.name, 'Popular');
      expect(top.extra.map((e) => e.name), ['genre', 'search', 'skip']);
      expect(top.extra.first.options, contains('Action'));
      expect(top.hasRequiredExtra, isFalse);
      expect(top.acceptsExtra('search'), isTrue);
    });

    test('OpenSubtitles v3', () {
      final m = AddonManifest.fromJson(fixture('opensubtitles_manifest.json'));
      expect(m.id, 'org.stremio.opensubtitlesv3');
      expect(m.resources.map((r) => r.name), ['subtitles']);
      expect(m.catalogs, isEmpty);
      expect(m.logo, startsWith('http'));
    });

    test('toJson conserva el manifest original', () {
      final json = fixture('cinemeta_manifest.json');
      expect(AddonManifest.fromJson(json).toJson(), json);
    });
  });

  group('supports', () {
    test('usa types e idPrefixes del manifest para recursos en string', () {
      final m = AddonManifest.fromJson(fixture('cinemeta_manifest.json'));
      expect(m.supports('meta', 'movie', 'tt0111161'), isTrue);
      expect(m.supports('meta', 'series', 'tt0903747:1:2'), isTrue);
      expect(m.supports('meta', 'tv', 'tt0111161'), isFalse);
      expect(m.supports('meta', 'movie', 'yt_id:abc'), isFalse);
      expect(m.supports('stream', 'movie', 'tt0111161'), isFalse);
    });

    test('un recurso en objeto pisa types e idPrefixes del manifest', () {
      final m = AddonManifest.fromJson(
        _manifest(
          types: ['movie', 'series', 'tv'],
          idPrefixes: ['tt'],
          resources: [
            'meta',
            {
              'name': 'stream',
              'types': ['movie'],
              'idPrefixes': ['yt_id:'],
            },
            {'name': 'subtitles'},
          ],
        ),
      );
      expect(m.supports('meta', 'tv', 'tt1'), isTrue);
      expect(m.supports('meta', 'tv', 'x1'), isFalse);
      expect(m.supports('stream', 'movie', 'yt_id:1'), isTrue);
      expect(m.supports('stream', 'movie', 'tt1'), isFalse);
      expect(m.supports('stream', 'series', 'yt_id:1'), isFalse);
      // Objeto sin types ni idPrefixes: hereda los types del manifest y
      // acepta cualquier id.
      expect(m.supports('subtitles', 'series', 'zz1'), isTrue);
      expect(m.supports('subtitles', 'channel', 'tt1'), isFalse);
    });

    test('un recurso en objeto sin idPrefixes acepta cualquier id', () {
      final m = AddonManifest.fromJson(
        _manifest(
          resources: [
            {
              'name': 'stream',
              'types': ['movie'],
            },
          ],
          idPrefixes: ['tt'],
        ),
      );
      expect(m.supports('stream', 'movie', 'otra:cosa'), isTrue);
    });

    test('sin idPrefixes en ningún lado acepta cualquier id del tipo', () {
      final m = AddonManifest.fromJson(_manifest());
      expect(m.supports('stream', 'movie', 'lo-que-sea'), isTrue);
      expect(m.supports('stream', 'channel', 'lo-que-sea'), isFalse);
    });

    test('idPrefixes vacío se toma como sin restricción', () {
      final m = AddonManifest.fromJson(_manifest(idPrefixes: <String>[]));
      expect(m.supports('stream', 'movie', 'abc'), isTrue);
    });

    test('catalog ignora idPrefixes', () {
      final m = AddonManifest.fromJson(
        _manifest(resources: ['catalog'], idPrefixes: ['tt']),
      );
      expect(m.supports('catalog', 'movie', 'cualquier-id'), isTrue);
      expect(m.supports('catalog', 'tv', 'cualquier-id'), isFalse);
    });
  });

  group('tolerancia', () {
    test('resources acepta strings y objetos y descarta lo raro', () {
      final m = AddonManifest.fromJson(
        _manifest(
          resources: [
            'catalog',
            {'name': 'meta', 'types': 'movie', 'idPrefixes': 5},
            {
              'types': ['movie'],
            },
            42,
            null,
          ],
        ),
      );
      expect(m.resources.map((r) => r.name), ['catalog', 'meta']);
      expect(m.resources[1].types, ['movie']);
      expect(m.resources[1].idPrefixes, isNull);
    });

    test('campos opcionales de tipo raro no tiran excepción', () {
      final m = AddonManifest.fromJson({
        'id': 'a.b',
        'name': 'N',
        'version': 3,
        'description': ['x'],
        'logo': 7,
        'resources': ['stream'],
        'types': 'movie',
        'idPrefixes': {'a': 1},
        'catalogs': 'nada',
      });
      expect(m.version, '');
      expect(m.description, '');
      expect(m.logo, isNull);
      expect(m.types, ['movie']);
      expect(m.idPrefixes, isNull);
      expect(m.catalogs, isEmpty);
    });

    test('descarta catálogos y extras inválidos y sigue con el resto', () {
      final m = AddonManifest.fromJson(
        _manifest(
          resources: ['catalog'],
          catalogs: [
            {'type': 'movie', 'id': 'a', 'name': 'A'},
            {'type': 'movie'},
            'x',
            {
              'type': 'series',
              'id': 'b',
              'extra': [
                {'name': 'search', 'isRequired': true},
                {'isRequired': true},
                {
                  'name': 'genre',
                  'options': ['x', 3],
                  'optionsLimit': '2',
                },
                7,
              ],
            },
          ],
        ),
      );
      expect(m.catalogs.map((c) => c.id), ['a', 'b']);
      expect(m.catalogs[0].name, 'A');
      final b = m.catalogs[1];
      expect(b.name, 'b'); // sin name, usa el id
      expect(b.extra.map((e) => e.name), ['search', 'genre']);
      expect(b.hasRequiredExtra, isTrue);
      expect(b.extra[1].options, ['x']);
      expect(b.extra[1].optionsLimit, 2);
    });

    test('lee el formato viejo extraRequired / extraSupported', () {
      final m = AddonManifest.fromJson(
        _manifest(
          resources: ['catalog'],
          catalogs: [
            {
              'type': 'movie',
              'id': 'busqueda',
              'extraRequired': ['search'],
              'extraSupported': ['search', 'genre'],
            },
            {
              'type': 'movie',
              'id': 'solo-requerido',
              'extraRequired': ['search'],
            },
            {
              'type': 'movie',
              'id': 'mixto',
              'extra': [
                {'name': 'genre'},
              ],
              'extraSupported': ['genre', 'skip'],
            },
          ],
        ),
      );
      final busqueda = m.catalogs[0];
      expect(busqueda.extra.map((e) => e.name), ['search', 'genre']);
      expect(busqueda.hasRequiredExtra, isTrue);
      expect(busqueda.extra[0].isRequired, isTrue);
      expect(busqueda.extra[1].isRequired, isFalse);
      expect(m.catalogs[1].hasRequiredExtra, isTrue);
      expect(m.catalogs[2].extra.map((e) => e.name), ['genre', 'skip']);
      expect(m.catalogs[2].hasRequiredExtra, isFalse);
    });

    test('rechaza manifests sin id, sin name o sin recursos válidos', () {
      expect(
        () => AddonManifest.fromJson({
          'name': 'x',
          'resources': ['stream'],
        }),
        throwsFormatException,
      );
      expect(
        () => AddonManifest.fromJson({
          'id': 'x',
          'resources': ['stream'],
        }),
        throwsFormatException,
      );
      expect(
        () => AddonManifest.fromJson({'id': 'x', 'name': 'x'}),
        throwsFormatException,
      );
    });
  });

  test('dos manifests con el mismo id, nombre y versión son iguales', () {
    final a = AddonManifest.fromJson(_manifest());
    final b = AddonManifest.fromJson(_manifest());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
