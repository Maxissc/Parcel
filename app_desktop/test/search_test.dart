import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/features/detail/detail_screen.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _searchMovie =
    'v3-cinemeta.strem.io/catalog/movie/top/search=matrix.json';
const _searchSeries =
    'v3-cinemeta.strem.io/catalog/series/top/search=matrix.json';

void main() {
  late Directory dir;
  late CatalogWorld world;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
    world.routes[_searchMovie] = {
      'metas': [
        metaItem('tt0133093', 'The Matrix'),
        metaItem('tt0234215', 'The Matrix Reloaded'),
      ],
    };
    world.routes[_searchSeries] = {'metas': []};
  });
  tearDown(() => deleteTempDir(dir));

  Future<void> openSearch(
    WidgetTester tester, {
    List<String> addons = const [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: addons,
      onboardingCompleted: true,
    );
    await pumpApp(tester, dir, world.client);
    await tester.tap(find.byIcon(Icons.search));
    await pumpIo(tester, ticks: 3);
  }

  Finder field() => find.byKey(const Key('search-field'));

  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<TextField>(field()).focusNode!.hasFocus;

  int searches() => world.requests.where((r) => r.contains('/search=')).length;

  testWidgets('al entrar enfoca el campo y explica qué hacer', (tester) async {
    await openSearch(tester);

    expect(fieldHasFocus(tester), isTrue);
    expect(find.text('Buscá algo para ver'), findsOneWidget);
    expect(searches(), 0);
  });

  testWidgets('espera 400 ms sin escribir antes de buscar', (tester) async {
    await openSearch(tester);

    await tester.enterText(field(), 'mat');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(field(), 'matrix');
    await tester.pump(const Duration(milliseconds: 399));
    expect(searches(), 0, reason: 'todavía no pasaron los 400 ms');

    await tester.pump(const Duration(milliseconds: 5));
    await pumpIo(tester, ticks: 6);

    // Una sola búsqueda, con el texto final, en cada catálogo con búsqueda.
    expect(searches(), 2);
    expect(world.requests, contains(_searchMovie));
    expect(world.requests.where((r) => r.contains('search=mat.')), isEmpty);
  });

  testWidgets('muestra una fila por catálogo y oculta la que viene vacía', (
    tester,
  ) async {
    await openSearch(tester);

    await tester.enterText(field(), 'matrix');
    await tester.pump(const Duration(milliseconds: 450));
    await pumpIo(tester, ticks: 6);

    expect(find.text('Popular · Películas'), findsOneWidget);
    expect(find.text('Popular · Series'), findsNothing);
    expect(find.text('The Matrix'), findsOneWidget);
    expect(find.text('The Matrix Reloaded'), findsOneWidget);
  });

  testWidgets('Enter busca al instante', (tester) async {
    await openSearch(tester);

    await tester.enterText(field(), 'matrix');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpIo(tester, ticks: 6);

    expect(find.text('The Matrix'), findsOneWidget);
  });

  testWidgets('sin resultados lo dice con el texto buscado', (tester) async {
    await openSearch(tester);

    for (final type in ['movie', 'series']) {
      world.routes['v3-cinemeta.strem.io/catalog/$type/top/search=zzzz.json'] =
          {'metas': []};
    }
    await tester.enterText(field(), 'zzzz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpIo(tester, ticks: 6);

    expect(find.text('No encontramos resultados para «zzzz»'), findsOneWidget);
  });

  testWidgets('borrar el texto vuelve al estado inicial', (tester) async {
    await openSearch(tester);
    await tester.enterText(field(), 'matrix');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpIo(tester, ticks: 6);
    expect(find.text('The Matrix'), findsOneWidget);

    await tester.tap(find.byTooltip('Borrar'));
    await pumpIo(tester, ticks: 3);

    expect(find.text('The Matrix'), findsNothing);
    expect(find.text('Buscá algo para ver'), findsOneWidget);
    expect(fieldHasFocus(tester), isTrue);
  });

  testWidgets('tocar un resultado abre el detalle', (tester) async {
    await openSearch(tester);
    await tester.enterText(field(), 'matrix');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpIo(tester, ticks: 6);

    await tester.tap(find.text('The Matrix'));
    await pumpIo(tester, ticks: 6);

    expect(find.byType(DetailScreen), findsOneWidget);
  });

  testWidgets('Ctrl+F desde otra sección va a Buscar con el campo enfocado', (
    tester,
  ) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: const [cinemetaUrl],
      onboardingCompleted: true,
    );
    await pumpApp(tester, dir, world.client);
    expect(find.byKey(const Key('search-field')), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpIo(tester, ticks: 3);

    expect(field(), findsOneWidget);
    expect(fieldHasFocus(tester), isTrue);
  });

  testWidgets('volver a Buscar con Ctrl+2 enfoca el campo otra vez', (
    tester,
  ) async {
    await openSearch(tester);
    // Se va a otra sección y el foco sale del campo.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await pumpIo(tester, ticks: 3);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpIo(tester, ticks: 3);

    expect(fieldHasFocus(tester), isTrue);
  });

  testWidgets('sin addons que busquen lo explica', (tester) async {
    await openSearch(tester, addons: const [subtitlesUrl, streamsAddonUrl]);

    expect(find.text('Ningún addon instalado permite buscar'), findsOneWidget);
  });
}
