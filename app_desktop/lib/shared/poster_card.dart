import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'remote_image.dart';
import 'skeleton.dart';

/// Medidas de una tarjeta según la forma del póster que declara el addon
/// (`posterShape`): `poster` (2:3, la de siempre), `square` o `landscape`.
class PosterSize {
  const PosterSize._(this.width, this.height);

  final double width;
  final double height;

  static const poster = PosterSize._(140, 210);
  static const square = PosterSize._(210, 210);
  static const landscape = PosterSize._(267, 150);

  /// Alto del bloque de texto de abajo (título y subtítulo).
  static const double captionHeight = 52;

  /// Alto de una fila de tarjetas: el de la más alta.
  static double get rowHeight => poster.height + captionHeight;

  factory PosterSize.of(String? shape) => switch (shape) {
    'landscape' => landscape,
    'square' => square,
    _ => poster,
  };
}

/// Tarjeta de un contenido: póster con título y una línea gris. Al pasar el
/// mouse o enfocarla con el teclado se eleva y se marca; clic o Enter la abre.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.poster,
    this.shape,
    this.caption,
    this.progress,
    this.onTap,
  });

  final String title;
  final String? poster;

  /// `posterShape` del addon.
  final String? shape;

  /// Línea gris bajo el título (año, «T1 E3»...).
  final String? caption;

  /// Fracción vista (0 a 1); si no es `null` dibuja la barra sobre el póster.
  final double? progress;
  final VoidCallback? onTap;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hovered = false;
  bool _focused = false;

  bool get _active => _hovered || _focused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = PosterSize.of(widget.shape);
    final radius = BorderRadius.circular(10);
    final progress = widget.progress;

    return SizedBox(
      width: size.width,
      child: Semantics(
        button: true,
        label: widget.title,
        excludeSemantics: true,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) {
            setState(() => _focused = v);
            if (v) {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 150),
                alignment: 0.5,
              );
            }
          },
          borderRadius: radius,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _active ? 1.04 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: size.width,
                  height: size.height,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: _focused ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: _active
                        ? const [
                            BoxShadow(
                              color: Color(0x99000000),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ]
                        : const [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RemoteImage(widget.poster, width: size.width),
                        AnimatedOpacity(
                          opacity: _active ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(color: Color(0x55000000)),
                            child: Center(
                              child: Icon(
                                Icons.play_circle_outline,
                                size: 44,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        if (progress != null)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              key: const Key('poster-progress'),
                              value: progress.clamp(0.0, 1.0),
                              minHeight: 4,
                              backgroundColor: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Tooltip(
                message: widget.title,
                waitDuration: const Duration(milliseconds: 700),
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _active ? scheme.primary : null,
                  ),
                ),
              ),
              if (widget.caption != null)
                Text(
                  widget.caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El lugar de una tarjeta mientras carga.
class PosterCardSkeleton extends StatelessWidget {
  const PosterCardSkeleton({super.key, this.shape});

  final String? shape;

  @override
  Widget build(BuildContext context) {
    final size = PosterSize.of(shape);
    return SizedBox(
      width: size.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: size.width, height: size.height, radius: 10),
          const SizedBox(height: Spacing.sm),
          Skeleton(width: size.width * 0.8, height: 12),
          const SizedBox(height: Spacing.xs),
          Skeleton(width: size.width * 0.4, height: 10),
        ],
      ),
    );
  }
}
