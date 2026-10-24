import 'package:parcel_core/parcel_core.dart';

import '../../data/browse_providers.dart';

/// Pone primero el grupo del addon con el que se vio el episodio anterior
/// ([preferredAddonUrl]); el resto queda en su orden.
List<StreamGroup> orderGroups(
  List<StreamGroup> groups,
  String? preferredAddonUrl,
) {
  if (preferredAddonUrl == null) return groups;
  final preferred = [
    for (final g in groups)
      if (g.addon.transportUrl == preferredAddonUrl) g,
  ];
  if (preferred.isEmpty) return groups;
  return [
    ...preferred,
    for (final g in groups)
      if (!preferred.contains(g)) g,
  ];
}

/// Los streams que son del mismo `bingeGroup` que el anterior primero; el
/// resto, en el orden del addon. Sin [bingeGroup] no cambia nada.
List<AddonStream> orderStreams(List<AddonStream> streams, String? bingeGroup) {
  if (bingeGroup == null) return streams;
  final same = [
    for (final s in streams)
      if (s.behaviorHints.bingeGroup == bingeGroup) s,
  ];
  if (same.isEmpty) return streams;
  return [
    ...same,
    for (final s in streams)
      if (!same.contains(s)) s,
  ];
}

/// El stream que se sugiere para seguir: de los del addon anterior, el que
/// tiene el mismo `bingeGroup` o, si no hay, el primero que se puede
/// reproducir. `null` si ninguno se puede reproducir.
AddonStream? recommendedStream(List<AddonStream> streams, String? bingeGroup) {
  AddonStream? firstPlayable;
  for (final s in orderStreams(streams, bingeGroup)) {
    if (!s.isPlayable) continue;
    if (bingeGroup != null && s.behaviorHints.bingeGroup == bingeGroup) {
      return s;
    }
    firstPlayable ??= s;
  }
  return firstPlayable;
}
