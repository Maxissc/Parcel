import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

const _url = 'https://subs.example.com/token-secreto/es.srt';

const _srt = '1\n00:00:01,000 --> 00:00:02,000\nCanción\n';

SubtitleFetcher _fetcher(
  Future<http.StreamedResponse> Function(http.BaseRequest) handler, {
  Duration timeout = const Duration(seconds: 15),
}) => SubtitleFetcher(
  MockClient.streaming((req, _) => handler(req)),
  timeout: timeout,
);

http.StreamedResponse _bytes(
  List<int> bytes, {
  int status = 200,
  int? contentLength,
}) => http.StreamedResponse(
  Stream.value(bytes),
  status,
  contentLength: contentLength ?? bytes.length,
);

void main() {
  group('decodificación', () {
    test('UTF-8', () {
      expect(
        SubtitleFetcher.decode(utf8.encode('Canción — ñandú')),
        'Canción — ñandú',
      );
    });

    test('UTF-8 con BOM', () {
      expect(
        SubtitleFetcher.decode([0xEF, 0xBB, 0xBF, ...utf8.encode('Hola')]),
        'Hola',
      );
    });

    test('UTF-16 LE y BE con BOM', () {
      const text = '1\n00:00:01,000 --> 00:00:02,000\nCanción ñandú\n';
      final units = text.codeUnits;
      final le = [
        0xFF,
        0xFE,
        for (final u in units) ...[u & 0xFF, u >> 8],
      ];
      final be = [
        0xFE,
        0xFF,
        for (final u in units) ...[u >> 8, u & 0xFF],
      ];
      expect(SubtitleFetcher.decode(le), text);
      expect(SubtitleFetcher.decode(be), text);
    });

    test('Latin-1 cuando hay muchos caracteres inválidos en UTF-8', () {
      final bytes = latin1.encode('Canción de ñandú, además él sabía qué pasó');
      expect(
        SubtitleFetcher.decode(bytes),
        'Canción de ñandú, además él sabía qué pasó',
      );
    });

    test('Latin-1 con comillas de Windows-1252', () {
      // 0x92 es la comilla ’ en Windows-1252.
      final bytes = [
        ...latin1.encode('It'),
        0x92,
        ...latin1.encode('s ca'),
        0xF1,
        0x6F,
        0x6E,
      ];
      expect(SubtitleFetcher.decode(bytes), 'It’s cañon');
    });

    test('un byte suelto inválido en un texto largo en UTF-8 no cambia la codificación', () {
      final bytes = [...utf8.encode('Canción ' * 400), 0xFF];
      final text = SubtitleFetcher.decode(bytes);
      expect(text, startsWith('Canción Canción'));
    });
  });

  group('fetchText y fetchCues', () {
    test('baja y parsea un SRT en UTF-8', () async {
      final cues = await _fetcher((_) async => _bytes(utf8.encode(_srt)))
          .fetchCues(_url);
      expect(cues, hasLength(1));
      expect(cues.single.text, 'Canción');
    });

    test('baja y parsea un SRT en Latin-1', () async {
      final cues = await _fetcher((_) async => _bytes(latin1.encode(_srt)))
          .fetchCues(_url);
      expect(cues.single.text, 'Canción');
    });

    test('no manda headers raros', () async {
      late http.BaseRequest seen;
      await _fetcher((req) async {
        seen = req;
        return _bytes(utf8.encode(_srt));
      }).fetchText(_url);
      expect(seen.method, 'GET');
      expect(seen.url.toString(), _url);
    });

    test('rechaza lo que declara más de 3 MB', () async {
      final fetcher = _fetcher(
        (_) async => _bytes([0x41], contentLength: 3 * 1024 * 1024 + 1),
      );
      await expectLater(
        fetcher.fetchText(_url),
        throwsA(
          isA<SubtitleException>().having(
            (e) => e.reason,
            'reason',
            SubtitleFailureReason.tooLarge,
          ),
        ),
      );
    });

    test(
      'corta la descarga que pasa de 3 MB aunque no declare el largo',
      () async {
        var chunks = 0;
        final controller = StreamController<List<int>>();
        final fetcher = _fetcher((_) async {
          Timer.periodic(const Duration(milliseconds: 1), (timer) {
            if (controller.isClosed) {
              timer.cancel();
              return;
            }
            chunks++;
            controller.add(List.filled(512 * 1024, 0x41));
          });
          return http.StreamedResponse(controller.stream, 200);
        });
        await expectLater(
          fetcher.fetchText(_url),
          throwsA(
            isA<SubtitleException>().having(
              (e) => e.reason,
              'reason',
              SubtitleFailureReason.tooLarge,
            ),
          ),
        );
        expect(chunks, lessThan(20));
        await controller.close();
      },
    );

    test('el tope se puede cambiar', () async {
      final fetcher = SubtitleFetcher(
        MockClient((_) async => http.Response('x' * 2000, 200)),
        maxBytes: 1000,
      );
      await expectLater(
        fetcher.fetchText(_url),
        throwsA(isA<SubtitleException>()),
      );
    });

    test('el tope por defecto es de 3 MB y el plazo de 15 s', () {
      final f = SubtitleFetcher(
        MockClient((_) async => http.Response('', 200)),
      );
      expect(f.maxBytes, 3 * 1024 * 1024);
      expect(f.timeout, const Duration(seconds: 15));
    });

    test('HTTP 404', () async {
      await expectLater(
        _fetcher((_) async => _bytes(const [], status: 404)).fetchText(_url),
        throwsA(
          isA<SubtitleException>()
              .having((e) => e.reason, 'reason', SubtitleFailureReason.http)
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('error de red sin la URL en el mensaje', () async {
      final fetcher = _fetcher(
        (_) async => throw http.ClientException('falló $_url', Uri.parse(_url)),
      );
      await expectLater(
        fetcher.fetchText(_url),
        throwsA(
          isA<SubtitleException>()
              .having((e) => e.reason, 'reason', SubtitleFailureReason.network)
              .having(
                (e) => e.toString(),
                'toString',
                isNot(contains('secreto')),
              )
              .having((e) => e.message, 'message', isNot(contains('secreto'))),
        ),
      );
    });

    test('el timeout aborta el pedido', () async {
      var aborted = false;
      final fetcher = _fetcher((req) {
        (req as http.Abortable).abortTrigger?.then((_) => aborted = true);
        return Completer<http.StreamedResponse>().future;
      }, timeout: const Duration(milliseconds: 50));
      await expectLater(
        fetcher.fetchText(_url),
        throwsA(
          isA<SubtitleException>().having(
            (e) => e.reason,
            'reason',
            SubtitleFailureReason.timeout,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(aborted, isTrue);
    });

    test('una URL inválida es un error de red', () async {
      await expectLater(
        _fetcher((_) async => _bytes(const [])).fetchText('no es una url'),
        throwsA(isA<SubtitleException>()),
      );
    });
  });
}
