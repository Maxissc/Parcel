import 'dart:async';
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

StremioAccountClient _client(
  Future<http.Response> Function(http.Request) handler,
) => StremioAccountClient(MockClient(handler));

Future<AccountException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on AccountException catch (e) {
    return e;
  }
  fail('Se esperaba una AccountException');
}

void main() {
  group('createLinkCode', () {
    test('lee code, link y qrcode de la respuesta real', () async {
      late http.Request seen;
      final client = _client((req) async {
        seen = req;
        return _fixture('stremio_create_link.json');
      });
      final link = await client.createLinkCode();
      expect(link.code, '5SHF');
      expect(link.link, 'https://link.stremio.com/5SHF');
      expect(link.qrcodeUrl, startsWith('https://link.stremio.com/qr?data='));
      expect(seen.method, 'GET');
      expect(
        seen.url.toString(),
        'https://link.stremio.com/api/v2/create?type=Create',
      );
    });

    test('sin red lanza error de red en español', () async {
      final client = _client(
        (_) async => throw http.ClientException('sin red'),
      );
      final e = await _failure(client.createLinkCode);
      expect(e.reason, AccountFailureReason.network);
      expect(e.message, contains('conexión'));
    });

    test('con 500 y cuerpo que no es JSON, servicio no disponible', () async {
      final client = _client((_) async => http.Response('oops', 500));
      final e = await _failure(client.createLinkCode);
      expect(e.reason, AccountFailureReason.serviceUnavailable);
    });
  });

  group('pollLinkCode', () {
    const fast = Duration(milliseconds: 1);

    test('trata el 101 como pendiente y termina con el authKey', () async {
      final urls = <String>[];
      var calls = 0;
      final client = _client((req) async {
        urls.add(req.url.toString());
        calls++;
        return calls < 3
            ? _fixture('stremio_read_pending.json')
            : _fixture('stremio_read_ok.json');
      });
      final keys = await client
          .pollLinkCode(
            '5SHF',
            interval: fast,
            timeout: const Duration(seconds: 5),
          )
          .toList();
      expect(keys, ['fake-auth-key']);
      expect(calls, 3);
      expect(
        urls.first,
        'https://link.stremio.com/api/v2/read?type=Read&code=5SHF',
      );
    });

    test('si vence el plazo, termina con LinkCodeExpired', () async {
      var calls = 0;
      final client = _client((_) async {
        calls++;
        return _fixture('stremio_read_pending.json');
      });
      final stream = client.pollLinkCode(
        '5SHF',
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 40),
      );
      await expectLater(stream, emitsError(isA<LinkCodeExpired>()));
      expect(calls, greaterThan(1));
    });

    test('se puede cancelar y deja de consultar', () async {
      var calls = 0;
      final first = Completer<void>();
      final client = _client((_) async {
        calls++;
        if (!first.isCompleted) first.complete();
        return _fixture('stremio_read_pending.json');
      });
      final sub = client
          .pollLinkCode(
            '5SHF',
            interval: fast,
            timeout: const Duration(seconds: 30),
          )
          .listen((_) {}, onError: (_) {});
      await first.future;
      await sub.cancel();
      final atCancel = calls;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, atCancel);
    });

    test('un error que no es 101 corta con error tipado', () async {
      final client = _client(
        (_) async => _fixture('stremio_session_not_found.json'),
      );
      final stream = client.pollLinkCode('5SHF', interval: fast);
      await expectLater(
        stream,
        emitsError(
          isA<AccountException>().having(
            (e) => e.reason,
            'reason',
            AccountFailureReason.rejected,
          ),
        ),
      );
    });

    test('un fallo de red corta con error de red', () async {
      final client = _client((_) async => throw http.ClientException('x'));
      await expectLater(
        client.pollLinkCode('5SHF', interval: fast),
        emitsError(
          isA<AccountException>().having(
            (e) => e.reason,
            'reason',
            AccountFailureReason.network,
          ),
        ),
      );
    });
  });

  group('login', () {
    test('devuelve el authKey y manda el cuerpo esperado', () async {
      late http.Request seen;
      final client = _client((req) async {
        seen = req;
        return _fixture('stremio_login_ok.json');
      });
      final key = await client.login('persona@example.com', 'fake-password');
      expect(key, 'fake-auth-key');
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'https://api.strem.io/api/login');
      expect(jsonDecode(seen.body), {
        'type': 'Login',
        'email': 'persona@example.com',
        'password': 'fake-password',
        'facebook': false,
      });
    });

    test(
      'mail inexistente (código 2 / wrongEmail) es cuenta inexistente',
      () async {
        final client = _client(
          (_) async => _fixture('stremio_login_user_not_found.json'),
        );
        final e = await _failure(() => client.login('nadie@example.com', 'x'));
        expect(e.reason, AccountFailureReason.accountNotFound);
        expect(
          e.message,
          'No encontramos una cuenta de Stremio con ese email.',
        );
      },
    );

    test('contraseña incorrecta', () async {
      final client = _client(
        (_) async => _fixture('stremio_login_wrong_password.json'),
      );
      final e = await _failure(
        () => client.login('persona@example.com', 'mal'),
      );
      expect(e.reason, AccountFailureReason.wrongPassword);
    });

    test('el error no incluye la contraseña ni el email', () async {
      final client = _client(
        (_) async => _fixture('stremio_login_user_not_found.json'),
      );
      final e = await _failure(
        () => client.login('persona@example.com', 'fake-password'),
      );
      expect('${e.message} $e', isNot(contains('fake-password')));
      expect('${e.message} $e', isNot(contains('persona@example.com')));
    });

    test('con una respuesta sin authKey, error de parseo', () async {
      final client = _client((_) async => http.Response('{"result":{}}', 200));
      final e = await _failure(() => client.login('persona@example.com', 'x'));
      expect(e.reason, AccountFailureReason.parse);
    });

    test('con 503, servicio no disponible', () async {
      final client = _client((_) async => http.Response('', 503));
      final e = await _failure(() => client.login('persona@example.com', 'x'));
      expect(e.reason, AccountFailureReason.serviceUnavailable);
    });

    test('sin red, error de red', () async {
      final client = _client((_) async => throw http.ClientException('x'));
      final e = await _failure(() => client.login('persona@example.com', 'x'));
      expect(e.reason, AccountFailureReason.network);
    });
  });

  group('getAddonCollection', () {
    test(
      'lee los addons con su manifest y flags, y descarta los sin URL',
      () async {
        late http.Request seen;
        final client = _client((req) async {
          seen = req;
          return _fixture('stremio_addon_collection.json');
        });
        final entries = await client.getAddonCollection('fake-auth-key');
        expect(
          seen.url.toString(),
          'https://api.strem.io/api/addonCollectionGet',
        );
        expect(jsonDecode(seen.body), {
          'type': 'AddonCollectionGet',
          'authKey': 'fake-auth-key',
          'update': true,
        });
        expect(entries.map((e) => e.transportUrl), [
          'https://v3-cinemeta.strem.io/manifest.json',
          'https://opensubtitles-v3.strem.io/manifest.json',
          'https://comunidad.example.com/fake-user-token/manifest.json',
          'http://127.0.0.1:11470/local-addon/manifest.json',
        ]);
        expect(entries[0].official, isTrue);
        expect(entries[0].isProtected, isTrue);
        expect(entries[1].isProtected, isFalse);
        expect(entries[2].official, isFalse);
        expect(entries[2].manifest!['id'], 'test.comunidad');
      },
    );

    test('sesión inexistente', () async {
      final client = _client(
        (_) async => _fixture('stremio_session_not_found.json'),
      );
      final e = await _failure(() => client.getAddonCollection('invalid'));
      expect(e.reason, AccountFailureReason.sessionExpired);
      expect(e.message, contains('sesión'));
    });

    test('toString de una entrada no incluye la URL completa', () async {
      final client = _client(
        (_) async => _fixture('stremio_addon_collection.json'),
      );
      final entries = await client.getAddonCollection('fake-auth-key');
      expect('${entries[2]}', isNot(contains('fake-user-token')));
      expect('${entries[2]}', contains('comunidad.example.com'));
    });
  });

  group('logout', () {
    test('manda el authKey a /api/logout', () async {
      late http.Request seen;
      final client = _client((req) async {
        seen = req;
        return _fixture('stremio_logout_ok.json');
      });
      await client.logout('fake-auth-key');
      expect(seen.url.toString(), 'https://api.strem.io/api/logout');
      expect(jsonDecode(seen.body), {
        'type': 'Logout',
        'authKey': 'fake-auth-key',
      });
    });

    test('nunca tira, ni sin red ni con error del servidor', () async {
      await _client((_) async => throw http.ClientException('x')).logout('k');
      await _client((_) async => http.Response('x', 500)).logout('k');
      await _client((_) async => _fixture('stremio_session_not_found.json'))
          .logout('k');
    });
  });
}
