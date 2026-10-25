import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

/// Cómo responde cada stream de prueba.
class _Behavior {
  const _Behavior.ok(this.after) : status = 206, never = false;
  const _Behavior.fail(this.after) : status = 404, never = false;
  const _Behavior.never() : status = 0, after = Duration.zero, never = true;

  final int status;
  final Duration after;
  final bool never;
}

class _Server {
  _Server(this.behaviors) {
    client = MockClient.streaming((request, _) {
      final name = request.url.pathSegments.last;
      requested.add(name);
      final behavior = behaviors[name] ?? const _Behavior.fail(Duration.zero);
      final completer = Completer<http.StreamedResponse>();
      final trigger = request is http.Abortable ? request.abortTrigger : null;
      trigger?.then((_) {
        aborted.add(name);
        if (!completer.isCompleted) {
          completer.completeError(http.RequestAbortedException(request.url));
        }
      });
      if (!behavior.never) {
        Timer(behavior.after, () {
          if (completer.isCompleted) return;
          completer.complete(
            http.StreamedResponse(
              Stream.value([0]),
              behavior.status,
              headers: behavior.status == 206
                  ? {
                      'content-type': 'video/mp4',
                      'content-range': 'bytes 0-0/900000000',
                    }
                  : {},
              contentLength: behavior.status == 206 ? 1 : 0,
            ),
          );
        });
      }
      return completer.future;
    });
  }

  final Map<String, _Behavior> behaviors;
  late final MockClient client;
  final List<String> requested = [];
  final List<String> aborted = [];
}

AddonStream _s(int i) =>
    AddonStream.fromJson({'name': 's$i', 'url': 'https://cdn.example.com/s$i'});

List<AddonStream> _streams(int n) => [for (var i = 1; i <= n; i++) _s(i)];

List<String?> _names(List<AddonStream> streams) => [
  for (final s in streams) s.name,
];

Duration _ms(int n) => Duration(milliseconds: n);

AutoStreamSelector _selector(
  _Server server, {
  Duration grace = const Duration(milliseconds: 300),
  int batchSize = 3,
}) => AutoStreamSelector(
  StreamProber(server.client, timeout: const Duration(seconds: 5)),
  batchSize: batchSize,
  grace: grace,
);

