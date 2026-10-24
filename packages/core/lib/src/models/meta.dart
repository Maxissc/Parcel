import 'addon_stream.dart';
import 'json_helpers.dart';

/// Un video de una meta: un episodio de una serie, una emisión de un canal, o
/// el único video de una película (que no trae `videos`).
class Video {
  const Video({
    required this.id,
    required this.title,
    this.released,
    this.thumbnail,
    this.overview,
    this.season,
    this.episode,
    this.available,
    this.streams = const [],
  });

  final String id;
  final String title;
  final DateTime? released;
  final String? thumbnail;
  final String? overview;
  final int? season;
  final int? episode;
  final bool? available;

  /// Streams que el addon de meta trajo embebidos. Si hay, Stremio no pide
  /// streams a otros addons para este video.
  final List<AddonStream> streams;

  /// Lanza [FormatException] si no tiene `id`.
  factory Video.fromJson(Map<String, dynamic> json) {
    final id = asNonEmptyString(json['id']);
    if (id == null) throw FormatException('Video sin id', json);
    return Video(
      id: id,
      title: asString(json['title']) ?? asString(json['name']) ?? '',
      released: asDate(json['released']),
      thumbnail: asNonEmptyString(json['thumbnail']),
      overview:
          asNonEmptyString(json['overview']) ??
          asNonEmptyString(json['description']),
      season: asInt(json['season']),
      episode: asInt(json['episode']) ?? asInt(json['number']),
      available: asBool(json['available']),
      streams: parseStreams(json['streams']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Video && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);

  @override
  String toString() => 'Video($id)';
}

/// Metadatos de un contenido. Sirve tanto para los ítems de un catálogo
/// (sin [videos]) como para el detalle completo.
class Meta {
  const Meta({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.posterShape,
    this.background,
    this.logo,
    this.description,
    this.releaseInfo,
    this.released,
    this.runtime,
    this.imdbRating,
    this.genres = const [],
    this.cast = const [],
    this.directors = const [],
    this.defaultVideoId,
    this.videos = const [],
  });

  final String id;
  final String type;
  final String name;
  final String? poster;

  /// `square`, `poster` o `landscape`; `null` equivale a `poster`.
  final String? posterShape;
  final String? background;
  final String? logo;
  final String? description;
  final String? releaseInfo;
  final DateTime? released;
  final String? runtime;
  final String? imdbRating;
  final List<String> genres;
  final List<String> cast;
  final List<String> directors;

  /// Video al que abrir directo (`behaviorHints.defaultVideoId`).
  final String? defaultVideoId;
  final List<Video> videos;

  /// Lanza [FormatException] si falta `id`, `type` o `name`.
  factory Meta.fromJson(Map<String, dynamic> json) {
    final id = asNonEmptyString(json['id']);
    final type = asNonEmptyString(json['type']);
    final name = asNonEmptyString(json['name']);
    if (id == null || type == null || name == null) {
      throw FormatException('Meta sin id, type o name', json);
    }
    List<String> strings(String key) =>
        List.unmodifiable(asStringList(json[key]) ?? const []);
    return Meta(
      id: id,
      type: type,
      name: name,
      poster: asNonEmptyString(json['poster']),
      posterShape: asNonEmptyString(json['posterShape']),
      background: asNonEmptyString(json['background']),
      logo: asNonEmptyString(json['logo']),
      description: asNonEmptyString(json['description']),
      releaseInfo: asNonEmptyString(json['releaseInfo']),
      released: asDate(json['released']),
      runtime: asNonEmptyString(json['runtime']),
      imdbRating: asNonEmptyString(json['imdbRating']),
      genres: strings('genres'),
      cast: strings('cast'),
      directors: strings('director'),
      defaultVideoId: asNonEmptyString(
        asMap(json['behaviorHints'])?['defaultVideoId'],
      ),
      videos: parseList(json['videos'], Video.fromJson),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Meta &&
      other.id == id &&
      other.type == type &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, type, name);

  @override
  String toString() => 'Meta($type $id $name)';
}

/// Lee una lista de metas y descarta las inválidas.
List<Meta> parseMetas(Object? raw) => parseList(raw, Meta.fromJson);
