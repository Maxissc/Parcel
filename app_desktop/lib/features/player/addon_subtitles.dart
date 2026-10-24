import 'package:parcel_core/parcel_core.dart';

import 'play_item.dart';

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
