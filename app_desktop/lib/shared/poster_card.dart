import 'dart:async';

import 'package:flutter/gestures.dart';
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

/// Lo que muestra el panel que aparece debajo de la tarjeta agrandada.
class CardPreview {
  const CardPreview({
    this.rating,
    this.year,
    this.genres = const [],
    this.synopsis,
    this.playLabel = 'Ver',
    this.onPlay,
    this.onInfo,
  });

  /// Nota de IMDb tal como la manda el addon.
  final String? rating;
  final String? year;
  final List<String> genres;
  final String? synopsis;
  final String playLabel;
  final VoidCallback? onPlay;
  final VoidCallback? onInfo;
}

/// Cómo crece una tarjeta: factor final, cuánto se espera con el mouse
/// encima y las duraciones de la animación.
abstract final class CardGrowth {
  static const double scale = 1.35;
  static const Duration hoverDelay = Duration(milliseconds: 350);
  static const Duration focusDelay = Duration(milliseconds: 200);
  static const Duration duration = Duration(milliseconds: 280);

  /// Alto del panel de abajo.
  static const double panelHeight = 136;
  static const double panelGap = 6;

  /// La escala y el panel tardan distinto: la tarjeta crece en los primeros
  /// 220 ms y el panel entra con 60 ms de retraso.
  static const double _cardEnd = 220 / 280;
  static const double _panelStart = 60 / 280;

