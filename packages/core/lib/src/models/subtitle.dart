import 'json_helpers.dart';

/// Subtítulo que ofrece un addon (o un stream).
class Subtitle {
  const Subtitle({
    required this.id,
    required this.url,
    required this.lang,
    this.label,
  });

  /// Identificador; si el addon no lo manda, se usa la [url].
  final String id;
  final String url;

  /// Código de idioma (ISO 639-2) o el texto que mandó el addon.
  final String lang;

  /// Texto para el selector, en lugar del nombre del idioma.
  final String? label;

  /// Lanza [FormatException] si falta `url` o `lang`.
  factory Subtitle.fromJson(Map<String, dynamic> json) {
    final url = asNonEmptyString(json['url']);
    final lang = asNonEmptyString(json['lang']);
    if (url == null || lang == null) {
      throw FormatException('Subtítulo sin url o lang', json);
    }
    return Subtitle(
      id: asNonEmptyString(json['id']) ?? url,
      url: url,
      lang: lang,
      label: asNonEmptyString(json['label']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Subtitle &&
      other.id == id &&
      other.url == url &&
      other.lang == lang &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, url, lang, label);

  @override
  String toString() => 'Subtitle($lang $url)';
}

/// Lee una lista de subtítulos y descarta los inválidos.
List<Subtitle> parseSubtitles(Object? raw) => parseList(raw, Subtitle.fromJson);
