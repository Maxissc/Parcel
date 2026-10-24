import 'addon_stream.dart';
import 'credits.dart';
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

/// Un tráiler de YouTube de una meta (`trailerStreams`).
class MetaTrailer {
  const MetaTrailer({required this.ytId, this.title});

  final String ytId;
  final String? title;

  /// Lanza [FormatException] si falta `ytId`.
  factory MetaTrailer.fromJson(Map<String, dynamic> json) {
    final ytId = asNonEmptyString(json['ytId']);
    if (ytId == null) throw FormatException('Tráiler sin ytId', json);
    return MetaTrailer(ytId: ytId, title: asNonEmptyString(json['title']));
  }

  @override
  bool operator ==(Object other) =>
      other is MetaTrailer && other.ytId == ytId && other.title == title;

  @override
  int get hashCode => Object.hash(ytId, title);

  @override
  String toString() => 'MetaTrailer($ytId)';
}

/// Un enlace de una meta (`links`): una categoría (`Cast`, `Directors`,
/// `Writers`, `Genres`...) con un nombre.
class MetaLink {
  const MetaLink({required this.name, required this.category, this.url});

  final String name;
  final String category;
  final String? url;

  /// Lanza [FormatException] si falta `name` o `category`.
  factory MetaLink.fromJson(Map<String, dynamic> json) {
    final name = asNonEmptyString(json['name']);
    final category = asNonEmptyString(json['category']);
    if (name == null || category == null) {
      throw FormatException('Link sin name o category', json);
    }
    return MetaLink(
      name: name,
      category: category,
      url: asNonEmptyString(json['url']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MetaLink &&
      other.name == name &&
      other.category == category &&
      other.url == url;

  @override
  int get hashCode => Object.hash(name, category, url);

  @override
  String toString() => 'MetaLink($category $name)';
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
    this.writers = const [],
    this.awards,
    this.country,
    this.originalLanguage,
    this.trailerStreams = const [],
    this.links = const [],
    this.castDetails = const [],
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
  final List<String> writers;
  final String? awards;

  /// País (o países, separados por coma) tal como lo manda el addon.
  final String? country;

  /// Idioma original (`original_language`, de TMDB o de `app_extras`) tal como
  /// vino: `es`, `ja`, `eng`...
  final String? originalLanguage;
  final List<MetaTrailer> trailerStreams;
  final List<MetaLink> links;

  /// Elenco con foto y personaje (`app_extras.cast`, o TMDB). Para mostrar el
  /// elenco mezclado, usar [credits].
  final List<CastMember> castDetails;

  /// Video al que abrir directo (`behaviorHints.defaultVideoId`).
  final String? defaultVideoId;
  final List<Video> videos;

  /// Elenco, dirección y guion sin repetidos. Las fotos y personajes de
  /// [castDetails] ganan; después van los nombres de [cast] y de los [links]
  /// `Cast`. La dirección y el guion juntan `director`/`writer` con los links
  /// `Directors`/`Writers`.
  Credits get credits => Credits(
    cast: mergeCast(castDetails, [...cast, ..._linkNames('cast')]),
    directors: mergeNames([directors, _linkNames('directors')]),
    writers: mergeNames([writers, _linkNames('writers')]),
  );

  List<String> _linkNames(String category) => [
    for (final link in links)
      if (link.category.toLowerCase() == category) link.name,
  ];

  /// Copia con [castDetails] y/o [originalLanguage] distintos (por ejemplo, los
  /// que dio TMDB).
  Meta copyWith({String? originalLanguage, List<CastMember>? castDetails}) =>
      Meta(
        id: id,
        type: type,
        name: name,
        poster: poster,
        posterShape: posterShape,
        background: background,
        logo: logo,
        description: description,
        releaseInfo: releaseInfo,
        released: released,
        runtime: runtime,
        imdbRating: imdbRating,
        genres: genres,
        cast: cast,
        directors: directors,
        writers: writers,
        awards: awards,
        country: country,
        originalLanguage: originalLanguage ?? this.originalLanguage,
        trailerStreams: trailerStreams,
        links: links,
        castDetails: castDetails ?? this.castDetails,
        defaultVideoId: defaultVideoId,
        videos: videos,
      );

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
    final extras = asMap(json['app_extras']);
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
      writers: strings('writer'),
      awards: asNonEmptyString(json['awards']),
      country: asNonEmptyString(json['country']),
      originalLanguage:
          asNonEmptyString(json['original_language']) ??
          asNonEmptyString(extras?['original_language']),
      trailerStreams: parseList(json['trailerStreams'], MetaTrailer.fromJson),
      links: parseList(json['links'], MetaLink.fromJson),
      castDetails: parseList(extras?['cast'], CastMember.fromJson),
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
