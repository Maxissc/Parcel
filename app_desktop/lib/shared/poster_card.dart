import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Ancho de la franja de las flechas ‹ › de una fila: la tarjeta agrandada
  /// no la tapa.
  static const double arrowGutter = 72;

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

/// Lo que una fila ([Shelf]) le ofrece a sus tarjetas: avisar que el mouse
/// está sobre la tarjeta agrandada, que cuenta como estar sobre la fila (las
/// flechas no se apagan).
class ShelfScope extends InheritedWidget {
  const ShelfScope({
    super.key,
    required this.onOverlayHover,
    required super.child,
  });

  final ValueChanged<bool> onOverlayHover;

  static ShelfScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShelfScope>();

  @override
  bool updateShouldNotify(ShelfScope old) => false;
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
  /// La única tarjeta agrandada de la pantalla: al abrir una se cierra la
  /// otra.
  static _PosterCardState? _active;

  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CardGrowth.duration,
  );
  late final Animation<double> _grow = CardGrowth.grow(_controller);
  late final Animation<double> _panel = CardGrowth.panel(_controller);

  /// `true` mientras la tarjeta agrandada se cierra o ya está cerrada: no
  /// recibe gestos.
  final ValueNotifier<bool> _isClosing = ValueNotifier(true);

  bool _overCard = false;
  bool _overPanel = false;
  bool _focused = false;

  /// Otra tarjeta tomó el lugar: esta no vuelve a abrirse hasta una intención
  /// nueva (el mouse o el foco entran de nuevo).
  bool _yielded = false;

  /// La tarjeta se está cerrando porque se movió la fila o la página: aunque
  /// el mouse vuelva a quedar sobre la tarjeta chica, no se reabre hasta que
  /// termine de cerrarse.
  bool _closingForScroll = false;
  Timer? _intent;
  Duration _intentDelay = Duration.zero;
  Timer? _leave;
  ScrollPosition? _rowPosition;
  ScrollPosition? _pagePosition;

  // Dónde cae la tarjeta agrandada, en pantalla; se calcula al abrirla.
  Rect _card = Rect.zero;
  Rect _box = Rect.zero;

  bool get _open => _portal.isShowing;
  bool get _wantsOpen => widget.preview != null;

  /// Crecer por foco solo vale en modo teclado: con el mouse o el toque el
  /// foco de un clic no la agranda.
  bool get _focusGrows =>
      _focused &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindScroll();
  }

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
    if (_active == this) _active = null;
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _rowPosition?.removeListener(_onScroll);
    _pagePosition?.removeListener(_onScroll);
    if (_overPanel) _notifyShelf(false);
    _intent?.cancel();
    _leave?.cancel();
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    _isClosing.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    _isClosing.value =
        status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed;
  }

  void _onHighlightMode(FocusHighlightMode mode) {
    if (mounted) _evaluate();
  }

  // --- Scroll de la fila y de la página -----------------------------------------

  void _bindScroll() {
    final row = Scrollable.maybeOf(context, axis: Axis.horizontal)?.position;
    if (row != _rowPosition) {
      _rowPosition?.removeListener(_onScroll);
      _rowPosition = row?..addListener(_onScroll);
    }
    final page = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (page != _pagePosition) {
      _pagePosition?.removeListener(_onScroll);
      _pagePosition = page?..addListener(_onScroll);
    }
  }

  /// Si la fila o la página se mueven, la tarjeta agrandada se cierra (se iría
  /// del lugar); una que todavía espera para abrirse espera a que pare.
  void _onScroll() {
    if (!mounted) return;
    if (_open) {
      _hide(reevaluate: true);
    } else if (_intent != null) {
      _intent!.cancel();
      _intent = Timer(_intentDelay, _show);
    }
  }

  /// Mueve la fila (horizontal) o la página (vertical) [delta] píxeles.
  void _scrollBy(Axis axis, double delta) {
    final position = Scrollable.maybeOf(context, axis: axis)?.position;
    if (position == null) return;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) position.jumpTo(target);
  }

  // --- Intención de abrir y de cerrar ------------------------------------------

  void _setOverCard(bool value) {
    _overCard = value;
    if (value) _yielded = false;
    _evaluate();
  }

  void _setOverPanel(bool value) {
    _setOverPanelQuiet(value);
    _evaluate();
  }

  void _setOverPanelQuiet(bool value) {
    if (_overPanel == value) return;
    _overPanel = value;
    _notifyShelf(value);
  }

  void _notifyShelf(bool value) {
    final callback = ShelfScope.maybeOf(context)?.onOverlayHover;
    if (callback == null) return;
    if (mounted) {
      callback(value);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback(value));
    }
  }

  void _setFocused(bool value) {
    _focused = value;
    if (value) {
      _yielded = false;
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
    final inside = _overCard || _overPanel || _focusGrows;
    if (inside) {
      _leave?.cancel();
      if (_yielded) {
        // Otra tarjeta tomó el lugar.
      } else if (_open) {
        if (!_closingForScroll &&
            _controller.status != AnimationStatus.forward &&
            !_controller.isCompleted) {
          unawaited(_controller.forward());
        }
      } else if (_intent == null) {
        _intentDelay = _overCard || _overPanel
            ? CardGrowth.hoverDelay
            : CardGrowth.focusDelay;
        _intent = Timer(_intentDelay, _show);
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
    // última), dejando libre la franja de las flechas.
    final scrollable = Scrollable.maybeOf(context)?.context.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    final gutter = ShelfScope.maybeOf(context) == null
        ? 0.0
        : CardGrowth.arrowGutter;
    var minX = 8.0;
    var maxX = double.infinity;
    if (scrollable is RenderBox && scrollable.attached) {
      final view = scrollable.localToGlobal(Offset.zero) & scrollable.size;
      minX = view.left + 8 + gutter;
      maxX = view.right - 8 - gutter;
    }
    var left = card.left - (width - size.width) / 2;
    if (maxX.isFinite && maxX - minX >= width) {
      left = left.clamp(minX, maxX - width);
    }

    // Vertical: dentro de la ventana y sin subirse por encima del área de la
    // página.
    var top = card.top - (height - size.height) / 2;
    final total = height + CardGrowth.panelGap + CardGrowth.panelHeight;
    var minTop = 8.0;
    final page = Scrollable.maybeOf(
      context,
      axis: Axis.vertical,
    )?.context.findRenderObject();
    if (page is RenderBox && page.attached) {
      minTop = page.localToGlobal(Offset.zero).dy + 8;
    }
    if (overlay is RenderBox && overlay.attached) {
      final bottom = overlay.size.height - 8;
      if (top + total > bottom) top = bottom - total;
    }
    if (top < minTop) top = minTop;

    // Una sola tarjeta agrandada por vez.
    final other = _active;
    if (other != null && other != this) other._yield();
    _active = this;
    _card = card;
    _box = Rect.fromLTWH(left, top, width, total);
    _portal.show();
    unawaited(_controller.forward());
    setState(() {});
  }

  /// Otra tarjeta se abrió: esta se va enseguida y no vuelve sola.
  void _yield() {
    _yielded = true;
    _intent?.cancel();
    _intent = null;
    _leave?.cancel();
    if (_open) _snapClosed();
  }

  /// El menú del clic derecho: la tarjeta agrandada se va y no vuelve a crecer
  /// mientras el menú está abierto (si no, taparía el menú).
  void _onContextMenu(Offset position) {
    _intent?.cancel();
    _intent = null;
    _overCard = false;
    if (_open) _hide();
    widget.onContextMenu?.call(position);
  }

  void _hide({bool reevaluate = false}) {
    _leave = null;
    if (!_open) return;
    if (reevaluate) _closingForScroll = true;
    if (_controller.status == AnimationStatus.reverse) return;
    unawaited(
      _controller.reverse().whenComplete(() {
        _closingForScroll = false;
        if (!mounted || _controller.value > 0) return;
        _setOverPanelQuiet(false);
        _portal.hide();
        if (_active == this) _active = null;
        setState(() {});
        if (reevaluate) _evaluate();
      }),
    );
  }

  void _snapClosed() {
    _closingForScroll = false;
    _controller.value = 0;
    _setOverPanelQuiet(false);
    _portal.hide();
    if (_active == this) _active = null;
  }

  /// La rueda sobre la tarjeta agrandada mueve lo que movería sin ella: la
  /// página con la rueda vertical, la fila con Shift o con el desplazamiento
  /// horizontal.
  void _forwardWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    final horizontal =
        HardwareKeyboard.instance.isShiftPressed || dx.abs() > dy.abs();
    final target = Scrollable.maybeOf(
      context,
      axis: horizontal ? Axis.horizontal : Axis.vertical,
    );
    if (target == null) return;
    final delta = horizontal && dx.abs() > dy.abs() ? dx : dy;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      target.position.pointerScroll(delta);
    });
    _setOverPanelQuiet(false);
    _evaluate();
  }

  /// Arrastrar con el mouse (o el dedo) sobre la tarjeta agrandada mueve la
  /// fila.
  void _forwardMove(PointerMoveEvent event) {
    if (event.buttons & kPrimaryButton == 0) return;
    _scrollBy(Axis.horizontal, -event.delta.dx);
  }

  /// Un pan del trackpad sobre la tarjeta agrandada mueve la fila y la
  /// página.
  void _forwardPan(PointerPanZoomUpdateEvent event) {
    _scrollBy(Axis.horizontal, -event.panDelta.dx);
    _scrollBy(Axis.vertical, -event.panDelta.dy);
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
                    : (d) => _onContextMenu(d.globalPosition),
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
        child: ValueListenableBuilder<bool>(
          valueListenable: _isClosing,
          builder: (context, closing, child) =>
              IgnorePointer(ignoring: closing, child: child),
          child: MouseRegion(
            onEnter: (_) => _setOverPanel(true),
            onExit: (_) => _setOverPanel(false),
            child: Listener(
              onPointerSignal: _forwardWheel,
              onPointerMove: _forwardMove,
              onPointerPanZoomUpdate: _forwardPan,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onTap,
                onSecondaryTapUp: widget.onContextMenu == null
                    ? null
                    : (d) => _onContextMenu(d.globalPosition),
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
