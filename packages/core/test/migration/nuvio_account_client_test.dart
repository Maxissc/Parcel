import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

import '../support.dart';

http.Response _fixture(String name, [int status = 200]) => http.Response.bytes(
  utf8.encode(fixtureText('migration/$name')),
  status,
  headers: {'content-type': 'application/json'},
);

const _fakeKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJmYWtlIjp0cnVlfQ.ZmFrZS1zaWduYXR1cmU';

/// Responde como Nuvio según la ruta y deja los pedidos en [seen].
class _FakeNuvio {
  final List<http.Request> seen = [];
  http.Response Function(http.Request)? onToken;
  http.Response Function(http.Request)? onAddons;
  http.Response Function(http.Request)? onWellKnown;

  Future<http.Response> handle(http.Request req) async {
    seen.add(req);
    final path = req.url.path;
    if (path == '/.well-known/nuvio') {
      return (onWellKnown ?? (_) => _fixture('nuvio_well_known.json'))(req);
    }
    if (path == '/auth/v1/token') {
      return (onToken ?? (_) => _fixture('nuvio_token_ok.json'))(req);
    }
    if (path == '/rest/v1/addons') {
      return (onAddons ??
          (_) => http.Response(
            fixtureText('migration/nuvio_addons.json'),
            200,
          ))(req);
    }
    if (path == '/auth/v1/logout') return http.Response('', 204);
    return http.Response('no existe', 404);
  }

  NuvioAccountClient client() => NuvioAccountClient(MockClient(handle));
}

Future<AccountException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on AccountException catch (e) {
    return e;
  }
  fail('Se esperaba una AccountException');
}

