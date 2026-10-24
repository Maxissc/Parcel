import 'package:parcel_core/parcel_core.dart' hide Video;
import 'package:parcel_core/parcel_core.dart' as core show Video;

import '../../data/browse_providers.dart';
import 'play_item.dart';
import 'source_candidates.dart';

/// Qué reproducir en la ruta `/play`: el contenido y, si no se elige a mano,
/// Parcel busca y elige sola la fuente.
class PlayArgs {
  const PlayArgs({
    required this.meta,
    this.video,
    this.resume = ResumeMode.ask,
    this.preferAddonUrl,
    this.preferBingeGroup,
    this.chosen,
    this.candidates = const [],
    this.fromStreams = false,
  });

  final Meta meta;

  /// El episodio; `null` en una película.
  final core.Video? video;
  final ResumeMode resume;

  /// Addon y `bingeGroup` del stream anterior (al pasar al episodio que
  /// sigue): dentro del ranking, esos van primero.
  final String? preferAddonUrl;
  final String? preferBingeGroup;

  /// Una fuente elegida a mano en la pantalla de streams: no se busca ni se
  /// prueba nada. [candidates] es la lista rankeada donde está (para el menú
  /// «Fuente»).
  final SourceCandidate? chosen;
  final List<SourceCandidate> candidates;

  /// Se llegó desde la pantalla de streams (que sigue abajo en la pila).
  final bool fromStreams;

  String get videoId => video?.id ?? meta.id;

  StreamsKey get key => (type: meta.type, videoId: videoId);
}
