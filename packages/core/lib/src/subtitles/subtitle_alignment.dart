import 'subtitle_parser.dart';

/// Qué tan probable es que un subtítulo esté sincronizado con el video.
enum SubtitleAlignment {
  /// El último cue termina entre el 85 % y el 100 % de la duración (más 30 s
  /// de margen): lo normal en un subtítulo del mismo corte.
  likely,

  /// El subtítulo termina después del video, a la duración multiplicada por un
  /// cociente de cuadros por segundo (25 / 23,976 o 25 / 24): casi seguro es de
  /// otra velocidad de video y se va corriendo.
  fpsMismatch,

  /// Termina muy lejos de la duración: otro corte, otra película o un
  /// subtítulo incompleto.
  unlikely,

  /// No se puede decir: falta la duración o el subtítulo no tiene cues.
  unknown;

  /// Estima la alineación de [cues] con un video de [videoDuration], mirando
  /// solo cuándo termina el último cue.
  ///
  /// Solo se marca `fpsMismatch` cuando el subtítulo dura más que el video
  /// (cociente > 1, ±0,6 %). Al revés (23,976 / 25 ≈ 0,959) no se puede
  /// distinguir de un subtítulo bien sincronizado que termina antes de los
  /// créditos, que es lo normal, así que queda como `likely`. Tampoco se detecta
  /// 24 / 23,976 (0,1 %).
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
    final upper = videoDuration + const Duration(seconds: 30);
    // En un video corto el cociente de fps cae dentro del margen normal: solo
    // cuenta si además el subtítulo se pasa de la duración más 30 s.
    if (last > upper) {
      for (final factor in _fpsFactors) {
        if ((ratio / factor - 1).abs() <= _fpsTolerance) return fpsMismatch;
      }
    }
    if (ratio >= 0.85 && last <= upper) return likely;
    return unlikely;
  }
}

const double _fpsTolerance = 0.006;

/// Cociente entre dos velocidades de video comunes cuando el subtítulo dura más
/// que el video.
const List<double> _fpsFactors = [25 / 23.976, 25 / 24];
