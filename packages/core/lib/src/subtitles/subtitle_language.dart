import '../models/subtitle.dart';

/// Idioma de un subtítulo, agrupado como le importa al usuario.
enum SubtitleLanguage {
  /// Español de Latinoamérica.
  latam,

  /// Español (de España o sin región).
  spanish,
  english,

  /// Cualquier otro idioma.
  other;

  /// Prioridad por defecto al ordenar: LatAm > español > inglés > resto.
  static const List<SubtitleLanguage> defaultPriority = [
    latam,
    spanish,
    english,
  ];

  /// Idioma de [subtitle], mirando el código `lang`, el `label` y [title]
  /// (por ejemplo, el título del stream o el nombre del archivo).
  ///
  /// Códigos que reconoce:
  /// - `spl`: el que usa OpenSubtitles v3 para el español de Latinoamérica
  ///   (verificado en su respuesta real; el resto del español viene como `spa`);
  /// - `es-419`, `es-LA` y `es-` más un país de Latinoamérica (`es-MX`,
  ///   `es-AR`, `es-CO`...);
  /// - `spa`, `es` y `es-ES` son español; `eng` y `en` (con región), inglés.
  ///
  /// Además marca como LatAm a un subtítulo en español cuyo label o título
  /// diga «Latino», «LatAm», «Latinoamérica», «América Latina» o «LA».
  static SubtitleLanguage detect(Subtitle subtitle, {String? title}) {
    final parts = subtitle.lang.trim().toLowerCase().split(RegExp('[-_]'));
    final base = parts.first;
    final region = parts.length > 1 ? parts[1] : null;
    final text = [subtitle.label, title].whereType<String>().join(' ');

    if (base == 'spl') return latam;
    if (base == 'es' &&
        region != null &&
        (region == '419' || region == 'la' || _latamRegions.contains(region))) {
      return latam;
    }
    if (base == 'eng' || base == 'en') return english;

    final spanish =
        base == 'spa' || base == 'es' || _spanishWords.hasMatch(text);
    if (spanish) {
      return _latamWords.hasMatch(text) || _latamInitials.hasMatch(text)
          ? latam
          : SubtitleLanguage.spanish;
    }
    if (_englishWords.hasMatch(text) && !_knownCode.hasMatch(base)) {
      return english;
    }
    return other;
  }
}

/// Ordena [subtitles] según [priority] (el primero de la lista va primero) y
/// deja al final los idiomas que no figuran. A igualdad mantiene el orden de
/// entrada (el de los addons). No modifica la lista original.
List<Subtitle> rankSubtitles(
  List<Subtitle> subtitles, {
  List<SubtitleLanguage> priority = SubtitleLanguage.defaultPriority,
}) {
  final entries = [
    for (var i = 0; i < subtitles.length; i++)
      (
        i,
        subtitles[i],
        () {
          final p = priority.indexOf(SubtitleLanguage.detect(subtitles[i]));
          return p < 0 ? priority.length : p;
        }(),
      ),
  ];
  entries.sort((a, b) {
    final c = a.$3.compareTo(b.$3);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in entries) e.$2];
}

/// Países de Latinoamérica (ISO 3166) para códigos tipo `es-MX`.
const Set<String> _latamRegions = {
  'mx', 'ar', 'co', 'cl', 'pe', 'uy', 've', 'ec', 'bo', 'py', 'cr', 'gt', //
  'hn', 'ni', 'pa', 'sv', 'do', 'cu', 'pr',
};

final RegExp _spanishWords = RegExp(
  r'espa[ñn]ol|spanish|castellano',
  caseSensitive: false,
);
final RegExp _englishWords = RegExp(
  r'\b(english|ingl[eé]s)\b',
  caseSensitive: false,
);
final RegExp _latamWords = RegExp(
  r'\blatino\b|\blatam\b|latinoam[eé]ric|am[eé]rica\s+latina|hispanoam[eé]ric',
  caseSensitive: false,
);

// «LA» en mayúsculas y suelto, como en «Spanish (LA)».
final RegExp _latamInitials = RegExp(r'\bLA\b');

// Códigos de idioma conocidos de 2 o 3 letras: si el código dice otra cosa,
// el label no lo pisa.
final RegExp _knownCode = RegExp(
  r'^(por|pob|fre|fra|ger|deu|ita|jpn|rus|chi|zht|zhe|kor|ara|dut|nld|pol|tur|swe|hin|'
  r'pt|fr|de|it|ja|ru|zh|ko|ar|nl|pl|tr|sv|hi|srp|hrv|cze|ron|ell|nor|fin|dan|heb)$',
);
