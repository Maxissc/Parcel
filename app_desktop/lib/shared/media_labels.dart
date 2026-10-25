import 'package:parcel_core/parcel_core.dart';

/// Nombre en español de un tipo de contenido de Stremio.
String typeLabel(String type) => switch (type) {
  'movie' => 'Películas',
  'series' => 'Series',
  'channel' => 'Canales',
  'tv' => 'TV',
  'anime' => 'Anime',
  _ => type.isEmpty ? type : '${type[0].toUpperCase()}${type.substring(1)}',
};

/// «T1 E3», o `null` si falta la temporada o el episodio.
String? episodeLabel(int? season, int? episode) {
  if (season == null || episode == null) return null;
  return 'T$season E$episode';
}

/// Saca «T1 E3» de un id de episodio de IMDb con la forma `tt0903747:1:3`;
/// `null` para cualquier otro id. Otros catálogos arman el id distinto (por
/// ejemplo `kitsu:7442:5` lleva el id de la serie en el medio), así que de ahí
/// no se puede saber la temporada.
String? episodeLabelFromVideoId(String videoId) {
  final match = _imdbEpisodeId.firstMatch(videoId);
  if (match == null) return null;
  return episodeLabel(int.parse(match.group(1)!), int.parse(match.group(2)!));
}

final RegExp _imdbEpisodeId = RegExp(r'^tt\d+:(\d+):(\d+)$');

/// Por qué falló un addon, en una frase corta. No incluye la URL del addon.
String failureText(AddonException error) => switch (error.reason) {
  AddonFailureReason.timeout => 'No respondió a tiempo',
  AddonFailureReason.network => 'No se pudo conectar',
  AddonFailureReason.http =>
    error.statusCode == null
        ? 'Respondió con un error'
        : 'Respondió con el error ${error.statusCode}',
  AddonFailureReason.parse => 'Mandó una respuesta que no se entiende',
  AddonFailureReason.invalidUrl => 'La dirección del addon no es válida',
  AddonFailureReason.storage => 'No se pudo guardar en disco',
};

/// «Quedan 12 min» o «Quedan 1 h 05 min»; `null` si ya no queda nada.
String? remainingLabel(Duration duration, Duration position) {
  final left = duration - position;
  if (left <= Duration.zero) return null;
  final minutes = (left.inSeconds / 60).ceil();
  if (minutes < 60) return 'Quedan $minutes min';
  final rest = (minutes % 60).toString().padLeft(2, '0');
  return 'Quedan ${minutes ~/ 60} h $rest min';
}
