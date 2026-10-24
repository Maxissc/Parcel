import 'package:parcel_core/parcel_core.dart';

import '../../data/app_settings.dart';
import '../../shared/urls.dart';

/// Idiomas preferidos (los de Ajustes) para elegir pistas al abrir un video.
/// `null` es «sin preferencia».
class TrackPreferences {
  const TrackPreferences({
    this.audioLanguage,
    this.subtitleLanguage,
    this.originalLanguage,
  });

  /// `original` o un código de idioma.
  final String? audioLanguage;

  /// `latam` o un código de idioma.
  final String? subtitleLanguage;

  /// Idioma original del contenido (3 letras), si se sabe: es el que busca el
  /// audio «Original».
  final String? originalLanguage;

  /// La pista de audio que corresponde al idioma preferido, o `null`. Con
  /// «Original» busca el audio en el idioma original y, si no lo sabe, deja la
  /// pista marcada por defecto.
  AudioTrack? pickAudio(List<AudioTrack> tracks) {
    final language = audioLanguage;
    if (language == null) return null;
    if (language == originalAudioCode) {
      return pickOriginalAudio(tracks, originalLanguage);
    }
    return pickPreferredTrack(tracks, [language]);
  }

  /// La pista de subtítulos que corresponde al idioma preferido, o `null`.
  SubtitleTrack? pickSubtitle(List<SubtitleTrack> tracks) {
    final language = subtitleLanguage;
    return language == null ? null : pickPreferredTrack(tracks, [language]);
  }
}

/// Nombre en español de un código de idioma, o el código en mayúsculas si no
/// se conoce.
String languageName(String code) {
  for (final entry in _names.entries) {
    if (languagesMatch(code, entry.key)) return entry.value;
  }
  return code.toUpperCase();
}

const Map<String, String> _names = {
  'spa': 'Español',
  'eng': 'Inglés',
  'por': 'Portugués',
  'fre': 'Francés',
  'ger': 'Alemán',
  'ita': 'Italiano',
  'jpn': 'Japonés',
  'rus': 'Ruso',
  'chi': 'Chino',
  'kor': 'Coreano',
  'ara': 'Árabe',
  'dut': 'Neerlandés',
  'pol': 'Polaco',
  'tur': 'Turco',
  'swe': 'Sueco',
  'hin': 'Hindi',
};

/// Subtítulos de addons que se cargan al reproductor: hasta [perLanguage] por
/// idioma (un addon como OpenSubtitles manda decenas) y [maxTotal] en total,
/// con el idioma preferido primero. A cada uno le pone un nombre legible.
List<Subtitle> selectAddonSubtitles(
  List<Subtitle> all, {
  String? preferredLanguage,
  int perLanguage = 2,
  int maxTotal = 8,
}) {
  final seen = <String>{};
  final byLanguage = <String, List<Subtitle>>{};
  for (final s in all) {
    // Una ruta de archivo local haría fallar al reproductor: solo http(s).
    if (!isHttpUrl(s.url) || !seen.add(s.url)) continue;
    byLanguage.putIfAbsent(s.lang.toLowerCase(), () => []).add(s);
  }
  bool isPreferred(String language) =>
      preferredLanguage != null && languagesMatch(language, preferredLanguage);
  final languages = [
    ...byLanguage.keys.where(isPreferred),
    ...byLanguage.keys.where((l) => !isPreferred(l)),
  ];
  final result = <Subtitle>[];
  for (final language in languages) {
    final group = byLanguage[language]!.take(perLanguage).toList();
    for (var i = 0; i < group.length; i++) {
      final s = group[i];
      final name = languageName(s.lang);
      final label = s.label ?? (group.length > 1 ? '$name ${i + 1}' : name);
      result.add(Subtitle(id: s.id, url: s.url, lang: s.lang, label: label));
    }
  }
  return result.take(maxTotal).toList();
}
