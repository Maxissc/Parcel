import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/progress_providers.dart';
import '../../data/providers.dart';
import '../../shared/catalog_row_section.dart';
import '../../shared/state_views.dart';
import 'continue_watching_row.dart';

/// Abre el detalle de [meta] (el ítem del catálogo viaja para mostrarse
/// enseguida mientras llega la meta completa).
void openDetail(BuildContext context, Meta meta) =>
    context.push(Routes.detailPath(meta.type, meta.id), extra: meta);

/// Inicio: «Seguir viendo» y una fila por cada catálogo de la home de los
/// addons. Las filas cargan solas y en paralelo.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Se redibuja cuando se instalan, quitan o reordenan addons.
    ref.watch(installedAddonsProvider);
    final catalogs = ref.watch(addonAggregatorProvider).homeCatalogs();
    final hasContinue = ref.watch(continueWatchingProvider).isNotEmpty;
    final statuses = [
      for (final catalog in catalogs)
        rowStatus(ref, (catalog: catalog, search: null)),
    ];

    if (catalogs.isEmpty && !hasContinue) {
      return EmptyState(
        icon: Icons.home_outlined,
        title: 'Tus addons no traen catálogos para el inicio',
        message:
            'Instalá un addon con catálogos, como Cinemeta, para ver acá '
            'películas y series.',
        actions: [
          FilledButton.icon(
            onPressed: () => context.go(Routes.addons),
            icon: const Icon(Icons.extension_outlined),
            label: const Text('Ir a Addons'),
          ),
        ],
      );
    }
    if (!hasContinue && statuses.every((s) => s == RowStatus.empty)) {
      return const EmptyState(
        icon: Icons.movie_outlined,
        title: 'No hay nada para mostrar por ahora',
        message: 'Tus catálogos vinieron vacíos. Probá de nuevo más tarde.',
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
      children: [
        ContinueWatchingRow(onOpen: (meta) => openDetail(context, meta)),
        for (final catalog in catalogs)
          CatalogRowSection(
            key: ValueKey((
              catalog.addon.transportUrl,
              catalog.catalog.type,
              catalog.catalog.id,
            )),
            catalog: catalog,
            onOpen: (meta) => openDetail(context, meta),
          ),
      ],
    );
  }
}
