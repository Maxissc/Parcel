import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/router.dart';
import 'package:parcel_desktop/data/providers.dart';
import 'package:parcel_desktop/features/catalog/catalog_screen.dart';
import 'package:parcel_desktop/features/detail/detail_screen.dart';
import 'package:parcel_desktop/features/home/home_screen.dart';
import 'package:parcel_desktop/features/player/play_item.dart' show ResumeMode;
import 'package:parcel_desktop/features/player/play_route.dart';
import 'package:parcel_desktop/shared/media_row.dart';
import 'package:parcel_desktop/shared/poster_card.dart';
import 'package:parcel_desktop/shared/skeleton.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _movieTop = 'v3-cinemeta.strem.io/catalog/movie/top.json';
const _manyUrl = 'https://many.example.com/manifest.json';

/// Un contenido de catálogo con todo lo que usa el billboard y el panel.
Map<String, dynamic> _rich(String id, String name, {String type = 'movie'}) => {
  ...metaItem(id, name, type: type, poster: 'https://img.example.com/$id.jpg'),
  'background': 'https://img.example.com/$id-bg.jpg',
  'description': 'Sinopsis de $name.',
  'genres': ['Acción', 'Drama'],
  'imdbRating': '8.7',
};

/// Texto dentro de una fila de tarjetas.
Finder _inRows(String text) =>
    find.descendant(of: find.byType(Shelf), matching: find.text(text));

