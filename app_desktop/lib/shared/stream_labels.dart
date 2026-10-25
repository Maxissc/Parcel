import 'package:parcel_core/parcel_core.dart';

/// Texto de calidad de un alto de video: «4K», «1080p»...
String resolutionLabel(int resolution) =>
    resolution >= 2160 ? '4K' : '${resolution}p';

/// Chips de un stream a partir de sus señales: resolución, HDR, DV, tamaño y
/// seeders. No incluye el estado de la caché (ver [StreamSignals.cached]).
List<String> signalChips(StreamSignals s) => [
  if (s.resolution != null) resolutionLabel(s.resolution!),
  if (s.hdr) 'HDR',
  if (s.dolbyVision) 'DV',
  if (s.sizeBytes != null && s.sizeBytes! > 0) formatSize(s.sizeBytes!),
  if (s.seeders != null) '👤 ${s.seeders}',
];

/// «1.5 GB» a partir de bytes.
String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 || value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// Chip de un stream que el debrid todavía tiene que descargar.
const String uncachedChip = 'Sin cachear';
const String uncachedTooltip =
    'Puede tardar en empezar: el debrid lo tiene que descargar';
