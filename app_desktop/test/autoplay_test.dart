import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/diagnostics/diag_log.dart';
import 'package:parcel_desktop/app/router.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/features/player/play_item.dart';
import 'package:parcel_desktop/features/player/side_panel.dart';
import 'package:parcel_desktop/features/player/play_args.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';
import 'package:parcel_desktop/features/streams/streams_screen.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _streamsKey = 'streams.example.com/stream/movie/tt0133093.json';

Map<String, dynamic> _stream(String name, String path, {String query = ''}) => {
  'name': name,
  'url': 'http://media.example.com/$path$query',
};

void main() {
  late Directory dir;
  late CatalogWorld world;
  late List<String> diagLines;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
    diagLines = [];
  });
  tearDown(() => deleteTempDir(dir));

  Meta matrix() => Meta.fromJson(movieMeta('tt0133093', 'The Matrix'));

  FakePlaybackEngine fake({String? openError}) =>
      FakePlaybackEngine(mediaDuration: const Duration(minutes: 10))
        ..openError = openError;

  /// Abre la app y empuja la ruta de reproducción directo.
  Future<void> play(
    WidgetTester tester,
    List<FakePlaybackEngine> engines, {
    StreamProber? prober,
    PlayArgs? args,
    List<PlaybackProgress> progress = const [],
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
      onboardingCompleted: true,
      progress: progress,
    );
    final queue = [...engines];
    await pumpApp(
      tester,
      dir,
      world.client,
      prober: prober,
      overrides: [
        playbackEngineFactoryProvider.overrideWithValue(
          () => queue.length > 1 ? queue.removeAt(0) : queue.first,
        ),
        diagLogProvider.overrideWithValue(DiagLog(sink: diagLines.add)),
      ],
    );
    routerOf(tester).push(
      Routes.play,
      extra: args ?? PlayArgs(meta: matrix(), resume: ResumeMode.resume),
    );
    await tester.pump();
  }

  testWidgets('arranca sola con el mejor stream y lo anota sin URLs', (
    tester,
  ) async {
    world.routes[_streamsKey] = {
      'streams': [
        _stream('Uno 720p', 'a.mkv', query: '?token=SECRETO'),
        _stream('Dos 1080p [RD+]', 'b.mkv', query: '?token=SECRETO'),
      ],
    };
    final engine = fake();
    await play(tester, [engine]);
    expect(find.text('Buscando la mejor fuente…'), findsOneWidget);
    await pumpIo(tester, ticks: 8);

    expect(find.byType(PlayerScreen), findsOneWidget);
    // Cacheado y 1080p gana al de 720p aunque venga después.
    expect(
      engine.lastSource?.url,
      startsWith('http://media.example.com/b.mkv'),
    );
    expect(
      diagLines.where((l) => l.contains('autoplay: elegida')),
      hasLength(1),
    );
    for (final line in diagLines) {
      expect(line, isNot(contains('SECRETO')));
      expect(line, isNot(contains('media.example.com')));
    }
    expect(find.textContaining('SECRETO'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpIo(tester, ticks: 4);
  });

  testWidgets('al arrancar con autoplay la lista de fuentes no se ve ni un '
      'cuadro', (tester) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p', 'a.mkv'), _stream('Dos 720p', 'b.mkv')],
    };
    await play(tester, [fake()]);

    // Desde el primer cuadro hasta que abre el reproductor.
    for (var i = 0; i < 60; i++) {
      expect(
        find.byType(StreamsScreen),
        findsNothing,
        reason: 'la lista asomó en el cuadro $i',
      );
      expect(find.text('Uno 1080p'), findsNothing);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }
    await pumpIo(tester, ticks: 8);
    expect(find.byType(PlayerScreen), findsOneWidget);
  });

  testWidgets('si la fuente falla al abrir, pasa a la siguiente con el aviso', (
    tester,
  ) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p', 'a.mkv'), _stream('Dos 1080p', 'b.mkv')],
    };
    // La segunda prueba de b.mkv espera: se alcanza a ver el aviso.
    final gate = Completer<void>();
    var bProbes = 0;
    final prober = StreamProber(
      MockClient((request) async {
        if (request.url.path == '/b.mkv' && ++bProbes == 2) {
          await gate.future;
        }
        return http.Response(
          '',
          206,
          headers: {
            'content-type': 'video/mp4',
            'content-range': 'bytes 0-0/52428800',
          },
        );
      }),
    );
    final broken = fake(openError: 'Failed to open');
    final good = fake();
    await play(tester, [broken, good], prober: prober);
    await pumpIo(tester, ticks: 8);

    expect(find.text('Esa fuente no anduvo, probando otra…'), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    gate.complete();
    await pumpIo(tester, ticks: 8);

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(broken.lastSource?.url, 'http://media.example.com/a.mkv');
    expect(good.lastSource?.url, 'http://media.example.com/b.mkv');
    expect(
      diagLines,
      contains(startsWith('[diag] autoplay: la fuente de Streams uno no')),
    );
  });

  testWidgets('una fuente que no arranca en 20 s también se saltea', (
    tester,
  ) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p', 'a.mkv'), _stream('Dos 1080p', 'b.mkv')],
    };
    final stalled = fake()..stallOnOpen = true;
    final good = fake();
    await play(tester, [stalled, good]);
    await pumpIo(tester, ticks: 6);
    expect(find.byType(PlayerScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 21));
    await pumpIo(tester, ticks: 8);

    expect(good.lastSource?.url, 'http://media.example.com/b.mkv');
  });

  testWidgets('sin fuentes que anden ofrece «Elegir a mano»', (tester) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p', 'a.mkv')],
    };
    await play(tester, [fake()], prober: fakeProber(broken: {'/a.mkv'}));
    await pumpIo(tester, ticks: 8);

    expect(find.text('No encontramos una fuente que funcione'), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);
    await tester.tap(find.byKey(const Key('play-manual')));
    await pumpIo(tester, ticks: 6);
    expect(find.byType(StreamsScreen), findsOneWidget);
    expect(find.text('Uno 1080p'), findsWidgets);
  });

  testWidgets('si solo hay fuentes sin cachear no las prueba y avisa', (
    tester,
  ) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p [RD download]', 'a.mkv')],
    };
    final engine = fake();
    await play(tester, [engine]);
    await pumpIo(tester, ticks: 8);

    expect(find.text('No encontramos una fuente lista'), findsOneWidget);
    expect(engine.openCount, 0);
    expect(find.byKey(const Key('play-manual')), findsOneWidget);
  });

  testWidgets('el menú «Fuente» lista el ranking y cambia de fuente', (
    tester,
  ) async {
    world.routes[_streamsKey] = {
      'streams': [
        _stream('Uno 1080p [RD+]', 'a.mkv'),
        _stream('Dos 720p [RD+]', 'b.mkv'),
        _stream('Tres 1080p [RD download]', 'c.mkv'),
      ],
    };
    final first = fake();
    final second = fake();
    await play(tester, [first, second]);
    await pumpIo(tester, ticks: 8);
    first.tick(const Duration(seconds: 42));
    await tester.pump();

    await tester.tap(find.byKey(const Key('player-source-menu')));
    await tester.pumpAndSettle();
    final items = find.byType(PanelOption);
    expect(items, findsNWidgets(3));
    expect(tester.widget<PanelOption>(items.at(0)).checked, isTrue);
    expect(tester.widget<PanelOption>(items.at(1)).checked, isFalse);
    // Los que hay que bajar en el debrid se marcan.
    expect(find.text('Sin cachear'), findsOneWidget);

    await tester.tap(items.at(1));
    await pumpIo(tester, ticks: 6);

    expect(second.lastSource?.url, 'http://media.example.com/b.mkv');
    // Sigue donde iba.
    expect(second.lastSource?.startPosition, const Duration(seconds: 42));
  });

  testWidgets('pregunta si continuar y respeta la respuesta', (tester) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p', 'a.mkv')],
    };
    final engine = fake();
    await play(
      tester,
      [engine],
      args: PlayArgs(meta: matrix()),
      progress: [
        PlaybackProgress(
          type: 'movie',
          metaId: 'tt0133093',
          videoId: 'tt0133093',
          position: const Duration(minutes: 3),
          duration: const Duration(minutes: 10),
          name: 'The Matrix',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    await pumpIo(tester, ticks: 8);
    expect(find.text('Ya empezaste esto'), findsOneWidget);
    expect(find.byType(PlayerScreen), findsNothing);

    await tester.tap(find.text('Continuar desde 3:00'));
    await pumpIo(tester, ticks: 8);
    expect(engine.lastSource?.startPosition, const Duration(minutes: 3));
  });

  testWidgets('las pantallas nuevas entran en 960×600 sin desbordar', (
    tester,
  ) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p [RD download]', 'a.mkv')],
    };
    await play(tester, [fake()]);
    tester.view.physicalSize = const Size(960, 600);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await pumpIo(tester, ticks: 8);
    expect(find.text('No encontramos una fuente lista'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a los 19 s la fuente sigue; un stream en vivo que avanza no '
      'se saltea', (tester) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p', 'a.mkv'), _stream('Dos 1080p', 'b.mkv')],
    };
    final stalled = fake()..stallOnOpen = true;
    final good = fake();
    await play(tester, [stalled, good]);
    await pumpIo(tester, ticks: 6);

    await tester.pump(const Duration(seconds: 19));
    expect(good.openCount, 0, reason: 'a los 19 s todavía se espera');

    // La posición avanza sin duración (en vivo): ya arrancó.
    stalled.tick(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    await pumpIo(tester, ticks: 4);

    expect(good.openCount, 0);
    expect(find.byType(PlayerScreen), findsOneWidget);
  });

  testWidgets('cada intento de fuente reusa el pedido de subtítulos del '
      'contenido', (tester) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p', 'a.mkv'), _stream('Dos 1080p', 'b.mkv')],
    };
    world.routes['opensubtitles-v3.strem.io/subtitles/movie/tt0133093.json'] = {
      'subtitles': [
        {'id': 'es', 'url': 'http://subs.example.com/es.srt', 'lang': 'spa'},
      ],
    };
    final broken = fake(openError: 'Failed to open');
    final good = fake();
    await play(tester, [broken, good]);
    await pumpIo(tester, ticks: 12);

    expect(good.lastSource?.url, 'http://media.example.com/b.mkv');
    expect(world.count('opensubtitles-v3.strem.io/subtitles'), 1);
  });

  testWidgets('volver mientras prueba las fuentes cancela: no se abre ningún '
      'motor', (tester) async {
    world.routes[_streamsKey] = {
      'streams': [_stream('Uno 1080p', 'a.mkv')],
    };
    final gate = Completer<void>();
    final prober = StreamProber(
      MockClient((request) async {
        await gate.future;
        return http.Response(
          '',
          206,
          headers: {
            'content-type': 'video/mp4',
            'content-range': 'bytes 0-0/52428800',
          },
        );
      }),
    );
    final engine = fake();
    await play(tester, [engine], prober: prober);
    await pumpIo(tester, ticks: 8);
    expect(find.text('Buscando la mejor fuente…'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpIo(tester, ticks: 6);
    expect(find.text('Buscando la mejor fuente…'), findsNothing);

    gate.complete();
    await pumpIo(tester, ticks: 8);
    expect(engine.openCount, 0);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
