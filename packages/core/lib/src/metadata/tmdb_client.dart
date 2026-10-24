import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/credits.dart';
import '../models/json_helpers.dart';
import '../protocol/abortable_http.dart';

/// Por qué falló un pedido a TMDB.
enum TmdbFailureReason {
  /// La key o el token no sirven (HTTP 401).
  auth,

  /// Otro status que no es 2xx.
  http,

  /// No se pudo conectar.
  network,

  /// No respondió a tiempo.
  timeout,

  /// La respuesta no tiene la forma esperada.
  parse,
}

/// Falla al hablar con TMDB. No guarda la URL ni la key.
class TmdbException implements Exception {
  const TmdbException(this.reason, this.message, {this.statusCode});

  final TmdbFailureReason reason;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'TmdbException(${reason.name}): $message';
}

/// Lo que TMDB sabe de un título de IMDb.
class TmdbMatch {
  const TmdbMatch({
    required this.id,
    required this.type,
    this.originalLanguage,
  });

  /// Id de TMDB.
  final int id;

  /// `movie` o `tv`.
  final String type;

  /// `original_language` de TMDB (`en`, `ja`...).
  final String? originalLanguage;

  @override
  String toString() => 'TmdbMatch($type $id $originalLanguage)';
}

/// Cliente mínimo de TMDB (opcional: solo se usa si el usuario puso su key).
///
/// Acepta una API key v3 (va en la query `api_key`) o un token de acceso v4
/// (empieza con `eyJ`; va en `Authorization: Bearer`). La key no sale en
/// `toString`, ni en los errores, ni en logs.
class TmdbClient {
  TmdbClient(
    http.Client client, {
    required String apiKey,
    this.timeout = const Duration(seconds: 10),
  }) : _http = client,
       _key = apiKey.trim() {
    if (_key.isEmpty) throw ArgumentError('La key de TMDB está vacía');
  }

  final http.Client _http;
  final String _key;
  final Duration timeout;

  bool get _isBearer => _key.startsWith('eyJ');

  /// Busca un título por su id de IMDb (`tt...`). `null` si TMDB no lo conoce
  /// o [imdbId] no es un id de IMDb.
  Future<TmdbMatch?> findByImdb(String imdbId) async {
    if (!_imdbId.hasMatch(imdbId)) return null;
    final json = await _get('/3/find/$imdbId', {'external_source': 'imdb_id'});
    for (final (key, type) in const [
      ('movie_results', 'movie'),
      ('tv_results', 'tv'),
    ]) {
      final results = json[key];
      if (results is! List) continue;
      for (final item in results) {
        final map = asMap(item);
        final id = asInt(map?['id']);
        if (map != null && id != null) {
          return TmdbMatch(
            id: id,
            type: type,
            originalLanguage: asNonEmptyString(map['original_language']),
          );
        }
      }
    }
    return null;
  }

  /// Elenco de [id] con la foto (`w185`) y el personaje. [type] es `movie` o
  /// `tv` (también se acepta `series`). Viene en el orden de TMDB, hasta
  /// [limit].
  Future<List<CastMember>> credits(
    int id,
    String type, {
    int limit = 30,
  }) async {
    final kind = type == 'movie' ? 'movie' : 'tv';
    // En series, `aggregate_credits` junta todas las temporadas; el personaje
    // viene en `roles`.
    final path = kind == 'tv' ? 'aggregate_credits' : 'credits';
    final json = await _get('/3/$kind/$id/$path', const {});
    final cast = json['cast'];
    if (cast is! List) {
      throw const TmdbException(
        TmdbFailureReason.parse,
        'La respuesta no trae "cast"',
      );
    }
    final entries = <(int, CastMember)>[];
    for (var i = 0; i < cast.length; i++) {
      final map = asMap(cast[i]);
      final name = asNonEmptyString(map?['name']);
      if (map == null || name == null) continue;
      final profile = asNonEmptyString(map['profile_path']);
      entries.add((
        asInt(map['order']) ?? i,
        CastMember(
          name: name.trim(),
          character: asNonEmptyString(map['character']) ?? _firstRole(map),
          photoUrl: profile == null ? null : '$_imageBase$profile',
        ),
      ));
    }
    // El orden de TMDB es el campo `order`; `sort` no es estable, así que
    // se desempata por posición.
    final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])]
      ..sort((a, b) {
        final c = a.$2.$1.compareTo(b.$2.$1);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return List.unmodifiable([for (final e in indexed.take(limit)) e.$2.$2]);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.themoviedb.org',
      path: path,
      queryParameters: {...query, if (!_isBearer) 'api_key': _key},
    );
    final http.Response response;
    try {
      response = await runWithTimeoutAbort(
        timeout,
        (abort) => getAbortable(
          _http,
          uri,
          headers: {
            'Accept': 'application/json',
            if (_isBearer) 'Authorization': 'Bearer $_key',
          },
          abortTrigger: abort,
        ),
      );
    } on TimeoutException {
      throw const TmdbException(TmdbFailureReason.timeout, 'Tiempo agotado');
    } on http.RequestAbortedException {
      throw const TmdbException(TmdbFailureReason.timeout, 'Pedido cancelado');
    } on Exception {
      // El texto del error trae la URL, que lleva la key: no se copia.
      throw const TmdbException(
        TmdbFailureReason.network,
        'No se pudo conectar con TMDB',
      );
    }
    if (response.statusCode == 401) {
      throw const TmdbException(
        TmdbFailureReason.auth,
        'TMDB no aceptó la key',
        statusCode: 401,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbException(
        TmdbFailureReason.http,
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // cae al error de abajo
    }
    throw const TmdbException(
      TmdbFailureReason.parse,
      'La respuesta no es un objeto JSON',
    );
  }

  @override
  String toString() => 'TmdbClient(${_isBearer ? 'token v4' : 'key v3'})';
}

final RegExp _imdbId = RegExp(r'^tt\d+$');
const String _imageBase = 'https://image.tmdb.org/t/p/w185';

/// Personaje de `aggregate_credits` (series): el primero de `roles`.
String? _firstRole(Map<String, dynamic> member) {
  final roles = member['roles'];
  if (roles is! List || roles.isEmpty) return null;
  return asNonEmptyString(asMap(roles.first)?['character']);
}
