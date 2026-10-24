import 'json_helpers.dart';

/// Recurso que ofrece un addon (`catalog`, `meta`, `stream`, `subtitles`...).
///
/// Declarado como string suelto (`"meta"`) valen los `types` e `idPrefixes` del
/// manifest. Declarado como objeto ([full]), los `types` son los suyos (o los
/// del manifest si no los trae) y los `idPrefixes` solo los suyos: sin ellos
/// acepta cualquier id, como dice la doc de Stremio.
class AddonResource {
  const AddonResource(
    this.name, {
    this.types,
    this.idPrefixes,
    this.full = false,
  });

  final String name;
  final List<String>? types;
  final List<String>? idPrefixes;

  /// `true` si vino como objeto y no como string.
  final bool full;

  /// Acepta un string (`"meta"`) o un objeto (`{name, types, idPrefixes}`).
  /// Lanza [FormatException] si no tiene nombre.
  factory AddonResource.fromJson(Object? json) {
    if (json is String && json.isNotEmpty) return AddonResource(json);
    final map = asMap(json);
    final name = map == null ? null : asNonEmptyString(map['name']);
    if (map == null || name == null) {
      throw FormatException('Recurso inválido', json);
    }
    return AddonResource(
      name,
      types: asStringList(map['types']),
      idPrefixes: asStringList(map['idPrefixes']),
      full: true,
    );
  }
}

/// Parámetro extra que acepta un catálogo (`search`, `genre`, `skip`...).
class CatalogExtra {
  const CatalogExtra({
    required this.name,
    this.isRequired = false,
    this.options = const [],
    this.optionsLimit = 1,
  });

  final String name;

  /// Si es `true`, el catálogo solo se puede pedir con este extra.
  final bool isRequired;

  /// Valores posibles (por ejemplo, los géneros). Vacío si es libre.
  final List<String> options;
  final int optionsLimit;

  factory CatalogExtra.fromJson(Map<String, dynamic> json) {
    final name = asNonEmptyString(json['name']);
    if (name == null) throw FormatException('Extra sin nombre', json);
    return CatalogExtra(
      name: name,
      isRequired: asBool(json['isRequired']) ?? false,
      options: List.unmodifiable(asStringList(json['options']) ?? const []),
      optionsLimit: asInt(json['optionsLimit']) ?? 1,
    );
  }
}

/// Catálogo declarado en el manifest de un addon.
class AddonCatalog {
  const AddonCatalog({
    required this.type,
    required this.id,
    required this.name,
    this.extra = const [],
  });

  final String type;
  final String id;
  final String name;
  final List<CatalogExtra> extra;

  /// `true` si alguno de los extras es obligatorio (no sirve para la home).
  bool get hasRequiredExtra => extra.any((e) => e.isRequired);

  /// `true` si el catálogo acepta el extra [name].
  bool acceptsExtra(String name) => extra.any((e) => e.name == name);

  factory AddonCatalog.fromJson(Map<String, dynamic> json) {
    final type = asNonEmptyString(json['type']);
    final id = asNonEmptyString(json['id']);
    if (type == null || id == null) {
      throw FormatException('Catálogo sin type o id', json);
    }
    return AddonCatalog(
      type: type,
      id: id,
      name: asNonEmptyString(json['name']) ?? id,
      extra: parseList(json['extra'], CatalogExtra.fromJson),
    );
  }
}

/// Manifest de un addon de Stremio.
class AddonManifest {
  const AddonManifest._({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.logo,
    required this.types,
    required this.idPrefixes,
    required this.resources,
    required this.catalogs,
    required Map<String, dynamic> raw,
  }) : _raw = raw;

  final String id;
  final String name;
  final String version;
  final String description;
  final String? logo;
  final List<String> types;
  final List<String>? idPrefixes;
  final List<AddonResource> resources;
  final List<AddonCatalog> catalogs;
  final Map<String, dynamic> _raw;

  /// Lee un manifest. Tolera campos faltantes o de tipo raro; lanza
  /// [FormatException] si no tiene `id`, `name` ni al menos un recurso válido.
  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    final id = asNonEmptyString(json['id']);
    final name = asNonEmptyString(json['name']);
    if (id == null || name == null) {
      throw FormatException('Manifest sin id o name', json);
    }
    final resources = <AddonResource>[];
    final rawResources = json['resources'];
    if (rawResources is List) {
      for (final item in rawResources) {
        try {
          resources.add(AddonResource.fromJson(item));
        } on FormatException {
          continue;
        }
      }
    }
    if (resources.isEmpty) {
      throw FormatException('Manifest sin recursos válidos', json);
    }
    return AddonManifest._(
      id: id,
      name: name,
      version: asString(json['version']) ?? '',
      description: asString(json['description']) ?? '',
      logo: asNonEmptyString(json['logo']),
      types: List.unmodifiable(asStringList(json['types']) ?? const []),
      idPrefixes: asStringList(json['idPrefixes']),
      resources: List.unmodifiable(resources),
      catalogs: parseList(json['catalogs'], AddonCatalog.fromJson),
      raw: Map.unmodifiable(json),
    );
  }

  /// El JSON original del manifest, tal como se leyó.
  Map<String, dynamic> toJson() => _raw;

  /// `true` si el addon declara el recurso [resource], sin mirar tipo ni id.
  bool hasResource(String resource) => resources.any((r) => r.name == resource);

  /// `true` si el addon atiende [resource] para ese [type] e [id].
  ///
  /// Mira `types` e `idPrefixes` según [AddonResource]. Un `idPrefixes` ausente o vacío no restringe. Para `catalog` no
  /// se mira el id (el protocolo lo pide siempre que esté en `catalogs`).
  bool supports(String resource, String type, String id) {
    for (final r in resources) {
      if (r.name != resource) continue;
      final types = r.types ?? this.types;
      if (!types.contains(type)) continue;
      if (resource == 'catalog') return true;
      final prefixes = r.full ? r.idPrefixes : idPrefixes;
      if (prefixes == null || prefixes.isEmpty || prefixes.any(id.startsWith)) {
        return true;
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is AddonManifest &&
      other.id == id &&
      other.name == name &&
      other.version == version;

  @override
  int get hashCode => Object.hash(id, name, version);

  @override
  String toString() => 'AddonManifest($id $version)';
}
