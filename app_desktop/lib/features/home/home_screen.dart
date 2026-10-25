import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/progress_providers.dart';
import '../../data/providers.dart';
import '../../shared/catalog_row_section.dart';
import '../../shared/state_views.dart';
import 'billboard.dart';
import 'continue_watching_row.dart';
import 'home_rows.dart';
import 'meta_actions.dart';

export 'meta_actions.dart' show openDetail;

/// Inicio: el billboard, «Seguir viendo» y una fila por cada catálogo de la
/// home de los addons, en el orden que eligió el usuario.
///
/// Las filas se piden recién cuando se acercan a la pantalla (una pantalla de
/// margen): la lista arma solo las que están cerca, y una fila que ya cargó
/// se queda en memoria.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogs = ref.watch(homeRowsProvider);
    final hasContinue = ref.watch(continueWatchingProvider).isNotEmpty;
    final allEmpty = ref.watch(homeRowsAllEmptyProvider);
    final hasAddonCatalogs = ref
        .watch(addonAggregatorProvider)
        .homeCatalogs()
        .isNotEmpty;

    if (!hasAddonCatalogs && !hasContinue) {
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
    if (!hasContinue && allEmpty) {
      return const EmptyState(
        icon: Icons.movie_outlined,
        title: 'No hay nada para mostrar por ahora',
        message: 'Tus catálogos vinieron vacíos. Probá de nuevo más tarde.',
      );
    }

    return ListView(
      key: const Key('home-list'),
      scrollCacheExtent: ScrollCacheExtent.pixels(
        MediaQuery.sizeOf(context).height,
      ),
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      children: [
        const Billboard(),
        const SizedBox(height: Spacing.md),
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
