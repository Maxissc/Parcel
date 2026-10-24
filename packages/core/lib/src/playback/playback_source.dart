import '../protocol/redact.dart';

/// Qué abrir en el reproductor: una URL, con headers y posición inicial.
class PlaybackSource {
  /// Lanza [ArgumentError] si [url] está vacía.
  PlaybackSource({
    required this.url,
    Map<String, String> headers = const {},
    this.startPosition = Duration.zero,
  }) : headers = Map.unmodifiable(headers) {
    if (url.trim().isEmpty) {
      throw ArgumentError.value(url, 'url', 'La URL no puede estar vacía');
    }
  }

  final String url;

  /// Headers HTTP para pedir la [url] (por ejemplo `proxyRequestHeaders` de un
  /// stream de addon).
  final Map<String, String> headers;

  /// Desde dónde empezar (para retomar un video).
  final Duration startPosition;

  @override
  String toString() => 'PlaybackSource(${redactAddonUrl(url)})';
}
