import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import '../../data/progress_providers.dart';
import '../../shared/media_labels.dart';
import '../../shared/media_row.dart';
import '../../shared/poster_card.dart';
import '../player/play_item.dart';
import 'meta_actions.dart';

/// Fila «Seguir viendo»: lo que quedó a medias, en tarjetas apaisadas con la
/// imagen del episodio, el chip del episodio («T1 E3»), la barra de lo visto y
/// cuánto falta. Se oculta si no hay nada.
class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({super.key, required this.onOpen});

  /// Se llama con un ítem mínimo (tipo, id, nombre y póster) para abrir su
  /// detalle.
  final void Function(Meta meta) onOpen;

  /// Alto de la fila: tarjeta 16:9 y la línea de abajo.
  static const double rowHeight =
      150 + PosterSize.captionHeight + Spacing.sm + Spacing.md;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final actions = MetaActions(context, ref);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        key: const Key('continue-watching'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RowHeader(title: 'Seguir viendo'),
          Shelf(
            key: const PageStorageKey<String>('shelf|continue-watching'),
            height: rowHeight,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final p = items[index];
              final meta = Meta(
                id: p.metaId,
                type: p.type,
                name: p.name,
                poster: p.poster,
              );
              final tag = p.type == 'movie'
                  ? null
                  : episodeLabelFromVideoId(p.videoId);
              return PosterCard(
                title: p.name,
                poster: p.thumbnail ?? p.poster,
                shape: 'landscape',
                caption: remainingLabel(p.duration, p.position),
                badge: tag,
                progress: p.fraction,
                onTap: () => onOpen(meta),
                onContextMenu: (position) =>
                    unawaited(actions.contextMenu(meta, position)),
                preview: CardPreview(
                  episode: tag,
                  remaining: remainingLabel(p.duration, p.position),
                  playLabel: 'Continuar',
                  onPlay: () => unawaited(
                    actions.play(
                      meta,
                      videoId: p.videoId,
                      resume: ResumeMode.resume,
                    ),
                  ),
                  onInfo: () => onOpen(meta),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
