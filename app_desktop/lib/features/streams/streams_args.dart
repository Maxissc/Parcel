import 'package:parcel_core/parcel_core.dart' hide Video;
import 'package:parcel_core/parcel_core.dart' as core show Video;

import '../../data/browse_providers.dart';
import '../player/play_item.dart';

/// Qué mostrarle a la pantalla de streams: la meta, el episodio (en una serie)
/// y cómo seguir.
class StreamsArgs {
  const StreamsArgs({
    required this.meta,
    this.video,
    this.resume = ResumeMode.ask,
    this.preferAddonUrl,
    this.preferBingeGroup,
  });

  final Meta meta;

  /// El episodio; `null` en una película.
  final core.Video? video;

  /// Se lo pasa al reproductor.
  final ResumeMode resume;

  /// Addon y `bingeGroup` del stream anterior: al pasar de un episodio al
  /// siguiente se sugiere el que coincide.
  final String? preferAddonUrl;
  final String? preferBingeGroup;

  String get videoId => video?.id ?? meta.id;

  StreamsKey get key => (type: meta.type, videoId: videoId);
}