  static Animation<double> grow(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: const Interval(0, _cardEnd, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(0, _cardEnd, curve: Curves.easeInCubic),
  );

  static Animation<double> panel(Animation<double> parent) => CurvedAnimation(
    parent: parent,
    curve: const Interval(_panelStart, 1, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(_panelStart, 1, curve: Curves.easeInCubic),
  );
}

/// Tarjeta de un contenido: póster con título y una línea gris.
///
/// Con [preview], tras un instante con el mouse encima (o al enfocarla con el
/// teclado) la tarjeta crece en su lugar, por encima de las vecinas, y debajo
/// aparece un panel con la info y los botones. Clic o Enter la abre; clic
/// derecho llama a [onContextMenu].
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.poster,
    this.shape,
    this.caption,
    this.badge,
    this.progress,
    this.onTap,
    this.preview,
    this.onContextMenu,
  });

  final String title;
  final String? poster;

  /// `posterShape` del addon.
  final String? shape;

  /// Línea gris bajo el título (año, «T1 E3»...).
  final String? caption;

  /// Chip sobre la imagen («T2 E4»).
  final String? badge;

  /// Fracción vista (0 a 1); si no es `null` dibuja la barra sobre el póster.
  final double? progress;
  final VoidCallback? onTap;
  final CardPreview? preview;

  /// Clic derecho (o la tecla de menú), con la posición en pantalla.
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard>
    with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CardGrowth.duration,
  );
  late final Animation<double> _grow = CardGrowth.grow(_controller);
  late final Animation<double> _panel = CardGrowth.panel(_controller);

  bool _overCard = false;
  bool _overPanel = false;
  bool _focused = false;
  Timer? _intent;
  Timer? _leave;

  // Dónde cae la tarjeta agrandada, en pantalla; se calcula al abrirla.
  Rect _card = Rect.zero;
  Rect _box = Rect.zero;

  bool get _open => _portal.isShowing;
  bool get _closing =>
      _controller.status == AnimationStatus.reverse ||
      (!_controller.isAnimating && _controller.value == 0);
  bool get _wantsOpen => widget.preview != null;

  @override
  void didUpdateWidget(PosterCard old) {
    super.didUpdateWidget(old);
    if (old.preview != null && widget.preview == null && _open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _snapClosed();
      });
    }
  }

  @override
  void dispose() {
    _intent?.cancel();
    _leave?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // --- Intención de abrir y de cerrar ------------------------------------------

  void _setOverCard(bool value) {
    _overCard = value;
    _evaluate();
  }

  void _setOverPanel(bool value) {
    _overPanel = value;
    _evaluate();
  }

  void _setFocused(bool value) {
    _focused = value;
    if (value) {
      Scrollable.ensureVisible(
        context,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    }
    _evaluate();
  }

  void _evaluate() {
    if (!mounted) return;
    if (!_wantsOpen) {
      setState(() {});
      return;
    }
    final inside = _overCard || _overPanel || _focused;
    if (inside) {
      _leave?.cancel();
      if (_open) {
        if (_controller.status != AnimationStatus.forward &&
            !_controller.isCompleted) {
          unawaited(_controller.forward());
        }
      } else {
        _intent ??= Timer(
          _overCard || _overPanel
              ? CardGrowth.hoverDelay
              : CardGrowth.focusDelay,
          _show,
        );
      }
    } else {
      _intent?.cancel();
      _intent = null;
      // Un respiro: al pasar del mouse de la tarjeta al panel (o al revés)
      // hay un instante en que ninguno de los dos lo tiene.
      _leave?.cancel();
      _leave = Timer(const Duration(milliseconds: 40), _hide);
    }
    setState(() {});
  }

  void _show() {
    _intent = null;
    if (!mounted || !_wantsOpen) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final size = PosterSize.of(widget.shape);
    final card = box.localToGlobal(Offset.zero) & Size(size.width, size.height);
    final scale = reduce ? 1.0 : CardGrowth.scale;
    final width = size.width * scale;
    final height = size.height * scale;

    // Horizontal: centrada sobre la tarjeta y sin salirse de la fila (queda
    // anclada a la izquierda en la primera visible y a la derecha en la
    // última).
    final scrollable = Scrollable.maybeOf(context)?.context.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    var minX = 8.0;
    var maxX = double.infinity;
    if (scrollable is RenderBox && scrollable.attached) {
      final view = scrollable.localToGlobal(Offset.zero) & scrollable.size;
      minX = view.left + 8;
      maxX = view.right - 8;
    }
    var left = card.left - (width - size.width) / 2;
    if (maxX.isFinite && maxX - minX >= width) {
      left = left.clamp(minX, maxX - width);
    }

    var top = card.top - (height - size.height) / 2;
    final total = height + CardGrowth.panelGap + CardGrowth.panelHeight;
    if (overlay is RenderBox && overlay.attached) {
      final bottom = overlay.size.height - 8;
      if (top + total > bottom) top = (bottom - total).clamp(8.0, top);
    }
    _card = card;
    _box = Rect.fromLTWH(left, top, width, total);
    _portal.show();
    unawaited(_controller.forward());
    setState(() {});
  }

  void _hide() {
    _leave = null;
    if (!_open) return;
    unawaited(
      _controller.reverse().whenComplete(() {
        if (!mounted || _controller.value > 0) return;
        _overPanel = false;
        _portal.hide();
        setState(() {});
      }),
    );
  }

  void _snapClosed() {
    _controller.value = 0;
    _overPanel = false;
    _portal.hide();
  }

  /// La rueda sobre la tarjeta agrandada mueve la página, como si no
  /// estuviera.
  void _forwardWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final page = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (page == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      page.position.pointerScroll(event.scrollDelta.dy);
    });
    _overPanel = false;
    _evaluate();
  }

  // --- Dibujo ---------------------------------------------------------------

  Widget _face(BuildContext context, {required double glow}) {
    final scheme = Theme.of(context).colorScheme;
    final size = PosterSize.of(widget.shape);
    final progress = widget.progress;
    final radius = BorderRadius.circular(10);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: _focused ? scheme.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: glow <= 0
            ? const []
            : [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.6 * glow),
                  blurRadius: 24 * glow,
                  offset: Offset(0, 10 * glow),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RemoteImage(
              widget.poster,
              width: size.width * CardGrowth.scale,
              placeholderIcon: Icons.movie_outlined,
            ),
            if (widget.badge != null)
              Positioned(
                left: 6,
                top: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      widget.badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = PosterSize.of(widget.shape);
    final radius = BorderRadius.circular(10);
    final simple = widget.preview == null;
    final active = simple && (_overCard || _focused);

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: CompositedTransformTarget(
        link: _link,
        child: SizedBox(
          width: size.width,
          child: Semantics(
            button: true,
            label: widget.title,
            excludeSemantics: true,
            child: MouseRegion(
              onEnter: (_) => _setOverCard(true),
              onExit: (_) => _setOverCard(false),
              child: InkWell(
                onTap: widget.onTap,
                onFocusChange: _setFocused,
                onSecondaryTapUp: widget.onContextMenu == null
                    ? null
                    : (d) => widget.onContextMenu!(d.globalPosition),
                borderRadius: radius,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RepaintBoundary(
                      child: AnimatedScale(
                        scale: active ? 1.04 : 1,
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: _face(context, glow: active ? 0.7 : 0),
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
                          color: active || _focused ? scheme.primary : null,
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
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final reduce = MediaQuery.disableAnimationsOf(overlayContext);
    final size = PosterSize.of(widget.shape);
    final preview = widget.preview;
    if (preview == null) return const SizedBox.shrink();
    final box = _box;
    final card = _card;
    final closing = _closing;
    // Dónde queda la tarjeta chica dentro de la caja de la grande.
    final startLeft = card.left - box.left;
    final startTop = card.top - box.top;

    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.topLeft,
      offset: Offset(box.left - card.left, box.top - card.top),
      child: Align(
        alignment: Alignment.topLeft,
        child: IgnorePointer(
          ignoring: closing,
          child: MouseRegion(
            onEnter: (_) => _setOverPanel(true),
            onExit: (_) => _setOverPanel(false),
            child: Listener(
              onPointerSignal: _forwardWheel,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onTap,
                onSecondaryTapUp: widget.onContextMenu == null
                    ? null
                    : (d) => widget.onContextMenu!(d.globalPosition),
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final t = _grow.value;
                        final p = _panel.value;
                        final scale = reduce
                            ? 1.0
                            : 1 + (CardGrowth.scale - 1) * t;
                        final dx = startLeft * (1 - t);
                        final dy = startTop * (1 - t);
                        final cardHeight = size.height * scale;
                        return Opacity(
                          opacity: reduce ? _controller.value : 1,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Transform(
                                transform: Matrix4.translationValues(dx, dy, 0)
                                  ..scaleByDouble(scale, scale, 1, 1),
                                child: SizedBox(
                                  key: const Key('card-grown'),
                                  width: size.width,
                                  height: size.height,
                                  child: _face(context, glow: t),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                top:
                                    dy +
                                    cardHeight +
                                    CardGrowth.panelGap +
                                    (reduce ? 0 : 10 * (1 - p)),
                                height: CardGrowth.panelHeight,
                                child: Opacity(
                                  opacity: p,
                                  child: _Panel(
                                    title: widget.title,
                                    preview: preview,
                                    onTap: widget.onTap,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.preview,
    required this.onTap,
  });

  final String title;
  final CardPreview preview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dim = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final facts = [
      if (preview.rating != null) '★ ${preview.rating}',
      ?preview.year,
      ...preview.genres.take(2),
    ];
    return Material(
      key: const Key('card-panel'),
      color: scheme.surfaceContainerHigh,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (facts.isNotEmpty)
              Text(
                facts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dim,
              ),
            if (preview.synopsis != null)
              Text(
                preview.synopsis!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dim,
              ),
            const Spacer(),
            ExcludeFocus(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    FilledButton.icon(
                      key: const Key('card-play'),
                      onPressed: preview.onPlay ?? onTap,
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(preview.playLabel),
                      style: _compact,
                    ),
                    OutlinedButton(
                      key: const Key('card-info'),
                      onPressed: preview.onInfo ?? onTap,
                      style: _compact,
                      child: const Text('Más info'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _compact = ButtonStyle(
    visualDensity: VisualDensity.compact,
    minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );
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
