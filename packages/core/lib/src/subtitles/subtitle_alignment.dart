import 'subtitle_parser.dart';

/// Qué tan probable es que un subtítulo esté sincronizado con el video.
enum SubtitleAlignment {
  /// El último cue termina entre el 85 % y el 100 % de la duración (más 30 s
  /// de margen): lo normal en un subtítulo del mismo corte.
  likely,

  /// El fin del subtítulo es la duración multiplicada por un cociente de
  /// cuadros por segundo (25 / 23,976, 24 / 25): casi seguro es de otra
  /// velocidad de video y se va corriendo.
  fpsMismatch,

  /// Termina muy lejos de la duración: otro corte, otra película o un
  /// subtítulo incompleto.
  unlikely,

  /// No se puede decir: falta la duración o el subtítulo no tiene cues.
  unknown;

  /// Estima la alineación de [cues] con un video de [videoDuration], mirando
  /// solo cuándo termina el último cue.
  ///
  /// El cociente de fps tiene prioridad sobre `likely` cuando coincide (±0,6 %).
  /// No se detecta 23,976 / 24, porque el cociente (0,1 %) es indistinguible de
  /// un subtítulo bien sincronizado.
  static SubtitleAlignment estimate(
    List<SubtitleCue> cues,
    Duration? videoDuration,
  ) {
    if (videoDuration == null ||
        videoDuration <= Duration.zero ||
        cues.isEmpty) {
      return unknown;
    }
    var last = Duration.zero;
    for (final cue in cues) {
      if (cue.end > last) last = cue.end;
    }
    final ratio = last.inMicroseconds / videoDuration.inMicroseconds;
    for (final factor in _fpsFactors) {
      if ((ratio / factor - 1).abs() <= _fpsTolerance) return fpsMismatch;
    }
    final upper = videoDuration + const Duration(seconds: 30);
    if (ratio >= 0.85 && last <= upper) return likely;
    return unlikely;
  }
}

const double _fpsTolerance = 0.006;

/// Cociente entre dos velocidades de video comunes, en los dos sentidos.
const List<double> _fpsFactors = [25 / 23.976, 23.976 / 25, 25 / 24, 24 / 25];