void main() {
  late _FakeNuvio fake;

  setUp(() => fake = _FakeNuvio());

  group('discover', () {
    test('lee backend_url y publishable_key de /.well-known/nuvio', () async {
      final service = await fake.client().discover();
      expect(service.backendUrl, 'https://api.nuvio.tv');
      expect(service.publishableKey, _fakeKey);
      expect(
        fake.seen.single.url.toString(),
        'https://api.nuvio.tv/.well-known/nuvio',
      );
    });

    test('cachea en memoria: la segunda vez no vuelve a pedir', () async {
      final client = fake.client();
      await client.discover();
      await client.discover();
      expect(fake.seen, hasLength(1));
      await client.discover(refresh: true);
      expect(fake.seen, hasLength(2));
    });

    test(
      'una respuesta sin la key es servicio no disponible y no se cachea',
      () async {
        fake.onWellKnown = (_) =>
            http.Response('{"backend_url":"https://x.example.com"}', 200);
        final client = fake.client();
        final e = await _failure(client.discover);
        expect(e.reason, AccountFailureReason.serviceUnavailable);
        fake.onWellKnown = null;
        expect((await client.discover()).publishableKey, _fakeKey);
      },
    );

    test('con 500 es servicio no disponible', () async {
      fake.onWellKnown = (_) => http.Response('x', 500);
      final e = await _failure(fake.client().discover);
      expect(e.reason, AccountFailureReason.serviceUnavailable);
    });

    test('sin red es error de red', () async {
      final client = NuvioAccountClient(
        MockClient((_) async => throw http.ClientException('x')),
      );
      final e = await _failure(client.discover);
      expect(e.reason, AccountFailureReason.network);
    });
  });

  group('login', () {
    test('devuelve la sesión y pide el token con apikey', () async {
      final session = await fake.client().login(
        'persona@example.com',
        'fake-password',
      );
      expect(session.accessToken, 'fake-access-token');
      final req = fake.seen.last;
      expect(req.method, 'POST');
      expect(
        req.url.toString(),
        'https://api.nuvio.tv/auth/v1/token?grant_type=password',
      );
      expect(req.headers['apikey'], _fakeKey);
      expect(jsonDecode(req.body), {
        'email': 'persona@example.com',
        'password': 'fake-password',
      });
    });

    test('credenciales inválidas', () async {
      fake.onToken = (_) => _fixture('nuvio_invalid_credentials.json', 400);
      final e = await _failure(
        () => fake.client().login('persona@example.com', 'mal'),
      );
      expect(e.reason, AccountFailureReason.invalidCredentials);
      expect(e.message, 'El email o la contraseña no son correctos.');
    });

    test('el error no incluye la contraseña ni el email', () async {
      fake.onToken = (_) => _fixture('nuvio_invalid_credentials.json', 400);
      final e = await _failure(
        () => fake.client().login('persona@example.com', 'fake-password'),
      );
      expect('${e.message} $e', isNot(contains('fake-password')));
      expect('${e.message} $e', isNot(contains('persona@example.com')));
    });

    test('servicio caído (503)', () async {
      fake.onToken = (_) => http.Response('', 503);
      final e = await _failure(
        () => fake.client().login('persona@example.com', 'x'),
      );
      expect(e.reason, AccountFailureReason.serviceUnavailable);
    });

    test('si el descubrimiento falla, servicio no disponible', () async {
      fake.onWellKnown = (_) => http.Response('', 502);
      final e = await _failure(
        () => fake.client().login('persona@example.com', 'x'),
      );
      expect(e.reason, AccountFailureReason.serviceUnavailable);
    });

    test('respuesta sin access_token es servicio no disponible', () async {
      fake.onToken = (_) => http.Response('{"foo":1}', 200);
      final e = await _failure(
        () => fake.client().login('persona@example.com', 'x'),
      );
      expect(e.reason, AccountFailureReason.serviceUnavailable);
    });

    test('toString de la sesión no filtra el token', () async {
      final session = await fake.client().login('persona@example.com', 'x');
      expect('$session', isNot(contains('fake-access-token')));
      expect('$session', isNot(contains('fake-refresh-token')));
      expect('${session.service}', isNot(contains(_fakeKey)));
    });
  });

  group('getAddons', () {
    test('pide con bearer y orden, y lee las filas válidas', () async {
      final client = fake.client();
      final session = await client.login('persona@example.com', 'x');
      final addons = await client.getAddons(session);
      final req = fake.seen.last;
      expect(req.url.path, '/rest/v1/addons');
      expect(req.url.queryParameters['order'], 'profile_id.asc,sort_order.asc');
      expect(
        req.url.queryParameters['select'],
        'url,name,enabled,sort_order,profile_id',
      );
      expect(req.headers['apikey'], _fakeKey);
      expect(req.headers['authorization'], 'Bearer fake-access-token');
      // La fila sin url se descarta.
      expect(addons, hasLength(3));
      expect(addons[0].url, 'https://v3-cinemeta.strem.io/manifest.json');
      expect(addons[0].name, 'Cinemeta');
      expect(addons[0].enabled, isTrue);
      expect(addons[0].profileId, 1);
      expect(addons[1].enabled, isFalse);
      expect(addons[1].sortOrder, 1);
      expect(addons[2].name, isNull);
      expect(addons[2].profileId, 2);
    });

    test('profile_id acepta entero o string numérico', () async {
      final client = fake.client();
      final session = await client.login('persona@example.com', 'x');
      fake.onAddons = (_) => http.Response(
        '[{"url":"https://a.example.com","profile_id":3},'
        '{"url":"https://b.example.com","profile_id":"2"},'
        '{"url":"https://c.example.com"}]',
        200,
      );
      final addons = await client.getAddons(session);
      expect(addons.map((a) => a.profileId), [3, 2, 1]);
    });

    test('un profile_id no numérico no se mezcla con el perfil 1', () async {
      final client = fake.client();
      final session = await client.login('persona@example.com', 'x');
      fake.onAddons = (_) => http.Response(
        '[{"url":"https://a.example.com","profile_id":"niños"},'
        '{"url":"https://b.example.com","profile_id":"adultos"},'
        '{"url":"https://c.example.com","profile_id":"niños"},'
        '{"url":"https://d.example.com","profile_id":1}]',
        200,
      );
      final ids = (await client.getAddons(session))
          .map((a) => a.profileId)
          .toList();
      expect(ids[0], isNot(1));
      expect(ids[1], isNot(1));
      expect(ids[0], isNot(ids[1]));
      expect(ids[0], ids[2]); // estable: el mismo texto da el mismo id
      expect(ids[3], 1);
    });

    test('sin permiso (RLS) o token vencido, sesión vencida', () async {
      final client = fake.client();
      final session = await client.login('persona@example.com', 'x');
      fake.onAddons = (_) => _fixture('nuvio_permission_denied.json', 401);
      final e = await _failure(() => client.getAddons(session));
      expect(e.reason, AccountFailureReason.sessionExpired);
    });

    test('con 500, servicio no disponible', () async {
      final client = fake.client();
      final session = await client.login('persona@example.com', 'x');
      fake.onAddons = (_) => http.Response('x', 500);
      final e = await _failure(() => client.getAddons(session));
      expect(e.reason, AccountFailureReason.serviceUnavailable);
    });

    test('toString de una fila no incluye la URL completa', () async {
      final client = fake.client();
      final session = await client.login('persona@example.com', 'x');
      final addons = await client.getAddons(session);
      expect('${addons[1]}', isNot(contains('fake-user-token')));
      expect('${addons[1]}', contains('torrent.example.com'));
    });
  });

  group('logout', () {
    test('manda el bearer a /auth/v1/logout', () async {
      final client = fake.client();
      final session = await client.login('persona@example.com', 'x');
      await client.logout(session);
      final req = fake.seen.last;
      expect(req.url.path, '/auth/v1/logout');
      expect(req.method, 'POST');
      expect(req.headers['authorization'], 'Bearer fake-access-token');
    });

    test('nunca tira', () async {
      final session = await fake.client().login('persona@example.com', 'x');
      final broken = NuvioAccountClient(
        MockClient((_) async => throw http.ClientException('x')),
      );
      await broken.logout(session);
      final erroring = NuvioAccountClient(
        MockClient((_) async => http.Response('x', 500)),
      );
      await erroring.logout(session);
    });
  });
}
