import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

const _secretUrl = 'https://cdn.example.com/token-ultra-secreto/video.mkv';

AddonStream _stream([String url = _secretUrl, Map<String, String>? headers]) =>
    AddonStream.fromJson({
      'name': 'Test 1080p',
      'url': url,
      'behaviorHints': {
        if (headers != null) 'proxyHeaders': {'request': headers},
      },
    });

http.StreamedResponse _response(
  int status, {
  Map<String, String> headers = const {},
  int? contentLength,
  List<int> body = const [0],
}) => http.StreamedResponse(
  Stream.value(body),
  status,
  headers: headers,
  contentLength: contentLength,
);

/// Pedidos recibidos y pedidos abortados, de la prueba en curso.
List<http.BaseRequest> requests = [];
List<Uri> aborted = [];

/// Cliente de prueba: [handler] recibe el pedido y devuelve la respuesta.
class _Fake {
  _Fake(Future<http.StreamedResponse> Function(http.BaseRequest) handler)
    : client = MockClient.streaming((req, _) {
        requests.add(req);
        final trigger = req is http.Abortable ? req.abortTrigger : null;
        trigger?.then((_) => aborted.add(req.url));
        return handler(req);
      });

  final MockClient client;
}

void main() {
  setUp(() {
    requests = [];
    aborted = [];
  });

  group('éxito', () {
    test(
      'una lista HLS chica es válida (el video viene en segmentos)',
      () async {
        for (final type in [
          'application/vnd.apple.mpegurl',
          'application/x-mpegURL; charset=utf-8',
        ]) {
          final fake = _Fake(
            (_) async => _response(
              200,
              headers: {'content-type': type},
              contentLength: 900,
            ),
          );
          final result = await StreamProber(fake.client).probe(_stream());
          expect(result.ok, isTrue, reason: type);
        }
      },
    );

    test('206 con Content-Range de 1,5 GB', () async {
      final fake = _Fake(
        (_) async => _response(
          206,
          headers: {
            'content-type': 'video/x-matroska',
            'content-range': 'bytes 0-0/1500000000',
          },
          contentLength: 1,
        ),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.ok, isTrue);
      expect(result.failure, isNull);
      expect(result.statusCode, 206);
      expect(result.totalBytes, 1500000000);
    });

    test('pide Range bytes=0-0 con los headers del stream', () async {
      final fake = _Fake(
        (_) async => _response(
          206,
          headers: {'content-range': 'bytes 0-0/1500000000'},
          contentLength: 1,
        ),
      );
      await StreamProber(fake.client).probe(
        _stream(_secretUrl, {
          'User-Agent': 'Parcel',
          'Referer': 'https://r.example/',
        }),
      );
      final headers = requests.single.headers;
      expect(requests.single.method, 'GET');
      expect(headers['Range'], 'bytes=0-0');
      expect(headers['User-Agent'], 'Parcel');
      expect(headers['Referer'], 'https://r.example/');
    });

    test('200 con Content-Length grande y sin content-type', () async {
      final fake = _Fake(
        (_) async => _response(200, contentLength: 800 * 1024 * 1024),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.ok, isTrue);
      expect(result.totalBytes, 800 * 1024 * 1024);
    });

    test('acepta video/*, application/octet-stream y x-matroska', () async {
      for (final type in [
        'video/mp4',
        'video/webm; charset=binary',
        'application/octet-stream',
        'application/x-matroska',
        'Video/MP4',
      ]) {
        final fake = _Fake(
          (_) async => _response(
            206,
            headers: {
              'content-type': type,
              'content-range': 'bytes 0-0/500000000',
            },
            contentLength: 1,
          ),
        );
        final result = await StreamProber(fake.client).probe(_stream());
        expect(result.ok, isTrue, reason: type);
      }
    });

    test('si no se conoce el tamaño (bytes 0-0/*) no lo descarta', () async {
      final fake = _Fake(
        (_) async => _response(
          206,
          headers: {
            'content-type': 'video/mp4',
            'content-range': 'bytes 0-0/*',
          },
          contentLength: 1,
        ),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.ok, isTrue);
      expect(result.totalBytes, isNull);
    });

    test(
      '206 sin Content-Range no toma el largo del rango como tamaño',
      () async {
        final fake = _Fake((_) async => _response(206, contentLength: 1));
        final result = await StreamProber(fake.client).probe(_stream());
        expect(result.ok, isTrue);
        expect(result.totalBytes, isNull);
      },
    );
  });

  group('fallas', () {
    test('placeholder de 300 KB', () async {
      final fake = _Fake(
        (_) async => _response(
          200,
          headers: {'content-type': 'video/mp4'},
          contentLength: 300 * 1024,
        ),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.ok, isFalse);
      expect(result.failure, ProbeFailure.placeholder);
      expect(result.totalBytes, 300 * 1024);
    });

    test('placeholder chico con Content-Range', () async {
      final fake = _Fake(
        (_) async => _response(
          206,
          headers: {
            'content-type': 'video/mp4',
            'content-range': 'bytes 0-0/300000',
          },
          contentLength: 1,
        ),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.failure, ProbeFailure.placeholder);
    });

    test('el mínimo se puede cambiar', () async {
      final fake = _Fake(
        (_) async => _response(200, contentLength: 5 * 1024 * 1024),
      );
      expect(
        (await StreamProber(fake.client).probe(_stream())).failure,
        ProbeFailure.placeholder,
      );
      expect(
        (await StreamProber(
          fake.client,
          minBytes: 1024 * 1024,
        ).probe(_stream())).ok,
        isTrue,
      );
    });

    test('404', () async {
      final fake = _Fake((_) async => _response(404));
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.ok, isFalse);
      expect(result.failure, ProbeFailure.http);
      expect(result.statusCode, 404);
    });

    test('403 y 500', () async {
      for (final status in [403, 500, 416]) {
        final fake = _Fake((_) async => _response(status));
        final result = await StreamProber(fake.client).probe(_stream());
        expect(result.failure, ProbeFailure.http, reason: '$status');
        expect(result.statusCode, status);
      }
    });

    test('tipo que no es de video (una página HTML)', () async {
      final fake = _Fake(
        (_) async => _response(
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
          contentLength: 80 * 1024 * 1024,
        ),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.failure, ProbeFailure.type);
    });

    test('error de red', () async {
      final fake = _Fake(
        (_) async => throw http.ClientException(
          'falló $_secretUrl',
          Uri.parse(_secretUrl),
        ),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.failure, ProbeFailure.network);
      expect(result.toString(), isNot(contains('token-ultra-secreto')));
    });

    test('un stream que no es http no se prueba', () async {
      final fake = _Fake((_) async => _response(200));
      final result = await StreamProber(fake.client)
          .probe(AddonStream.fromJson({'name': 't', 'infoHash': 'abc'}));
      expect(result.failure, ProbeFailure.invalidUrl);
      expect(requests, isEmpty);
    });

    test('la URL no aparece en el resultado', () async {
      final fake = _Fake((_) async => _response(404));
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.toString(), isNot(contains('token-ultra-secreto')));
      expect(result.toString(), isNot(contains('cdn.example.com')));
    });
  });

  group('timeout y cancelación', () {
    test('el timeout aborta el pedido', () async {
      final fake = _Fake((_) => Completer<http.StreamedResponse>().future);
      final result = await StreamProber(
        fake.client,
        timeout: const Duration(milliseconds: 50),
      ).probe(_stream());
      expect(result.failure, ProbeFailure.timeout);
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));
      expect(aborted, [Uri.parse(_secretUrl)]);
    });

    test('el timeout por defecto es de 8 segundos', () {
      expect(
        StreamProber(MockClient((_) async => http.Response('', 200))).timeout,
        const Duration(seconds: 8),
      );
    });

    test('cancelar desde afuera aborta el pedido', () async {
      final fake = _Fake((_) => Completer<http.StreamedResponse>().future);
      final cancel = Completer<void>();
      final future = StreamProber(fake.client)
          .probe(_stream(), abortTrigger: cancel.future);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancel.complete();
      final result = await future;
      expect(result.failure, ProbeFailure.cancelled);
      await Future<void>.delayed(Duration.zero);
      expect(aborted, hasLength(1));
    });
  });

  group('redirects', () {
    test('sigue un redirect relativo', () async {
      final fake = _Fake((req) async {
        if (req.url.path == '/token-ultra-secreto/video.mkv') {
          return _response(
            302,
            headers: {'location': '/final/video.mkv'},
            contentLength: 0,
          );
        }
        return _response(
          206,
          headers: {
            'content-type': 'video/mp4',
            'content-range': 'bytes 0-0/900000000',
          },
          contentLength: 1,
        );
      });
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.ok, isTrue);
      expect(requests.map((r) => r.url.path), [
        '/token-ultra-secreto/video.mkv',
        '/final/video.mkv',
      ]);
      expect(requests.every((r) => r.headers['Range'] == 'bytes=0-0'), isTrue);
    });

    test(
      'sigue un redirect a otro host sin mandarle Authorization ni Cookie',
      () async {
        final fake = _Fake((req) async {
          if (req.url.host == 'cdn.example.com') {
            return _response(
              307,
              headers: {'location': 'https://otro.example.net/v.mp4'},
              contentLength: 0,
            );
          }
          return _response(
            206,
            headers: {'content-range': 'bytes 0-0/900000000'},
            contentLength: 1,
          );
        });
        final result = await StreamProber(fake.client).probe(
          _stream(_secretUrl, {
            'Authorization': 'Bearer abc',
            'Cookie': 'a=b',
            'User-Agent': 'Parcel',
          }),
        );
        expect(result.ok, isTrue);
        expect(requests[0].headers['Authorization'], 'Bearer abc');
        expect(requests[1].url.host, 'otro.example.net');
        expect(requests[1].headers.containsKey('Authorization'), isFalse);
        expect(requests[1].headers.containsKey('Cookie'), isFalse);
        expect(requests[1].headers['User-Agent'], 'Parcel');
      },
    );

    test('un loop de redirects falla con http', () async {
      final fake = _Fake(
        (req) async =>
            _response(302, headers: {'location': '/otra'}, contentLength: 0),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.failure, ProbeFailure.http);
      expect(requests.length, lessThanOrEqualTo(6));
    });

    test('un redirect sin Location falla con http', () async {
      final fake = _Fake((_) async => _response(302, contentLength: 0));
      final result = await StreamProber(fake.client).probe(_stream());
      expect(result.failure, ProbeFailure.http);
    });

    test('a otro host solo reenvía User-Agent y Range', () async {
      final fake = _Fake((req) async {
        if (req.url.host == 'cdn.example.com') {
          return _response(
            307,
            headers: {'location': 'https://otro.example.net/v.mp4'},
            contentLength: 0,
          );
        }
        return _response(
          206,
          headers: {'content-range': 'bytes 0-0/900000000'},
          contentLength: 1,
        );
      });
      await StreamProber(fake.client).probe(
        _stream(_secretUrl, {
          'User-Agent': 'Parcel',
          'Referer': 'https://r.example/',
          'X-Token': 'abc',
          'Origin': 'https://r.example',
        }),
      );
      final second = requests[1].headers;
      expect(second['User-Agent'], 'Parcel');
      expect(second['Range'], 'bytes=0-0');
      expect(second.containsKey('Referer'), isFalse);
      expect(second.containsKey('X-Token'), isFalse);
      expect(second.containsKey('Origin'), isFalse);
      // En el mismo host se mantienen todos.
      expect(requests[0].headers['Referer'], 'https://r.example/');
    });

    test('cancelar durante un salto no sigue con el próximo', () async {
      final gate = Completer<void>();
      final fake = _Fake((req) async {
        await gate.future;
        return _response(
          302,
          headers: {'location': '/final/video.mkv'},
          contentLength: 0,
        );
      });
      final cancel = Completer<void>();
      final future = StreamProber(fake.client)
          .probe(_stream(), abortTrigger: cancel.future);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancel.complete();
      expect((await future).failure, ProbeFailure.cancelled);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, hasLength(1));
    });
  });

  group('no baja el cuerpo', () {
    http.StreamedResponse withBody(
      StreamController<List<int>> body,
      int status,
      Map<String, String> headers,
    ) => http.StreamedResponse(
      body.stream,
      status,
      headers: headers,
      contentLength: status == 206 ? 1 : 800 * 1024 * 1024,
    );

    test('206: cancela el cuerpo', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final fake = _Fake(
        (_) async => withBody(body, 206, {
          'content-type': 'video/mp4',
          'content-range': 'bytes 0-0/900000000',
        }),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      await Future<void>.delayed(Duration.zero);
      expect(result.ok, isTrue);
      expect(cancelled, isTrue);
    });

    test('200 sin Range: cancela el cuerpo', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final fake = _Fake(
        (_) async => withBody(body, 200, {'content-type': 'video/mp4'}),
      );
      final result = await StreamProber(fake.client).probe(_stream());
      await Future<void>.delayed(Duration.zero);
      expect(result.ok, isTrue);
      expect(cancelled, isTrue);
    });
  });

  group('content-type', () {
    test('solo falla por type con tipos de texto, json, xml o js', () async {
      for (final type in [
        'text/html',
        'text/plain; charset=utf-8',
        'application/json',
        'application/xml',
        'application/javascript',
        'application/x-javascript',
      ]) {
        final fake = _Fake(
          (_) async => _response(
            200,
            headers: {'content-type': type},
            contentLength: 80 * 1024 * 1024,
          ),
        );
        final result = await StreamProber(fake.client).probe(_stream());
        expect(result.failure, ProbeFailure.type, reason: type);
      }
    });

    test('cualquier otro tipo pasa al chequeo de tamaño', () async {
      for (final type in [
        'application/force-download',
        'binary/octet-stream',
        'application/mp4',
        'application/dash+xml',
      ]) {
        final big = _Fake(
          (_) async => _response(
            200,
            headers: {'content-type': type},
            contentLength: 80 * 1024 * 1024,
          ),
        );
        expect(
          (await StreamProber(big.client).probe(_stream())).ok,
          isTrue,
          reason: type,
        );
        final small = _Fake(
          (_) async => _response(
            200,
            headers: {'content-type': type},
            contentLength: 100 * 1024,
          ),
        );
        expect(
          (await StreamProber(small.client).probe(_stream())).failure,
          ProbeFailure.placeholder,
          reason: type,
        );
      }
    });
  });
}
