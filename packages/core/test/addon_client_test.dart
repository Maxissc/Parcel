import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import 'support.dart';

const _base = 'https://addon.example.com/cfg';

InstalledAddon _addon([String base = _base]) => InstalledAddon(
  transportUrl: '$base/manifest.json',
  manifest: AddonManifest.fromJson({
    'id': 'org.test',
    'name': 'Test',
    'resources': ['catalog', 'meta', 'stream', 'subtitles'],
    'types': ['movie', 'series'],
  }),
);

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

AddonClient _client(FutureOr<http.Response> Function(http.Request) handler) =>
    AddonClient(MockClient((req) async => handler(req)));

void main() {
  group('buildResourceUrl', () {
    test('arma las rutas del protocolo', () {
      String url(String resource, String type, String id) => buildResourceUrl(
        baseUrl: _base,
        resource: resource,
        type: type,
        id: id,
      );
      expect(url('catalog', 'movie', 'top'), '$_base/catalog/movie/top.json');
      expect(
        url('meta', 'movie', 'tt0111161'),
        '$_base/meta/movie/tt0111161.json',
      );
      expect(
        url('stream', 'movie', 'tt0111161'),
        '$_base/stream/movie/tt0111161.json',
      );
      expect(
        url('subtitles', 'movie', 'tt0111161'),
        '$_base/subtitles/movie/tt0111161.json',
      );
    });

    test('pone la query del manifest al final del recurso', () {
      expect(
        buildResourceUrl(
          baseUrl: 'https://host.example/x',
          query: 'token=1',
          resource: 'catalog',
          type: 'movie',
          id: 'top',
        ),
        'https://host.example/x/catalog/movie/top.json?token=1',
      );
      expect(
        buildResourceUrl(
          baseUrl: 'https://host.example/x',
          query: 'token=1',
          resource: 'catalog',
          type: 'movie',
          id: 'top',
          extra: const {'skip': '20'},
        ),
        'https://host.example/x/catalog/movie/top/skip=20.json?token=1',
      );
    });

    test('codifica los ids con dos puntos como Stremio', () {
      expect(
        buildResourceUrl(
          baseUrl: _base,
          resource: 'stream',
          type: 'series',
          id: 'tt0903747:1:2',
        ),
        '$_base/stream/series/tt0903747%3A1%3A2.json',
      );
      expect(
        buildResourceUrl(
          baseUrl: _base,
          resource: 'meta',
          type: 'channel',
          id: 'yt_id:UC123/x y',
        ),
        '$_base/meta/channel/yt_id%3AUC123%2Fx%20y.json',
      );
    });

    test('arma los extras como k=v&k2=v2 con valores codificados', () {
      expect(
        buildResourceUrl(
          baseUrl: _base,
          resource: 'catalog',
          type: 'movie',
          id: 'top',
          extra: {
            'genre': 'Sci-Fi',
            'search': 'game of thrones & más',
            'skip': '100',
          },
        ),
        '$_base/catalog/movie/top/'
        'genre=Sci-Fi&search=game%20of%20thrones%20%26%20m%C3%A1s&skip=100.json',
      );
    });

    test('sin extras no agrega el segmento', () {
      expect(
        buildResourceUrl(
          baseUrl: _base,
          resource: 'catalog',
          type: 'movie',
          id: 'top',
          extra: const {},
        ),
        '$_base/catalog/movie/top.json',
      );
    });
  });

  group('InstalledAddon', () {
    test('deriva la base de transporte y va y vuelve por JSON', () {
      final addon = _addon();
      expect(addon.baseUrl, _base);
      final back = InstalledAddon.fromJson(addon.toJson());
      expect(back, addon);
      expect(back.manifest.supports('stream', 'movie', 'x'), isTrue);
    });
  });

  group('AddonClient', () {
    test('baja y normaliza el manifest', () async {
      Uri? asked;
      final client = _client((req) {
        asked = req.url;
        return _json(fixture('cinemeta_manifest.json'));
      });
      final addon = await client.fetchManifest(
        '  stremio://v3-cinemeta.strem.io/ ',
      );
      expect(asked.toString(), 'https://v3-cinemeta.strem.io/manifest.json');
      expect(addon.transportUrl, 'https://v3-cinemeta.strem.io/manifest.json');
      expect(addon.baseUrl, 'https://v3-cinemeta.strem.io');
      expect(addon.manifest.name, 'Cinemeta');
    });

    test('un manifest con query pide los recursos con esa query', () async {
      Uri? asked;
      final client = _client((req) {
        asked = req.url;
        return _json({'metas': []});
      });
      final addon = InstalledAddon(
        transportUrl: 'https://host.example/x/manifest.json?token=1',
        manifest: _addon().manifest,
      );
      await client.catalog(addon, 'movie', 'top');
      expect(
        asked.toString(),
        'https://host.example/x/catalog/movie/top.json?token=1',
      );
    });

    test('pide un catálogo con extras y parsea las metas', () async {
      Uri? asked;
      final client = _client((req) {
        asked = req.url;
        return _json(fixture('cinemeta_catalog_movie_top.json'));
      });
      final metas = await client.catalog(
        _addon(),
        'movie',
        'top',
        extra: {'search': 'matrix'},
      );
      expect(asked.toString(), '$_base/catalog/movie/top/search=matrix.json');
      expect(metas, hasLength(4));
    });

    test('pide la meta de una serie', () async {
      Uri? asked;
      final client = _client((req) {
        asked = req.url;
        return _json(fixture('cinemeta_meta_series_tt0903747.json'));
      });
      final meta = await client.meta(_addon(), 'series', 'tt0903747');
      expect(asked.toString(), '$_base/meta/series/tt0903747.json');
      expect(meta.name, 'Breaking Bad');
      expect(meta.videos, hasLength(5));
    });

    test('pide los streams de un episodio y descarta los inválidos', () async {
      Uri? asked;
      final client = _client((req) {
        asked = req.url;
        return _json(fixture('stream_http_synthetic.json'));
      });
      final streams = await client.streams(_addon(), 'series', 'tt0903747:1:2');
      expect(asked.toString(), '$_base/stream/series/tt0903747%3A1%3A2.json');
      expect(streams, hasLength(5));
      expect(streams.where((s) => s.isPlayable), hasLength(1));
    });

    test('pide subtítulos con extras', () async {
      Uri? asked;
      final client = _client((req) {
        asked = req.url;
        return _json(fixture('opensubtitles_subtitles_movie_tt0111161.json'));
      });
      final subs = await client.subtitles(
        _addon(),
        'movie',
        'tt0111161',
        extra: {'videoHash': 'abc', 'videoSize': '123'},
      );
      expect(
        asked.toString(),
        '$_base/subtitles/movie/tt0111161/videoHash=abc&videoSize=123.json',
      );
      expect(subs, hasLength(5));
    });

    test('lee UTF-8 aunque el content-type no diga charset', () async {
      final client = _client(
        (req) => _json({
          'metas': [
            {'id': 'a', 'type': 'movie', 'name': 'Película ñandú'},
          ],
        }),
      );
      final metas = await client.catalog(_addon(), 'movie', 'top');
      expect(metas.single.name, 'Película ñandú');
    });

    test('una lista vacía es una respuesta válida', () async {
      final client = _client((req) => _json({'streams': []}));
      expect(await client.streams(_addon(), 'movie', 'tt1'), isEmpty);
    });

    Future<AddonException> failure(
      AddonClient client,
      Future<Object?> Function(AddonClient) call,
    ) async {
      try {
        await call(client);
      } on AddonException catch (e) {
        return e;
      }
      fail('Tendría que haber lanzado AddonException');
    }

    test('un status que no es 2xx es una falla http con el código', () async {
      final client = _client((req) => http.Response('nope', 404));
      final e = await failure(
        client,
        (c) => c.streams(_addon(), 'movie', 'tt1'),
      );
      expect(e.reason, AddonFailureReason.http);
      expect(e.statusCode, 404);
    });

    test('un cuerpo que no es JSON es una falla de parseo', () async {
      final client = _client((req) => http.Response('<html>', 200));
      final e = await failure(client, (c) => c.meta(_addon(), 'movie', 'tt1'));
      expect(e.reason, AddonFailureReason.parse);
    });

    test(
      'una respuesta sin la clave esperada es una falla de parseo',
      () async {
        final client = _client((req) => _json({'otra': 1}));
        for (final call in <Future<Object?> Function(AddonClient)>[
          (c) => c.catalog(_addon(), 'movie', 'top'),
          (c) => c.meta(_addon(), 'movie', 'tt1'),
          (c) => c.streams(_addon(), 'movie', 'tt1'),
          (c) => c.subtitles(_addon(), 'movie', 'tt1'),
        ]) {
          final e = await failure(client, call);
          expect(e.reason, AddonFailureReason.parse);
        }
      },
    );

    test('una meta inválida es una falla de parseo', () async {
      final client = _client(
        (req) => _json({
          'meta': {'id': 'x'},
        }),
      );
      final e = await failure(client, (c) => c.meta(_addon(), 'movie', 'x'));
      expect(e.reason, AddonFailureReason.parse);
    });

    test('un error de red es una falla de red', () async {
      final client = _client((req) => throw const SocketException('sin red'));
      final e = await failure(
        client,
        (c) => c.streams(_addon(), 'movie', 'tt1'),
      );
      expect(e.reason, AddonFailureReason.network);
    });

    test('un manifest inválido o una URL mala fallan con motivo', () async {
      final client = _client((req) => _json({'name': 'sin id'}));
      var e = await failure(client, (c) => c.fetchManifest('https://a.com'));
      expect(e.reason, AddonFailureReason.parse);
      e = await failure(client, (c) => c.fetchManifest('esto no es una url'));
      expect(e.reason, AddonFailureReason.invalidUrl);
    });
  });
}
