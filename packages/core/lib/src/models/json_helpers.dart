// Ayudas para leer JSON de addons sin explotar con campos faltantes o de tipo
// raro. Uso interno del paquete.

String? asString(Object? value) => value is String ? value : null;

String? asNonEmptyString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool? asBool(Object? value) => value is bool ? value : null;

DateTime? asDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Map<String, dynamic>? asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return null;
}

/// Lista de strings; ignora los elementos que no lo son. Un string suelto se
/// toma como lista de uno. Devuelve `null` si no hay nada que leer.
List<String>? asStringList(Object? value) {
  if (value is String) return [value];
  if (value is List) return value.whereType<String>().toList(growable: false);
  return null;
}

/// Parsea cada elemento de [raw] con [parse] y descarta los inválidos (los que
/// no son objeto o lanzan [FormatException]).
List<T> parseList<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) return const [];
  final result = <T>[];
  for (final item in raw) {
    final map = asMap(item);
    if (map == null) continue;
    try {
      result.add(parse(map));
    } on FormatException {
      continue;
    }
  }
  return List.unmodifiable(result);
}
