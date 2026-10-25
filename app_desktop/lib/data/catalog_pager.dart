import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../shared/media_labels.dart';
import 'providers.dart';

/// Qué catálogo paginar y con qué género (`null` es «Todos»).
typedef PagerKey = ({CatalogRef catalog, String? genre});

/// Lo que lleva cargado la pantalla de «Ver todo».
class CatalogPage {
  const CatalogPage({
    this.items = const [],
    this.loading = false,
    this.failure,
    this.end = false,
  });

  final List<Meta> items;

  /// Hay un pedido en curso (el primero o uno de «más»).
  final bool loading;

  /// Por qué falló el último pedido, o `null`.
  final String? failure;

  /// El addon ya no tiene más páginas (o no admite `skip`).
  final bool end;

  bool get isFirstLoad => loading && items.isEmpty;

  CatalogPage copyWith({
    List<Meta>? items,
    bool? loading,
    Object? failure = _keep,
    bool? end,
  }) => CatalogPage(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    failure: identical(failure, _keep) ? this.failure : failure as String?,
    end: end ?? this.end,
  );
}

const Object _keep = Object();

/// Pide las páginas de un catálogo de a una, con el extra `skip` si el addon lo
/// soporta, y filtra por el extra `genre`.
class CatalogPager extends Notifier<CatalogPage> {
  CatalogPager(this.key);

  final PagerKey key;
  int _generation = 0;

  bool get _paged => key.catalog.catalog.acceptsExtra('skip');

  @override
  CatalogPage build() {
    ref.onDispose(() => _generation++);
    scheduleMicrotask(loadMore);
    return const CatalogPage(loading: true);
  }

  /// Pide la página que sigue. No hace nada si ya está pidiendo o si no hay
  /// más.
  Future<void> loadMore() async {
    if (!ref.mounted) return;
    final current = state;
    if (current.end || _inFlight) return;
    _inFlight = true;
    final generation = _generation;
    state = current.copyWith(loading: true, failure: null);
    final result = await ref
        .read(addonAggregatorProvider)
        .fetchCatalog(
          key.catalog,
          extra: {
            if (key.genre != null) 'genre': key.genre!,
            if (_raw > 0) 'skip': '$_raw',
          },
        );
    _inFlight = false;
    if (!ref.mounted || generation != _generation) return;
    switch (result) {
      case AddonFailure(:final error):
        state = state.copyWith(loading: false, failure: failureText(error));
      case AddonSuccess(:final value):
        _raw += value.length;
        final known = {for (final m in state.items) '${m.type}/${m.id}'};
        final fresh = [
          for (final m in value)
            if (known.add('${m.type}/${m.id}')) m,
        ];
        state = state.copyWith(
          items: [...state.items, ...fresh],
          loading: false,
          // Sin `skip` el addon da todo de una vez; con `skip`, una página sin
          // nada nuevo es el final.
          end: !_paged || fresh.isEmpty,
        );
    }
  }

  bool _inFlight = false;
  int _raw = 0;

  /// Vuelve a pedir lo último que falló.
  Future<void> retry() => loadMore();
}

final catalogPagerProvider = NotifierProvider.autoDispose
    .family<CatalogPager, CatalogPage, PagerKey>(CatalogPager.new);
