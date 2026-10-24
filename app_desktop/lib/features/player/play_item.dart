import 'package:parcel_core/parcel_core.dart' hide Video;
import 'package:parcel_core/parcel_core.dart' as core show Video;

import '../../shared/media_labels.dart';

/// Cómo arrancar un video que ya se empezó a ver.
enum ResumeMode {
  /// Pregunta «Continuar desde…» o «Desde el principio».
  ask,

  /// Retoma directo donde quedó.
  resume,

  /// Empieza de cero sin preguntar (el usuario ya eligió «Desde el principio»).
  fromStart,
}

/// Qué se está reproduciendo: la meta, el episodio (si es una serie) y el
/// stream elegido. Con esto se sabe a quién guardarle el progreso, qué
/// subtítulos pedir y cuál es el episodio que sigue.
class PlayItem {
  const PlayItem({
    required this.meta,
    this.video,
    required this.stream,
    this.addonUrl,
    this.addonName,
  });

  final Meta meta;

  /// El episodio; `null` en una película.
  final core.Video? video;
  final AddonStream stream;

  /// `transportUrl` del addon que ofreció el stream.
  final String? addonUrl;

  /// Nombre del addon que ofreció el stream.
  final String? addonName;

  String get type => meta.type;

  /// Id con el que se piden streams y subtítulos y se guarda el progreso.
  String get videoId => video?.id ?? meta.id;

  /// «T1 E3», o `null` si no es un episodio numerado.
  String? get episodeTag => video == null ? null : episodeTagOf(video!);

  /// Texto para el reproductor y el título de la ventana: «Nombre», o
  /// «Nombre · T1 E3 · Título del episodio» en una serie.
  String get title {
    final v = video;
    if (v == null) return meta.name;
    final episodeTitle = v.title.trim();
    return [
      meta.name,
      ?episodeTag,
      if (episodeTitle.isNotEmpty) episodeTitle,
    ].join(' · ');
  }

  /// Pedidos extra para buscar subtítulos, con lo que el stream sabe del
  /// archivo.
  Map<String, String> get subtitleExtra {
    final hints = stream.behaviorHints;
    return {
      'videoHash': ?hints.videoHash,
      if (hints.videoSize != null) 'videoSize': '${hints.videoSize}',
      'filename': ?hints.filename,
    };
  }

  /// El episodio que sigue al actual, o `null` si no hay (o es una película).
  ///
  /// El orden es por temporada y episodio; los especiales (temporada 0) van al
  /// final y solo siguen a otro especial.
  core.Video? get nextEpisode => nextVideo(meta, video);
}

/// «T1 E3» de un episodio, o `null` si no se puede saber.
String? episodeTagOf(core.Video video) =>
    episodeLabel(video.season, video.episode) ??
    episodeLabelFromVideoId(video.id);

/// Los episodios de [meta] en el orden en que se ven: temporada, episodio, y
/// los especiales (temporada 0) al final.
List<core.Video> orderedEpisodes(Meta meta) {
  int seasonKey(core.Video v) {
    final season = v.season ?? 1;
    return season == 0 ? 1 << 30 : season;
  }

  final list = [...meta.videos];
  // `sort` de Dart no es estable: el índice desempata.
  final index = {for (var i = 0; i < list.length; i++) list[i]: i};
  list.sort((a, b) {
    final bySeason = seasonKey(a).compareTo(seasonKey(b));
    if (bySeason != 0) return bySeason;
    final byEpisode = (a.episode ?? 0).compareTo(b.episode ?? 0);
    if (byEpisode != 0) return byEpisode;
    return index[a]!.compareTo(index[b]!);
  });
  return list;
}

/// El episodio que sigue a [current] en [meta]. No ofrece uno que todavía no
/// salió (su fecha es posterior a [now], que por defecto es ahora).
core.Video? nextVideo(Meta meta, core.Video? current, {DateTime? now}) {
  if (current == null) return null;
  final list = orderedEpisodes(meta);
  final at = list.indexWhere((v) => v.id == current.id);
  if (at < 0 || at + 1 >= list.length) return null;
  final next = list[at + 1];
  // De la última temporada normal no se salta a los especiales.
  if ((next.season ?? 1) == 0 && (current.season ?? 1) != 0) return null;
  final released = next.released;
  if (released != null && released.isAfter(now ?? DateTime.now())) return null;
  return next;
}
