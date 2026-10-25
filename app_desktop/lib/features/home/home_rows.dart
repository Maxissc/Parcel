import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../data/home_layout.dart';
import '../../data/providers.dart';

/// Las filas de la home que se muestran, en el orden elegido y sin las
/// ocultas. Una fila oculta no se pide.
final homeRowsProvider = Provider.autoDispose<List<CatalogRef>>((ref) {
  ref.watch(installedAddonsProvider);
  final layout = ref.watch(appSettingsProvider.select((s) => s.homeLayout));
  return applyHomeLayout(
    ref.watch(addonAggregatorProvider).homeCatalogs(),
    layout,
  );
});

/// Todas las filas posibles de la home, también las ocultas, en el orden
/// elegido (la lista de ajustes).
final homeAllRowsProvider = Provider.autoDispose<List<CatalogRef>>((ref) {
  ref.watch(installedAddonsProvider);
  final layout = ref.watch(appSettingsProvider.select((s) => s.homeLayout));
  return applyHomeLayout(
    ref.watch(addonAggregatorProvider).homeCatalogs(),
    layout,
    includeHidden: true,
  );
});

/// Qué filas ya cargaron y vinieron vacías. La home no pide todas las filas de
/// entrada (solo las que se acercan a la pantalla), así que no puede mirarlas
/// todas: cada fila avisa acá cuando termina.
final homeEmptyRowsProvider = NotifierProvider<HomeEmptyRows, Set<String>>(
  HomeEmptyRows.new,
);

class HomeEmptyRows extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void report(String key, {required bool empty}) {
    if (!ref.mounted || state.contains(key) == empty) return;
    state = empty ? {...state, key} : ({...state}..remove(key));
  }
}

/// `true` cuando todas las filas visibles de la home terminaron y vinieron
/// vacías.
final homeRowsAllEmptyProvider = Provider.autoDispose<bool>((ref) {
  final rows = ref.watch(homeRowsProvider);
  if (rows.isEmpty) return false;
  final empty = ref.watch(homeEmptyRowsProvider);
  return rows.every((c) => empty.contains(homeRowKey(c)));
});
