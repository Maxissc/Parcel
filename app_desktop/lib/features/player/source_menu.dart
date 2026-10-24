import 'source_candidates.dart';

/// Las fuentes entre las que se puede cambiar en el reproductor (menú
/// «Fuente»), de la mejor a la peor, con la que suena ahora marcada.
class SourceMenu {
  const SourceMenu({
    required this.candidates,
    required this.current,
    required this.onPick,
  });

  final List<SourceCandidate> candidates;

  /// Índice en [candidates] de la fuente actual.
  final int current;

  /// El usuario eligió [index]; [position] es dónde iba el video.
  final void Function(int index, Duration position) onPick;
}
