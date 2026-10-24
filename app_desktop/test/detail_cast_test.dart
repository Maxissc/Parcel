import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/router.dart';
import 'package:parcel_desktop/features/detail/cast_section.dart';
import 'package:parcel_desktop/features/detail/tmdb_enrichment.dart';

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
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> openDetail(
    WidgetTester tester, {
    http.Client? client,
    String? tmdbApiKey,
    List<Uri>? opened,
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
      onboardingCompleted: true,
      tmdbApiKey: tmdbApiKey,
    );
    await pumpApp(tester, dir, client ?? world.client, openedUrls: opened);
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
  });
}
