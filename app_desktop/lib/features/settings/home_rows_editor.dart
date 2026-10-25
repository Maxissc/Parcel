import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/home_layout.dart';
import '../../data/providers.dart';
import '../../shared/media_labels.dart';
import '../home/home_rows.dart';

/// Ajustes → Inicio: las filas de la home con asa para ordenarlas, un
/// interruptor para ocultarlas y «Restablecer».
class HomeRowsEditor extends ConsumerWidget {
  const HomeRowsEditor({super.key});

  Future<void> _save(BuildContext context, Future<void> save) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await save;
    } on Object {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el cambio. Probá de nuevo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(homeAllRowsProvider);
    final layout = ref.watch(appSettingsProvider.select((s) => s.homeLayout));
    final notifier = ref.read(appSettingsProvider.notifier);
    if (rows.isEmpty) {
      return const ListTile(
        title: Text('Tus addons no traen catálogos para el inicio.'),
      );
    }
    final keys = [for (final r in rows) homeRowKey(r)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableListView.builder(
          key: const Key('home-rows-editor'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: rows.length,
          onReorderItem: (oldIndex, newIndex) {
            final next = [...keys];
            next.insert(newIndex, next.removeAt(oldIndex));
            unawaited(
              _save(
                context,
                notifier.setHomeLayout(layout.copyWith(order: next)),
              ),
            );
          },
          itemBuilder: (context, index) {
            final catalog = rows[index];
            final key = keys[index];
            final visible = !layout.hidden.contains(key);
            return ListTile(
              key: ValueKey(key),
              leading: ReorderableDragStartListener(
                index: index,
                child: const Tooltip(
                  message: 'Arrastrar para ordenar',
                  child: Icon(Icons.drag_handle),
                ),
              ),
              title: Text(
                '${catalog.catalog.name} · ${typeLabel(catalog.catalog.type)}',
              ),
              subtitle: Text(catalog.addon.manifest.name),
              trailing: Switch(
                key: Key('home-row-switch-$index'),
                value: visible,
                onChanged: (v) {
                  final hidden = {...layout.hidden};
                  if (v) {
                    hidden.remove(key);
                  } else {
                    hidden.add(key);
                  }
                  unawaited(
                    _save(
                      context,
                      notifier.setHomeLayout(
                        // El orden queda tal cual se ve ahora.
                        layout.copyWith(order: keys, hidden: hidden),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.xs,
          ),
          child: TextButton.icon(
            key: const Key('home-rows-reset'),
            onPressed: layout.isDefault
                ? null
                : () => unawaited(
                    _save(context, notifier.setHomeLayout(const HomeLayout())),
                  ),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Restablecer'),
          ),
        ),
      ],
    );
  }
}
