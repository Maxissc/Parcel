import 'package:parcel_core/parcel_core.dart';

import 'play_item.dart';
import 'track_preferences.dart';

/// Subtítulos que ofrecen el propio stream y los addons de subtítulos para
/// [item], ya filtrados y con nombre (ver [selectAddonSubtitles]).
///
/// Un addon que falla no tumba al resto. Nunca lanza: si no hay nada, devuelve
/// una lista vacía.
Future<List<Subtitle>> fetchAddonSubtitles(
  AddonAggregator aggregator,
  PlayItem item, {
  String? preferredLanguage,
}) async {
  try {
    final results = await aggregator.subtitles(
      item.type,
      item.videoId,
      extra: item.subtitleExtra,
    );
    final all = <Subtitle>[
      ...item.stream.subtitles,
      for (final result in results)
        if (result is AddonSuccess<List<Subtitle>>) ...result.value,
    ];
    return selectAddonSubtitles(all, preferredLanguage: preferredLanguage);
  } on Object {
    return const [];
  }
}
