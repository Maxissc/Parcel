import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/data/playback_providers.dart';
import 'package:parcel_desktop/data/providers.dart';

/// Manifest mínimo válido de un addon.
Map<String, dynamic> manifestJson(
  String id,
  String name, {
  bool configurable = false,
  String version = '1.0.0',
  String? logo,
}) => {
  'id': id,
  'name': name,
  'version': version,
  'description': 'Descripción de $name',
  'resources': ['catalog', 'stream'],
  'types': ['movie', 'series'],
  'catalogs': [],
  'logo': ?logo,
  if (configurable) 'behaviorHints': {'configurable': true},
};

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Addons "del mundo" para los tests: URL de manifest -> manifest. Lo que no
/// está acá responde 404.
typedef ManifestRoutes = Map<String, Map<String, dynamic>>;

const cinemetaUrl = 'https://v3-cinemeta.strem.io/manifest.json';
const subtitlesUrl = 'https://opensubtitles-v3.strem.io/manifest.json';
const torrentUrl = 'https://torrent.example.com/secret-token/manifest.json';

ManifestRoutes defaultRoutes() => {
  cinemetaUrl: manifestJson('com.linvo.cinemeta', 'Cinemeta'),
  subtitlesUrl: manifestJson('org.stremio.opensubtitlesv3', 'OpenSubtitles v3'),
  torrentUrl: manifestJson(
    'org.example.torrent',
    'Torrent',
    configurable: true,
  ),
};

/// Cliente HTTP falso: sirve los [routes] y, para lo demás, llama a [extra]
/// (si está) antes de responder 404.
MockClient mockWorld(
  ManifestRoutes routes, {
  Future<http.Response?> Function(http.Request request)? extra,
}) {
  return MockClient((request) async {
    final custom = await extra?.call(request);
    if (custom != null) return custom;
    final manifest = routes[request.url.toString()];
    if (manifest != null) return jsonResponse(manifest);
    return http.Response('no encontrado', 404);
  });
}

/// Carpeta temporal para los datos de un test.
Directory makeTempDir() => Directory.systemTemp.createTempSync('parcel_test_');

/// Prober que da por buenos los videos de `media.example.com` (de 50 MB) y
/// rechaza con 404 todo lo demás. [broken] lista paths que responden 404.
StreamProber fakeProber({Set<String> broken = const {}}) => StreamProber(
  MockClient((request) async {
    final url = request.url;
    if (url.host == 'media.example.com' && !broken.contains(url.path)) {
      return http.Response(
        '',
        206,
        headers: {
          'content-type': 'video/mp4',
          'content-range': 'bytes 0-0/52428800',
        },
      );
    }
    return http.Response('no encontrado', 404);
  }),
);

/// Overrides para correr la app sobre [dir] con el [client] falso. No toca el
/// navegador ni la ventana. La prueba de fuentes usa [prober].
List<Override> testOverrides(
  Directory dir,
  http.Client client, {
  List<Uri>? openedUrls,
  WindowService window = const NoopWindowService(),
  StreamProber? prober,
}) => [
  streamProberProvider.overrideWithValue(prober ?? fakeProber()),
  dataDirectoryProvider.overrideWith((ref) => dir),
  httpClientProvider.overrideWithValue(client),
  windowServiceProvider.overrideWithValue(window),
  urlOpenerProvider.overrideWithValue((uri) async {
    openedUrls?.add(uri);
    return true;
  }),
];

/// Contenedor para tests de lógica (sin widgets), con los datos ya abiertos.
Future<ProviderContainer> openContainer(
  Directory dir,
  http.Client client,
) async {
  final container = ProviderContainer(
    overrides: testOverrides(dir, client),
    retry: (_, _) => null,
  );
  await container.read(appDataProvider.future);
  return container;
}

/// Lee los nombres de los addons guardados en disco, sin pasar por la app.
/// Es síncrono a propósito: los tests de widgets no avanzan el disco asíncrono.
List<String> savedAddonNames(Directory dir) {
  final file = File('${dir.path}${Platform.pathSeparator}addons.json');
  if (!file.existsSync()) return [];
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final a in json['addons'] as List)
      ((a as Map)['manifest'] as Map)['name'] as String,
  ];
}

/// Instala por URL los addons que ya existen en [routes].
Future<void> preinstall(ProviderContainer container, List<String> urls) async {
  for (final url in urls) {
    await container.read(installedAddonsProvider.notifier).installUrl(url);
  }
}

/// Un [AddonManifest] listo, sin pasar por la red.
InstalledAddon addon(String url, Map<String, dynamic> manifest) =>
    InstalledAddon(
      transportUrl: url,
      manifest: AddonManifest.fromJson(manifest),
    );
