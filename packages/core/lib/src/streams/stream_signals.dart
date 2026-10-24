import '../models/addon_stream.dart';

/// Lo que se puede leer del texto de un stream (`name`, `title`,
/// `description` y nombre de archivo): resolución, si está cacheado en un
/// servicio debrid, HDR, etc. Sirve para ordenar los streams y para los chips
/// de la interfaz.
///
/// Es una lectura por texto, sin garantía: cada addon escribe como quiere.
/// `null` significa «no se sabe».
class StreamSignals {
  const StreamSignals({
    this.resolution,
    this.cached,
    this.hdr = false,
    this.dolbyVision = false,
    this.isCam = false,
    this.sizeBytes,
    this.seeders,
  });

  /// Alto del video: 2160, 1440, 1080, 720, 576 o 480.
  final int? resolution;

  /// `true` si el addon dice que está cacheado en el debrid (`[RD+]`, `⚡`),
  /// `false` si dice que hay que bajarlo (`[RD download]`, `⏳`).
  final bool? cached;
  final bool hdr;
  final bool dolbyVision;

  /// Copia de baja calidad: CAM, TS, TELESYNC, HDCAM, SCREENER.
  final bool isCam;

  /// Tamaño del archivo. Las unidades se toman en base 1024 (GB = GiB), como
  /// las escriben los addons de torrents.
  final int? sizeBytes;
  final int? seeders;

  /// Señales de [stream]: lee `name`, `title`, `description` y `filename`; el
  /// tamaño cae a `behaviorHints.videoSize` si el texto no lo trae.
  factory StreamSignals.of(AddonStream stream) {
    final text = [
      stream.name,
      stream.title,
      stream.description,
      stream.behaviorHints.filename,
    ].whereType<String>().join('\n');
    final fromText = StreamSignals.fromText(text);
    if (fromText.sizeBytes != null || stream.behaviorHints.videoSize == null) {
      return fromText;
    }
    return StreamSignals(
      resolution: fromText.resolution,
      cached: fromText.cached,
      hdr: fromText.hdr,
      dolbyVision: fromText.dolbyVision,
      isCam: fromText.isCam,
      sizeBytes: stream.behaviorHints.videoSize,
      seeders: fromText.seeders,
    );
  }

  /// Señales de un texto suelto.
  factory StreamSignals.fromText(String text) => StreamSignals(
    resolution: _resolution(text),
    cached: _cached(text),
    hdr: _hdr.hasMatch(text),
    dolbyVision: _dolbyVision.hasMatch(text),
    isCam: _cam.hasMatch(text),
    sizeBytes: _size(text),
    seeders: _seeders(text),
  );

  @override
  String toString() =>
      'StreamSignals(${resolution ?? '?'}p cached=$cached hdr=$hdr '
      'dv=$dolbyVision cam=$isCam size=$sizeBytes seeders=$seeders)';
}

final RegExp _p = RegExp(
  r'(?<![0-9])(2160|1440|1080|720|576|480)\s*p\b',
  caseSensitive: false,
);
final RegExp _dimensions = RegExp(r'\d{3,4}x(2160|1440|1080|720|576|480)\b');
final RegExp _fourK = RegExp(r'\b(4k|uhd)\b', caseSensitive: false);

int? _resolution(String text) {
  final p = _p.firstMatch(text);
  if (p != null) return int.parse(p.group(1)!);
  final d = _dimensions.firstMatch(text);
  if (d != null) return int.parse(d.group(1)!);
  if (_fourK.hasMatch(text)) return 2160;
  return null;
}

const String _services = 'RD|AD|PM|DL|TB|ED|OC|PR';
final RegExp _cachedTag = RegExp('\\[($_services)\\+\\]');
final RegExp _downloadTag = RegExp(
  '\\[($_services)\\s*download\\]',
  caseSensitive: false,
);
final RegExp _uncached = RegExp(
  r'\b(uncached|not\s+cached)\b',
  caseSensitive: false,
);
final RegExp _cachedWord = RegExp(r'\bcached\b', caseSensitive: false);
final RegExp _downloadWord = RegExp(r'\bdownload\b', caseSensitive: false);

bool? _cached(String text) {
  if (_cachedTag.hasMatch(text)) return true;
  if (_downloadTag.hasMatch(text)) return false;
  if (text.contains('⚡')) return true;
  if (text.contains('⏳')) return false;
  if (_uncached.hasMatch(text)) return false;
  if (_cachedWord.hasMatch(text)) return true;
  if (_downloadWord.hasMatch(text)) return false;
  return null;
}

final RegExp _hdr = RegExp(r'\bhdr(10\+?)?\b', caseSensitive: false);
final RegExp _dolbyVision = RegExp(
  r'\b(dolby\s*vision|dovi|dv)\b',
  caseSensitive: false,
);

// CAM / HDCAM / CAMRip, TS / HDTS / TELESYNC, SCREENER / SCR / DVDSCR. Un «TS»
// pegado a un punto al final (`pelicula.ts`) es una extensión, no una copia.
final RegExp _cam = RegExp(
  r'\b(hd)?cam(rip)?\b'
  r'|\bhdts\b'
  r'|(?<!\.)\bts\b'
  r'|\.ts\.'
  r'|\btele-?sync\b'
  r'|\b(dvd)?scr(eener)?\b',
  caseSensitive: false,
);

const String _number = r'(\d+(?:[.,]\d+)?)';
const String _unit = r'(TB|GB|MB|GiB|MiB|TiB)';
final RegExp _sizeWithEmoji = RegExp(
  '💾\\s*$_number\\s*$_unit',
  caseSensitive: false,
);
final RegExp _sizeAny = RegExp(
  '(?<![\\d.,])$_number\\s*$_unit\\b',
  caseSensitive: false,
);

int? _size(String text) {
  final m = _sizeWithEmoji.firstMatch(text) ?? _sizeAny.firstMatch(text);
  if (m == null) return null;
  final value = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (value == null) return null;
  final unit = m.group(2)!.toLowerCase();
  final factor = switch (unit) {
    'tb' || 'tib' => 1024.0 * 1024 * 1024 * 1024,
    'gb' || 'gib' => 1024.0 * 1024 * 1024,
    _ => 1024.0 * 1024,
  };
  return (value * factor).round();
}

final RegExp _seedersRe = RegExp(r'👤\s*(\d+)');

int? _seeders(String text) {
  final m = _seedersRe.firstMatch(text);
  return m == null ? null : int.parse(m.group(1)!);
}
