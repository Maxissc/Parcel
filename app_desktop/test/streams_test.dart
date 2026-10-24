import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/router.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';
import 'package:parcel_desktop/features/streams/stream_info.dart';
import 'package:parcel_desktop/features/streams/streams_args.dart';
import 'package:parcel_desktop/features/streams/streams_screen.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _firstKey = 'streams.example.com/stream/movie/tt0133093.json';
const _secondKey = 'more-streams.example.com/stream/movie/tt0133093.json';

Map<String, dynamic> _streamsBody() => {
  'streams': [
    {
      'name': 'Streams uno\n1080p',
      'description': 'The.Matrix.1999.1080p.BluRay HDR\n💾 2.1 GB',
      'url': 'http://media.example.com/matrix.mkv',
      'behaviorHints': {
        'bingeGroup': 'uno-1080',
        'proxyHeaders': {
          'request': {'Referer': 'http://origen.example.com'},
        },
      },
    },
    {
      'name': 'Torrent',
      'title': 'Matrix 2160p DV 12.5 GB',
      'infoHash': 'abc123',
    },
    {
      'name': 'Web',
      'title': 'Mirar en el sitio',
      'externalUrl': 'https://web.example.com/watch',
    },
  ],
};

AddonStream _s(Map<String, dynamic> json) =>
    AddonStream.fromJson({'url': 'http://x/v.mkv', ...json});

