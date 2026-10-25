import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../data/playback_providers.dart';
import '../../data/providers.dart';
import 'play_item.dart';
import 'subtitle_catalog.dart';

/// Subtítulos que ofrecen el propio stream y los addons de subtítulos para
/// [item], sin filtrar: el catálogo del reproductor los ordena y analiza.
///
/// Un addon que falla no tumba al resto. Nunca lanza: si no hay nada, devuelve
/// una lista vacía.
Future<List<Subtitle>> fetchAddonSubtitles(
  AddonAggregator aggregator,
  PlayItem item,
) async {
  try {
    final results = await aggregator.subtitles(
      item.type,
      item.videoId,
      extra: item.subtitleExtra,
    );
    return [
      ...item.stream.subtitles,
      for (final result in results)
        if (result is AddonSuccess<List<Subtitle>>) ...result.value,
    ];
  } on Object {
    return const [];
  }
}

/// Arma los subtítulos de un contenido nuevo. Cuando termina [cancel] se abortan
/// las descargas en curso.
ContentSubtitles newContentSubtitles(WidgetRef ref, Future<void> cancel) {
  final settings = ref.read(appSettingsProvider);
  return ContentSubtitles(
    catalog: SubtitleCatalog(
      fetcher: ref.read(subtitleFetcherFactoryProvider)(cancel),
      priority:
          subtitlePriorityFor(settings.subtitleLanguage) ??
          SubtitleLanguage.defaultPriority,
    ),
    aggregator: ref.read(addonAggregatorProvider),
  );
}

/// Los subtítulos de un mismo contenido (película o episodio), compartidos por
/// todos los intentos de reproducción: cada fuente que se prueba reusa el
/// catálogo (y lo ya analizado). Lo que cambia entre intentos es lo que el
/// stream sabe del archivo (hash, tamaño, nombre): eso solo suma pedidos a los
/// addons, no rehace los anteriores.
class ContentSubtitles {
  ContentSubtitles({required this.catalog, required this._aggregator});

  final SubtitleCatalog catalog;
  final AddonAggregator _aggregator;
  final Map<String, Future<List<Subtitle>>> _requests = {};

  /// Cuántos pedidos distintos se hicieron a los addons.
  int get requestCount => _requests.length;

  /// Pide (una sola vez por cada combinación de pedido) los subtítulos de
  /// [item].
  Future<List<Subtitle>> forItem(PlayItem item) {
    final key =
        '${item.type}|${item.videoId}|${jsonEncode(item.subtitleExtra)}';
    return _requests.putIfAbsent(
      key,
      () => fetchAddonSubtitles(_aggregator, item),
    );
  }

  void dispose() => catalog.dispose();
}
