import 'json_helpers.dart';

/// Hasta dónde se vio un video («seguir viendo»).
class PlaybackProgress {
  const PlaybackProgress({
    required this.type,
    required this.metaId,
    required this.videoId,
    required this.position,
    required this.duration,
    required this.name,
    required this.updatedAt,
    this.poster,
    this.thumbnail,
  });

  /// Tipo de contenido (`movie`, `series`...).
  final String type;

  /// Id de la meta (la serie, no el episodio).
  final String metaId;

  /// Id del video (el episodio; igual a [metaId] en una película).
  final String videoId;
  final Duration position;
  final Duration duration;

  /// Nombre para mostrar en la lista.
  final String name;
  final String? poster;

  /// Imagen apaisada para «Seguir viendo»: la miniatura del episodio o el
  /// fondo del contenido. Los archivos viejos no la traen.
  final String? thumbnail;
  final DateTime updatedAt;

  /// Fracción vista, de 0 a 1 (0 si no se conoce la [duration]).
  double get fraction => duration > Duration.zero
      ? position.inMilliseconds / duration.inMilliseconds
      : 0;

  /// `true` si está «en curso»: entre 3 % y 92 % visto, ambos incluidos.
  bool get isInProgress {
    if (duration <= Duration.zero) return false;
    final p = position.inMilliseconds * 100;
    final d = duration.inMilliseconds;
    return p >= d * 3 && p <= d * 92;
  }

  /// Lanza [FormatException] si falta alguno de los campos obligatorios.
  factory PlaybackProgress.fromJson(Map<String, dynamic> json) {
    final type = asNonEmptyString(json['type']);
    final metaId = asNonEmptyString(json['metaId']);
    final videoId = asNonEmptyString(json['videoId']);
    final positionMs = asInt(json['positionMs']);
    final durationMs = asInt(json['durationMs']);
    final updatedAt = asDate(json['updatedAt']);
    if (type == null ||
        metaId == null ||
        videoId == null ||
        positionMs == null ||
        durationMs == null ||
        updatedAt == null) {
      throw FormatException('Progreso inválido', json);
    }
    return PlaybackProgress(
      type: type,
      metaId: metaId,
      videoId: videoId,
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: durationMs),
      name: asString(json['name']) ?? '',
      poster: asNonEmptyString(json['poster']),
      thumbnail: asNonEmptyString(json['thumbnail']),
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'metaId': metaId,
    'videoId': videoId,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'name': name,
    'poster': ?poster,
    'thumbnail': ?thumbnail,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is PlaybackProgress &&
      other.type == type &&
      other.metaId == metaId &&
      other.videoId == videoId &&
      other.position == position &&
      other.duration == duration &&
      other.name == name &&
      other.poster == poster &&
      other.thumbnail == thumbnail &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    type,
    metaId,
    videoId,
    position,
    duration,
    name,
    poster,
    thumbnail,
    updatedAt,
  );

  @override
  String toString() => 'PlaybackProgress($type $videoId $position/$duration)';
}
