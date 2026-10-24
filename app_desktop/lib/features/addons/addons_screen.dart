import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/platform.dart';
import '../../data/providers.dart';
import '../../shared/addon_logo.dart';
import '../../shared/page_layout.dart';
import '../../shared/redacted_url.dart';
import '../../shared/state_views.dart';
import 'add_addon_dialog.dart';
import 'addon_utils.dart';

/// Addons instalados: se ven, se reordenan (el orden es la prioridad), se
/// quitan, se agregan y se configuran.
class AddonsScreen extends ConsumerWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(installedAddonsProvider);
    return PageLayout(
      title: 'Addons',
      subtitle: addons.isEmpty
          ? null
          : '${addons.length} ${addons.length == 1 ? 'instalado' : 'instalados'}'
                ' · El orden define cuál tiene prioridad. Arrastrá para '
                'cambiarlo.',
      actions: [
        OutlinedButton.icon(
          key: const Key('import-from-accounts'),
          onPressed: () => context.push(Routes.onboarding),
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const Text('Importar desde Stremio o Nuvio'),
        ),
        FilledButton.icon(
          key: const Key('add-by-url'),
          onPressed: () => _add(context),
          icon: const Icon(Icons.add),
          label: const Text('Agregar por URL'),
        ),
      ],
      child: addons.isEmpty
          ? EmptyState(
              icon: Icons.extension_outlined,
              title: 'Todavía no tenés addons',
              message:
                  'Los addons le dan a Parcel el contenido. Traelos desde tu '
                  'cuenta de Stremio o Nuvio, o agregá uno con su URL.',
              actions: [
                FilledButton.icon(
                  onPressed: () => context.push(Routes.onboarding),
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Importar desde Stremio o Nuvio'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar por URL'),
                ),
              ],
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: Spacing.lg),
              itemCount: addons.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _reorder(context, ref, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final addon = addons[index];
                return _AddonTile(
                  key: ValueKey(addon.transportUrl),
                  addon: addon,
                  index: index,
                  isLast: index == addons.length - 1,
                );
              },
            ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showAddAddonDialog(context);
    if (name == null) return;
    _snack(messenger, 'Agregaste $name.');
  }

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    int oldIndex,
    int newIndex,
  ) async {
    await _persist(
      ScaffoldMessenger.of(context),
      () => ref.read(installedAddonsProvider.notifier).move(oldIndex, newIndex),
    );
  }
}

void _snack(
  ScaffoldMessengerState messenger,
  String text, {
  SnackBarAction? action,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        duration: const Duration(seconds: 6),
      ),
    );
}

/// Corre un cambio que escribe en disco y avisa si falla.
Future<void> _persist(
  ScaffoldMessengerState messenger,
  Future<void> Function() change,
) async {
  try {
    await change();
  } on FileSystemException {
    _snack(messenger, 'No pudimos guardar el cambio en el disco.');
  }
}

enum _Action { configure, moveUp, moveDown, remove }

class _AddonTile extends ConsumerWidget {
  const _AddonTile({
    super.key,
    required this.addon,
    required this.index,
    required this.isLast,
  });

  final InstalledAddon addon;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final manifest = addon.manifest;
    final configurable = isConfigurable(addon);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Tooltip(
                    message: 'Arrastrá para cambiar el orden',
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.sm),
                      child: Icon(
                        Icons.drag_indicator,
                        key: Key('drag-${manifest.name}'),
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              AddonLogo(manifest.logo, size: 56),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            manifest.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (manifest.version.isNotEmpty) ...[
                          const SizedBox(width: Spacing.sm),
                          Text(
                            'v${manifest.version}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (manifest.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.xs),
                        child: Text(
                          manifest.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: Spacing.sm),
                    Wrap(
                      spacing: Spacing.xs,
                      runSpacing: Spacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final type in manifest.types)
                          _TypeChip(typeLabel(type)),
                        RedactedUrl(addon.transportUrl),
                      ],
                    ),
                  ],
                ),
              ),
              if (configurable)
                IconButton(
                  key: Key('configure-${manifest.name}'),
                  tooltip: 'Configurar',
                  icon: const Icon(Icons.tune),
                  onPressed: () => _configure(context, ref),
                ),
              PopupMenuButton<_Action>(
                key: Key('menu-${manifest.name}'),
                tooltip: 'Más opciones',
                onSelected: (action) => _onAction(context, ref, action),
                itemBuilder: (context) => [
                  if (configurable)
                    const PopupMenuItem(
                      value: _Action.configure,
                      child: Text('Configurar'),
                    ),
                  if (index > 0)
                    const PopupMenuItem(
                      value: _Action.moveUp,
                      child: Text('Subir'),
                    ),
                  if (!isLast)
                    const PopupMenuItem(
                      value: _Action.moveDown,
                      child: Text('Bajar'),
                    ),
                  const PopupMenuItem(
                    value: _Action.remove,
                    child: Text('Quitar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onAction(BuildContext context, WidgetRef ref, _Action action) {
    final notifier = ref.read(installedAddonsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _Action.configure:
        unawaited(_configure(context, ref));
      case _Action.moveUp:
        unawaited(_persist(messenger, () => notifier.move(index, index - 1)));
      case _Action.moveDown:
        unawaited(_persist(messenger, () => notifier.move(index, index + 1)));
      case _Action.remove:
        unawaited(_remove(context, ref));
    }
  }

  Future<void> _configure(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(urlOpenerProvider)(configureUri(addon));
    if (!opened) _snack(messenger, 'No pudimos abrir el navegador.');
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final name = addon.manifest.name;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Quitar $name?'),
        content: const Text(
          'Se quita de Parcel. Podés volver a agregarlo cuando quieras.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final notifier = ref.read(installedAddonsProvider.notifier);
    try {
      final position = await notifier.remove(addon);
      _snack(
        messenger,
        'Quitaste $name.',
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => unawaited(
            _persist(messenger, () => notifier.restore(addon, position)),
          ),
        ),
      );
    } on FileSystemException {
      _snack(messenger, 'No pudimos guardar el cambio en el disco.');
    }
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
