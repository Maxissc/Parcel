import 'package:parcel_core/parcel_core.dart';

import '../../data/browse_providers.dart';
import '../../playback/playback_errors.dart';
import '../../shared/stream_labels.dart';

/// Un stream reproducible con el addon que lo ofreció.
class SourceCandidate {
  SourceCandidate({
    required this.stream,
    required this.addonUrl,
    required this.addonName,
  }) : signals = StreamSignals.of(stream);

  final AddonStream stream;
  final String addonUrl;
  final String addonName;
  final StreamSignals signals;

  /// `false` si el addon dice que el debrid lo tiene que descargar. La
  /// elección automática nunca lo prueba ni lo usa: probarlo encola el
  /// torrent en la cuenta.
  bool get isReady => signals.cached != false;

  /// Nombre del stream en una línea, sin URLs.
  String get streamName {
    final raw = stream.name ?? stream.title ?? '';
    final text = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join(' · ');
    return redactUrlsInText(text);
  }

  /// Texto para los menús: addon, nombre y chips. Nunca lleva la URL.
  String get label {
    final parts = <String>[
      addonName,
      if (streamName.isNotEmpty && streamName != addonName) streamName,
      ...signalChips(signals),
    ];
    return parts.join(' · ');
  }
}

/// Los streams reproducibles de [groups], del mejor al peor (ver
/// `rankStreams`). Con [preferBingeGroup] (el episodio anterior) pasan
/// adelante los que tienen el mismo `bingeGroup` (y, si hay [preferAddonUrl],
/// los de ese addon). Sin `bingeGroup`, [preferAddonUrl] adelanta los listos
/// del mismo addon. En los dos casos no se descarta nada: lo demás queda como
/// alternativa.
List<SourceCandidate> rankCandidates(
  List<StreamGroup> groups, {
  QualityPreference quality = QualityPreference.p1080,
  String? preferAddonUrl,
  String? preferBingeGroup,
}) {
  final owner = Map<AddonStream, SourceCandidate>.identity();
  final all = <AddonStream>[];
  for (final group in groups) {
    final result = group.result;
    if (result is! AddonSuccess<List<AddonStream>>) continue;
    for (final stream in result.value) {
      if (!stream.isPlayable) continue;
      owner[stream] = SourceCandidate(
        stream: stream,
        addonUrl: group.addon.transportUrl,
        addonName: group.addon.manifest.name,
      );
      all.add(stream);
    }
  }
  final ranked = [
    for (final s in rankStreams(all, quality: quality)) owner[s]!,
  ];
  if (preferBingeGroup == null) {
    if (preferAddonUrl == null) return ranked;
    bool sameReadyAddon(SourceCandidate c) =>
        c.isReady && c.addonUrl == preferAddonUrl;
    return [
      ...ranked.where(sameReadyAddon),
      ...ranked.where((c) => !sameReadyAddon(c)),
    ];
  }
  bool same(SourceCandidate c) =>
      c.stream.behaviorHints.bingeGroup == preferBingeGroup &&
      (preferAddonUrl == null || c.addonUrl == preferAddonUrl);
  return [...ranked.where(same), ...ranked.where((c) => !same(c))];
}
