import 'package:flutter/material.dart';

import 'urls.dart';

/// Ancho en píxeles al que se decodifica una imagen que se muestra a [width]
/// píxeles lógicos. Las imágenes chicas (pósters) usan su tamaño justo; las
/// anchas (fondos) se redondean hacia arriba a escalones de 480 px, así
/// redimensionar la ventana no vuelve a bajar ni a decodificar la imagen.
int remoteImageDecodeWidth(double width, double devicePixelRatio) {
  final pixels = (width * devicePixelRatio).round();
  const step = 480;
  if (pixels <= step) return pixels;
  return (pixels / step).ceil() * step;
}

/// El proveedor con el que [RemoteImage] muestra [url] a [width]: sirve para
/// precargarla con la misma entrada de la caché.
ImageProvider remoteImageProvider(
  String url,
  double width,
  double devicePixelRatio,
) => ResizeImage.resizeIfNeeded(
  remoteImageDecodeWidth(width, devicePixelRatio),
  null,
  NetworkImage(url),
);

/// Imagen de la red que llena su espacio: muestra un fondo con un ícono
/// mientras carga, aparece con un fundido y, si falla, deja el fondo con un
/// ícono de imagen rota.
///
/// [width] es el ancho en que se va a mostrar (en píxeles lógicos): la imagen
/// se decodifica a ese tamaño y no al original, que ahorra memoria.
class RemoteImage extends StatelessWidget {
  const RemoteImage(
    this.url, {
    super.key,
    required this.width,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholderIcon = Icons.movie_outlined,
    this.showPlaceholder = true,
  });

  final String? url;
  final double width;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final IconData placeholderIcon;

  /// Con `false` no dibuja el fondo gris ni el ícono mientras carga ni si falla
  /// (para logos con transparencia, que se verían sobre una caja gris).
  final bool showPlaceholder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon) => ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          size: 32,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
    final source = url;
    if (!showPlaceholder) {
      if (source == null || !isHttpUrl(source)) return const SizedBox.shrink();
      return Image.network(
        source,
        fit: fit,
        alignment: alignment,
        cacheWidth: remoteImageDecodeWidth(
          width,
          MediaQuery.devicePixelRatioOf(context),
        ),
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    if (source == null || !isHttpUrl(source)) {
      return placeholder(placeholderIcon);
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder(placeholderIcon),
        Image.network(
          source,
          fit: fit,
          alignment: alignment,
          cacheWidth: remoteImageDecodeWidth(width, pixelRatio),
          gaplessPlayback: true,
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              placeholder(Icons.broken_image_outlined),
        ),
      ],
    );
  }
}
