import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

/// Cliente que nunca responde pero se entera si el pedido se aborta.
class _HangingServer {
  final List<Uri> started = [];
  final List<Uri> aborted = [];

  late final MockClient client = MockClient.streaming((request, _) {
    started.add(request.url);
    final completer = Completer<http.StreamedResponse>();
    final trigger = request is http.Abortable ? request.abortTrigger : null;
    trigger?.then((_) {
      aborted.add(request.url);
      if (!completer.isCompleted) {
        completer.completeError(http.RequestAbortedException(request.url));
      }
    });
    return completer.future;
  });
}

final _addon = InstalledAddon(
  transportUrl: 'https://lento.example.com/manifest.json',
  manifest: AddonManifest.fromJson({
    'id': 'test.lento',
    'name': 'Lento',
    'version': '1.0.0',
    'resources': ['stream', 'subtitles', 'meta', 'catalog'],
    'types': ['movie'],
  }),
);

void main() {
  test('el agregador aborta el pedido cuando vence el timeout', () async {
    final server = _HangingServer();
    final agg = AddonAggregator(
      client: AddonClient(server.client),
      addons: () => [_addon],
      timeout: const Duration(milliseconds: 50),
    );
    final results = await agg.streams('movie', 'tt1');
    final failure = results.single as AddonFailure<List<AddonStream>>;
    expect(failure.error.reason, AddonFailureReason.timeout);
    await Future<void>.delayed(Duration.zero);
    expect(server.started, hasLength(1));
    expect(server.aborted, server.started);
  });

  test('el agregador aborta también los subtítulos y la meta', () async {
    final server = _HangingServer();
    final agg = AddonAggregator(
      client: AddonClient(server.client),
      addons: () => [_addon],
      timeout: const Duration(milliseconds: 50),
    );
    await agg.subtitles('movie', 'tt1');
    await agg.meta('movie', 'tt1');
    await agg.fetchCatalog(
      CatalogRef(
        _addon,
        AddonCatalog.fromJson({'type': 'movie', 'id': 'top', 'name': 'Top'}),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(server.started, hasLength(3));
    expect(server.aborted, hasLength(3));
  });

  test('el repositorio aborta el manifest cuando vence el timeout', () async {
    final server = _HangingServer();
    final dir = Directory.systemTemp.createTempSync('parcel_abort_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = await AddonRepository.open(
      client: AddonClient(server.client),
      filePath: '${dir.path}/addons.json',
      installTimeout: const Duration(milliseconds: 50),
    );
    final result = await repo.install('https://lento.example.com');
    expect((result as InstallFailed).error.reason, AddonFailureReason.timeout);
    await Future<void>.delayed(Duration.zero);
    expect(server.aborted, hasLength(1));
  });

  test('un pedido sin timeout no se aborta', () async {
    final seen = <bool>[];
    final client = AddonClient(
      MockClient.streaming((request, _) async {
        final trigger = (request as http.Abortable).abortTrigger;
        var fired = false;
        trigger?.then((_) => fired = true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        seen.add(fired);
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'streams': [
                  {'url': 'https://cdn.example.com/a.mp4'},
                ],
              }),
            ),
          ),
          200,
        );
      }),
    );
    final streams = await client.streams(_addon, 'movie', 'tt1');
    expect(streams, hasLength(1));
    expect(seen, [false]);
  });

  test(
    'abortTrigger propio: el cliente falla con una AddonException',
    () async {
      final server = _HangingServer();
      final client = AddonClient(server.client);
      final trigger = Completer<void>();
      final future = client.streams(
        _addon,
        'movie',
        'tt1',
        abortTrigger: trigger.future,
      );
      trigger.complete();
      await expectLater(
        future,
        throwsA(
          isA<AddonException>()
              .having((e) => e.reason, 'reason', AddonFailureReason.timeout)
              .having(
                (e) => e.toString(),
                'toString',
                isNot(contains('lento')),
              ),
        ),
      );
    },
  );
}
