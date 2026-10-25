import '../models/addon_stream.dart';
import 'stream_signals.dart';

/// Calidad que prefiere el usuario.
enum QualityPreference {
  /// 1080p > 2160p > 720p > resto.
  p1080([1080, 2160, 720]),

  /// 2160p > 1080p > 720p > resto.
  p2160([2160, 1080, 720]),

  /// 720p > 1080p > 2160p > resto.
  p720([720, 1080, 2160]);

  const QualityPreference(this._order);

  final List<int> _order;

  /// Puesto de [resolution] (0 es el mejor); lo que no figura va al final.
  int rankOf(int? resolution) {
    final i = resolution == null ? -1 : _order.indexOf(resolution);
    return i < 0 ? _order.length : i;
  }
}

/// Ordena los streams reproducibles de mejor a peor y descarta el resto
/// (torrents, YouTube, enlaces externos).
///
/// Criterios, en orden:
/// 1. Cacheados en debrid primero; después los que no dicen nada; al final los
///    que hay que bajar (suelen devolver un video corto de «descargando»).
/// 2. Las copias CAM/TS/SCREENER, después de las buenas.
/// 3. La calidad según [quality].
/// 4. A igualdad, el orden de entrada (que debería ser el de los addons).
List<AddonStream> rankStreams(
  List<AddonStream> streams, {
  QualityPreference quality = QualityPreference.p1080,
}) {
  final entries = <_Entry>[];
  for (final stream in streams) {
    if (!stream.isPlayable) continue;
    final signals = StreamSignals.of(stream);
    entries.add(
      _Entry(
        stream,
        entries.length,
        switch (signals.cached) {
          true => 0,
          null => 1,
          false => 2,
        },
        signals.isCam ? 1 : 0,
        quality.rankOf(signals.resolution),
      ),
    );
  }
  entries.sort();
  return [for (final e in entries) e.stream];
}

class _Entry implements Comparable<_Entry> {
  _Entry(this.stream, this.index, this.cacheTier, this.cam, this.quality);

  final AddonStream stream;
  final int index;
  final int cacheTier;
  final int cam;
  final int quality;

  @override
  int compareTo(_Entry other) {
    var c = cacheTier.compareTo(other.cacheTier);
    if (c != 0) return c;
    c = cam.compareTo(other.cam);
    if (c != 0) return c;
    c = quality.compareTo(other.quality);
    if (c != 0) return c;
    return index.compareTo(other.index);
  }
}