void main() {
  late Directory dir;
  late CatalogWorld world;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
    world.routes[_firstKey] = _streamsBody();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Meta matrix() => Meta.fromJson(movieMeta('tt0133093', 'The Matrix'));

  Future<void> openStreams(
    WidgetTester tester,
    StreamsArgs args, {
    List<String> addons = const [streamsAddonUrl, secondStreamsAddonUrl],
    List<Uri>? openedUrls,
    FakePlaybackEngine? engine,
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: [cinemetaUrl, subtitlesUrl, ...addons],
      onboardingCompleted: true,
    );
    await pumpApp(
      tester,
      dir,
      world.client,
      openedUrls: openedUrls,
      overrides: [
        if (engine != null)
          playbackEngineFactoryProvider.overrideWithValue(() => engine),
      ],
    );
    routerOf(tester).push(Routes.streams, extra: args);
    await pumpIo(tester, ticks: 6);
  }

  testWidgets('agrupa por addon en orden y cada grupo cuenta su estado', (
    tester,
  ) async {
    world.routes[_secondKey] = {'streams': []};
    await openStreams(tester, StreamsArgs(meta: matrix()));

    expect(find.text('Streams uno'), findsOneWidget);
    expect(find.text('Streams dos'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Streams uno')).dy,
      lessThan(tester.getTopLeft(find.text('Streams dos')).dy),
    );
    expect(find.text('3 streams'), findsOneWidget);
    expect(find.text('Sin streams'), findsOneWidget);
    // Nombre como etiqueta y descripción multilínea.
    expect(find.text('Streams uno\n1080p'), findsOneWidget);
    expect(
      find.textContaining('The.Matrix.1999.1080p.BluRay HDR'),
      findsOneWidget,
    );
    // Chips detectados del texto.
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('HDR'), findsOneWidget);
    expect(find.text('2.1 GB'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('DV'), findsOneWidget);
    expect(find.text('12.5 GB'), findsOneWidget);
  });

  testWidgets('un addon que falla muestra el motivo y no tumba a los demás', (
    tester,
  ) async {
    world.failing.add(_secondKey);
    await openStreams(tester, StreamsArgs(meta: matrix()));

    expect(find.text('3 streams'), findsOneWidget);
    expect(
      find.text('No se pudo cargar · Respondió con el error 500'),
      findsOneWidget,
    );
  });

  testWidgets('muestra «Buscando…» en el grupo que todavía no respondió', (
    tester,
  ) async {
    final gate = Completer<void>();
    world.gates[_secondKey] = gate;
    world.routes[_secondKey] = {'streams': []};
    await openStreams(tester, StreamsArgs(meta: matrix()));

    expect(find.text('3 streams'), findsOneWidget);
    expect(find.text('Buscando…'), findsOneWidget);
    expect(find.textContaining('Buscando en 2 addons'), findsOneWidget);

    gate.complete();
    await pumpIo(tester, ticks: 4);
    expect(find.text('Buscando…'), findsNothing);
    expect(find.text('Sin streams'), findsOneWidget);
  });

  testWidgets('los torrents quedan deshabilitados y avisan por qué', (
    tester,
  ) async {
    await openStreams(tester, StreamsArgs(meta: matrix()));

    expect(
      find.byTooltip('Los torrents todavía no están soportados'),
      findsOneWidget,
    );
    await tester.tap(find.text('Torrent'));
    await pumpIo(tester, ticks: 2);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(StreamsScreen), findsOneWidget);
  });

  testWidgets('un enlace externo avisa que se abre fuera y abre el navegador', (
    tester,
  ) async {
    final opened = <Uri>[];
    await openStreams(tester, StreamsArgs(meta: matrix()), openedUrls: opened);

    expect(find.byTooltip('Se abre fuera de Parcel'), findsOneWidget);
    await tester.tap(find.text('Web'));
    await pumpIo(tester, ticks: 2);

    expect(opened, [Uri.parse('https://web.example.com/watch')]);
    expect(find.byType(PlayerScreen), findsNothing);
  });

  testWidgets(
    'elegir un stream reproducible abre el reproductor con sus headers',
    (tester) async {
      final engine = FakePlaybackEngine();
      await openStreams(tester, StreamsArgs(meta: matrix()), engine: engine);

      await tester.tap(find.text('Streams uno\n1080p'));
      await pumpIo(tester, ticks: 4);

      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(engine.lastSource!.url, 'http://media.example.com/matrix.mkv');
      expect(engine.lastSource!.headers, {
        'Referer': 'http://origen.example.com',
      });
      expect(find.text('The Matrix'), findsWidgets);
    },
  );

  testWidgets('sin addons de streams explica qué hacer', (tester) async {
    await openStreams(tester, StreamsArgs(meta: matrix()), addons: const []);

    expect(
      find.text('Ningún addon instalado ofrece streams para esto'),
      findsOneWidget,
    );
    expect(find.text('Ir a Addons'), findsOneWidget);
  });

  testWidgets(
    'para el episodio siguiente sugiere el mismo addon y bingeGroup',
    (tester) async {
      await openStreams(
        tester,
        StreamsArgs(
          meta: matrix(),
          preferAddonUrl: streamsAddonUrl,
          preferBingeGroup: 'uno-1080',
        ),
      );

      expect(find.text('Igual que el anterior'), findsOneWidget);
    },
  );

  testWidgets('el sugerido tiene el foco y Enter lo reproduce', (tester) async {
    final engine = FakePlaybackEngine(
      mediaDuration: const Duration(minutes: 10),
    );
    await openStreams(
      tester,
      StreamsArgs(
        meta: matrix(),
        preferAddonUrl: streamsAddonUrl,
        preferBingeGroup: 'uno-1080',
      ),
      engine: engine,
    );

    final focus = FocusManager.instance.primaryFocus;
    expect(focus, isNotNull);
    expect(focus!.debugLabel, 'stream-recomendado');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpIo(tester, ticks: 4);
    expect(engine.lastSource?.url, 'http://media.example.com/matrix.mkv');
  });

  testWidgets(
    'sin bingeGroup, el addon del episodio anterior va primero y sugiere su '
    'primer stream',
    (tester) async {
      world.routes[_secondKey] = {
        'streams': [
          {'name': 'Dos 720p', 'url': 'http://media.example.com/dos.mkv'},
          {'name': 'Dos 1080p', 'url': 'http://media.example.com/dos2.mkv'},
        ],
      };
      final engine = FakePlaybackEngine(
        mediaDuration: const Duration(minutes: 10),
      );
      await openStreams(
        tester,
        StreamsArgs(meta: matrix(), preferAddonUrl: secondStreamsAddonUrl),
        engine: engine,
      );

      // «Streams dos» (el addon anterior) aparece antes que «Streams uno».
      expect(
        tester.getTopLeft(find.text('Streams dos')).dy,
        lessThan(tester.getTopLeft(find.text('Streams uno').first).dy),
      );
      expect(find.text('Del mismo addon'), findsOneWidget);
      expect(find.text('Igual que el anterior'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpIo(tester, ticks: 4);
      expect(engine.lastSource?.url, 'http://media.example.com/dos.mkv');
    },
  );

  testWidgets(
    'al terminar un episodio, «siguiente» abre sus streams y atrás vuelve al inicio',
    (tester) async {
      final meta = Meta.fromJson(seriesMeta('tt0903747', 'Breaking Bad'));
      world.routes['streams.example.com/stream/series/tt0903747:1:3.json'] = {
        'streams': [
          {
            'name': 'Streams uno',
            'title': 'Episodio 3',
            'url': 'http://media.example.com/e3.mkv',
            'behaviorHints': {'bingeGroup': 'uno-1080'},
          },
        ],
      };
      world.routes['streams.example.com/stream/series/tt0903747:2:1.json'] = {
        'streams': [
          {
            'name': 'Streams uno',
            'title': 'Episodio 4',
            'url': 'http://media.example.com/e4.mkv',
            'behaviorHints': {'bingeGroup': 'uno-1080'},
          },
        ],
      };
      final engine = FakePlaybackEngine(
        mediaDuration: const Duration(minutes: 10),
      );
      await openStreams(
        tester,
        StreamsArgs(meta: meta, video: meta.videos[2]),
        addons: const [streamsAddonUrl],
        engine: engine,
      );
      await tester.tap(find.text('Episodio 3'));
      await pumpIo(tester, ticks: 4);
      expect(find.byType(PlayerScreen), findsOneWidget);

      engine.tick(const Duration(minutes: 11));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Ver siguiente episodio'));
      await pumpIo(tester, ticks: 6);

      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byType(StreamsScreen), findsOneWidget);
      expect(find.text('T2 E1 · Episodio 2x1'), findsOneWidget);
      expect(find.text('Episodio 4'), findsOneWidget);
      expect(find.text('Igual que el anterior'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await pumpIo(tester, ticks: 6);
      expect(find.byType(StreamsScreen), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
    },
  );

  group('etiquetas del texto del stream', () {
    test('detecta resolución, HDR, DV y tamaño', () {
      expect(
        detectStreamChips(_s({'title': 'Movie 2160p UHD HDR10 DV 45.3 GB'})),
        ['4K', 'HDR', 'DV', '45.3 GB'],
      );
      expect(detectStreamChips(_s({'name': '4K'})), ['4K']);
      expect(detectStreamChips(_s({'name': 'Dolby Vision 1080p'})), [
        '1080p',
        'DV',
      ]);
      expect(detectStreamChips(_s({'title': 'x 720p 800 MB'})), [
        '720p',
        '800 MB',
      ]);
      expect(detectStreamChips(_s({'title': 'size 1,4 GiB'})), ['1.4 GB']);
    });

    test('no confunde números sueltos con calidades', () {
      expect(
        detectStreamChips(_s({'title': 'Año 2160 de 1080 caras'})),
        isEmpty,
      );
      expect(detectStreamChips(_s({'name': 'Server DVD'})), isEmpty);
    });

    test('sin tamaño en el texto usa el del addon', () {
      final stream = _s({
        'title': '1080p',
        'behaviorHints': {'videoSize': 3221225472},
      });
      expect(detectStreamChips(stream), ['1080p', '3.0 GB']);
    });

    test('qué se puede reproducir', () {
      expect(blockOf(_s({})), isNull);
      expect(
        blockOf(AddonStream.fromJson({'infoHash': 'a'})),
        StreamBlock.torrent,
      );
      expect(
        blockOf(AddonStream.fromJson({'externalUrl': 'https://a.b'})),
        StreamBlock.external,
      );
      expect(
        blockOf(AddonStream.fromJson({'ytId': 'abc'})),
        StreamBlock.unsupported,
      );
    });
  });
}
