/// Lo que implementa un motor que puede subir los subtítulos (para que no
/// queden debajo de los controles).
///
/// Es aparte de `PlaybackEngine` (que vive en `parcel_core`): la pantalla del
/// reproductor lo usa si el motor lo implementa, y si no, los subtítulos
/// quedan donde están.
abstract interface class SubtitleLiftable {
  /// Sube los subtítulos [lift] veces el alto de la pantalla (0 = su lugar de
  /// siempre; 0,1 = un 10 % del alto más arriba).
  Future<void> setSubtitleLift(double lift);
}
