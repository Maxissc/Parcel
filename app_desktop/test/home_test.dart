import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/browse_providers.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/data/providers.dart';
import 'package:parcel_desktop/features/detail/detail_screen.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';
import 'package:parcel_desktop/shared/media_row.dart';
import 'package:parcel_desktop/shared/poster_card.dart';
import 'package:parcel_desktop/shared/skeleton.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _movieTop = 'v3-cinemeta.strem.io/catalog/movie/top.json';
const _seriesTop = 'v3-cinemeta.strem.io/catalog/series/top.json';
const _broken = 'v3-cinemeta.strem.io/catalog/movie/broken.json';

PlaybackProgress _progress(
  String type,
  String metaId,
  String videoId,
  String name, {
  int minutes = 4,
  DateTime? at,
}) => PlaybackProgress(
  type: type,
  metaId: metaId,
  videoId: videoId,
  position: Duration(minutes: minutes),
  duration: const Duration(minutes: 10),
  name: name,
  updatedAt: at ?? DateTime.utc(2026, 1, 1),
);

/// Texto dentro de una fila de tarjetas (el billboard repite el primer
/// título, así que `find.text` a secas encuentra dos).
Finder _inRows(String text) =>
    find.descendant(of: find.byType(Shelf), matching: find.text(text));

