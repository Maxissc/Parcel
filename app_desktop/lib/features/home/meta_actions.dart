import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart' hide Video;
import 'package:parcel_core/parcel_core.dart' as core show Video;

import '../../app/router.dart';
import '../../data/browse_providers.dart';
import '../../data/progress_providers.dart';
import '../../data/providers.dart';
import '../../shared/poster_card.dart';
import '../detail/detail_utils.dart';
import '../player/play_args.dart';
import '../player/play_item.dart';
import '../streams/streams_args.dart';

/// Abre el detalle de [meta] (el ítem del catálogo viaja para mostrarse
/// enseguida mientras llega la meta completa).
void openDetail(BuildContext context, Meta meta) =>
    context.push(Routes.detailPath(meta.type, meta.id), extra: meta);

/// Lo que hace falta para leer un proveedor (`ref.read` de un `Ref` o de un
/// `WidgetRef`).
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Qué se va a ver de un contenido: la meta completa y, en una serie, el
/// episodio.
class WatchTarget {
  const WatchTarget(this.meta, this.video);

  final Meta meta;
  final core.Video? video;

  String get videoId => video?.id ?? meta.id;
}

/// Qué ver al darle «Ver» a [hint] desde un catálogo.
///
/// Una película es ella misma. Una serie necesita la meta completa (para
/// saber los episodios): se pide, y se elige [videoId] si se pasa; si no, el
/// que quedó a medias; si no, el que sigue al último visto; si no, el primero.
/// Devuelve `null` si no se pudo saber.
Future<WatchTarget?> resolveTarget(
  Reader read,
  Meta hint, {
  String? videoId,
}) async {
  if (hint.type == 'movie') return WatchTarget(hint, null);
  final result = await read(
    metaProvider((type: hint.type, id: hint.id)).future,
  );
  if (result is! AddonSuccess<Meta>) return null;
  final meta = result.value;
  if (!hasEpisodes(meta)) return WatchTarget(meta, null);
  final repository = read(progressRepositoryProvider);
  core.Video? pick;
  if (videoId != null) {
    pick = meta.videos.where((v) => v.id == videoId).firstOrNull;
  }
  if (pick == null) {
    final last = lastWatched(
      meta,
      (id) => repository.get(meta.type, meta.id, id),
    );
    if (last != null) {
      final lastVideo = meta.videos.firstWhere((v) => v.id == last.videoId);
      pick = last.isInProgress ? lastVideo : nextVideo(meta, lastVideo);
    }
  }
  if (pick == null) {
    final ordered = orderedEpisodes(meta);
    pick = ordered.firstWhere(
      (v) => (v.season ?? 1) != 0,
      orElse: () => ordered.first,
    );
  }
  return WatchTarget(meta, pick);
}

/// Acciones sobre un contenido que sale de un catálogo: ver, ver la ficha,
/// elegir la fuente y marcar visto. Las usan las tarjetas, el billboard y el
/// menú del clic derecho.
class MetaActions {
  MetaActions(this._context, this._ref);

  final BuildContext _context;
  final WidgetRef _ref;

  /// Reproduce: con la fuente automática, directo; si no, la lista de
  /// streams.
  Future<void> play(
    Meta meta, {
    String? videoId,
    ResumeMode resume = ResumeMode.ask,
    bool chooseSource = false,
  }) async {
    final target = await resolveTarget(_ref.read, meta, videoId: videoId);
    if (!_context.mounted) return;
    if (target == null) {
      ScaffoldMessenger.maybeOf(_context)?.showSnackBar(
        const SnackBar(content: Text('No se pudo preparar el contenido')),
      );
      return;
    }
    final auto = _ref.read(appSettingsProvider).autoSelectSource;
    if (auto && !chooseSource) {
      unawaited(
        _context.push(
          Routes.play,
          extra: PlayArgs(
            meta: target.meta,
            video: target.video,
            resume: resume,
          ),
        ),
      );
    } else {
      unawaited(
        _context.push(
          Routes.streams,
          extra: StreamsArgs(
            meta: target.meta,
            video: target.video,
            resume: resume,
          ),
        ),
      );
    }
  }

  void info(Meta meta) => openDetail(_context, meta);

  /// Marca como visto (`seen`) o como no visto lo que se vería ahora.
  Future<void> markWatched(Meta meta, {required bool seen}) async {
    final target = await resolveTarget(_ref.read, meta);
    if (target == null || !_context.mounted) return;
    final saved = _ref
        .read(progressRepositoryProvider)
        .get(target.meta.type, target.meta.id, target.videoId);
    final duration = saved != null && saved.duration > Duration.zero
        ? saved.duration
        : const Duration(minutes: 1);
    await _ref
        .read(progressSaverProvider)
        .save(
          PlaybackProgress(
            type: target.meta.type,
            metaId: target.meta.id,
            videoId: target.videoId,
            position: seen ? duration : Duration.zero,
            duration: duration,
            name: target.meta.name,
            poster: target.meta.poster,
            thumbnail: saved?.thumbnail,
            updatedAt: DateTime.now(),
          ),
        );
  }

  /// Menú del clic derecho sobre una tarjeta.
  Future<void> contextMenu(Meta meta, Offset position) async {
    final overlay =
        Overlay.of(_context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<_MenuAction>(
      context: _context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _MenuAction.play,
          child: ListTile(
            leading: Icon(Icons.play_arrow),
            title: Text('Ver'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _MenuAction.info,
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Más info'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _MenuAction.source,
          child: ListTile(
            leading: Icon(Icons.list_alt_outlined),
            title: Text('Elegir fuente'),
            dense: true,
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _MenuAction.seen,
          child: ListTile(
            leading: Icon(Icons.visibility_outlined),
            title: Text('Marcar como visto'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _MenuAction.unseen,
          child: ListTile(
            leading: Icon(Icons.visibility_off_outlined),
            title: Text('Marcar como no visto'),
            dense: true,
          ),
        ),
      ],
    );
    if (choice == null || !_context.mounted) return;
    switch (choice) {
      case _MenuAction.play:
        await play(meta);
      case _MenuAction.info:
        info(meta);
      case _MenuAction.source:
        await play(meta, chooseSource: true);
      case _MenuAction.seen:
        await markWatched(meta, seen: true);
      case _MenuAction.unseen:
        await markWatched(meta, seen: false);
    }
  }

  /// La tarjeta de un contenido de catálogo, con su panel y su menú.
  PosterCard card(Meta meta, {VoidCallback? onOpen}) {
    return PosterCard(
      title: meta.name,
      poster: meta.poster,
      shape: meta.posterShape,
      caption: meta.releaseInfo,
      onTap: onOpen ?? () => info(meta),
      onContextMenu: (position) => unawaited(contextMenu(meta, position)),
      preview: previewOf(
        meta,
        onPlay: () => unawaited(play(meta)),
        onInfo: onOpen ?? () => info(meta),
      ),
    );
  }
}

enum _MenuAction { play, info, source, seen, unseen }

/// El panel de la tarjeta de [meta].
CardPreview previewOf(
  Meta meta, {
  String playLabel = 'Ver',
  VoidCallback? onPlay,
  VoidCallback? onInfo,
}) {
  final year = meta.releaseInfo ?? meta.released?.year.toString();
  return CardPreview(
    rating: meta.imdbRating,
    year: year,
    genres: meta.genres,
    synopsis: meta.description,
    playLabel: playLabel,
    onPlay: onPlay,
    onInfo: onInfo,
  );
}