void main() {
  test('los valores por defecto son 2 en paralelo, 9 intentos y 1,5 s', () {
    final selector = AutoStreamSelector(
      StreamProber(MockClient((_) async => http.Response('', 200))),
    );
    expect(selector.batchSize, 2);
    expect(selector.maxAttempts, 9);
    expect(selector.grace, const Duration(milliseconds: 1500));
  });

  test(
    'el 2.º responde antes pero el 1.º llega dentro de la gracia y gana',
    () async {
      final server = _Server({
        's1': _Behavior.ok(_ms(60)),
        's2': _Behavior.ok(_ms(5)),
        's3': const _Behavior.never(),
      });
      final result = await _selector(server).select(_streams(3));
      expect(result.chosen?.name, 's1');
      expect(result.cancelled, isFalse);
      // El 3.º, que no había respondido, se abortó.
      await Future<void>.delayed(Duration.zero);
      expect(server.aborted, contains('s3'));
      expect(server.aborted, isNot(contains('s1')));
    },
  );

  test(
    'si el 1.º no llega dentro de la gracia, gana el 2.º y se aborta el 1.º',
    () async {
      final server = _Server({
        's1': const _Behavior.never(),
        's2': _Behavior.ok(_ms(5)),
        's3': const _Behavior.never(),
      });
      final stopwatch = Stopwatch()..start();
      final result = await _selector(server).select(_streams(3));
      expect(result.chosen?.name, 's2');
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(250));
      await Future<void>.delayed(Duration.zero);
      expect(server.aborted, containsAll(['s1', 's3']));
    },
  );

  test('el 1.º falla y gana el 2.º sin esperar la gracia', () async {
    final server = _Server({
      's1': _Behavior.fail(_ms(5)),
      's2': _Behavior.ok(_ms(20)),
      's3': const _Behavior.never(),
    });
    final stopwatch = Stopwatch()..start();
    final result = await _selector(
      server,
      grace: const Duration(seconds: 5),
    ).select(_streams(3));
    expect(result.chosen?.name, 's2');
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    await Future<void>.delayed(Duration.zero);
    expect(server.aborted, contains('s3'));
  });

  test('si el 1.º ya respondió bien no espera a los demás', () async {
    final server = _Server({
      's1': _Behavior.ok(_ms(5)),
      's2': const _Behavior.never(),
      's3': const _Behavior.never(),
    });
    final stopwatch = Stopwatch()..start();
    final result = await _selector(
      server,
      grace: const Duration(seconds: 5),
    ).select(_streams(3));
    expect(result.chosen?.name, 's1');
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    await Future<void>.delayed(Duration.zero);
    expect(server.aborted, containsAll(['s2', 's3']));
  });

  test('si fallan los 3 primeros sigue con los siguientes', () async {
    final server = _Server({
      's1': _Behavior.fail(_ms(5)),
      's2': _Behavior.fail(_ms(5)),
      's3': _Behavior.fail(_ms(5)),
      's4': _Behavior.fail(_ms(5)),
      's5': _Behavior.ok(_ms(5)),
    });
    final result = await _selector(server).select(_streams(8));
    expect(result.chosen?.name, 's5');
    expect(result.attempts, 6);
    expect(server.requested.toSet(), {'s1', 's2', 's3', 's4', 's5', 's6'});
  });

  test('hasta 9 intentos y después se rinde', () async {
    final server = _Server({});
    final result = await _selector(server).select(_streams(15));
    expect(result.chosen, isNull);
    expect(result.cancelled, isFalse);
    expect(result.attempts, 9);
    expect(server.requested.toSet(), {for (var i = 1; i <= 9; i++) 's$i'});
  });

  test('con menos streams que intentos prueba todos y termina', () async {
    final server = _Server({});
    final result = await _selector(server).select(_streams(2));
    expect(result.chosen, isNull);
    expect(result.attempts, 2);
  });

  test('sin streams no hay elegido', () async {
    final result = await _selector(_Server({})).select(const []);
    expect(result.chosen, isNull);
    expect(result.attempts, 0);
    expect(result.alternatives, isEmpty);
  });

  test('cancelar aborta todos los pedidos', () async {
    final server = _Server({
      's1': const _Behavior.never(),
      's2': const _Behavior.never(),
      's3': const _Behavior.never(),
    });
    final cancel = Completer<void>();
    final future = _selector(server).select(_streams(5), cancel: cancel.future);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(server.requested, hasLength(3));
    cancel.complete();
    final result = await future;
    expect(result.cancelled, isTrue);
    expect(result.chosen, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(server.aborted.toSet(), {'s1', 's2', 's3'});
    // No arranca otra tanda después de cancelar.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.requested, hasLength(3));
  });

  test('cancelar antes de empezar no pide nada', () async {
    final server = _Server({'s1': _Behavior.ok(_ms(5))});
    final result = await _selector(server)
        .select(_streams(3), cancel: Future<void>.value());
    expect(result.cancelled, isTrue);
    expect(server.requested, isEmpty);
  });

  test(
    'la cola de alternativas no repite el elegido ni los que fallaron',
    () async {
      final server = _Server({
        's1': _Behavior.fail(_ms(5)),
        's2': _Behavior.ok(_ms(5)),
        's3': _Behavior.ok(_ms(5)),
      });
      final result = await _selector(server).select(_streams(6));
      expect(result.chosen?.name, 's2');
      expect(_names(result.alternatives), ['s3', 's4', 's5', 's6']);
      expect(result.alternatives, isNot(contains(result.chosen)));
    },
  );

  test('si nadie sirve la cola no tiene los que ya fallaron', () async {
    final server = _Server({});
    final result = await _selector(server).select(_streams(12));
    expect(_names(result.alternatives), ['s10', 's11', 's12']);
  });

  test('un batchSize menor a 1 no se acepta', () {
    final prober = StreamProber(
      MockClient((_) async => http.Response('', 200)),
    );
    expect(() => AutoStreamSelector(prober, batchSize: 0), throwsA(anything));
  });

  test('no prueba ni elige los no cacheados: quedan al final', () async {
    final server = _Server({
      's1': _Behavior.ok(_ms(5)),
      's2': _Behavior.ok(_ms(5)),
      's3': _Behavior.ok(_ms(5)),
    });
    final streams = [
      AddonStream.fromJson({
        'name': 's1 [RD download]',
        'url': 'https://cdn.example.com/s1',
      }),
      AddonStream.fromJson({
        'name': 's2',
        'url': 'https://cdn.example.com/s2',
      }),
      AddonStream.fromJson({
        'name': 's3 [RD+]',
        'url': 'https://cdn.example.com/s3',
      }),
    ];
    final result = await _selector(server).select(streams);
    expect(result.chosen?.name, 's2');
    expect(server.requested, isNot(contains('s1')));
    expect(_names(result.alternatives), ['s3 [RD+]', 's1 [RD download]']);
    expect(_names(result.unprobed), ['s1 [RD download]']);
  });

  test('si solo hay no cacheados no pide nada y no elige', () async {
    final server = _Server({'s1': _Behavior.ok(_ms(5))});
    final result = await _selector(server).select([
      AddonStream.fromJson({
        'name': 's1 ⏳',
        'url': 'https://cdn.example.com/s1',
      }),
    ]);
    expect(result.chosen, isNull);
    expect(server.requested, isEmpty);
    expect(result.attempts, 0);
    expect(result.alternatives, hasLength(1));
    expect(result.unprobed, hasLength(1));
  });

  test('si el prober tira un error cuenta como falla y sigue', () async {
    final client = MockClient.streaming(
      (request, _) async => http.StreamedResponse(
        Stream.value([0]),
        206,
        headers: {
          'content-type': 'video/mp4',
          'content-range': 'bytes 0-0/900000000',
        },
        contentLength: 1,
      ),
    );
    final result = await AutoStreamSelector(
      _ThrowingProber(client),
      batchSize: 1,
    ).select(_streams(2));
    expect(result.chosen?.name, 's2');
    expect(result.alternatives, isEmpty);
  });
}

class _ThrowingProber extends StreamProber {
  _ThrowingProber(super.client);

  @override
  Future<ProbeResult> probe(AddonStream stream, {Future<void>? abortTrigger}) {
    if (stream.name == 's1') return Future.error(StateError('x'));
    return super.probe(stream, abortTrigger: abortTrigger);
  }
}
