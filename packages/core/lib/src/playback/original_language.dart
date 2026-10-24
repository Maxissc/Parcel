import '../models/meta.dart';
import 'playback_track.dart';
import 'playback_utils.dart';

/// Idioma original de [meta], en código de 3 letras (`eng`, `spa`, `jpn`...), o
/// `null` si no se puede saber.
///
/// Usa `original_language` si la meta lo trae (de TMDB o de `app_extras`); si
/// no, el primer país de `country` que figure en un mapa corto de países
/// (Estados Unidos, Reino Unido, España, México, Japón, Corea del Sur...).
String? inferOriginalLanguage(Meta meta) {
  final declared = meta.originalLanguage?.trim().toLowerCase();
  if (declared != null && declared.isNotEmpty) {
    return _toThreeLetters[declared] ?? declared;
  }
  final country = meta.country;
  if (country == null) return null;
  for (final part in country.split(RegExp(r'[,/|;]'))) {
    final language = _countryLanguage[part.trim().toLowerCase()];
    if (language != null) return language;
  }
  return null;
}

/// La pista de audio original: la que está en [language], sin ser un
/// comentario ni un doblaje marcado en el título. Si no hay, la pista marcada
/// por defecto o, si tampoco, la primera. `null` si no hay pistas.
AudioTrack? pickOriginalAudio(List<AudioTrack> tracks, String? language) {
  if (tracks.isEmpty) return null;
  if (language != null) {
    for (final track in tracks) {
      if (languagesMatch(track.language, language) &&
          !_commentary.hasMatch(track.title ?? '') &&
          !_dubbed.hasMatch(track.title ?? '')) {
        return track;
      }
    }
  }
  for (final track in tracks) {
    if (track.isDefault) return track;
  }
  return tracks.first;
}

final RegExp _commentary = RegExp(r'comment|comentario', caseSensitive: false);
final RegExp _dubbed = RegExp(
  r'\bdub|dubbing|dublad|dublagem|doblaje|doblad',
  caseSensitive: false,
);

const Map<String, String> _toThreeLetters = {
  'en': 'eng',
  'es': 'spa',
  'fr': 'fre',
  'de': 'ger',
  'it': 'ita',
  'ja': 'jpn',
  'ko': 'kor',
  'hi': 'hin',
  'pt': 'por',
  'zh': 'chi',
  'cn': 'chi', // TMDB usa «cn» para el cantonés.
  'ru': 'rus',
};

const Map<String, String> _countryLanguage = {
  'united states': 'eng',
  'united states of america': 'eng',
  'usa': 'eng',
  'united kingdom': 'eng',
  'uk': 'eng',
  'canada': 'eng',
  'australia': 'eng',
  'ireland': 'eng',
  'new zealand': 'eng',
  'spain': 'spa',
  'mexico': 'spa',
  'argentina': 'spa',
  'colombia': 'spa',
  'chile': 'spa',
  'france': 'fre',
  'germany': 'ger',
  'italy': 'ita',
  'japan': 'jpn',
  'south korea': 'kor',
  'india': 'hin',
  'brazil': 'por',
  'portugal': 'por',
  'china': 'chi',
  'hong kong': 'chi',
  'taiwan': 'chi',
  'russia': 'rus',
};
