// Addon Stremio mínimo SOLO para desarrollo: sirve un catálogo, metas y streams
// que apuntan a un video local. Uso: dart tool/dev_addon.dart [--port 7000]
// [--media samples/sample.mkv] y después instalar http://127.0.0.1:7000/manifest.json
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final port = int.tryParse(options['port'] ?? '') ?? 7000;
  final media = File(options['media'] ?? _defaultMedia());
  if (!media.existsSync()) {
    stderr.writeln(
      'No encuentro el video ${media.path}. Generalo con tool/make_samples.ps1 '
      'o pasá --media <archivo>.',
    );
    exitCode = 1;
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final base = 'http://127.0.0.1:${server.port}';
  stdout.writeln('Addon de desarrollo en $base/manifest.json');
  stdout.writeln('Video: ${media.path}');
  // Cada pedido en paralelo: el reproductor abre varias conexiones a la vez.
  await for (final request in server) {
    unawaited(_serve(request, base, media));
  }
}

Future<void> _serve(HttpRequest request, String base, File media) async {
  try {
    await _handle(request, base, media);
  } on Object catch (e) {
    stderr.writeln('Error en ${request.uri.path}: $e');
    try {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    } on Object {
      // La conexión ya se cortó.
    }
  }
}

Map<String, String> _parse(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    result[args[i].replaceFirst('--', '')] = args[i + 1];
  }
  return result;
}

String _defaultMedia() {
  final root = File.fromUri(Platform.script).parent.parent.path;
  return '$root${Platform.pathSeparator}samples${Platform.pathSeparator}sample.mkv';
}

const _movieId = 'parcel:sample';
const _seriesId = 'parcel:serie';

Map<String, dynamic> _manifest() => {
  'id': 'org.parcel.dev',
  'name': 'Parcel Dev',
  'version': '0.0.1',
  'description': 'Addon de prueba de Parcel: un video local.',
  'resources': [
    'catalog',
    {
      'name': 'meta',
      'types': ['movie', 'series'],
      'idPrefixes': ['parcel'],
    },
    // Streams también para cualquier id de IMDb, así se prueban los subtítulos
    // de OpenSubtitles con contenido real.
    {
      'name': 'stream',
      'types': ['movie', 'series'],
      'idPrefixes': ['parcel', 'tt'],
    },
  ],
  'types': ['movie', 'series'],
  'idPrefixes': ['parcel'],
  'catalogs': [
    {'type': 'movie', 'id': 'dev-movies', 'name': 'Pruebas de Parcel'},
    {'type': 'series', 'id': 'dev-series', 'name': 'Series de prueba'},
  ],
};

Map<String, dynamic> _movie() => {
  'id': _movieId,
  'type': 'movie',
  'name': 'Video de prueba',
  'releaseInfo': '2026',
  'description': 'Un video corto local para probar la reproducción.',
  'genres': ['Prueba'],
  'runtime': '1 min',
};

Map<String, dynamic> _series() => {
  'id': _seriesId,
  'type': 'series',
  'name': 'Serie de prueba',
  'releaseInfo': '2026',
  'description': 'Dos episodios con el mismo video, para probar «siguiente».',
  'genres': ['Prueba'],
  'videos': [
    for (var e = 1; e <= 2; e++)
      {
        'id': '$_seriesId:1:$e',
        'title': 'Episodio $e',
        'season': 1,
        'episode': e,
        'released': '2026-01-0${e}T00:00:00.000Z',
      },
  ],
};

List<Map<String, dynamic>> _streams(String base) => [
  {
    'name': 'Parcel Dev\n1080p',
    'description': 'Video local de prueba\n💾 1 MB',
    'url': '$base/media',
    'behaviorHints': {'bingeGroup': 'parcel-dev'},
  },
  {
    'name': 'Parcel Dev\nTorrent',
    'description': 'Un torrent de mentira (no se reproduce)',
    'infoHash': '0123456789abcdef0123456789abcdef01234567',
  },
  {
    'name': 'Parcel Dev\nWeb',
    'description': 'Un enlace externo de mentira',
    'externalUrl': 'https://example.com/',
  },
];

Future<void> _handle(HttpRequest request, String base, File media) async {
  final response = request.response;
  response.headers.set('Access-Control-Allow-Origin', '*');
  final path = request.uri.pathSegments.map(Uri.decodeComponent).toList();

  Future<void> json(Object body) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  if (path.length == 1 && path[0] == 'manifest.json') {
    return json(_manifest());
  }
  if (path.length == 1 && path[0] == 'media') {
    return _serveMedia(request, media);
  }
  if (path.length >= 3) {
    final resource = path[0];
    final type = path[1];
    final id = path[2].replaceFirst(RegExp(r'\.json$'), '');
    if (resource == 'catalog' && type == 'movie') {
      return json({
        'metas': [
          {..._movie()}..remove('videos'),
        ],
      });
    }
    if (resource == 'catalog' && type == 'series') {
      return json({
        'metas': [
          {..._series()}..remove('videos'),
        ],
      });
    }
    if (resource == 'meta' && id == _movieId) return json({'meta': _movie()});
    if (resource == 'meta' && id == _seriesId) return json({'meta': _series()});
    if (resource == 'stream') return json({'streams': _streams(base)});
  }
  response.statusCode = HttpStatus.notFound;
  await response.close();
}

/// Sirve el video con soporte de `Range`, que es lo que usa el reproductor
/// para saltar a una posición.
Future<void> _serveMedia(HttpRequest request, File media) async {
  final response = request.response;
  final length = await media.length();
  response.headers
    ..set(HttpHeaders.acceptRangesHeader, 'bytes')
    ..contentType = ContentType(
      'video',
      media.path.toLowerCase().endsWith('.mp4') ? 'mp4' : 'x-matroska',
    );

  var start = 0;
  var end = length - 1;
  final range = request.headers.value(HttpHeaders.rangeHeader);
  final match = range == null
      ? null
      : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
  if (match != null) {
    final from = int.tryParse(match.group(1)!);
    final to = int.tryParse(match.group(2)!);
    if (from != null) {
      start = from;
      if (to != null) end = to;
    } else if (to != null) {
      start = length - to;
    }
    end = end.clamp(start, length - 1);
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/$length',
    );
  }
  response.contentLength = end - start + 1;
  if (request.method == 'HEAD') {
    await response.close();
    return;
  }
  await response.addStream(media.openRead(start, end + 1));
  await response.close();
}
