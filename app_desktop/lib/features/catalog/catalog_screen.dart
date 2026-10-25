import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/catalog_pager.dart';
import '../../shared/media_labels.dart';
import '../../shared/poster_card.dart';
import '../../shared/state_views.dart';
import '../home/meta_actions.dart';

/// «Ver todo»: el catálogo entero de una fila, en una grilla de pósters, con
/// chips para filtrar por género (si el addon los declara) y más páginas al
/// llegar al final (si el addon soporta `skip`).
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.catalog});

  final CatalogRef catalog;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final ScrollController _scroll = ScrollController();
  String? _genre;

  PagerKey get _key => (catalog: widget.catalog, genre: _genre);

  List<String> get _genres {
    final extra = widget.catalog.catalog.extra
        .where((e) => e.name == 'genre')
        .firstOrNull;
    return extra?.options ?? const [];
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Pide la página que sigue cuando faltan menos de dos pantallas para el
  // final.
  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (ref.read(catalogPagerProvider(_key)).failure != null) return;
    final position = _scroll.position;
    if (position.extentAfter < position.viewportDimension * 2) {
      unawaited(ref.read(catalogPagerProvider(_key).notifier).loadMore());
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  void _pickGenre(String? genre) {
    if (genre == _genre) return;
    setState(() => _genre = genre);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = widget.catalog;
    final page = ref.watch(catalogPagerProvider(_key));
    // Si la página no llena la pantalla, hay que seguir pidiendo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMore();
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver (Esc)',
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                '${catalog.catalog.name} · ${typeLabel(catalog.catalog.type)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              catalog.addon.manifest.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_genres.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                key: const Key('genre-chips'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: Spacing.xs,
                ),
                children: [
                  _GenreChip(
                    label: 'Todos',
                    selected: _genre == null,
                    onSelected: () => _pickGenre(null),
                  ),
                  for (final genre in _genres)
                    _GenreChip(
                      label: genre,
                      selected: _genre == genre,
                      onSelected: () => _pickGenre(genre),
                    ),
                ],
              ),
            ),
          Expanded(child: _body(context, page)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, CatalogPage page) {
    if (page.isFirstLoad) {
      return GridView.builder(
        key: const Key('catalog-skeleton'),
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Spacing.lg),
        gridDelegate: _grid,
        itemCount: 24,
        itemBuilder: (_, _) => const PosterCardSkeleton(),
      );
    }
    if (page.items.isEmpty) {
      if (page.failure != null) {
        return ErrorState(
          title: 'No se pudo cargar el catálogo',
          message: page.failure!,
          onRetry: () =>
              unawaited(ref.read(catalogPagerProvider(_key).notifier).retry()),
        );
      }
      return const EmptyState(
        icon: Icons.movie_outlined,
        title: 'No hay nada para mostrar',
        message: 'Este catálogo vino vacío. Probá con otro género.',
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Spacing.lg),
          sliver: SliverGrid.builder(
            gridDelegate: _grid,
            itemCount: page.items.length,
            itemBuilder: (context, index) {
              final meta = page.items[index];
              return Align(
                alignment: Alignment.topLeft,
                child: MetaActions(context, ref).card(meta),
              );
            },
          ),
        ),
        SliverToBoxAdapter(child: _footer(page)),
      ],
    );
  }

  Widget _footer(CatalogPage page) {
    if (page.failure != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        child: Center(
          child: TextButton.icon(
            key: const Key('catalog-retry-more'),
            onPressed: () => unawaited(
              ref.read(catalogPagerProvider(_key).notifier).retry(),
            ),
            icon: const Icon(Icons.refresh),
            label: Text('${page.failure} · Reintentar'),
          ),
        ),
      );
    }
    if (page.loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: Spacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: Spacing.lg);
  }

  static const _grid = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 172,
    mainAxisExtent: 210 + PosterSize.captionHeight + Spacing.sm,
    mainAxisSpacing: Spacing.md,
    crossAxisSpacing: Spacing.md,
  );
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
