import 'playback_track.dart';

/// Formatea un tiempo de reproducción: `m:ss`, o `h:mm:ss` desde una hora.
///
/// Descarta los milisegundos; un valor negativo cuenta como cero.
String formatPlaybackTime(Duration d) {
  final totalSeconds = d.isNegative ? 0 : d.inSeconds;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Equivalencias entre códigos ISO 639-2 (2 o 3 letras) y el de 2 letras.
const Map<String, String> _iso2 = {
  'spa': 'es',
  'eng': 'en',
  'por': 'pt',
  'fre': 'fr',
  'fra': 'fr',
  'ger': 'de',
  'deu': 'de',
  'ita': 'it',
  'jpn': 'ja',
  'rus': 'ru',
  'chi': 'zh',
  'zho': 'zh',
  'kor': 'ko',
  'ara': 'ar',
  'dut': 'nl',
  'nld': 'nl',
  'pol': 'pl',
  'tur': 'tr',
  'swe': 'sv',
  'hin': 'hi',
};

String _normalizeLanguage(String code) {
  final base = code.toLowerCase().split(RegExp('[-_]')).first.trim();
  return _iso2[base] ?? base;
}

/// `true` si [trackLanguage] y [preferred] son el mismo idioma.
///
/// Ignora mayúsculas y región (`pt_BR` coincide con `por`) y entiende los
/// códigos de 2 y 3 letras más comunes. Un código que no conoce solo coincide
/// consigo mismo.
bool languagesMatch(String? trackLanguage, String preferred) {
  if (trackLanguage == null || trackLanguage.trim().isEmpty) return false;
  if (preferred.trim().isEmpty) return false;
  return _normalizeLanguage(trackLanguage) == _normalizeLanguage(preferred);
}

/// Primera pista que coincide con el primer idioma preferido que tenga alguna.
///
/// [preferredLanguages] va en orden de preferencia. Devuelve `null` si no hay
/// coincidencia.
T? pickPreferredTrack<T extends PlaybackTrack>(
  List<T> tracks,
  List<String> preferredLanguages,
) {
  for (final preferred in preferredLanguages) {
    for (final track in tracks) {
      if (languagesMatch(track.language, preferred)) return track;
    }
  }
  return null;
}
