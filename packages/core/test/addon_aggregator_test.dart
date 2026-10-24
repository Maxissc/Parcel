import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import 'support.dart';

InstalledAddon _addon(
  String host, {
  List<Object> resources = const ['stream'],
  List<String> types = const ['movie', 'series'],
  List<String>? idPrefixes,
  List<Map<String, Object>> catalogs = const [],
}) => InstalledAddon(
  transportUrl: 'https://$host/manifest.json',
  manifest: AddonManifest.fromJson({
    'id': 'test.$host',
    'name': host,
    'version': '1.0.0',
    'resources': resources,
    'types': types,
    'idPrefixes': ?idPrefixes,
    'catalogs': catalogs,
  }),
);

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object> _stream(String name, [String? url]) => {
  'name': name,
  'url': url ?? 'https://cdn.example.com/$name.mp4',
};

AddonAggregator _aggregator(
  List<InstalledAddon> addons,
  FutureOr<http.Response> Function(http.Request) handler, {
  Duration timeout = const Duration(seconds: 15),
}) => AddonAggregator(
  client: AddonClient(MockClient((req) async => handler(req))),
  addons: () => addons,
  timeout: timeout,
);

void main() {
  group('catálogos', () {
    final cinemeta = InstalledAddon(
      transportUrl: 'https://v3-cinemeta.strem.io/manifest.json',
      manifest: AddonManifest.fromJson(fixture('cinemeta_manifest.json')),
    );
    final catalogos = _addon(
      'catalogos.example.com',
      resources: ['catalog'],
      catalogs: [
        {'type': 'movie', 'id': 'libre', 'name': 'Libre'},
        {
          'type': 'movie',
          'id': 'solo-busqueda',
          'name': 'Buscar',
          'extra': [
            {'name': 'search', 'isRequired': true},
          ],
        },
        {
          'type': 'series',
          'id': 'por-genero',
          'name': 'Por género',
          'extra': [
            {
              'name': 'genre',
              'isRequired': true,
              'options': ['Drama'],
            },
          ],
        },
        {
          'type': 'series',
          'id': 'con-skip',
          'name': 'Con skip',
          'extra': [
            {'name': 'skip'},
          ],
        },
      ],
    );

    test('la home trae los catálogos sin extras obligatorios, en orden', () {
      final agg = _aggregator([catalogos, cinemeta], (_) => _json({}));
      final home = agg.homeCatalogs();
      expect(
        home.map((r) => '${r.addon.manifest.name}/${r.catalog.id}').take(4),
        [
          'catalogos.example.com/libre',
          'catalogos.example.com/con-skip',
          'Cinemeta/top',
          'Cinemeta/top',
        ],
      );
      expect(home.any((r) => r.catalog.hasRequiredExtra), isFalse);
      final cinemetaCount = cinemeta.manifest.catalogs
          .where((c) => !c.hasRequiredExtra)
          .length;
      expect(home, hasLength(2 + cinemetaCount));
    });

    test('la búsqueda trae los catálogos que aceptan el extra search', () {
      final agg = _aggregator([catalogos, cinemeta], (_) => _json({}));
      final search = agg.searchCatalogs();
      expect(search.first.catalog.id, 'solo-busqueda');
      expect(search.every((r) => r.catalog.acceptsExtra('search')), isTrue);
      expect(
        search.where((r) => r.addon == cinemeta).map((r) => r.catalog.type),
        containsAll(['movie', 'series']),
      );
      expect(search.any((r) => r.catalog.id == 'con-skip'), isFalse);
    });

    test('fetchCatalog pide el catálogo y devuelve éxito o falla', () async {
      final urls = <String>[];
      final agg = _aggregator([catalogos], (req) {
        urls.add(req.url.toString());
        if (req.url.path.contains('libre')) {
          return _json(fixture('cinemeta_catalog_movie_top.json'));
        }
        return http.Response('caído', 503);
      });
      final home = agg.homeCatalogs();
      final ok = await agg.fetchCatalog(home[0], extra: {'skip': '20'});
      expect(urls.single, endsWith('/catalog/movie/libre/skip=20.json'));
      expect(ok, isA<AddonSuccess<List<Meta>>>());
      expect((ok as AddonSuccess<List<Meta>>).value, hasLength(4));

      final bad = await agg.fetchCatalog(home[1]);
      expect(bad, isA<AddonFailure<List<Meta>>>());
      expect(
        (bad as AddonFailure<List<Meta>>).error.reason,
        AddonFailureReason.http,
      );
    });
  });

  group('streams', () {
    test('un resultado por addon que soporta stream, en orden', () async {
      final a = _addon('a.example.com');
      final sinSoporte = _addon('b.example.com', resources: ['meta']);
      final otroTipo = _addon('c.example.com', types: ['tv']);
      final prefijo = _addon('d.example.com', idPrefixes: ['yt_id:']);
      final e = _addon('e.example.com');
      final hosts = <String>[];
      final agg = _aggregator([a, sinSoporte, otroTipo, prefijo, e], (req) {
        hosts.add(req.url.host);
        return _json({
          'streams': [_stream(req.url.host)],
        });
      });
      final results = await agg.streams('movie', 'tt0111161');
      expect(results.map((r) => r.addon), [a, e]);
      expect(hosts, unorderedEquals(['a.example.com', 'e.example.com']));
      final first = results.first as AddonSuccess<List<AddonStream>>;
      expect(first.value.single.name, 'a.example.com');
    });

    test(
      'un addon caído no tumba al resto y cada falla trae su motivo',
      () async {
        final ok = _addon('ok.example.com');
        final http500 = _addon('http.example.com');
        final roto = _addon('roto.example.com');
        final lento = _addon('lento.example.com');
        final agg = _aggregator([http500, lento, roto, ok], (req) {
          switch (req.url.host) {
            case 'http.example.com':
              return http.Response('error', 500);
            case 'roto.example.com':
              return http.Response('<html>', 200);
            case 'lento.example.com':
              return Completer<http.Response>().future; // no responde nunca
            default:
              return _json({
                'streams': [_stream('bueno')],
              });
          }
        }, timeout: const Duration(milliseconds: 100));
        final results = await agg.streams('movie', 'tt1');
        expect(results.map((r) => r.addon), [http500, lento, roto, ok]);
        AddonFailureReason reason(AddonResult<List<AddonStream>> r) =>
            (r as AddonFailure<List<AddonStream>>).error.reason;
        expect(reason(results[0]), AddonFailureReason.http);
        expect(reason(results[1]), AddonFailureReason.timeout);
        expect(reason(results[2]), AddonFailureReason.parse);
        expect(results[3], isA<AddonSuccess<List<AddonStream>>>());
      },
    );

    test('un error inesperado de un addon no tumba al resto', () async {
      final ok = _addon('ok.example.com');
      final raro = _addon('raro.example.com');
      final agg = _aggregator([raro, ok], (req) {
        if (req.url.host == 'raro.example.com') {
          throw StateError('token-secreto en el mensaje');
        }
        return _json({
          'streams': [_stream('bueno')],
        });
      });
      final results = await agg.streams('movie', 'tt1');
      final falla = results[0] as AddonFailure<List<AddonStream>>;
      expect(falla.reason, AddonFailureReason.parse);
      expect('${falla.error}', isNot(contains('token-secreto')));
      expect(results[1], isA<AddonSuccess<List<AddonStream>>>());
    });

    test('pide a todos los addons en paralelo', () async {
      final addons = [_addon('a.example.com'), _addon('b.example.com')];
      var started = 0;
      final bothStarted = Completer<void>();
      final agg = _aggregator(addons, (req) async {
        if (++started == 2) bothStarted.complete();
        await bothStarted.future; // si fuera en serie, el primero se colgaría
        return _json({
          'streams': [_stream('x')],
        });
      }, timeout: const Duration(seconds: 2));
      final results = await agg.streams('movie', 'tt1');
      expect(results.every((r) => r is AddonSuccess), isTrue);
    });

    test('usa el id codificado de un episodio', () async {
      final urls = <String>[];
      final agg = _aggregator([_addon('a.example.com')], (req) {
        urls.add(req.url.toString());
        return _json({'streams': []});
      });
      await agg.streams('series', 'tt0903747:1:2');
      expect(
        urls.single,
        'https://a.example.com/stream/series/tt0903747%3A1%3A2.json',
      );
    });

    test(
      'sin addons que soporten el recurso devuelve una lista vacía',
      () async {
        final agg = _aggregator(
          [
            _addon('a.example.com', resources: ['meta']),
          ],
          (_) {
            fail('no debería pedir nada');
          },
        );
        expect(await agg.streams('movie', 'tt1'), isEmpty);
      },
    );

    test('el timeout por defecto es de 15 segundos', () {
      final agg = AddonAggregator(
        client: AddonClient(MockClient((_) async => _json({}))),
        addons: () => const [],
      );
      expect(agg.timeout, const Duration(seconds: 15));
    });
  });

  group('meta', () {
    final metaJson = fixture('cinemeta_meta_series_tt0903747.json');

    test(
      'usa el primer addon, en orden, que soporte meta y responda bien',
      () async {
        final sinMeta = _addon('stream.example.com');
        final falla = _addon('falla.example.com', resources: ['meta']);
        final ok1 = _addon('ok1.example.com', resources: ['meta']);
        final ok2 = _addon('ok2.example.com', resources: ['meta']);
        final hosts = <String>[];
        final agg = _aggregator([sinMeta, falla, ok1, ok2], (req) {
          hosts.add(req.url.host);
          return req.url.host == 'falla.example.com'
              ? http.Response('x', 500)
              : _json(metaJson);
        });
        final result = await agg.meta('series', 'tt0903747');
        expect(result, isA<AddonSuccess<Meta>>());
        expect(result!.addon, ok1);
        expect((result as AddonSuccess<Meta>).value.name, 'Breaking Bad');
        expect(hosts, ['falla.example.com', 'ok1.example.com']);
      },
    );

    test('si ninguno responde bien devuelve la primera falla', () async {
      final a = _addon('a.example.com', resources: ['meta']);
      final b = _addon('b.example.com', resources: ['meta']);
      final agg = _aggregator(
        [a, b],
        (req) => req.url.host == 'a.example.com'
            ? http.Response('x', 404)
            : Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 50),
      );
      final result = await agg.meta('movie', 'tt1');
      expect(result, isA<AddonFailure<Meta>>());
      expect(result!.addon, a);
      expect(
        (result as AddonFailure<Meta>).error.reason,
        AddonFailureReason.http,
      );
    });

    test('un timeout pasa al siguiente addon', () async {
      final lento = _addon('lento.example.com', resources: ['meta']);
      final ok = _addon('ok.example.com', resources: ['meta']);
      final agg = _aggregator(
        [lento, ok],
        (req) => req.url.host == 'lento.example.com'
            ? Completer<http.Response>().future
            : _json(metaJson),
        timeout: const Duration(milliseconds: 50),
      );
      final result = await agg.meta('series', 'tt0903747');
      expect(result!.addon, ok);
    });

    test('devuelve null si ningún addon soporta meta para ese id', () async {
      final agg = _aggregator([
        _addon('a.example.com', resources: ['meta'], idPrefixes: ['yt_id:']),
      ], (_) => fail('no debería pedir nada'));
      expect(await agg.meta('movie', 'tt1'), isNull);
    });
  });

  group('subtítulos', () {
    test('agrega los de todos los addons que soportan subtitles', () async {
      final subsA = _addon('a.example.com', resources: ['subtitles']);
      final subsB = _addon('b.example.com', resources: ['subtitles']);
      final otro = _addon('c.example.com');
      final agg = _aggregator([subsA, otro, subsB], (req) {
        if (req.url.host == 'b.example.com') return http.Response('x', 500);
        return _json(fixture('opensubtitles_subtitles_movie_tt0111161.json'));
      });
      final results = await agg.subtitles(
        'movie',
        'tt0111161',
        extra: {'videoHash': 'abc'},
      );
      expect(results.map((r) => r.addon), [subsA, subsB]);
      expect((results[0] as AddonSuccess<List<Subtitle>>).value, hasLength(5));
      expect(results[1], isA<AddonFailure<List<Subtitle>>>());
    });
  });
}
