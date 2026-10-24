import '../protocol/redact.dart';
import 'json_helpers.dart';
import 'subtitle.dart';

/// Pistas de comportamiento de un stream (`behaviorHints`).
class StreamBehaviorHints {
  const StreamBehaviorHints({
    this.notWebReady = false,
    this.bingeGroup,
    this.countryWhitelist = const [],
    this.videoHash,
    this.videoSize,
    this.filename,
    this.proxyRequestHeaders = const {},
    this.proxyResponseHeaders = const {},
  });

  final bool notWebReady;
  final String? bingeGroup;
  final List<String> countryWhitelist;

  /// Hash de OpenSubtitles del video, para buscar subtítulos.
  final String? videoHash;
  final int? videoSize;
  final String? filename;

  /// Headers que hay que mandar al pedir la `url` (`proxyHeaders.request`).
  final Map<String, String> proxyRequestHeaders;
  final Map<String, String> proxyResponseHeaders;

  factory StreamBehaviorHints.fromJson(Object? raw) {
    final json = asMap(raw);
    if (json == null) return const StreamBehaviorHints();
    final proxy = asMap(json['proxyHeaders']);
    return StreamBehaviorHints(
      notWebReady: asBool(json['notWebReady']) ?? false,
      bingeGroup: asNonEmptyString(json['bingeGroup']),
      countryWhitelist: List.unmodifiable(
        asStringList(json['countryWhitelist']) ?? const [],
      ),
      videoHash: asNonEmptyString(json['videoHash']),
      videoSize: asInt(json['videoSize']),
      filename: asNonEmptyString(json['filename']),
      proxyRequestHeaders: _stringMap(proxy?['request']),
      proxyResponseHeaders: _stringMap(proxy?['response']),
    );
  }
}

Map<String, String> _stringMap(Object? raw) {
  final map = asMap(raw);
  if (map == null) return const {};
  return Map.unmodifiable({
    for (final e in map.entries)
      if (e.value is String) e.key: e.value as String,
  });
}

/// Un stream que ofrece un addon para un video.
///
/// Tiene al menos una fuente: [url], [ytId], [infoHash] o [externalUrl].
class AddonStream {
  const AddonStream({
    this.url,
    this.ytId,
    this.infoHash,
    this.fileIdx,
    this.externalUrl,
    this.name,
    this.title,
    this.description,
    this.subtitles = const [],
    this.sources = const [],
    this.behaviorHints = const StreamBehaviorHints(),
  });

  final String? url;
  final String? ytId;
  final String? infoHash;
  final int? fileIdx;
  final String? externalUrl;

  /// Nombre corto (suele indicar la calidad).
  final String? name;

  /// Descripción vieja del stream (hoy `description`).
  final String? title;
  final String? description;
  final List<Subtitle> subtitles;

  /// Trackers y nodos DHT de un torrent.
  final List<String> sources;
  final StreamBehaviorHints behaviorHints;

  /// `true` si Parcel puede reproducirlo en v1: tiene una `url` http o https.
  /// Los torrents (`infoHash`) y el resto no.
  bool get isPlayable {
    final u = url == null ? null : Uri.tryParse(url!);
    return u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.isNotEmpty;
  }

  /// Lanza [FormatException] si no tiene ninguna fuente reconocible.
  factory AddonStream.fromJson(Map<String, dynamic> json) {
    final url = asNonEmptyString(json['url']);
    final ytId = asNonEmptyString(json['ytId']);
    final infoHash = asNonEmptyString(json['infoHash']);
    final externalUrl = asNonEmptyString(json['externalUrl']);
    if (url == null &&
        ytId == null &&
        infoHash == null &&
        externalUrl == null) {
      throw FormatException('Stream sin fuente', json);
    }
    return AddonStream(
      url: url,
      ytId: ytId,
      infoHash: infoHash,
      fileIdx: asInt(json['fileIdx']),
      externalUrl: externalUrl,
      name: asNonEmptyString(json['name']),
      title: asNonEmptyString(json['title']),
      description: asNonEmptyString(json['description']),
      subtitles: parseSubtitles(json['subtitles']),
      sources: List.unmodifiable(asStringList(json['sources']) ?? const []),
      behaviorHints: StreamBehaviorHints.fromJson(json['behaviorHints']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AddonStream &&
      other.url == url &&
      other.ytId == ytId &&
      other.infoHash == infoHash &&
      other.fileIdx == fileIdx &&
      other.externalUrl == externalUrl &&
      other.name == name;

  @override
  int get hashCode =>
      Object.hash(url, ytId, infoHash, fileIdx, externalUrl, name);

  @override
  String toString() {
    final shownUrl = url == null ? null : redactAddonUrl(url!);
    return 'AddonStream(${name ?? shownUrl ?? infoHash ?? ytId})';
  }
}

/// Lee una lista de streams y descarta los inválidos.
List<AddonStream> parseStreams(Object? raw) =>
    parseList(raw, AddonStream.fromJson);
