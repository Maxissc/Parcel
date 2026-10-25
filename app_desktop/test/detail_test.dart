import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/router.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/features/detail/detail_screen.dart';
import 'package:parcel_desktop/features/detail/detail_utils.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';
import 'package:parcel_desktop/features/streams/streams_screen.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _matrixMeta = 'v3-cinemeta.strem.io/meta/movie/tt0133093.json';
const _bbMeta = 'v3-cinemeta.strem.io/meta/series/tt0903747.json';

PlaybackProgress _progress({
  String type = 'movie',
  String metaId = 'tt0133093',
  String? videoId,
  Duration position = const Duration(minutes: 2),
  DateTime? at,
}) => PlaybackProgress(
  type: type,
  metaId: metaId,
  videoId: videoId ?? metaId,
  position: position,
  duration: const Duration(minutes: 10),
  name: 'x',
  updatedAt: at ?? DateTime.utc(2026, 1, 1),
);

void main() {
  late Directory dir;
  late CatalogWorld world;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
    world.routes['streams.example.com/stream/movie/tt0133093.json'] = {
      'streams': [
        {'name': 'Calidad HD', 'url': 'http://media.example.com/matrix.mkv'},
      ],
    };
  });
  tearDown(() => deleteTempDir(dir));

  Future<void> openDetail(
    WidgetTester tester,
    String path, {
    Meta? hint,
    List<PlaybackProgress> progress = const [],
    FakePlaybackEngine? engine,
    bool tall = false,
    bool? autoSelectSource,
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
      onboardingCompleted: true,
      autoSelectSource: autoSelectSource,
      progress: progress,
    );
    await pumpApp(
      tester,
      dir,
      world.client,
      overrides: [
        if (engine != null)
          playbackEngineFactoryProvider.overrideWithValue(() => engine),
      ],
    );
    // El elenco empuja la lista de episodios hacia abajo: con una ventana alta
    // se ven los primeros sin scroll.
    if (tall) tester.view.physicalSize = const Size(1280, 1400);
    routerOf(tester).push(path, extra: hint);
    await pumpIo(tester, ticks: 6);
  }

  testWidgets('una serie muestra sus datos, temporadas y episodios', (
    tester,
  ) async {
    await openDetail(
      tester,
      Routes.detailPath('series', 'tt0903747'),
      tall: true,
    );

    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('2008–2013'), findsOneWidget);
    expect(find.text('47 min'), findsOneWidget);
    expect(find.text('9.5'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);
    expect(find.textContaining('Un profesor de química'), findsOneWidget);
    expect(find.textContaining('Bryan Cranston'), findsOneWidget);
    // La primera temporada que no es de especiales, con sus episodios.
    expect(find.text('Temporada 1'), findsOneWidget);
    for (final n in [1, 2, 3]) {
      expect(find.text('$n. Episodio 1x$n'), findsOneWidget);
    }
    expect(find.text('1. Episodio 2x1'), findsNothing);
    // Sin nada visto no hay botón de continuar.
    expect(find.byKey(const Key('detail-continue')), findsNothing);
  });

  testWidgets('una serie con mil episodios solo arma los que se ven', (
    tester,
  ) async {
    world.routes[_bbMeta] = {
      'meta': seriesMeta('tt0903747', 'Breaking Bad', episodes: {1: 1000}),
    };
    await openDetail(tester, Routes.detailPath('series', 'tt0903747'));

    final built = find.textContaining('Episodio 1x').evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(40));

    // Los de más abajo aparecen al desplazarse.
    final last = find.text('1000. Episodio 1x1000');
    expect(last, findsNothing);
    await tester.scrollUntilVisible(
      last,
      800,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 400,
    );
    expect(last, findsOneWidget);
  });

  testWidgets('el selector lista las temporadas con los especiales al final', (
    tester,
  ) async {
    await openDetail(tester, Routes.detailPath('series', 'tt0903747'));

    await tester.tap(find.byKey(const Key('season-selector')));
    await tester.pumpAndSettle();
    final labels = ['Temporada 1', 'Temporada 2', 'Especiales'];
    final positions = [
      for (final l in labels) tester.getTopLeft(find.text(l).last).dy,
    ];
    expect(positions, [...positions]..sort());
    await tester.tap(find.text('Especiales').last);
    await tester.pumpAndSettle();

    expect(find.text('1. Episodio 0x1'), findsOneWidget);
    expect(find.text('1. Episodio 1x1'), findsNothing);
  });

  testWidgets('abre en la temporada del último episodio visto y lo ofrece', (
    tester,
  ) async {
    await openDetail(
      tester,
      Routes.detailPath('series', 'tt0903747'),
      progress: [
        _progress(
          type: 'series',
          metaId: 'tt0903747',
          videoId: 'tt0903747:2:1',
        ),
        _progress(
          type: 'series',
          metaId: 'tt0903747',
          videoId: 'tt0903747:1:1',
          at: DateTime.utc(2025, 1, 1),
        ),
      ],
    );

    expect(find.text('1. Episodio 2x1'), findsOneWidget);
    expect(find.text('1. Episodio 1x1'), findsNothing);
    expect(find.text('Continuar T2 E1 desde 2:00'), findsOneWidget);
    // El episodio en curso muestra su barra de progreso.
    expect(find.byKey(const Key('episode-progress')), findsOneWidget);
  });

  testWidgets('tocar un episodio lo reproduce solo con la mejor fuente', (
    tester,
  ) async {
    world.routes['streams.example.com/stream/series/tt0903747:1:2.json'] = {
      'streams': [
        {'name': 'Streams uno', 'url': 'http://media.example.com/e2.mkv'},
      ],
    };
    final engine = FakePlaybackEngine(
      mediaDuration: const Duration(minutes: 10),
    );
    await openDetail(
      tester,
      Routes.detailPath('series', 'tt0903747'),
      engine: engine,
      tall: true,
    );

    await tester.tap(find.text('2. Episodio 1x2'));
    await pumpIo(tester, ticks: 8);

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(StreamsScreen), findsNothing);
    expect(engine.lastSource?.url, 'http://media.example.com/e2.mkv');
    expect(
      world.requests,
      contains('streams.example.com/stream/series/tt0903747:1:2.json'),
    );
  });

  testWidgets(
    'con la fuente automática apagada, el episodio abre los streams',
    (tester) async {
      world.routes['streams.example.com/stream/series/tt0903747:1:2.json'] = {
        'streams': [
          {'name': 'Streams uno', 'url': 'http://media.example.com/e2.mkv'},
        ],
      };
      await openDetail(
        tester,
        Routes.detailPath('series', 'tt0903747'),
        autoSelectSource: false,
        tall: true,
      );

      await tester.tap(find.text('2. Episodio 1x2'));
      await pumpIo(tester, ticks: 6);

      expect(find.byType(StreamsScreen), findsOneWidget);
      expect(find.text('T1 E2 · Episodio 1x2'), findsOneWidget);
    },
  );

  testWidgets('«Ver» arranca solo con el mejor stream', (tester) async {
    final engine = FakePlaybackEngine(
      mediaDuration: const Duration(minutes: 10),
    );
    await openDetail(
      tester,
      Routes.detailPath('movie', 'tt0133093'),
      engine: engine,
    );

    expect(find.text('The Matrix'), findsOneWidget);
    expect(find.text('Continuar desde 2:00'), findsNothing);
    await tester.tap(find.text('Ver'));
    await tester.pump();
    // Mientras busca, la pantalla de carga sobre el fondo del contenido.
    expect(find.text('Buscando la mejor fuente…'), findsOneWidget);
    await pumpIo(tester, ticks: 8);

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(StreamsScreen), findsNothing);
    expect(engine.lastSource?.url, 'http://media.example.com/matrix.mkv');
  });

  testWidgets('«Elegir fuente» abre la lista de streams', (tester) async {
    await openDetail(tester, Routes.detailPath('movie', 'tt0133093'));

    await tester.tap(find.byKey(const Key('detail-choose-source')));
    await pumpIo(tester, ticks: 6);

    expect(find.byType(StreamsScreen), findsOneWidget);
    expect(find.text('Calidad HD'), findsWidgets);
  });

  testWidgets('con progreso ofrece «Continuar» y retoma sin preguntar', (
    tester,
  ) async {
    final engine = FakePlaybackEngine(
      mediaDuration: const Duration(minutes: 10),
    );
    await openDetail(
      tester,
      Routes.detailPath('movie', 'tt0133093'),
      progress: [_progress()],
      engine: engine,
    );

    expect(find.text('Continuar desde 2:00'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
    await tester.tap(find.text('Continuar desde 2:00'));
    await pumpIo(tester, ticks: 8);

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.text('Ya empezaste esto'), findsNothing);
    expect(engine.lastSource!.startPosition, const Duration(minutes: 2));
  });

  testWidgets('mientras carga muestra lo del catálogo y después los datos', (
    tester,
  ) async {
    final gate = Completer<void>();
    world.gates[_matrixMeta] = gate;
    final hint = Meta.fromJson(metaItem('tt0133093', 'The Matrix'));
    await openDetail(
      tester,
      Routes.detailPath('movie', 'tt0133093'),
      hint: hint,
    );

    expect(find.text('The Matrix'), findsOneWidget);
    expect(find.textContaining('Un hacker descubre'), findsNothing);
    expect(find.text('Ver'), findsNothing);

    gate.complete();
    await pumpIo(tester, ticks: 6);
    expect(find.textContaining('Un hacker descubre'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
  });

  testWidgets('si falla ofrece reintentar y carga al volver a probar', (
    tester,
  ) async {
    world.failing.add(_bbMeta);
    await openDetail(tester, Routes.detailPath('series', 'tt0903747'));

    expect(find.text('No pudimos abrir el detalle'), findsOneWidget);
    expect(
      find.text('El addon respondió con un error (HTTP 500).'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);

    world.failing.clear();
    await tester.tap(find.text('Reintentar'));
    await pumpIo(tester, ticks: 6);

    expect(find.text('No pudimos abrir el detalle'), findsNothing);
    expect(find.text('Temporada 1'), findsOneWidget);
  });

  testWidgets('si falla pero viene de un catálogo muestra lo que se sabe', (
    tester,
  ) async {
    world.failing.add(_matrixMeta);
    final hint = Meta.fromJson(metaItem('tt0133093', 'The Matrix'));
    await openDetail(
      tester,
      Routes.detailPath('movie', 'tt0133093'),
      hint: hint,
    );

    expect(find.text('The Matrix'), findsOneWidget);
    expect(
      find.textContaining('Solo tenemos los datos del catálogo'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
  });

  testWidgets('Esc vuelve a la pantalla anterior', (tester) async {
    await openDetail(tester, Routes.detailPath('movie', 'tt0133093'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpIo(tester, ticks: 6);

    expect(find.byType(DetailScreen), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  group('temporadas', () {
    final meta = Meta.fromJson(seriesMeta('tt1', 'S'));

    test('van en orden y los especiales al final', () {
      expect(seasonsOf(meta), [1, 2, 0]);
      expect(seasonName(0), 'Especiales');
      expect(seasonName(3), 'Temporada 3');
    });

    test('abre en la del último episodio visto o en la primera normal', () {
      expect(defaultSeason(meta, null), 1);
      expect(
        defaultSeason(meta, _progress(metaId: 'tt1', videoId: 'tt1:2:2')),
        2,
      );
      // Un progreso que no es de esta serie no cuenta.
      expect(defaultSeason(meta, _progress(metaId: 'tt1', videoId: 'otro')), 1);
      final onlySpecials = Meta.fromJson(
        seriesMeta('tt2', 'E', episodes: const {0: 2}),
      );
      expect(defaultSeason(onlySpecials, null), 0);
    });

    test('los episodios salen por número', () {
      expect(episodesOf(meta, 2).map((v) => v.episode), [1, 2]);
    });
  });

  testWidgets(
    'con la fuente automática, cada episodio ofrece «Elegir fuente»',
    (tester) async {
      world.routes['streams.example.com/stream/series/tt0903747:1:2.json'] = {
        'streams': [
          {'name': 'Streams uno', 'url': 'http://media.example.com/e2.mkv'},
        ],
      };
      await openDetail(
        tester,
        Routes.detailPath('series', 'tt0903747'),
        tall: true,
      );

      expect(find.byTooltip('Elegir fuente'), findsNWidgets(3));
      await tester.tap(
        find.byKey(const Key('episode-choose-source-tt0903747:1:2')),
      );
      await pumpIo(tester, ticks: 8);

      expect(find.byType(StreamsScreen), findsOneWidget);
      expect(find.text('T1 E2 · Episodio 1x2'), findsOneWidget);
    },
  );

  testWidgets('con la fuente automática apagada no hay «Elegir fuente» por '
      'episodio (el toque ya abre la lista)', (tester) async {
    await openDetail(
      tester,
      Routes.detailPath('series', 'tt0903747'),
      tall: true,
      autoSelectSource: false,
    );

    expect(find.byTooltip('Elegir fuente'), findsNothing);
  });
}
