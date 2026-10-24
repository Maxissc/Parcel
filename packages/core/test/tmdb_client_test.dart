import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

// Claves falsas, obviamente inventadas.
const _v3Key = 'FAKE-V3-KEY-0123456789abcdef';
const _v4Token = 'eyJFAKE.V4-TOKEN.not-a-real-jwt-0123456789';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

const _findBody = {
  'movie_results': [
    {'id': 278, 'original_language': 'en', 'title': 'The Shawshank Redemption'},
  ],
  'tv_results': [],
  'person_results': [],
};

const _creditsBody = {
  'id': 278,
  'cast': [
    {
      'name': 'Morgan Freeman',
      'character': "Ellis Boyd 'Red' Redding",
      'profile_path': '/oGJ0P0hhtbXUPSbQJ9mDqYzHeSE.jpg',
      'order': 1,
    },
    {
      'name': 'Tim Robbins',
      'character': 'Andy Dufresne',
      'profile_path': '/hsAUX7qOVBKhZfN8vwzB0ZNKzIE.jpg',
      'order': 0,
    },
    {'name': 'Sin Foto', 'character': '', 'profile_path': null, 'order': 2},
    {'character': 'Sin nombre', 'profile_path': '/x.jpg', 'order': 3},
  ],
  'crew': [],
};

