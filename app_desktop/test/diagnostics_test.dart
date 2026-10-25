import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/app/diagnostics/diag_log.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/diagnostics/playback_diagnostics.dart';
import 'package:parcel_desktop/data/platform.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _brokenUrl = 'https://roto.example.com/token-secreto/manifest.json';

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir());
  tearDown(() => deleteTempDir(dir));

  test(
    'PARCEL_DIAG_PASTE llega a la configuración (solo con PARCEL_DIAG=1)',
    () {
      // fromEnvironment solo devuelve algo en debug, que es como corren los tests.
      final config = DiagnosticsConfig.fromEnvironment({
        'PARCEL_DIAG': '1',
        'PARCEL_DIAG_PASTE': 'https://a.example.com https://b.example.com',
      });
      expect(config?.paste, 'https://a.example.com https://b.example.com');
      expect(
        DiagnosticsConfig.fromEnvironment({'PARCEL_DIAG_PASTE': 'x'}),
        isNull,
      );
    },
  );

  test('DiagLog antepone [diag] y el apagado no escribe nada', () {
    final lines = <String>[];
    DiagLog(sink: lines.add).log('hola');
    const DiagLog.disabled().log('no sale');
    expect(lines, ['[diag] hola']);
  });

  testWidgets(
    'el diagnóstico pega la lista, confirma y deja el informe en el log',
    (tester) async {
      final lines = <String>[];
      await pumpApp(
        tester,
        dir,
        mockWorld(defaultRoutes()),
        overrides: [
          diagnosticsConfigProvider.overrideWithValue(
            const DiagnosticsConfig(
              paste: '$cinemetaUrl $subtitlesUrl $_brokenUrl',
            ),
          ),
          diagLogProvider.overrideWithValue(DiagLog(sink: lines.add)),
        ],
      );
      await pumpUntil(tester, find.byKey(const Key('go-home')));

      final log = lines.join('\n');
      expect(lines, everyElement(startsWith('[diag] ')));
      expect(log, contains('onboarding paso=welcome'));
      expect(log, contains('onboarding fuente=pasted candidatos=3'));
      expect(log, contains('onboarding paso=progress'));
      expect(
        log,
        contains('onboarding informe instalados=2 yaEstaban=0 fallaron=1'),
      );
      // El que falló sale con su host y su motivo, nunca con la URL completa.
      expect(
        log,
        contains(
          'roto.example.com resultado=failed '
          'motivo="El addon respondió con un error (HTTP 404)."',
        ),
      );
      expect(log, isNot(contains('token-secreto')));
      expect(log, isNot(contains('/manifest.json')));
    },
  );

  test('ocultar una fila y Ver todo llegan a la configuración', () {
    final config = DiagnosticsConfig.fromEnvironment({
      'PARCEL_DIAG': '1',
      'PARCEL_DIAG_HIDE_ROW': '2',
      'PARCEL_DIAG_SEE_ALL': '1',
    });
    expect(config?.hideRow, 2);
    expect(config?.seeAll, isTrue);
    final off = DiagnosticsConfig.fromEnvironment({'PARCEL_DIAG': '1'});
    expect(off?.hideRow, isNull);
    expect(off?.seeAll, isFalse);
  });

  test('las variables del recorrido llegan a la configuración', () {
    final config = DiagnosticsConfig.fromEnvironment({
      'PARCEL_DIAG': '1',
      'PARCEL_DIAG_OPEN': 'series/tt0903747',
      'PARCEL_DIAG_SEARCH': 'matrix',
      'PARCEL_DIAG_PLAY_FIRST_STREAM': '1',
    });
    expect(config?.open, 'series/tt0903747');
    expect(config?.search, 'matrix');
    expect(config?.playFirstStream, isTrue);
    final off = DiagnosticsConfig.fromEnvironment({'PARCEL_DIAG': '1'});
    expect(off?.open, isNull);
    expect(off?.playFirstStream, isFalse);
  });

  test(
    'las variables de reproducción automática llegan a la configuración',
    () {
      final config = DiagnosticsConfig.fromEnvironment({
        'PARCEL_DIAG': '1',
        'PARCEL_DIAG_AUTOPLAY': '1',
        'PARCEL_DIAG_SYNC_TAPS': '12.0, 35.5,basura',
        'PARCEL_DIAG_MIN_PROBE_BYTES': '0',
      });
      expect(config?.autoplay, isTrue);
      expect(config?.syncTaps, [
        const Duration(seconds: 12),
        const Duration(seconds: 35, milliseconds: 500),
      ]);
      expect(config?.probeMinBytes, 0);
      final off = DiagnosticsConfig.fromEnvironment({'PARCEL_DIAG': '1'});
      expect(off?.autoplay, isFalse);
      expect(off?.syncTaps, isEmpty);
      expect(off?.probeMinBytes, isNull);
    },
  );

  group('recorrido de la navegación', () {
    late CatalogWorld world;

    setUp(() {
      world = CatalogWorld();
      for (final type in ['movie', 'series']) {
        world.routes['v3-cinemeta.strem.io/catalog/$type/top/search=matrix.json'] =
            {
              'metas': type == 'movie'
                  ? [metaItem('tt0133093', 'The Matrix')]
                  : [],
            };
      }
      world.routes['streams.example.com/stream/series/tt0903747:1:1.json'] = {
        'streams': [
          {'name': 'Streams uno', 'url': 'http://media.example.com/e1.mkv'},
          {'name': 'Torrent', 'infoHash': 'abc'},
        ],
      };
    });

    Future<List<String>> run(
      WidgetTester tester,
      DiagnosticsConfig config, {
      List<String> addons = const [
        cinemetaUrl,
        subtitlesUrl,
        streamsAddonUrl,
        secondStreamsAddonUrl,
      ],
      FakePlaybackEngine? engine,
    }) async {
      final lines = <String>[];
      await seedData(
        tester,
        dir,
        world.client,
        urls: addons,
        onboardingCompleted: true,
      );
      await pumpApp(
        tester,
        dir,
        world.client,
        overrides: [
          diagnosticsConfigProvider.overrideWithValue(config),
          diagLogProvider.overrideWithValue(DiagLog(sink: lines.add)),
          if (engine != null)
            playbackEngineFactoryProvider.overrideWithValue(() => engine),
        ],
      );
      for (var i = 0; i < 40; i++) {
        await pumpIo(tester, ticks: 3);
        final done = lines.any(
          (l) =>
              l.contains('streams series tt0903747:1:1: Streams dos') ||
              l.contains('ningún addon instalado ofrece streams'),
        );
        if (done) break;
      }
      await pumpIo(tester, ticks: 3);
      return lines;
    }

    testWidgets('cuenta inicio, búsqueda, detalle y streams en el log', (
      tester,
    ) async {
      final lines = await run(
        tester,
        const DiagnosticsConfig(open: 'series/tt0903747', search: 'matrix'),
      );
      final log = lines.join('\n');

      expect(lines, everyElement(startsWith('[diag] ')));
      expect(
        log,
        contains('home fila «Popular · Películas» (Cinemeta): 2 ítems'),
      );
      expect(
        log,
        contains('home fila «Sin nada · Películas» (Cinemeta): vacía'),
      );
      expect(log, contains('home: 3 de 4 catálogos con ítems'));
      expect(log, contains('seguir viendo: 0 ítems'));
      expect(
        log,
        contains(
          'búsqueda «matrix»: 2 catálogos con búsqueda; '
          '«Popular · Películas» 1 resultados; «Popular · Series» 0 resultados',
        ),
      );
      expect(
        log,
        contains(
          'detalle series/tt0903747: «Breaking Bad» · 6 episodios · '
          '3 temporadas [1, 2, 0]',
        ),
      );
      expect(
        log,
        contains(
          'streams series tt0903747:1:1: Streams uno: 2 streams '
          '(1 reproducibles)',
        ),
      );
      expect(
        log,
        contains('streams series tt0903747:1:1: Streams dos: falló (http)'),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin addons de streams dice que ninguno ofrece streams', (
      tester,
    ) async {
      final lines = await run(
        tester,
        const DiagnosticsConfig(open: 'movie/tt0133093'),
        addons: const [cinemetaUrl, subtitlesUrl],
      );

      expect(
        lines.join('\n'),
        contains(
          'streams movie tt0133093: ningún addon instalado ofrece streams '
          'para esto',
        ),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('PARCEL_DIAG_PLAY_FIRST_STREAM reproduce el primer stream', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(
        mediaDuration: const Duration(minutes: 10),
      );
      final lines = await run(
        tester,
        const DiagnosticsConfig(
          open: 'series/tt0903747',
          playFirstStream: true,
        ),
        engine: engine,
      );
      await tester.pump(const Duration(seconds: 2));
      await pumpIo(tester, ticks: 10);

      expect(
        lines.join('\n'),
        contains(
          'reproducción: abre el primer stream reproducible de Streams uno',
        ),
      );
      expect(engine.lastSource?.url, 'http://media.example.com/e1.mkv');
      await tester.pumpWidget(const SizedBox());
      await pumpIo(tester, ticks: 4);
    });
  });
}
