import 'dart:convert';

import 'package:parcel_core/parcel_core.dart';

/// Rango dinámico a partir de `video-params/gamma` y `video-params/colormatrix`
/// de mpv: `pq` es HDR10, `hlg` es HLG, y una matriz `dolbyvision` es Dolby
/// Vision (gana sobre el gamma).
DynamicRange dynamicRangeOf({String? gamma, String? colormatrix}) {
  if ((colormatrix ?? '').toLowerCase().contains('dolby')) {
    return DynamicRange.dolbyVision;
  }
  return switch ((gamma ?? '').toLowerCase()) {
    'pq' => DynamicRange.hdr10,
    'hlg' => DynamicRange.hlg,
    _ => DynamicRange.sdr,
  };
}

/// Cuánto video hay cargado alrededor de la posición.
class BufferRange {
  const BufferRange(this.ahead, this.behind);

  final Duration ahead;
  final Duration behind;
}

/// Lee `demuxer-cache-state` (JSON) de mpv y mide cuánto hay cargado por
/// delante y por detrás de [position], dentro del rango que contiene la
/// posición. `null` si [json] no se puede leer o no trae rangos.
BufferRange? bufferFromCacheState(String json, Duration position) {
  if (json.trim().isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final ranges = decoded['seekable-ranges'];
  if (ranges is! List) return null;
  final at = position.inMicroseconds / Duration.microsecondsPerSecond;
  for (final range in ranges) {
    if (range is! Map) continue;
    final start = range['start'];
    final end = range['end'];
    if (start is! num || end is! num) continue;
    if (at >= start && at <= end) {
      return BufferRange(_seconds(end - at), _seconds(at - start));
    }
  }
  return const BufferRange(Duration.zero, Duration.zero);
}

Duration _seconds(num value) =>
    Duration(microseconds: (value * Duration.microsecondsPerSecond).round());

/// Nombre corto de un códec: lo que viene antes del primer espacio
/// (`hevc (HEVC (High Efficiency Video Coding))` es `hevc`). `null` si vacío.
String? shortCodecName(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  return text.split(RegExp(r'\s+')).first;
}

/// Decodificador por hardware de `hwdec-current`; `null` si es `no` o vacío.
String? hardwareDecoderName(String raw) {
  final text = raw.trim();
  return text.isEmpty || text == 'no' ? null : text;
}

double? parseMpvDouble(String raw) => double.tryParse(raw.trim());

int? parseMpvInt(String raw) {
  final text = raw.trim();
  return int.tryParse(text) ?? double.tryParse(text)?.round();
}
