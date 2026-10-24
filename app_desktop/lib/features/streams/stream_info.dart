import 'package:parcel_core/parcel_core.dart';

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

/// El texto del stream donde se buscan calidad, formato y tamaño.
String _haystack(AddonStream s) => [
  s.name,
  s.title,
  s.description,
  s.behaviorHints.filename,
].whereType<String>().join('\n');

final RegExp _uhd = RegExp(r'\b(2160p|4k|uhd)\b', caseSensitive: false);
final RegExp _fullHd = RegExp(r'\b1080[pi]\b', caseSensitive: false);
final RegExp _hd = RegExp(r'\b720p\b', caseSensitive: false);
final RegExp _hdr = RegExp(r'\bhdr(10\+?)?\b', caseSensitive: false);
final RegExp _dolbyVision = RegExp(
  r'\b(dv|dovi|dolby[\s._-]?vision)\b',
  caseSensitive: false,
);
final RegExp _size = RegExp(
  r'(\d+(?:[.,]\d+)?)\s?(TB|GB|MB|GiB|MiB|TiB)\b',
  caseSensitive: false,
);

/// Etiquetas que se ven en el texto del stream: resolución (4K, 1080p, 720p),
/// HDR, DV y tamaño. Si el texto no trae el tamaño, se usa el
/// `videoSize` que informa el addon.
List<String> detectStreamChips(AddonStream stream) {
  final text = _haystack(stream);
  final chips = <String>[
    if (_uhd.hasMatch(text))
      '4K'
    else if (_fullHd.hasMatch(text))
      '1080p'
    else if (_hd.hasMatch(text))
      '720p',
    if (_hdr.hasMatch(text)) 'HDR',
    if (_dolbyVision.hasMatch(text)) 'DV',
  ];
  final match = _size.firstMatch(text);
  if (match != null) {
    final number = match.group(1)!.replaceAll(',', '.');
    chips.add('$number ${_unit(match.group(2)!)}');
  } else if (stream.behaviorHints.videoSize case final size?) {
    if (size > 0) chips.add(formatBytes(size));
  }
  return chips;
}

String _unit(String unit) => switch (unit.toLowerCase()) {
  'gib' => 'GB',
  'mib' => 'MB',
  'tib' => 'TB',
  _ => unit.toUpperCase(),
};

/// «1.5 GB» a partir de bytes.
String formatBytes(int bytes) {
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
