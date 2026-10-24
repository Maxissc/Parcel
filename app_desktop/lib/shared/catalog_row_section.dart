import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../app/theme.dart';
import '../data/browse_providers.dart';
import 'media_labels.dart';
import 'media_row.dart';
import 'poster_card.dart';

/// Resultado de mirar una fila de catálogo, para decidir qué mostrar arriba.
enum RowStatus { loading, empty, failed, ready }

/// Estado de la fila de [key] sin dibujarla (la home lo usa para saber si no
/// hay nada que mostrar).
RowStatus rowStatus(WidgetRef ref, CatalogKey key) =>
    rowStatusOf(ref.watch(catalogItemsProvider(key)));

/// Igual que [rowStatus], desde el valor ya leído.
RowStatus rowStatusOf(AsyncValue<AddonResult<List<Meta>>> async) {
  final result = async.value;
  if (async.isLoading && result == null) return RowStatus.loading;
  if (async.hasError || result is AddonFailure) return RowStatus.failed;
  if (result is AddonSuccess<List<Meta>>) {
    return result.value.isEmpty ? RowStatus.empty : RowStatus.ready;
  }
  return RowStatus.loading;
}

/// Una fila de la home o de la búsqueda: el catálogo de un addon.
///
/// Carga sola, muestra esqueletos mientras espera, se oculta si viene vacía y
/// ofrece «Reintentar» si falla.
class CatalogRowSection extends ConsumerWidget {
  const CatalogRowSection({
    super.key,
    required this.catalog,
    this.search,
    required this.onOpen,
  });

  final CatalogRef catalog;

  /// Texto de búsqueda, o `null` para el catálogo sin filtrar.
  final String? search;
  final void Function(Meta meta) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (catalog: catalog, search: search);
    final async = ref.watch(catalogItemsProvider(key));
    final title =
        '${catalog.catalog.name} · ${typeLabel(catalog.catalog.type)}';
    final addonName = catalog.addon.manifest.name;

    Widget failed(String reason) => _Section(
      title: title,
      addonName: addonName,
      child: _RowError(
        reason: reason,
        onRetry: () => ref.invalidate(catalogItemsProvider(key)),
      ),
    );

    return async.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      loading: () => _Section(
        title: title,
        addonName: addonName,
        child: const ShelfSkeleton(),
      ),
      error: (_, _) => failed('Algo falló al pedir el catálogo'),
      data: (result) => switch (result) {
        AddonFailure(:final error) => failed(failureText(error)),
        AddonSuccess(:final value) when value.isEmpty =>
          const SizedBox.shrink(),
        AddonSuccess(:final value) => _Section(
          title: title,
          addonName: addonName,
          child: Shelf(
            itemCount: value.length,
            itemBuilder: (context, index) {
              final meta = value[index];
              return PosterCard(
                title: meta.name,
                poster: meta.poster,
                shape: meta.posterShape,
                caption: meta.releaseInfo,
                onTap: () => onOpen(meta),
              );
            },
          ),
        ),
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.addonName,
    required this.child,
  });

  final String title;
  final String addonName;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RowHeader(title: title, subtitle: addonName),
          child,
        ],
      ),
    );
  }
}

class _RowError extends StatelessWidget {
  const _RowError({required this.reason, required this.onRetry});

  final String reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: scheme.error),
          const SizedBox(width: Spacing.sm),
          Text('No se pudo cargar', style: TextStyle(color: scheme.error)),
          Text(' · $reason', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(width: Spacing.sm),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
