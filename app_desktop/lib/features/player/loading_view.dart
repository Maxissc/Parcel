import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../shared/remote_image.dart';
import '../../shared/urls.dart';

/// Lo que se muestra del contenido mientras carga: su fondo, su logo y su
/// nombre.
class LoadingArt {
  const LoadingArt({required this.name, this.background, this.logo});

  /// Fondo (o, si no hay, el póster), logo y nombre de [meta].
  factory LoadingArt.fromMeta(Meta meta) => LoadingArt(
    name: meta.name,
    background: meta.background ?? meta.poster,
    logo: meta.logo,
  );

  final String name;
  final String? background;
  final String? logo;
}

/// Pantalla de carga del reproductor (y de la búsqueda de la fuente): el fondo
/// del contenido a pantalla llena con un velo oscuro, su logo (o su nombre) que
/// «respira» en el centro y una línea de estado debajo.
class PlayerLoadingView extends StatelessWidget {
  const PlayerLoadingView({
    super.key,
    required this.art,
    required this.status,
    required this.onBack,
  });

  final LoadingArt art;

  /// Qué está pasando: «Buscando la mejor fuente…», «Abriendo…»...
  final String status;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          RemoteImage(art.background, width: 1280, showPlaceholder: false),
          // Velo: negro parejo y un degradado radial que oscurece los bordes.
          ColoredBox(color: Colors.black.withValues(alpha: 0.62)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.95,
                colors: [Color(0x00000000), Color(0xB3000000)],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Breathing(child: _Title(art: art)),
                const SizedBox(height: 28),
                Text(
                  status,
                  key: const Key('loading-status'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: TextButton.icon(
                key: const Key('loading-back'),
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El logo si lo hay y carga; si no, el nombre en letra grande.
class _Title extends StatelessWidget {
  const _Title({required this.art});

  final LoadingArt art;

  @override
  Widget build(BuildContext context) {
    final name = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Text(
        art.name,
        key: const Key('loading-name'),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.displayMedium
            ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
    final logo = art.logo;
    if (logo == null || !isHttpUrl(logo)) return name;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 180),
      child: Image.network(
        logo,
        key: const Key('loading-logo'),
        fit: BoxFit.contain,
        cacheHeight: (180 * MediaQuery.devicePixelRatioOf(context)).round(),
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
        errorBuilder: (_, _, _) => name,
      ),
    );
  }
}

/// «Respiración»: la opacidad va de 0,55 a 1 y la escala de 0,98 a 1,02, un
/// ciclo cada 2,4 s con `easeInOutSine`, en bucle. Con las animaciones apagadas
/// queda quieto.
class Breathing extends StatefulWidget {
  const Breathing({super.key, required this.child});

  final Widget child;

  /// Un ciclo entero (sube y baja).
  static const Duration cycle = Duration(milliseconds: 2400);

  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Breathing.cycle ~/ 2,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutSine,
  );
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _still && _controller.isAnimating) return;
    _still = still;
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        key: const Key('loading-breathing'),
        opacity: 0.55 + 0.45 * _curve.value,
        child: Transform.scale(scale: 0.98 + 0.04 * _curve.value, child: child),
      ),
    );
  }
}

/// Muestra [child] con [visible] y, al ocultarlo, lo apaga con un fundido y lo
/// saca del árbol. Mientras se apaga no recibe clics.
class FadingOverlay extends StatefulWidget {
  const FadingOverlay({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  /// Lo que dura el fundido hacia el primer cuadro.
  static const Duration fade = Duration(milliseconds: 350);

  @override
  State<FadingOverlay> createState() => _FadingOverlayState();
}

class _FadingOverlayState extends State<FadingOverlay> {
  late bool _present = widget.visible;

  @override
  void didUpdateWidget(FadingOverlay old) {
    super.didUpdateWidget(old);
    if (widget.visible) {
      _present = true;
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _present = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: FadingOverlay.fade,
        curve: Curves.easeOut,
        onEnd: () {
          if (mounted && !widget.visible) setState(() => _present = false);
        },
        child: widget.child,
      ),
    );
  }
}
