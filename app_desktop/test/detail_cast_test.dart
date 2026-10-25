import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/router.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/features/detail/cast_section.dart';
import 'package:parcel_desktop/features/detail/tmdb_enrichment.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _matrixMeta = 'v3-cinemeta.strem.io/meta/movie/tt0133093.json';

Map<String, dynamic> _richMeta() => {
  ...movieMeta('tt0133093', 'The Matrix'),
  'country': 'USA',
  'awards': 'Won 4 Oscars',
  'director': ['Lana Wachowski'],
  'writer': ['Lilly Wachowski'],
  'cast': ['Keanu Reeves', 'Carrie-Anne Moss'],
  'trailerStreams': [
    {'title': 'Tráiler', 'ytId': 'vKQi3bBA1y8'},
  ],
  'app_extras': {
    'cast': [
      {
        'name': 'Keanu Reeves',
        'character': 'Neo',
        'photo': 'https://img.example.com/keanu.jpg',
      },
    ],
  },
};

void main() {
  late Directory dir;
  late CatalogWorld world;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
    world.routes[_matrixMeta] = {'meta': _richMeta()};
  });
  tearDown(() => deleteTempDir(dir));

  Future<void> openDetail(
    WidgetTester tester, {
    http.Client? client,
    String? tmdbApiKey,
    List<Uri>? opened,
    FakePlaybackEngine? engine,
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
      onboardingCompleted: true,
      tmdbApiKey: tmdbApiKey,
    );
    await pumpApp(
      tester,
      dir,
      client ?? world.client,
      openedUrls: opened,
      overrides: [
        if (engine != null)
          playbackEngineFactoryProvider.overrideWithValue(() => engine),
      ],
    );
    tester.view.physicalSize = const Size(1280, 1200);
    routerOf(tester).push(Routes.detailPath('movie', 'tt0133093'));
    await pumpIo(tester, ticks: 8);
  }

  testWidgets('muestra el elenco con foto o con iniciales, y los datos', (
    tester,
  ) async {
    await openDetail(tester);

    expect(find.text('Elenco'), findsOneWidget);
    // Con foto del addon, y personaje.
    expect(find.byKey(const Key('cast-photo-Keanu Reeves')), findsOneWidget);
    expect(find.text('Neo'), findsOneWidget);
    // Sin foto: avatar con iniciales.
    expect(find.byKey(const Key('cast-photo-Carrie-Anne Moss')), findsNothing);
    expect(find.text('CM'), findsOneWidget);
    expect(
      find.textContaining('Lana Wachowski', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Lilly Wachowski', findRichText: true),
      findsOneWidget,
    );
    // Datos: IMDb, país y premios.
    expect(find.byKey(const Key('detail-imdb')), findsOneWidget);
    expect(find.text('8.7'), findsOneWidget);
    expect(find.text('USA'), findsOneWidget);
    expect(find.text('Won 4 Oscars'), findsOneWidget);
  });

  testWidgets('el botón de tráiler abre YouTube en el navegador', (
    tester,
  ) async {
    final opened = <Uri>[];
    await openDetail(tester, opened: opened);

    await tester.tap(find.byKey(const Key('detail-trailer')));
    await tester.pump();

    expect(opened, [Uri.parse('https://www.youtube.com/watch?v=vKQi3bBA1y8')]);
  });

  testWidgets('con la key de TMDB suma fotos y no muestra la key', (
    tester,
  ) async {
    world.routes['api.themoviedb.org/3/find/tt0133093'] = {
      'movie_results': [
        {'id': 603, 'original_language': 'en'},
      ],
      'tv_results': [],
    };
    world.routes['api.themoviedb.org/3/movie/603/credits'] = {
      'cast': [
        {
          'name': 'Carrie-Anne Moss',
          'character': 'Trinity',
          'profile_path': '/c.jpg',
          'order': 1,
        },
        {
          'name': 'Laurence Fishburne',
          'character': 'Morpheus',
          'profile_path': '/l.jpg',
          'order': 2,
        },
      ],
    };
    await openDetail(tester, tmdbApiKey: 'CLAVE-SECRETA-TMDB');
    await pumpIo(tester, ticks: 8);

    expect(world.count('api.themoviedb.org/3/find/tt0133093'), 1);
    // Foto de TMDB para Carrie-Anne Moss y alguien nuevo.
    expect(
      find.byKey(const Key('cast-photo-Carrie-Anne Moss')),
      findsOneWidget,
    );
    expect(find.text('Trinity'), findsOneWidget);
    expect(find.text('Laurence Fishburne'), findsOneWidget);
    expect(find.textContaining('CLAVE-SECRETA'), findsNothing);
  });

  testWidgets('el elenco entra en 960×600 sin desbordar', (tester) async {
    await openDetail(tester);
    tester.view.physicalSize = const Size(960, 600);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Elenco'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('TMDB', () {
    const findKey = 'api.themoviedb.org/3/find/tt0133093';

    void routeTmdb({String language = 'ja'}) {
      world.routes[findKey] = {
        'movie_results': [
          {'id': 603, 'original_language': language},
        ],
        'tv_results': [],
      };
      world.routes['api.themoviedb.org/3/movie/603/credits'] = {
        'cast': [
          {'name': 'Carrie-Anne Moss', 'profile_path': '/c.jpg', 'order': 1},
        ],
      };
    }

    testWidgets('el idioma original de TMDB llega al reproductor', (
      tester,
    ) async {
      routeTmdb();
      world.routes['streams.example.com/stream/movie/tt0133093.json'] = {
        'streams': [
          {'name': 'Uno 1080p', 'url': 'http://media.example.com/a.mkv'},
        ],
      };
      final engine = FakePlaybackEngine(
        mediaDuration: const Duration(minutes: 10),
        audioTracks: const [
          AudioTrack(id: '1', language: 'spa'),
          AudioTrack(id: '2', language: 'eng', isDefault: true),
          AudioTrack(id: '3', language: 'jpn'),
        ],
      );
      await openDetail(
        tester,
        tmdbApiKey: 'CLAVE-SECRETA-TMDB',
        engine: engine,
      );
      await pumpIo(tester, ticks: 8);

      await tester.tap(find.byKey(const Key('detail-watch')));
      await pumpUntil(tester, find.byType(PlayerScreen));
      await pumpIo(tester, ticks: 12);

      // El audio por defecto es «Original» y TMDB dijo que es japonés.
      expect(engine.state.selectedAudio?.id, '3');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpIo(tester, ticks: 12);
    });

    testWidgets('al salir del detalle se abortan los pedidos a TMDB', (
      tester,
    ) async {
      routeTmdb();
      final gate = Completer<void>();
      world.gates[findKey] = gate;
      final spy = _AbortSpy(world.client);
      await openDetail(tester, client: spy, tmdbApiKey: 'CLAVE-SECRETA-TMDB');
      expect(spy.tmdbRequests, 1);
      expect(spy.tmdbAborted, isFalse);

      routerOf(tester).pop();
      await pumpIo(tester, ticks: 6);

      expect(spy.tmdbAborted, isTrue);
      gate.complete();
      await pumpIo(tester, ticks: 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una key que TMDB rechaza se avisa en Ajustes, sin mostrarla', (
      tester,
    ) async {
      final spy = _AbortSpy(world.client)..tmdbStatus = 401;
      await openDetail(tester, client: spy, tmdbApiKey: 'CLAVE-SECRETA-TMDB');
      await pumpIo(tester, ticks: 8);

      routerOf(tester).go(Routes.settings);
      await pumpIo(tester, ticks: 6);
      tester.view.physicalSize = const Size(1280, 1800);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('La key de TMDB no es válida'), findsOneWidget);
      // La key va enmascarada en el campo y no se dibuja como texto.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains('CLAVE-SECRETA'),
        ),
        findsNothing,
      );
    });
  });

  group('lógica', () {
    test('iniciales y color estable por nombre', () {
      expect(initialsOf('Tim Robbins'), 'TR');
      expect(initialsOf('  madonna '), 'M');
      expect(initialsOf('Ana de Armas'), 'AD');
      expect(initialsOf(''), '');
      expect(avatarColorOf('Tim Robbins'), avatarColorOf('tim robbins '));
      expect(
        avatarColorOf('Tim Robbins'),
        isNot(avatarColorOf('Morgan Freeman')),
      );
    });

    test('mergeCastDetails: la foto del addon gana y TMDB suma el resto', () {
      final merged = mergeCastDetails(
        const [
          CastMember(name: 'Ana', photoUrl: 'http://a/ana.jpg'),
          CastMember(name: 'Solo Addon'),
        ],
        const [
          CastMember(name: 'ana', character: 'X', photoUrl: 'http://t/ana.jpg'),
          CastMember(name: 'Luis', character: 'Y', photoUrl: 'http://t/l.jpg'),
          CastMember(
            name: 'Solo Addon',
            character: 'Z',
            photoUrl: 'http://t/s.jpg',
          ),
        ],
      );
      expect(merged.map((m) => m.name), ['Ana', 'Luis', 'Solo Addon']);
      expect(merged[0].photoUrl, 'http://a/ana.jpg');
      expect(merged[2].photoUrl, 'http://t/s.jpg');
    });

    test('mergeCastDetails mezcla campo por campo', () {
      final merged = mergeCastDetails(
        const [
          // Personaje del addon, sin foto.
          CastMember(name: 'Ana', character: 'Neo'),
          // Foto del addon, sin personaje.
          CastMember(name: 'Luis', photoUrl: 'http://a/luis.jpg'),
        ],
        const [
          CastMember(
            name: 'Ana',
            character: 'Otro',
            photoUrl: 'http://t/a.jpg',
          ),
          CastMember(
            name: 'Luis',
            character: 'Trinity',
            photoUrl: 'http://t/l.jpg',
          ),
        ],
      );
      expect(merged[0].character, 'Neo');
      expect(merged[0].photoUrl, 'http://t/a.jpg');
      expect(merged[1].character, 'Trinity');
      expect(merged[1].photoUrl, 'http://a/luis.jpg');
    });

    test('las iniciales ignoran los signos', () {
      expect(initialsOf('"Bob" Smith'), 'BS');
      expect(initialsOf('- Ana'), 'A');
      expect(initialsOf('...'), '');
      expect(initialsOf('Álvaro Núñez'), 'ÁN');
    });
  });
}

/// Un cliente que mira los pedidos a TMDB: cuenta cuántos hubo, anota si los
/// abortaron y, si se le pide, responde con otro status.
class _AbortSpy extends http.BaseClient {
  _AbortSpy(this._inner);

  final http.Client _inner;
  int tmdbRequests = 0;
  bool tmdbAborted = false;
  int? tmdbStatus;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.host == 'api.themoviedb.org') {
      tmdbRequests++;
      final trigger = request is http.Abortable ? request.abortTrigger : null;
      if (trigger != null) unawaited(trigger.then((_) => tmdbAborted = true));
      final status = tmdbStatus;
      if (status != null) {
        return Future.value(
          http.StreamedResponse(const Stream.empty(), status, request: request),
        );
      }
    }
    return _inner.send(request);
  }
}
