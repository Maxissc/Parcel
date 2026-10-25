import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/addon_manifest.dart';
import '../models/addon_stream.dart';
import '../models/installed_addon.dart';
import '../models/meta.dart';
import '../models/subtitle.dart';
import 'abortable_http.dart';
import 'addon_exception.dart';
import 'manifest_url.dart';
import 'routes.dart';

/// Cliente del protocolo de addons de Stremio.
///
/// Todas las fallas salen como [AddonException]. No aplica timeout propio: lo
/// pone quien lo usa (el agregador, el repositorio), que pasa un
/// `abortTrigger` para cortar el pedido de verdad al vencer el plazo. Si se
/// aborta, la falla es [AddonFailureReason.timeout].
class AddonClient {
  AddonClient(http.Client httpClient) : _http = httpClient;

  final http.Client _http;

  /// Baja el manifest de [url] (se normaliza antes) y arma el addon.
  Future<InstalledAddon> fetchManifest(
    String url, {
    Future<void>? abortTrigger,
  }) async {
    final String transportUrl;
    try {
      transportUrl = normalizeManifestUrl(url);
    } on FormatException catch (e) {
      throw AddonException(AddonFailureReason.invalidUrl, e.message, url: url);
    }
    final json = await _getJson(transportUrl, abortTrigger);
    try {
      return InstalledAddon(
        transportUrl: transportUrl,
        manifest: AddonManifest.fromJson(json),
      );
    } on FormatException catch (e) {
      throw AddonException(
        AddonFailureReason.parse,
        'Manifest inválido: ${e.message}',
        url: transportUrl,
      );
    }
  }

  /// Items de un catálogo (`/catalog/{type}/{id}[/extras].json`).
  Future<List<Meta>> catalog(
    InstalledAddon addon,
    String type,
    String id, {
    Map<String, String> extra = const {},
    Future<void>? abortTrigger,
  }) async {
    final url = _url(addon, 'catalog', type, id, extra);
    final json = await _getJson(url, abortTrigger);
    return parseMetas(_list(json, 'metas', url));
  }

  /// Metadatos completos (`/meta/{type}/{id}.json`).
  Future<Meta> meta(
    InstalledAddon addon,
    String type,
    String id, {
    Future<void>? abortTrigger,
  }) async {
    final url = _url(addon, 'meta', type, id, const {});
    final json = await _getJson(url, abortTrigger);
    final raw = json['meta'];
    if (raw is! Map<String, dynamic>) {
      throw AddonException(
        AddonFailureReason.parse,
        'La respuesta no trae "meta"',
        url: url,
      );
    }
    try {
      return Meta.fromJson(raw);
    } on FormatException catch (e) {
      throw AddonException(
        AddonFailureReason.parse,
        'Meta inválida: ${e.message}',
        url: url,
      );
    }
  }

  /// Streams de un video (`/stream/{type}/{videoId}.json`).
  Future<List<AddonStream>> streams(
    InstalledAddon addon,
    String type,
    String id, {
    Map<String, String> extra = const {},
    Future<void>? abortTrigger,
  }) async {
    final url = _url(addon, 'stream', type, id, extra);
    final json = await _getJson(url, abortTrigger);
    return parseStreams(_list(json, 'streams', url));
  }

  /// Subtítulos de un video (`/subtitles/{type}/{id}.json`). [extra] lleva
  /// `videoHash`, `videoSize` y `filename` cuando se conocen.
  Future<List<Subtitle>> subtitles(
    InstalledAddon addon,
    String type,
    String id, {
    Map<String, String> extra = const {},
    Future<void>? abortTrigger,
  }) async {
    final url = _url(addon, 'subtitles', type, id, extra);
    final json = await _getJson(url, abortTrigger);
    return parseSubtitles(_list(json, 'subtitles', url));
  }

  String _url(
    InstalledAddon addon,
    String resource,
    String type,
    String id,
    Map<String, String> extra,
  ) => buildResourceUrl(
    baseUrl: addon.baseUrl,
    query: transportQuery(addon.transportUrl),
    resource: resource,
    type: type,
    id: id,
    extra: extra,
  );

  Object? _list(Map<String, dynamic> json, String key, String url) {
    final value = json[key];
    if (value is! List) {
      throw AddonException(
        AddonFailureReason.parse,
        'La respuesta no trae "$key"',
        url: url,
      );
    }
    return value;
  }

  Future<Map<String, dynamic>> _getJson(
    String url,
    Future<void>? abortTrigger,
  ) async {
    final http.Response response;
    try {
      response = await getAbortable(
        _http,
        Uri.parse(url),
        abortTrigger: abortTrigger,
      );
    } on TimeoutException {
      throw AddonException(
        AddonFailureReason.timeout,
        'Tiempo agotado',
        url: url,
      );
    } on http.RequestAbortedException {
      throw AddonException(
        AddonFailureReason.timeout,
        'Pedido cancelado',
        url: url,
      );
    } on Exception {
      // El texto de la excepción puede traer la URL completa, con tokens del
      // usuario: no se copia al mensaje.
      throw AddonException(
        AddonFailureReason.network,
        'No se pudo conectar con el addon',
        url: url,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AddonException(
        AddonFailureReason.http,
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        url: url,
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
    throw AddonException(
      AddonFailureReason.parse,
      'La respuesta no es un objeto JSON',
      url: url,
    );
  }
}