void main() {
  late Directory dir;
  late CatalogWorld world;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
  });
  tearDown(() => deleteTempDir(dir));

  Future<void> openHome(
    WidgetTester tester, {
    List<PlaybackProgress> progress = const [],
    List<String> addons = const [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
    FakePlaybackEngine? engine,
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: addons,
      onboardingCompleted: true,
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
    await pumpIo(tester, ticks: 6);
  }

  testWidgets(
    'muestra una fila por catálogo con el addon en gris y oculta las vacías',
    (tester) async {
      await openHome(tester);

      expect(find.text('Popular · Películas'), findsOneWidget);
      expect(find.text('Popular · Series'), findsOneWidget);
      expect(find.text('Cinemeta'), findsWidgets);
      expect(_inRows('The Matrix'), findsOneWidget);
      expect(_inRows('Breaking Bad'), findsOneWidget);
      // Vacía: no se dibuja. Con extra obligatorio: no es de la home.
      expect(find.text('Sin nada · Películas'), findsNothing);
      expect(find.text('Por género · Películas'), findsNothing);
      expect(world.requests.where((r) => r.contains('genre-only')), isEmpty);
      expect(find.byKey(const Key('continue-watching')), findsNothing);
    },
  );

  testWidgets('las filas cargan en paralelo, con esqueletos mientras esperan', (
    tester,
  ) async {
    final gates = {_movieTop: Completer<void>(), _seriesTop: Completer<void>()};
    world.gates.addAll(gates);
    await openHome(tester);

    // Los dos pedidos salieron sin esperar al otro.
    expect(world.requests, containsAll([_movieTop, _seriesTop]));
    expect(find.byType(Skeleton), findsWidgets);
    expect(_inRows('The Matrix'), findsNothing);
    expect(find.text('Popular · Películas'), findsOneWidget);

    gates[_seriesTop]!.complete();
    await pumpIo(tester, ticks: 4);
    expect(_inRows('Breaking Bad'), findsOneWidget);
    expect(_inRows('The Matrix'), findsNothing, reason: 'la otra sigue');

    gates[_movieTop]!.complete();
    await pumpIo(tester, ticks: 4);
    expect(_inRows('The Matrix'), findsOneWidget);
    expect(find.byType(Skeleton), findsNothing);
  });

  testWidgets('cuando carga una fila solo se redibuja esa fila', (
    tester,
  ) async {
    final gates = {_movieTop: Completer<void>(), _seriesTop: Completer<void>()};
    world.gates.addAll(gates);
    await openHome(tester);
    gates[_seriesTop]!.complete();
    await pumpIo(tester, ticks: 4);
    expect(_inRows('Breaking Bad'), findsOneWidget);

    final rebuilt = <String>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) =>
        rebuilt.add(element.widget.runtimeType.toString());
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    gates[_movieTop]!.complete();
    await pumpIo(tester, ticks: 4);
    debugOnRebuildDirtyWidget = null;

    expect(_inRows('The Matrix'), findsOneWidget);
    expect(rebuilt.where((w) => w == 'HomeScreen'), isEmpty);
    expect(rebuilt.where((w) => w == 'CatalogRowSection'), hasLength(1));
  });

  testWidgets('quitar un addon libera las filas que guardaba su catálogo', (
    tester,
  ) async {
    await openHome(tester);
    final container = containerOf(tester);
    final catalog = container
        .read(addonAggregatorProvider)
        .homeCatalogs()
        .first;
    final key = (catalog: catalog, search: null);
    expect(container.exists(catalogItemsProvider(key)), isTrue);

    final notifier = container.read(installedAddonsProvider.notifier);
    await tester.runAsync(() => notifier.remove(catalog.addon));
    await pumpIo(tester, ticks: 4);

    expect(container.exists(catalogItemsProvider(key)), isFalse);
  });

  testWidgets(
    'una fila caída dice que no se pudo cargar y reintenta sola esa fila',
    (tester) async {
      world.failing.add(_broken);
      await openHome(tester);
      // La tercera fila carga recién cuando se acerca a la pantalla.
      await tester.drag(
        find.byKey(const Key('home-list')),
        const Offset(0, -500),
      );
      await pumpIo(tester, ticks: 6);

      expect(find.text('Caído · Películas'), findsOneWidget);
      expect(find.text('No se pudo cargar'), findsOneWidget);
      expect(find.textContaining('Respondió con el error 500'), findsOneWidget);
      // Las otras filas siguen bien.
      expect(_inRows('The Matrix'), findsOneWidget);
      final before = world.count('catalog/movie/top.json');

      world.failing.clear();
      await tester.tap(find.text('Reintentar'));
      await pumpIo(tester, ticks: 6);

      expect(find.text('No se pudo cargar'), findsNothing);
      expect(find.text('Se recuperó'), findsOneWidget);
      expect(world.count('catalog/movie/top.json'), before);
    },
  );

  testWidgets('«Seguir viendo» muestra el progreso y el episodio en series', (
    tester,
  ) async {
    await openHome(
      tester,
      progress: [
        _progress('series', 'tt0903747', 'tt0903747:1:3', 'Breaking Bad'),
        _progress(
          'movie',
          'tt0133093',
          'tt0133093',
          'The Matrix',
          at: DateTime.utc(2026, 2, 1),
        ),
      ],
    );

    final row = find.byKey(const Key('continue-watching'));
    expect(row, findsOneWidget);
    expect(find.text('Seguir viendo'), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('T1 E3')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('poster-progress')),
      ),
      findsNWidgets(2),
    );
    // Primero lo más reciente.
    final titles = find.descendant(of: row, matching: find.byType(PosterCard));
    expect(
      tester.getTopLeft(titles.at(0)).dx,
      lessThan(tester.getTopLeft(titles.at(1)).dx),
    );
    expect(
      find.descendant(of: titles.at(0), matching: find.text('The Matrix')),
      findsOneWidget,
    );
  });

  testWidgets('la tarjeta respeta la forma del póster', (tester) async {
    world.routes[_movieTop] = {
      'metas': [
        metaItem('tt1', 'Alta'),
        metaItem('tt2', 'Panorámica', shape: 'landscape'),
        metaItem('tt3', 'Cuadrada', shape: 'square'),
      ],
    };
    await openHome(tester);

    double width(String title) => tester
        .getSize(
          find.ancestor(
            of: find.text(title),
            matching: find.byType(PosterCard),
          ),
        )
        .width;
    expect(width('Alta'), 140);
    expect(width('Cuadrada'), 210);
    expect(width('Panorámica'), 267);
  });

  testWidgets(
    'la rueda baja la página, Shift la fila, y las flechas aparecen al pasar',
    (tester) async {
      world.routes[_movieTop] = {
        'metas': [
          for (var i = 0; i < 30; i++) metaItem('tt${100 + i}', 'Peli $i'),
        ],
      };
      await openHome(tester);

      final shelf = find.byType(Shelf).first;
      Finder inShelf(String tooltip) =>
          find.descendant(of: shelf, matching: find.byTooltip(tooltip));
      ScrollPosition positionOf(Finder of) => tester
          .state<ScrollableState>(
            find.descendant(of: of, matching: find.byType(Scrollable)).first,
          )
          .position;
      double rowPixels() => positionOf(shelf).pixels;
      double pagePixels() =>
          positionOf(find.byKey(const Key('home-list'))).pixels;
      expect(rowPixels(), 0);
      expect(inShelf('Ver más').hitTestable(), findsNothing);

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(shelf)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(inShelf('Ver más').hitTestable(), findsOneWidget);
      expect(inShelf('Ver anteriores').hitTestable(), findsNothing);

      // La rueda común baja la página y no toca la fila.
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pump();
      expect(rowPixels(), 0);
      expect(pagePixels(), greaterThan(0));

      // Con Shift mueve la fila.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(shelf)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(rowPixels(), 300);
      expect(inShelf('Ver anteriores').hitTestable(), findsOneWidget);

      await tester.tap(inShelf('Ver más'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(rowPixels(), greaterThan(300));
    },
  );

  testWidgets('sin catálogos en los addons lo dice y lleva a Addons', (
    tester,
  ) async {
    await openHome(tester, addons: const [subtitlesUrl, streamsAddonUrl]);

    expect(
      find.text('Tus addons no traen catálogos para el inicio'),
      findsOneWidget,
    );
    expect(find.text('Ir a Addons'), findsOneWidget);
  });

  testWidgets('con todos los catálogos vacíos avisa que no hay nada', (
    tester,
  ) async {
    world.routes[_movieTop] = {'metas': []};
    world.routes[_seriesTop] = {'metas': []};
    world.routes[_broken] = {'metas': []};
    await openHome(tester);

    expect(find.text('No hay nada para mostrar por ahora'), findsOneWidget);
  });

  testWidgets('tocar una tarjeta abre el detalle', (tester) async {
    await openHome(tester);

    await tester.tap(_inRows('The Matrix'));
    await pumpIo(tester, ticks: 6);

    expect(find.byType(DetailScreen), findsOneWidget);
    expect(find.textContaining('Un hacker descubre'), findsOneWidget);
  });

  testWidgets('reproducir guarda el progreso y aparece en «Seguir viendo»', (
    tester,
  ) async {
    world.routes['streams.example.com/stream/movie/tt0133093.json'] = {
      'streams': [
        {'name': 'Calidad HD', 'url': 'http://media.example.com/matrix.mkv'},
      ],
    };
    final engine = FakePlaybackEngine(
      mediaDuration: const Duration(minutes: 10),
    );
    await openHome(tester, engine: engine);
    expect(find.byKey(const Key('continue-watching')), findsNothing);

    await tester.tap(_inRows('The Matrix'));
    await pumpIo(tester, ticks: 6);
    await tester.tap(find.text('Ver'));
    await pumpIo(tester, ticks: 8);
    expect(find.byType(PlayerScreen), findsOneWidget);

    engine.tick(const Duration(minutes: 4));
    await tester.pump();
    await engine.pause();
    await tester.pump();
    await tester.pump();

    // Atrás, atrás: reproductor y detalle.
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpIo(tester, ticks: 6);
    }

    final row = find.byKey(const Key('continue-watching'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('The Matrix')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('poster-progress')),
      ),
      findsOneWidget,
    );
    final saved = containerOf(tester)
        .read(progressRepositoryProvider)
        .get('movie', 'tt0133093', 'tt0133093');
    expect(saved!.position, const Duration(minutes: 4));
    expect(saved.duration, const Duration(minutes: 10));
  });
}
