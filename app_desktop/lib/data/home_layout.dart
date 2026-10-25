import 'package:parcel_core/parcel_core.dart';

/// Identifica la fila de un catálogo en los ajustes: el id del addon (no su
/// URL, que puede llevar claves), el tipo y el id del catálogo.
String homeRowKey(CatalogRef ref) =>
    '${ref.addon.manifest.id}|${ref.catalog.type}|${ref.catalog.id}';

/// Cómo quiere el usuario ver las filas de la home: el orden y cuáles oculta.
class HomeLayout {
  const HomeLayout({this.order = const [], this.hidden = const {}});

  /// Claves ([homeRowKey]) en el orden elegido. Las que no están van al final,
  /// en el orden de los addons.
  final List<String> order;

  /// Claves de las filas ocultas.
  final Set<String> hidden;

  bool get isDefault => order.isEmpty && hidden.isEmpty;

  HomeLayout copyWith({List<String>? order, Set<String>? hidden}) =>
      HomeLayout(order: order ?? this.order, hidden: hidden ?? this.hidden);

  @override
  bool operator ==(Object other) =>
      other is HomeLayout &&
      _sameList(other.order, order) &&
      other.hidden.length == hidden.length &&
      other.hidden.containsAll(hidden);

  @override
  int get hashCode => Object.hash(Object.hashAll(order), hidden.length);

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Las filas de [catalogs] en el orden de [layout]; sin las ocultas, salvo con
/// [includeHidden] (la pantalla de ajustes las lista todas).
List<CatalogRef> applyHomeLayout(
  List<CatalogRef> catalogs,
  HomeLayout layout, {
  bool includeHidden = false,
}) {
  final byKey = {for (final c in catalogs) homeRowKey(c): c};
  final result = <CatalogRef>[];
  final placed = <String>{};
  for (final key in layout.order) {
    final catalog = byKey[key];
    if (catalog != null && placed.add(key)) result.add(catalog);
  }
  for (final c in catalogs) {
    if (placed.add(homeRowKey(c))) result.add(c);
  }
  if (includeHidden) return result;
  return [
    for (final c in result)
      if (!layout.hidden.contains(homeRowKey(c))) c,
  ];
}
