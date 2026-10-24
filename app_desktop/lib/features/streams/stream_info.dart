import 'package:parcel_core/parcel_core.dart';

import '../../shared/stream_labels.dart';

/// Por qué un stream no se puede reproducir en Parcel (todavía).
enum StreamBlock {
  /// Es un torrent (`infoHash`).
  torrent,

  /// Es un enlace que se abre en el navegador (`externalUrl`).
  external,

  /// Otra cosa (por ejemplo un video de YouTube).
  unsupported,
}

/// Qué pasa si se toca [stream]: `null` si se reproduce, o por qué no.
StreamBlock? blockOf(AddonStream stream) {
  if (stream.isPlayable) return null;
  if (stream.infoHash != null) return StreamBlock.torrent;
  if (stream.externalUrl != null) return StreamBlock.external;
  return StreamBlock.unsupported;
}

/// Etiquetas del stream según sus señales (`StreamSignals` del core):
/// resolución (4K, 1080p, 720p), HDR, DV, tamaño y seeders.
List<String> detectStreamChips(AddonStream stream) =>
    signalChips(StreamSignals.of(stream));

/// «1.5 GB» a partir de bytes.
String formatBytes(int bytes) => formatSize(bytes);
