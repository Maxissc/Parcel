import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import '../../data/progress_providers.dart';
import '../../shared/media_labels.dart';
import '../../shared/media_row.dart';
import '../../shared/poster_card.dart';

/// Fila «Seguir viendo»: lo que quedó a medias, con la barra de lo visto sobre
/// el póster y, en series, el episodio («T1 E3»). Se oculta si no hay nada.
class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({super.key, required this.onOpen});

  /// Se llama con un ítem mínimo (tipo, id, nombre y póster) para abrir su
  /// detalle.
  final void Function(Meta meta) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        key: const Key('continue-watching'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RowHeader(title: 'Seguir viendo'),
          Shelf(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final p = items[index];
              return PosterCard(
                title: p.name,
                poster: p.poster,
                caption: p.type == 'movie'
                    ? null
                    : episodeLabelFromVideoId(p.videoId),
                progress: p.fraction,
                onTap: () => onOpen(
                  Meta(
                    id: p.metaId,
                    type: p.type,
                    name: p.name,
                    poster: p.poster,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
