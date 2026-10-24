import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_desktop/app/app.dart';
import 'package:parcel_desktop/app/router.dart';

import 'test_env.dart';

const streamsAddonUrl = 'https://streams.example.com/manifest.json';
const secondStreamsAddonUrl = 'https://more-streams.example.com/manifest.json';

/// Manifest de un Cinemeta de mentira: catálogos de películas y series (uno
/// vacío y uno que falla) y metas.
Map<String, dynamic> cinemetaManifest() => {
  'id': 'com.linvo.cinemeta',
  'name': 'Cinemeta',
  'version': '3.0.0',
  'description': 'Catálogo de prueba',
  'resources': ['catalog', 'meta'],
  'types': ['movie', 'series'],
  'idPrefixes': ['tt'],
  'catalogs': [
    {
      'type': 'movie',
      'id': 'top',
      'name': 'Popular',
      'extra': [
        {'name': 'search'},
        {'name': 'skip'},
      ],
    },
    {
      'type': 'series',
      'id': 'top',
      'name': 'Popular',
      'extra': [
        {'name': 'search'},
      ],
    },
    {'type': 'movie', 'id': 'empty', 'name': 'Sin nada'},
    {'type': 'movie', 'id': 'broken', 'name': 'Caído'},
    {
      'type': 'movie',
      'id': 'genre-only',
      'name': 'Por género',
      'extra': [
        {'name': 'genre', 'isRequired': true},
      ],
    },
  ],
};

Map<String, dynamic> openSubtitlesManifest() => {
  'id': 'org.stremio.opensubtitlesv3',
  'name': 'OpenSubtitles v3',
  'version': '1.0.0',
  'description': 'Subtítulos de prueba',
  'resources': ['subtitles'],
  'types': ['movie', 'series'],
  'idPrefixes': ['tt'],
  'catalogs': [],
};

Map<String, dynamic> streamsManifest(String id, String name) => {
  'id': id,
  'name': name,
  'version': '1.0.0',
  'description': 'Streams de prueba',
  'resources': ['stream'],
  'types': ['movie', 'series'],
  'idPrefixes': ['tt'],
  'catalogs': [],
};

Map<String, dynamic> metaItem(
  String id,
  String name, {
  String type = 'movie',
  String? poster,
  String? shape,
  String? releaseInfo = '1999',
}) => {
  'id': id,
  'type': type,
  'name': name,
  'poster': ?poster,
  'posterShape': ?shape,
  'releaseInfo': ?releaseInfo,
};

/// Una serie con [episodes] episodios por temporada. La temporada 0 son los
/// especiales.
Map<String, dynamic> seriesMeta(
  String id,
  String name, {
  Map<int, int> episodes = const {1: 3, 2: 2, 0: 1},
}) => {
  ...metaItem(id, name, type: 'series', releaseInfo: '2008–2013'),
  'description': 'Un profesor de química se mete en problemas.',
  'genres': ['Drama', 'Crimen'],
  'cast': ['Bryan Cranston', 'Aaron Paul'],
  'runtime': '47 min',
  'imdbRating': '9.5',
  'background': 'https://img.example.com/bg.jpg',
  'videos': [
    for (final entry in episodes.entries)
      for (var e = 1; e <= entry.value; e++)
        {
          'id': '$id:${entry.key}:$e',
          'title': 'Episodio ${entry.key}x$e',
          'season': entry.key,
          'episode': e,
          'released':
              '2008-01-${(e + 9).toString().padLeft(2, '0')}T00:00:00.000Z',
        },
  ],
};

Map<String, dynamic> movieMeta(String id, String name) => {
  ...metaItem(id, name),
  'description': 'Un hacker descubre la verdad.',
  'genres': ['Acción', 'Ciencia ficción'],
  'cast': ['Keanu Reeves'],
  'runtime': '136 min',
  'imdbRating': '8.7',
};

/// Un mundo de red de mentira con Cinemeta, OpenSubtitles y dos addons de
/// streams. Lo que se carga en [routes] responde 200 con ese JSON (la clave es
/// `host/ruta` ya decodificada); lo que no está, 404. [failing] y [slow]
/// permiten hacer fallar o demorar un pedido.
class CatalogWorld {
  CatalogWorld() {
    routes.addAll({
      'v3-cinemeta.strem.io/catalog/movie/top.json': {
        'metas': [
          metaItem(
            'tt0133093',
            'The Matrix',
            poster: 'https://img.example.com/matrix.jpg',
          ),
          metaItem('tt0110912', 'Pulp Fiction'),
        ],
      },
      'v3-cinemeta.strem.io/catalog/series/top.json': {
        'metas': [
          metaItem(
            'tt0903747',
            'Breaking Bad',
            type: 'series',
            releaseInfo: '2008–2013',
          ),
        ],
      },
      'v3-cinemeta.strem.io/catalog/movie/empty.json': {'metas': []},
      'v3-cinemeta.strem.io/meta/movie/tt0133093.json': {
        'meta': movieMeta('tt0133093', 'The Matrix'),
      },
      'v3-cinemeta.strem.io/meta/series/tt0903747.json': {
        'meta': seriesMeta('tt0903747', 'Breaking Bad'),
      },
    });
  }

  final Map<String, Object> routes = {};

  /// Pedidos que llegaron, como `host/ruta` decodificado.
  final List<String> requests = [];

  /// Rutas (`host/ruta`) que responden 500.
  final Set<String> failing = {};

  /// Cuántos pedidos hay en [requests] que contienen [fragment].
  int count(String fragment) =>
      requests.where((r) => r.contains(fragment)).length;

  MockClient get client => MockClient((request) async {
    final url = request.url;
    final key = '${url.host}${Uri.decodeComponent(url.path)}';
    requests.add(key);
    final manifest = {
      cinemetaUrl: cinemetaManifest(),
      subtitlesUrl: openSubtitlesManifest(),
      streamsAddonUrl: streamsManifest('org.example.streams', 'Streams uno'),
      secondStreamsAddonUrl: streamsManifest('org.example.more', 'Streams dos'),
    }[url.toString()];
    if (manifest != null) return jsonResponse(manifest);
    if (failing.contains(key)) return http.Response('error', 500);
    final body = routes[key];
    if (body != null) return jsonResponse(body);
    return http.Response('no encontrado', 404);
  });
}

/// La URL de los recursos de un addon de prueba, para armar las claves de
/// [CatalogWorld.routes].
String routeKey(String manifestUrl, String path) {
  final uri = Uri.parse(manifestUrl);
  return '${uri.host}/$path';
}

/// El router de la app que está corriendo en [tester].
GoRouter routerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ParcelApp)))
        .read(routerProvider);

/// El contenedor de providers de la app que está corriendo en [tester].
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ParcelApp)));
