import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/providers.dart';
import '../../shared/catalog_row_section.dart';
import '../../shared/state_views.dart';
import '../home/home_screen.dart';

/// Cuenta los pedidos de «enfocá el campo de búsqueda» (Ctrl+F desde
/// cualquier sección).
final searchFocusRequestProvider = NotifierProvider<SearchFocusRequest, int>(
  SearchFocusRequest.new,
);

class SearchFocusRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

/// Buscar: un campo y, abajo, los resultados en una fila por cada catálogo de
/// búsqueda de los addons.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  /// Espera desde que se deja de escribir hasta que se busca.
  static const Duration debounce = Duration(milliseconds: 400);

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'search-field');
  Timer? _debounce;
  String _query = '';
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusField());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Las secciones viven todas a la vez; al volver a esta se enfoca el campo.
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_wasActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusField());
    }
    _wasActive = active;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _focusField() {
    if (mounted) _focus.requestFocus();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() => _query = '');
      return;
    }
    _debounce = Timer(SearchScreen.debounce, () => _apply(trimmed));
    setState(() {}); // para el botón de borrar
  }

  void _apply(String query) {
    if (mounted && query != _query) setState(() => _query = query);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(searchFocusRequestProvider, (_, _) => _focusField());
    ref.watch(installedAddonsProvider);
    final catalogs = ref.watch(addonAggregatorProvider).searchCatalogs();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.lg,
            Spacing.md,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: TextField(
                key: const Key('search-field'),
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (text) {
                  _debounce?.cancel();
                  if (text.trim().isNotEmpty) _apply(text.trim());
                },
                decoration: InputDecoration(
                  hintText: 'Buscar películas y series',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar',
                          icon: const Icon(Icons.close),
                          onPressed: _clear,
                        ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: _results(context, catalogs, theme)),
      ],
    );
  }

  Widget _results(
    BuildContext context,
    List<CatalogRef> catalogs,
    ThemeData theme,
  ) {
    if (catalogs.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Ningún addon instalado permite buscar',
        message: 'Instalá un addon con búsqueda, como Cinemeta.',
        actions: [
          FilledButton.icon(
            onPressed: () => context.go(Routes.addons),
            icon: const Icon(Icons.extension_outlined),
            label: const Text('Ir a Addons'),
          ),
        ],
      );
    }
    if (_query.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Buscá algo para ver',
        message:
            'Escribí el nombre de una película o serie y buscamos en '
            'todos tus addons.',
      );
    }
    return _SearchResults(
      query: _query,
      catalogs: catalogs,
      onOpen: (meta) => openDetail(context, meta),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.query,
    required this.catalogs,
    required this.onOpen,
  });

  final String query;
  final List<CatalogRef> catalogs;
  final void Function(Meta meta) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = [
      for (final catalog in catalogs)
        rowStatus(ref, (catalog: catalog, search: query)),
    ];
    if (statuses.every((s) => s == RowStatus.empty)) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No encontramos resultados para «$query»',
        message: 'Probá con otras palabras o revisá cómo está escrito.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      children: [
        for (final catalog in catalogs)
          CatalogRowSection(
            key: ValueKey((
              catalog.addon.transportUrl,
              catalog.catalog.type,
              catalog.catalog.id,
              query,
            )),
            catalog: catalog,
            search: query,
            onOpen: onOpen,
          ),
      ],
    );
  }
}
