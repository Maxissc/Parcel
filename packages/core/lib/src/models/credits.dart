import 'json_helpers.dart';

/// Un integrante del elenco.
class CastMember {
  const CastMember({required this.name, this.character, this.photoUrl});

  final String name;

  /// Personaje que interpreta, si se conoce.
  final String? character;

  /// Foto, si se conoce.
  final String? photoUrl;

  /// Lanza [FormatException] si falta `name`. Lee `name`, `character` y `photo`
  /// (el formato de `app_extras.cast`).
  factory CastMember.fromJson(Map<String, dynamic> json) {
    final name = asNonEmptyString(json['name']);
    if (name == null) throw FormatException('Elenco sin nombre', json);
    return CastMember(
      name: name.trim(),
      character: asNonEmptyString(json['character']),
      photoUrl: asNonEmptyString(json['photo']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CastMember &&
      other.name == name &&
      other.character == character &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(name, character, photoUrl);

  @override
  String toString() => 'CastMember($name)';
}

/// Elenco y equipo de un contenido, ya mezclados y sin repetidos.
class Credits {
  const Credits({
    this.cast = const [],
    this.directors = const [],
    this.writers = const [],
  });

  final List<CastMember> cast;
  final List<String> directors;
  final List<String> writers;
}

/// Junta [detailed] (con fotos y personajes) y [names] sin repetir: gana el que
/// tiene datos. Primero van los detallados, en su orden; después los nombres
/// que faltan.
List<CastMember> mergeCast(List<CastMember> detailed, Iterable<String> names) {
  final seen = <String>{};
  final result = <CastMember>[];
  for (final member in detailed) {
    if (seen.add(nameKey(member.name))) result.add(member);
  }
  for (final name in names) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && seen.add(nameKey(trimmed))) {
      result.add(CastMember(name: trimmed));
    }
  }
  return List.unmodifiable(result);
}

/// Junta listas de nombres sin repetir, en orden.
List<String> mergeNames(Iterable<Iterable<String>> lists) {
  final seen = <String>{};
  final result = <String>[];
  for (final list in lists) {
    for (final name in list) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty && seen.add(nameKey(trimmed))) {
        result.add(trimmed);
      }
    }
  }
  return List.unmodifiable(result);
}

/// Clave para comparar nombres: sin mayúsculas, tildes ni espacios de más.
String nameKey(String name) {
  final lower = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    buffer.write(
      _folded[String.fromCharCode(rune)] ?? String.fromCharCode(rune),
    );
  }
  return buffer.toString();
}

const Map<String, String> _folded = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ñ': 'n', 'ç': 'c',
};
