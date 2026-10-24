import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../protocol/abortable_http.dart';
import 'subtitle_parser.dart';

/// Por qué falló bajar un subtítulo.
enum SubtitleFailureReason {
  /// No se pudo conectar (o la URL no es válida).
  network,

  /// Respondió con un status que no es 2xx.
  http,

  /// No respondió a tiempo.
  timeout,

  /// El archivo pasa del tope de tamaño.
  tooLarge,
}

/// Falla al bajar un subtítulo. No guarda la URL: puede llevar tokens.
class SubtitleException implements Exception {
  const SubtitleException(this.reason, this.message, {this.statusCode});

  final SubtitleFailureReason reason;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'SubtitleException(${reason.name}): $message';
}

/// Baja subtítulos externos (de los addons) y los decodifica.
///
/// Tiene un tope de tamaño ([maxBytes]) y un plazo ([timeout]); al vencer el
/// plazo o pasarse del tope, corta la descarga.
class SubtitleFetcher {
  SubtitleFetcher(
    http.Client client, {
    this.maxBytes = 3 * 1024 * 1024,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client;

  final http.Client _client;
  final int maxBytes;
  final Duration timeout;

  /// Texto del subtítulo de [url]. Lanza [SubtitleException].
  Future<String> fetchText(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw const SubtitleException(
        SubtitleFailureReason.network,
        'URL de subtítulo inválida',
      );
    }
    try {
      final bytes = await runWithTimeoutAbort(
        timeout,
        (abort) => _download(uri, abort),
      );
      return decode(bytes);
    } on SubtitleException {
      rethrow;
    } on TimeoutException {
      throw const SubtitleException(
        SubtitleFailureReason.timeout,
        'Tiempo agotado',
      );
    } on http.RequestAbortedException {
      throw const SubtitleException(
        SubtitleFailureReason.timeout,
        'Pedido cancelado',
      );
    } on Exception {
      // El texto del error puede traer la URL: no se copia.
      throw const SubtitleException(
        SubtitleFailureReason.network,
        'No se pudo bajar el subtítulo',
      );
    }
  }

  /// Baja [url] y la parsea. Lanza [SubtitleException].
  Future<List<SubtitleCue>> fetchCues(String url) async =>
      SubtitleParser.parse(await fetchText(url));

  Future<List<int>> _download(Uri uri, Future<void> abort) async {
    final request = http.AbortableRequest('GET', uri, abortTrigger: abort);
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      unawaited(
        response.stream.listen((_) {}, onError: (Object _) {}).cancel(),
      );
      throw SubtitleException(
        SubtitleFailureReason.http,
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      unawaited(
        response.stream.listen((_) {}, onError: (Object _) {}).cancel(),
      );
      throw _tooLarge();
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      // Al lanzar acá, `await for` cancela la suscripción y corta la conexión.
      if (bytes.length > maxBytes) throw _tooLarge();
    }
    return bytes;
  }

  SubtitleException _tooLarge() => SubtitleException(
    SubtitleFailureReason.tooLarge,
    'El subtítulo pesa más de ${maxBytes ~/ 1024} KB',
  );

  /// Decodifica [bytes] como UTF-8 y, si hay muchos caracteres inválidos
  /// (más de 1 cada 1000), como Latin-1 (con las comillas y símbolos de
  /// Windows-1252). Saca el BOM.
  static String decode(List<int> bytes) {
    final utf8Text = utf8.decode(bytes, allowMalformed: true);
    var invalid = 0;
    for (final unit in utf8Text.runes) {
      if (unit == 0xFFFD) invalid++;
    }
    final text = invalid > 0 && invalid / utf8Text.runes.length > 0.001
        ? _decodeWindows1252(bytes)
        : utf8Text;
    return text.startsWith('﻿') ? text.substring(1) : text;
  }
}

/// Latin-1 con los símbolos de Windows-1252 en 0x80-0x9F (`’`, `“`, `…`).
String _decodeWindows1252(List<int> bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.writeCharCode(b >= 0x80 && b <= 0x9F ? _cp1252[b - 0x80] : b);
  }
  return buffer.toString();
}

const List<int> _cp1252 = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, //
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, //
];