void main() {
  late Directory dir;
  late CatalogWorld world;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
    world.routes['v3-cinemeta.strem.io/catalog/series/top.json'] = {
      'metas': [_rich('tt0903747', 'Breaking Bad', type: 'series')],
    };
    world.routes[_movieTop] = {
      'metas': [for (var i = 1; i <= 6; i++) _rich('tt90000$i', 'Peli $i')],
    };
  });
  tearDown(() => deleteTempDir(dir));

  Future<void> openHome(
    WidgetTester tester, {
    http.Client? client,
    List<String>? addons,
    List<PlaybackProgress> progress = const [],
    Size? size,
    Map<String, Object?>? settings,
  }) async {
    final http_ = client ?? world.client;
    await seedData(
      tester,
      dir,
      http_,
      urls: addons ?? const [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
      onboardingCompleted: true,
      progress: progress,
    );
    if (settings != null) {
      final file = File('${dir.path}/settings.json');
      final current =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      file.writeAsStringSync(jsonEncode({...current, ...settings}));
    }
    await pumpApp(tester, dir, http_);
    if (size != null) tester.view.physicalSize = size;
    await pumpIo(tester, ticks: 6);
  }

  Finder billboard() => find.byKey(const Key('billboard'));
  Finder billboardTitle() => find.descendant(
    of: billboard(),
    matching: find.byKey(const Key('billboard-title')),
  );
  String titleText(WidgetTester tester) =>
      tester.widget<Text>(billboardTitle()).data!;

  group('billboard', () {
    testWidgets('muestra hasta 4 destacados con título, datos, sinopsis y '
        'botones', (tester) async {
      await openHome(tester);

      expect(billboard(), findsOneWidget);
      expect(titleText(tester), 'Peli 1');
      expect(find.text('IMDb 8.7 · 1999 · Acción · Drama'), findsOneWidget);
      expect(find.text('Sinopsis de Peli 1.'), findsOneWidget);
      expect(find.byKey(const Key('billboard-play')), findsOneWidget);
      expect(find.text('Ver'), findsWidgets);
      expect(find.byKey(const Key('billboard-info')), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(Key('billboard-dot-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('billboard-dot-4')), findsNothing);
    });

    testWidgets('rota cada 9 s con fundido', (tester) async {
      await openHome(tester);
      expect(titleText(tester), 'Peli 1');

      await tester.pump(const Duration(seconds: 8));
      expect(titleText(tester), 'Peli 1');
      await tester.pump(const Duration(seconds: 1));
      // Mientras dura el fundido están las dos.
      await tester.pump(const Duration(milliseconds: 300));
      expect(billboardTitle(), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(titleText(tester), 'Peli 2');
    });

    testWidgets('se frena con el mouse encima', (tester) async {
      await openHome(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(billboard()));
      await tester.pump();

      await tester.pump(const Duration(seconds: 30));
      expect(titleText(tester), 'Peli 1');

      await mouse.moveTo(const Offset(5, 780));
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      await tester.pump(const Duration(seconds: 1));
      expect(titleText(tester), 'Peli 2');
      await mouse.removePointer();
    });

    testWidgets('se frena con la ventana sin foco', (tester) async {
      await openHome(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 30));
      expect(titleText(tester), 'Peli 1');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 9));
      await tester.pump(const Duration(seconds: 1));
      expect(titleText(tester), 'Peli 2');
    });

    testWidgets('los indicadores saltan al destacado', (tester) async {
      await openHome(tester);
      await tester.tap(find.byKey(const Key('billboard-dot-2')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(titleText(tester), 'Peli 3');
    });

    testWidgets('«Más info» abre la ficha', (tester) async {
      await openHome(tester);
      await tester.tap(find.byKey(const Key('billboard-info')));
      await pumpIo(tester, ticks: 6);
      expect(find.byType(DetailScreen), findsOneWidget);
    });

    testWidgets('«Ver» arranca el autoplay', (tester) async {
      await openHome(tester);
      await tester.tap(find.byKey(const Key('billboard-play')));
      await pumpIo(tester, ticks: 6);
      expect(find.byType(PlayRoute), findsOneWidget);
    });

    testWidgets('el primero de «Seguir viendo» va primero y dice «Continuar '
        'T1 E3»', (tester) async {
      await openHome(
        tester,
        progress: [
          PlaybackProgress(
            type: 'series',
            metaId: 'tt0903747',
            videoId: 'tt0903747:1:3',
            position: const Duration(minutes: 4),
            duration: const Duration(minutes: 10),
            name: 'Breaking Bad',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      expect(titleText(tester), 'Breaking Bad');
      expect(find.text('Continuar T1 E3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('billboard-play')));
      await pumpUntil(tester, find.byType(PlayRoute));
      final args = tester.widget<PlayRoute>(find.byType(PlayRoute)).args;
      expect(args.meta.id, 'tt0903747');
      expect(args.video?.id, 'tt0903747:1:3');
      expect(args.resume, ResumeMode.resume);
    });
  });

  testWidgets('«Seguir viendo» son tarjetas apaisadas con el chip del '
      'episodio, la barra y cuánto queda', (tester) async {
    await openHome(
      tester,
      progress: [
        PlaybackProgress(
          type: 'series',
          metaId: 'tt0903747',
          videoId: 'tt0903747:2:4',
          position: const Duration(minutes: 38),
          duration: const Duration(minutes: 50),
          name: 'Breaking Bad',
          thumbnail: 'https://img.example.com/e.jpg',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    final row = find.byKey(const Key('continue-watching'));
    expect(
      find.descendant(of: row, matching: find.text('T2 E4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Quedan 12 min')),
      findsOne,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('poster-progress')),
      ),
      findsOneWidget,
    );
    final card = find.descendant(of: row, matching: find.byType(PosterCard));
    expect(tester.getSize(card).width, 267);
  });

  group('tarjeta que crece en la home', () {
    testWidgets('el panel trae IMDb, año, géneros y sinopsis; «Ver» '
        'reproduce', (tester) async {
      await openHome(tester);
      final card = find.ancestor(
        of: _inRows('Peli 2'),
        matching: find.byType(PosterCard),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('card-grown')), findsOneWidget);
      expect(find.text('★ 8.7 · 1999 · Acción · Drama'), findsOneWidget);
      expect(find.text('Sinopsis de Peli 2.'), findsWidgets);

      await tester.tap(find.byKey(const Key('card-play')));
      await pumpIo(tester, ticks: 6);
      expect(find.byType(PlayRoute), findsOneWidget);
      await mouse.removePointer();
    });
  });

  group('carga por cercanía', () {
    late CatalogWorld many;
    late http.Client client;

    setUp(() {
      many = world;
      many.routes.addAll({
        for (var i = 0; i < 10; i++)
          'many.example.com/catalog/movie/c$i.json': {
            'metas': [metaItem('tt70000$i', 'De la fila $i')],
          },
      });
      client = MockClient((request) async {
        if (request.url.toString() == _manyUrl) {
          return jsonResponse({
            'id': 'many',
            'name': 'Muchas',
            'version': '1.0.0',
            'resources': ['catalog'],
            'types': ['movie'],
            'catalogs': [
              for (var i = 0; i < 10; i++)
                {'type': 'movie', 'id': 'c$i', 'name': 'Fila $i'},
            ],
          });
        }
        return many.client.get(request.url);
      });
    });

    testWidgets('una fila fuera de pantalla se pide recién al acercarse y no '
        'se repite al volver', (tester) async {
      await openHome(tester, client: client, addons: const [_manyUrl]);

      expect(many.count('catalog/movie/c0.json'), 1);
      expect(many.count('catalog/movie/c9.json'), 0);
      expect(many.count('catalog/movie/c8.json'), 0);

      final list = find.byKey(const Key('home-list'));
      final last = find.text('De la fila 9');
      Future<void> scrollToLast() async {
        for (var i = 0; i < 6 && last.evaluate().isEmpty; i++) {
          await tester.drag(list, const Offset(0, -3000));
          await pumpIoUntil(
            tester,
            () => last.evaluate().isNotEmpty,
            timeout: const Duration(seconds: 2),
          );
        }
        expect(last, findsOneWidget);
      }

      await scrollToLast();
      expect(many.count('catalog/movie/c9.json'), 1);

      // Vuelve arriba y otra vez abajo: nada se pide de nuevo.
      await tester.drag(list, const Offset(0, 6000));
      await pumpUntil(tester, find.text('De la fila 0'));
      await scrollToLast();
      expect(many.count('catalog/movie/c0.json'), 1);
      expect(many.count('catalog/movie/c9.json'), 1);
    });

    testWidgets('mientras espera muestra esqueletos', (tester) async {
      final gate = Completer<void>();
      many.gates['many.example.com/catalog/movie/c0.json'] = gate;
      await openHome(tester, client: client, addons: const [_manyUrl]);
      expect(find.byType(Skeleton), findsWidgets);
      gate.complete();
      await pumpIo(tester, ticks: 4);
    });
  });

  group('Ver todo', () {
    Future<void> openSeeAll(WidgetTester tester) async {
      await openHome(tester);
      await tester.tap(find.byKey(const Key('row-see-all')).first);
      await pumpIo(tester, ticks: 6);
    }

    testWidgets('abre la grilla, trae páginas con skip y termina al no '
        'haber más', (tester) async {
      world.routes['v3-cinemeta.strem.io/catalog/movie/top/skip=6.json'] = {
        'metas': [_rich('tt900100', 'Peli de la página 2')],
      };
      world.routes['v3-cinemeta.strem.io/catalog/movie/top/skip=7.json'] = {
        'metas': <Object>[],
      };
      await openSeeAll(tester);

      expect(find.byType(CatalogScreen), findsOneWidget);
      expect(find.text('Peli 3'), findsOneWidget);
      expect(find.text('Peli de la página 2'), findsOneWidget);
      expect(world.count('catalog/movie/top/skip=6.json'), 1);
      expect(world.count('catalog/movie/top/skip=7.json'), 1);
      expect(world.count('catalog/movie/top/skip=8.json'), 0);
    });

    testWidgets('los chips filtran por género con el extra genre', (
      tester,
    ) async {
      world.routes['v3-cinemeta.strem.io/catalog/movie/top/genre=Drama.json'] =
          {
            'metas': [_rich('tt900200', 'Solo drama')],
          };
      await openSeeAll(tester);
      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Acción'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Drama'));
      await pumpUntil(tester, find.text('Solo drama'));

      // Un solo pedido con el género, y la lista es la filtrada.
      expect(world.count('catalog/movie/top/genre=Drama.json'), 1);
      expect(find.text('Solo drama'), findsOneWidget);
      expect(find.text('Peli 3'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Todos'));
      await pumpUntil(tester, find.text('Peli 3'));
      expect(find.text('Peli 3'), findsOneWidget);
    });

    testWidgets('un addon sin skip da una sola página y termina', (
      tester,
    ) async {
      await openHome(tester);
      final before = world.count('catalog/series/top');
      final seeAll = find.byKey(const Key('row-see-all')).at(1);
      await tester.ensureVisible(seeAll);
      await tester.tap(seeAll);
      await pumpUntil(tester, find.byType(CatalogScreen));
      await pumpUntil(
        tester,
        find.descendant(
          of: find.byType(CatalogScreen),
          matching: find.text('Breaking Bad'),
        ),
      );
      // Un tiempo para que un pedido de más, si existiera, llegue.
      await pumpIo(tester, ticks: 4);
      expect(world.count('catalog/series/top'), before + 1);
      expect(
        world.requests.where((r) => r.contains('catalog/series/top/skip')),
        isEmpty,
      );
    });

    testWidgets('los duplicados entre páginas no se repiten', (tester) async {
      world.routes['v3-cinemeta.strem.io/catalog/movie/top/skip=6.json'] = {
        'metas': [_rich('tt900003', 'Peli 3'), _rich('tt900300', 'Peli nueva')],
      };
      world.routes['v3-cinemeta.strem.io/catalog/movie/top/skip=8.json'] = {
        'metas': <Object>[],
      };
      await openSeeAll(tester);
      await pumpUntil(tester, find.text('Peli nueva'));
      expect(find.text('Peli 3'), findsOneWidget);
      expect(find.text('Peli nueva'), findsOneWidget);
      await pumpUntil(tester, find.byType(CatalogScreen));
      expect(world.count('catalog/movie/top/skip=8.json'), 1);
    });

    testWidgets('cambiar de género con un pedido en vuelo descarta la '
        'respuesta vieja', (tester) async {
      const page2 = 'v3-cinemeta.strem.io/catalog/movie/top/skip=6.json';
      world.routes[page2] = {
        'metas': [_rich('tt900100', 'Peli de la página 2')],
      };
      world.routes['v3-cinemeta.strem.io/catalog/movie/top/genre=Drama.json'] =
          {
            'metas': [_rich('tt900200', 'Solo drama')],
          };
      final gate = Completer<void>();
      world.gates[page2] = gate;
      await openSeeAll(tester);
      // El pedido de la página 2 está en vuelo.
      await pumpIoUntil(tester, () => world.count('top/skip=6.json') > 0);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Drama'));
      await pumpUntil(tester, find.text('Solo drama'));
      gate.complete();
      await pumpIo(tester, ticks: 4);

      expect(find.text('Solo drama'), findsOneWidget);
      expect(find.text('Peli de la página 2'), findsNothing);
      expect(find.text('Peli 3'), findsNothing);
    });

    testWidgets('el clic en el título también lo abre y Atrás vuelve', (
      tester,
    ) async {
      await openHome(tester);
      await tester.tap(find.byKey(const Key('row-title')).first);
      await pumpIo(tester, ticks: 6);
      expect(find.byType(CatalogScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpIo(tester, ticks: 4);
      expect(find.byType(CatalogScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('tiene esqueletos, estado de error y vacío', (tester) async {
      await openHome(tester);
      final gate = Completer<void>();
      world.gates[_movieTop] = gate;
      world.failing.add(_movieTop);
      await tester.tap(find.byKey(const Key('row-see-all')).first);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('catalog-skeleton')), findsOneWidget);
      gate.complete();
      await pumpIo(tester, ticks: 6);
      expect(find.text('No se pudo cargar el catálogo'), findsOneWidget);

      world.failing.clear();
      world.routes[_movieTop] = {'metas': <Object>[]};
      await tester.tap(find.text('Reintentar'));
      await pumpIo(tester, ticks: 6);
      expect(find.text('No hay nada para mostrar'), findsOneWidget);
    });
  });

  group('clic derecho', () {
    Future<void> rightClick(WidgetTester tester, String title) async {
      final card = find.ancestor(
        of: _inRows(title),
        matching: find.byType(PosterCard),
      );
      await tester.tap(card, buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('el menú ofrece Ver, Más info, Elegir fuente y marcar visto', (
      tester,
    ) async {
      await openHome(tester);
      await rightClick(tester, 'Peli 1');
      for (final text in [
        'Ver',
        'Más info',
        'Elegir fuente',
        'Marcar como visto',
        'Marcar como no visto',
      ]) {
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString().startsWith('PopupMenuItem'),
            ),
            matching: find.text(text),
          ),
          findsWidgets,
          reason: text,
        );
      }
    });

    testWidgets('«Marcar como visto» y «no visto» cambian el progreso', (
      tester,
    ) async {
      await openHome(tester);
      PlaybackProgress? saved() =>
          containerOf(tester)
              .read(progressRepositoryProvider)
              .get('movie', 'tt900001', 'tt900001');

      await rightClick(tester, 'Peli 1');
      await tester.tap(find.text('Marcar como visto').last);
      await pumpIo(tester, ticks: 6);
      expect(saved()!.fraction, 1);
      expect(saved()!.isInProgress, isFalse);

      await rightClick(tester, 'Peli 1');
      await tester.tap(find.text('Marcar como no visto').last);
      await pumpIo(tester, ticks: 6);
      expect(saved()!.position, Duration.zero);
    });

    testWidgets('«Más info» abre la ficha', (tester) async {
      await openHome(tester);
      await rightClick(tester, 'Peli 1');
      await tester.tap(find.text('Más info').last);
      await pumpIo(tester, ticks: 6);
      expect(find.byType(DetailScreen), findsOneWidget);
    });
  });

  group('ordenar y ocultar filas', () {
    Future<void> goToSettings(WidgetTester tester) async {
      routerOf(tester).go(Routes.settings);
      await pumpIo(tester, ticks: 4);
    }

    testWidgets('en Ajustes se oculta una fila, se ordena y se restablece; '
        'persiste al reiniciar', (tester) async {
      await openHome(tester, size: const Size(1280, 1800));
      expect(_inRows('Breaking Bad'), findsOneWidget);
      await goToSettings(tester);

      // Oculta «Popular · Series» (la segunda fila).
      expect(
        tester
            .widget<ReorderableListView>(
              find.byKey(const Key('home-rows-editor')),
            )
            .itemCount,
        4,
      );
      await tester.ensureVisible(find.byKey(const Key('home-row-switch-1')));
      await tester.tap(find.byKey(const Key('home-row-switch-1')));
      await pumpIo(tester, ticks: 4);
      // Y manda la primera fila al final.
      tester
          .widget<ReorderableListView>(
            find.byKey(const Key('home-rows-editor')),
          )
          .onReorderItem!(0, 3);

      final file = File('${dir.path}/settings.json');
      Map<String, dynamic> saved() =>
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      await pumpIoUntil(
        tester,
        () =>
            (saved()['homeOrder'] as List).isNotEmpty &&
            (saved()['homeOrder'] as List).last ==
                'com.linvo.cinemeta|movie|top',
      );
      expect(saved()['version'], 3);
      expect(saved()['homeHidden'], ['com.linvo.cinemeta|series|top']);
      expect(saved()['homeOrder'], [
        'com.linvo.cinemeta|series|top',
        'com.linvo.cinemeta|movie|empty',
        'com.linvo.cinemeta|movie|broken',
        'com.linvo.cinemeta|movie|top',
      ]);

      routerOf(tester).go(Routes.home);
      await pumpIo(tester, ticks: 4);
      expect(_inRows('Breaking Bad'), findsNothing);

      // «Reiniciar»: la app se arma de nuevo sobre los mismos datos.
      await pumpApp(tester, dir, world.client);
      tester.view.physicalSize = const Size(1280, 1800);
      await pumpIo(tester, ticks: 6);
      expect(_inRows('Breaking Bad'), findsNothing);
      expect(_inRows('Peli 1'), findsOneWidget);

      await goToSettings(tester);
      await tester.ensureVisible(find.byKey(const Key('home-rows-reset')));
      await tester.tap(find.byKey(const Key('home-rows-reset')));
      await pumpIo(tester, ticks: 4);
      routerOf(tester).go(Routes.home);
      await pumpIo(tester, ticks: 6);
      expect(_inRows('Breaking Bad'), findsOneWidget);
    });

    testWidgets('tocar un interruptor solo guarda lo oculto, no el orden', (
      tester,
    ) async {
      await openHome(tester, size: const Size(1280, 1800));
      await goToSettings(tester);
      await tester.ensureVisible(find.byKey(const Key('home-row-switch-1')));
      await tester.tap(find.byKey(const Key('home-row-switch-1')));
      final file = File('${dir.path}/settings.json');
      Map<String, dynamic> saved() =>
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      await pumpIoUntil(
        tester,
        () => (saved()['homeHidden'] as List).isNotEmpty,
      );
      expect(saved()['homeHidden'], ['com.linvo.cinemeta|series|top']);
      expect(saved()['homeOrder'], isEmpty);
    });

    testWidgets('con todas las filas ocultas la home lo dice y lleva a '
        'Ajustes', (tester) async {
      await openHome(
        tester,
        settings: {
          'version': 3,
          'homeHidden': [
            'com.linvo.cinemeta|movie|top',
            'com.linvo.cinemeta|series|top',
            'com.linvo.cinemeta|movie|empty',
            'com.linvo.cinemeta|movie|broken',
          ],
        },
      );
      expect(find.text('Ocultaste todas las filas'), findsOneWidget);
      expect(find.byType(Shelf), findsNothing);

      await tester.tap(find.byKey(const Key('home-open-settings')));
      await pumpUntil(tester, find.byKey(const Key('home-rows-editor')));
    });

    testWidgets('las filas ocultas no se piden y el orden manda en la home', (
      tester,
    ) async {
      await openHome(
        tester,
        settings: {
          'version': 3,
          'homeHidden': ['com.linvo.cinemeta|movie|top'],
          'homeOrder': ['com.linvo.cinemeta|series|top'],
        },
      );
      expect(world.count('catalog/movie/top.json'), 0);
      expect(_inRows('Peli 1'), findsNothing);
      expect(_inRows('Breaking Bad'), findsOneWidget);
      // El billboard sale de la primera fila visible.
      expect(titleText(tester), 'Breaking Bad');
    });
  });

  group('teclado y Atrás', () {
    Future<void> focus(WidgetTester tester, String title) async {
      Focus.of(tester.element(_inRows(title).first)).requestFocus();
      await tester.pump();
    }

    bool hasFocus(WidgetTester tester, String title) =>
        Focus.of(tester.element(_inRows(title).first)).hasFocus;

    testWidgets('las flechas pasan entre tarjetas y entre filas, y Enter '
        'abre', (tester) async {
      await openHome(tester);
      await focus(tester, 'Peli 1');
      expect(hasFocus(tester, 'Peli 1'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(hasFocus(tester, 'Peli 2'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(hasFocus(tester, 'Peli 1'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      expect(hasFocus(tester, 'Breaking Bad'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 400));
      expect(hasFocus(tester, 'Peli 1'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpIo(tester, ticks: 6);
      expect(find.byType(DetailScreen), findsOneWidget);
    });

    testWidgets(
      '↓ desde una tarjeta de la derecha no cae en «Ver todo ›», pero '
      'Tab sí llega',
      (tester) async {
        await openHome(tester, size: const Size(700, 1000));
        await focus(tester, 'Peli 4');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 400));
        expect(hasFocus(tester, 'Breaking Bad'), isTrue);

        final seeAll = find.byKey(const Key('row-see-all')).last;
        var reached = false;
        for (var i = 0; i < 12 && !reached; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump(const Duration(milliseconds: 300));
          reached = Focus.of(tester.element(seeAll)).hasFocus;
        }
        expect(reached, isTrue);
      },
    );

    testWidgets('al pasar a una fila de abajo la home se desplaza para '
        'mostrarla', (tester) async {
      await openHome(tester, size: const Size(960, 600));
      final list = find.byKey(const Key('home-list'));
      double page() => tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position
          .pixels;
      await focus(tester, 'Peli 1');
      final before = page();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 500));
      expect(hasFocus(tester, 'Breaking Bad'), isTrue);
      expect(page(), greaterThan(before));
      final card = find.ancestor(
        of: _inRows('Breaking Bad'),
        matching: find.byType(PosterCard),
      );
      expect(tester.getRect(card.first).bottom, lessThanOrEqualTo(600));
    });

    testWidgets('Esc y el botón Atrás del mouse vuelven', (tester) async {
      await openHome(tester);
      await tester.tap(_inRows('Peli 1'));
      await pumpIo(tester, ticks: 6);
      expect(find.byType(DetailScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpIo(tester, ticks: 6);
      expect(find.byType(DetailScreen), findsNothing);

      await tester.tap(_inRows('Peli 1'));
      await pumpIo(tester, ticks: 6);
      expect(find.byType(DetailScreen), findsOneWidget);
      final back = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await back.down(const Offset(600, 400));
      await back.up();
      await pumpIo(tester, ticks: 6);
      expect(find.byType(DetailScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  testWidgets('la home y Ver todo entran en 960×600 sin desbordar', (
    tester,
  ) async {
    await openHome(tester, size: const Size(960, 600));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('row-see-all')).first);
    await pumpIo(tester, ticks: 6);
    expect(find.byType(CatalogScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
