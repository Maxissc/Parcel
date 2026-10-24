import 'package:flutter/widgets.dart';

/// Lo que implementa un motor de reproducción que dibuja el video en un widget.
///
/// La pantalla del reproductor lo usa si el motor lo implementa; si no, deja el
/// fondo negro (los motores falsos de los tests no dibujan video).
abstract interface class VideoSurfaceProvider {
  Widget buildVideoSurface(BuildContext context);
}
