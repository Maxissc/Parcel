import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/addon_stream.dart';

/// Por qué un stream no sirvió.
enum ProbeFailure {
  /// El archivo es demasiado chico: casi seguro un video de «descargando» o de
  /// error, no la película.
  placeholder,

  /// El servidor respondió algo que no es 200 ni 206 (o un redirect roto).
  http,

  /// No se pudo conectar.
  network,

  /// No respondió a tiempo.
  timeout,

  /// El `content-type` no es de video.
  type,

  /// El stream no tiene una URL http o https.
  invalidUrl,

  /// Alguien canceló la prueba.
  cancelled,
}

/// Resultado de probar un stream. No guarda la URL: puede llevar tokens.
class ProbeResult {
  const ProbeResult.success({
    this.statusCode,
    this.totalBytes,
    this.contentType,
  }) : failure = null;

  const ProbeResult.failure(
    ProbeFailure this.failure, {
    this.statusCode,
    this.totalBytes,
    this.contentType,
  });

  /// `null` si el stream sirve.
  final ProbeFailure? failure;
  final int? statusCode;

  /// Tamaño total del archivo, si el servidor lo dijo.
  final int? totalBytes;
  final String? contentType;

  bool get ok => failure == null;

  @override
  String toString() => ok
      ? 'ProbeResult(ok $statusCode $totalBytes bytes)'
      : 'ProbeResult(${failure!.name} $statusCode)';
}

/// Prueba si un stream responde de verdad antes de dárselo al reproductor.
///
/// Hace un `GET` con `Range: bytes=0-0` (y los headers de
/// `behaviorHints.proxyHeaders.request`), sigue los redirects y mira el status,
/// el tipo y el tamaño. No baja el cuerpo: corta la conexión al tener los
/// headers. Si vence [timeout], aborta el pedido de verdad.
class StreamProber {
  StreamProber(
    http.Client client, {
    this.timeout = const Duration(seconds: 8),
    this.minBytes = 20 * 1024 * 1024,
    this.maxRedirects = 5,
  }) : _client = client;

  final http.Client _client;

  /// Plazo total de la prueba (con los redirects).
  final Duration timeout;

  /// Tamaño mínimo para creerle a un archivo, cuando se conoce.
  final int minBytes;
  final int maxRedirects;

  /// Prueba [stream]. [abortTrigger] cancela la prueba y aborta el pedido.
  /// Nunca lanza: las fallas salen en [ProbeResult.failure].
  Future<ProbeResult> probe(
    AddonStream stream, {
    Future<void>? abortTrigger,
  }) async {
    final url = stream.url == null ? null : Uri.tryParse(stream.url!);
    if (!stream.isPlayable || url == null) {
      return const ProbeResult.failure(ProbeFailure.invalidUrl);
    }
    final abort = Completer<void>();
    final done = Completer<ProbeResult>();
    void finish(ProbeResult result) {
      if (done.isCompleted) return;
      done.complete(result);
      // Si no sirvió (o venció el plazo), se corta el pedido que siga abierto.
      // Si sirvió, el cuerpo ya se descartó y no hay nada que abortar.
      if (!result.ok && !abort.isCompleted) abort.complete();
    }

    final timer = Timer(
      timeout,
      () => finish(const ProbeResult.failure(ProbeFailure.timeout)),
    );
    abortTrigger?.then(
      (_) => finish(const ProbeResult.failure(ProbeFailure.cancelled)),
      onError: (_) {},
    );
    _fetch(url, stream.behaviorHints.proxyRequestHeaders, abort.future).then(
      finish,
      onError: (Object error) => finish(
        // El texto del error puede traer la URL: no se copia.
        ProbeResult.failure(
          error is http.RequestAbortedException
              ? ProbeFailure.timeout
              : ProbeFailure.network,
        ),
      ),
    );
    try {
      return await done.future;
    } finally {
      timer.cancel();
    }
  }

  Future<ProbeResult> _fetch(
    Uri start,
    Map<String, String> proxyHeaders,
    Future<void> abort,
  ) async {
    var uri = start;
    var headers = {...proxyHeaders, 'Range': 'bytes=0-0'};
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final request = http.AbortableRequest('GET', uri, abortTrigger: abort)
        ..followRedirects = false
        ..headers.addAll(headers);
      final response = await _client.send(request);
      // No se baja el cuerpo: alcanza con los headers.
      unawaited(
        response.stream.listen((_) {}, onError: (Object _) {}).cancel(),
      );
      if (_redirects.contains(response.statusCode)) {
        final next = _redirectTarget(uri, response.headers['location']);
        if (next == null) {
          return ProbeResult.failure(
            ProbeFailure.http,
            statusCode: response.statusCode,
          );
        }
        if (next.host != uri.host || next.port != uri.port) {
          headers = {
            for (final e in headers.entries)
              if (!_sensitive.contains(e.key.toLowerCase())) e.key: e.value,
          };
        }
        uri = next;
        continue;
      }
      return _judge(response);
    }
    return const ProbeResult.failure(ProbeFailure.http);
  }

  ProbeResult _judge(http.StreamedResponse response) {
    final status = response.statusCode;
    final contentType = response.headers['content-type'];
    final total = _totalBytes(response);
    if (status != 200 && status != 206) {
      return ProbeResult.failure(
        ProbeFailure.http,
        statusCode: status,
        contentType: contentType,
      );
    }
    if (!_isVideoType(contentType)) {
      return ProbeResult.failure(
        ProbeFailure.type,
        statusCode: status,
        totalBytes: total,
        contentType: contentType,
      );
    }
    if (total != null && total < minBytes) {
      return ProbeResult.failure(
        ProbeFailure.placeholder,
        statusCode: status,
        totalBytes: total,
        contentType: contentType,
      );
    }
    return ProbeResult.success(
      statusCode: status,
      totalBytes: total,
      contentType: contentType,
    );
  }
}

const Set<int> _redirects = {301, 302, 303, 307, 308};

/// Headers que no se reenvían a otro host al seguir un redirect.
const Set<String> _sensitive = {
  'authorization',
  'cookie',
  'proxy-authorization',
};

Uri? _redirectTarget(Uri from, String? location) {
  if (location == null || location.trim().isEmpty) return null;
  final target = Uri.tryParse(location.trim());
  if (target == null) return null;
  final resolved = from.resolveUri(target);
  final ok =
      (resolved.scheme == 'http' || resolved.scheme == 'https') &&
      resolved.host.isNotEmpty;
  return ok ? resolved : null;
}

bool _isVideoType(String? contentType) {
  if (contentType == null || contentType.trim().isEmpty) return true;
  final type = contentType.split(';').first.trim().toLowerCase();
  return type.startsWith('video/') ||
      type == 'application/octet-stream' ||
      type == 'application/x-matroska';
}

final RegExp _contentRange = RegExp(r'^\s*bytes\s+\d+-\d+/(\d+|\*)\s*$');

/// Tamaño total del archivo: del `Content-Range` o, en un 200, del
/// `Content-Length`. En un 206 sin `Content-Range` el largo es el del rango,
/// no el del archivo, así que no se sabe.
int? _totalBytes(http.StreamedResponse response) {
  final range = response.headers['content-range'];
  if (range != null) {
    final m = _contentRange.firstMatch(range);
    final total = m?.group(1);
    return total == null || total == '*' ? null : int.tryParse(total);
  }
  if (response.statusCode == 206) return null;
  return response.contentLength ??
      int.tryParse(response.headers['content-length'] ?? '');
}