void main() {
  group('autenticación', () {
    test('una key v3 va en la query api_key', () async {
      late http.Request seen;
      final tmdb = TmdbClient(
        MockClient((req) async {
          seen = req;
          return _json(_findBody);
        }),
        apiKey: _v3Key,
      );
      await tmdb.findByImdb('tt0111161');
      expect(seen.url.host, 'api.themoviedb.org');
      expect(seen.url.path, '/3/find/tt0111161');
      expect(seen.url.queryParameters['api_key'], _v3Key);
      expect(seen.url.queryParameters['external_source'], 'imdb_id');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'un token v4 (eyJ...) va en el header Authorization: Bearer',
      () async {
        late http.Request seen;
        final tmdb = TmdbClient(
          MockClient((req) async {
            seen = req;
            return _json(_findBody);
          }),
          apiKey: _v4Token,
        );
        await tmdb.findByImdb('tt0111161');
        expect(seen.headers['Authorization'], 'Bearer $_v4Token');
        expect(seen.url.queryParameters.containsKey('api_key'), isFalse);
        expect(seen.url.toString(), isNot(contains('eyJ')));
      },
    );

    test('ignora espacios alrededor de la key', () async {
      late http.Request seen;
      final tmdb = TmdbClient(
        MockClient((req) async {
          seen = req;
          return _json(_findBody);
        }),
        apiKey: '  $_v3Key\n',
      );
      await tmdb.findByImdb('tt0111161');
      expect(seen.url.queryParameters['api_key'], _v3Key);
    });

    test('una key vacía no se puede usar', () {
      expect(
        () => TmdbClient(MockClient((_) async => _json({})), apiKey: '  '),
        throwsArgumentError,
      );
    });
  });

  group('findByImdb', () {
    test('da el id, el tipo y el idioma original', () async {
      final tmdb = TmdbClient(
        MockClient((_) async => _json(_findBody)),
        apiKey: _v3Key,
      );
      final found = await tmdb.findByImdb('tt0111161');
      expect(found, isNotNull);
      expect(found!.id, 278);
      expect(found.type, 'movie');
      expect(found.originalLanguage, 'en');
    });

    test('una serie viene en tv_results', () async {
      final tmdb = TmdbClient(
        MockClient(
          (_) async => _json({
            'movie_results': [],
            'tv_results': [
              {'id': 1396, 'original_language': 'en', 'name': 'Breaking Bad'},
            ],
          }),
        ),
        apiKey: _v3Key,
      );
      final found = await tmdb.findByImdb('tt0903747');
      expect(found!.id, 1396);
      expect(found.type, 'tv');
    });

    test('sin resultados, null', () async {
      final tmdb = TmdbClient(
        MockClient((_) async => _json({'movie_results': [], 'tv_results': []})),
        apiKey: _v3Key,
      );
      expect(await tmdb.findByImdb('tt9999999'), isNull);
    });

    test('un id que no es de IMDb no hace ningún pedido', () async {
      var calls = 0;
      final tmdb = TmdbClient(
        MockClient((_) async {
          calls++;
          return _json(_findBody);
        }),
        apiKey: _v3Key,
      );
      expect(await tmdb.findByImdb('kitsu:123'), isNull);
      expect(await tmdb.findByImdb(''), isNull);
      expect(calls, 0);
    });
  });

  group('credits', () {
    test(
      'da el elenco con foto w185 y personaje, en el orden de TMDB',
      () async {
        late http.Request seen;
        final tmdb = TmdbClient(
          MockClient((req) async {
            seen = req;
            return _json(_creditsBody);
          }),
          apiKey: _v3Key,
        );
        final cast = await tmdb.credits(278, 'movie');
        expect(seen.url.path, '/3/movie/278/credits');
        expect(cast.map((c) => c.name), [
          'Tim Robbins',
          'Morgan Freeman',
          'Sin Foto',
        ]);
        expect(cast[0].character, 'Andy Dufresne');
        expect(
          cast[0].photoUrl,
          'https://image.tmdb.org/t/p/w185/hsAUX7qOVBKhZfN8vwzB0ZNKzIE.jpg',
        );
        expect(cast[2].photoUrl, isNull);
        expect(cast[2].character, isNull);
      },
    );

    test('para series usa /tv/', () async {
      late http.Request seen;
      final tmdb = TmdbClient(
        MockClient((req) async {
          seen = req;
          return _json(_creditsBody);
        }),
        apiKey: _v3Key,
      );
      await tmdb.credits(1396, 'tv');
      expect(seen.url.path, '/3/tv/1396/aggregate_credits');
      await tmdb.credits(1396, 'series');
      expect(seen.url.path, '/3/tv/1396/aggregate_credits');
    });

    test('en series el personaje sale de roles[0].character', () async {
      final tmdb = TmdbClient(
        MockClient(
          (_) async => _json({
            'cast': [
              {
                'name': 'Bryan Cranston',
                'profile_path': '/b.jpg',
                'order': 0,
                'roles': [
                  {'character': 'Walter White', 'episode_count': 62},
                  {'character': 'Otro', 'episode_count': 1},
                ],
              },
              {'name': 'Sin Roles', 'order': 1, 'roles': []},
            ],
          }),
        ),
        apiKey: _v3Key,
      );
      final cast = await tmdb.credits(1396, 'tv');
      expect(cast.first.name, 'Bryan Cranston');
      expect(cast.first.character, 'Walter White');
      expect(cast.last.character, isNull);
    });

    test('limit corta la lista', () async {
      final tmdb = TmdbClient(
        MockClient((_) async => _json(_creditsBody)),
        apiKey: _v3Key,
      );
      expect(await tmdb.credits(278, 'movie', limit: 1), hasLength(1));
    });

    test('se mezcla con el elenco de la meta', () async {
      final tmdb = TmdbClient(
        MockClient((_) async => _json(_creditsBody)),
        apiKey: _v3Key,
      );
      final cast = await tmdb.credits(278, 'movie');
      final meta = Meta.fromJson({
        'id': 'tt0111161',
        'type': 'movie',
        'name': 'X',
        'cast': ['Tim Robbins', 'Bob Gunton'],
      }).copyWith(castDetails: cast);
      expect(meta.credits.cast.map((c) => c.name), [
        'Tim Robbins',
        'Morgan Freeman',
        'Sin Foto',
        'Bob Gunton',
      ]);
      expect(meta.credits.cast.first.photoUrl, isNotNull);
    });
  });

  group('la key no se filtra', () {
    test('toString del cliente y de lo que devuelve', () async {
      for (final key in [_v3Key, _v4Token]) {
        final tmdb = TmdbClient(
          MockClient((_) async => _json(_findBody)),
          apiKey: key,
        );
        expect(tmdb.toString(), isNot(contains(key)));
        expect(tmdb.toString(), isNot(contains('FAKE')));
        final found = await tmdb.findByImdb('tt0111161');
        expect(found.toString(), isNot(contains(key)));
      }
    });

    test('errores de red', () async {
      for (final key in [_v3Key, _v4Token]) {
        final tmdb = TmdbClient(
          MockClient(
            (req) async =>
                throw http.ClientException('falló ${req.url}', req.url),
          ),
          apiKey: key,
        );
        await expectLater(
          tmdb.findByImdb('tt0111161'),
          throwsA(
            isA<TmdbException>()
                .having((e) => e.reason, 'reason', TmdbFailureReason.network)
                .having(
                  (e) => e.toString(),
                  'toString',
                  isNot(contains('FAKE')),
                )
                .having((e) => e.message, 'message', isNot(contains('FAKE'))),
          ),
        );
      }
    });

    test('401: key inválida', () async {
      final tmdb = TmdbClient(
        MockClient(
          (_) async => _json({
            'status_code': 7,
            'status_message':
                'Invalid API key: You must be granted a valid key.',
          }, 401),
        ),
        apiKey: _v3Key,
      );
      await expectLater(
        tmdb.findByImdb('tt0111161'),
        throwsA(
          isA<TmdbException>()
              .having((e) => e.reason, 'reason', TmdbFailureReason.auth)
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.toString(), 'toString', isNot(contains('FAKE'))),
        ),
      );
    });

    test('otros HTTP, respuesta rota y timeout', () async {
      TmdbClient client(
        Future<http.Response> Function() handler, {
        Duration timeout = const Duration(seconds: 10),
      }) => TmdbClient(
        MockClient((_) => handler()),
        apiKey: _v3Key,
        timeout: timeout,
      );

      await expectLater(
        client(() async => _json({}, 500)).findByImdb('tt1'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.reason,
            'reason',
            TmdbFailureReason.http,
          ),
        ),
      );
      await expectLater(
        client(() async => http.Response('<html>', 200)).findByImdb('tt1'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.reason,
            'reason',
            TmdbFailureReason.parse,
          ),
        ),
      );
      await expectLater(
        client(() async => _json([1, 2])).credits(1, 'movie'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.reason,
            'reason',
            TmdbFailureReason.parse,
          ),
        ),
      );
      await expectLater(
        client(
          () => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 50),
        ).findByImdb('tt1'),
        throwsA(
          isA<TmdbException>().having(
            (e) => e.reason,
            'reason',
            TmdbFailureReason.timeout,
          ),
        ),
      );
    });

    test('el timeout aborta el pedido', () async {
      var aborted = false;
      final tmdb = TmdbClient(
        MockClient.streaming((req, _) {
          (req as http.Abortable).abortTrigger?.then((_) => aborted = true);
          return Completer<http.StreamedResponse>().future;
        }),
        apiKey: _v3Key,
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(tmdb.findByImdb('tt1'), throwsA(isA<TmdbException>()));
      await Future<void>.delayed(Duration.zero);
      expect(aborted, isTrue);
    });
  });
}
