import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'poster_card.dart';

/// Título de una fila: el nombre y, en gris al lado, de dónde viene.
class RowHeader extends StatelessWidget {
  const RowHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;

  /// Algo a la derecha del título (por ejemplo «Reintentar»).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: Spacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Fila horizontal que se desplaza con la rueda del mouse (sin Shift) y con
/// flechas que aparecen al pasar el mouse. Si la fila ya no puede moverse en
/// esa dirección, la rueda sigue de largo y mueve la página.
class Shelf extends StatefulWidget {
  const Shelf({super.key, required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  static const double height =
      210 + PosterSize.captionHeight + Spacing.sm + Spacing.md;

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  final ScrollController _controller = ScrollController();
  bool _hovered = false;
  double? _target;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  // Lo último que se dibujó de las flechas: la fila solo se redibuja cuando
  // una flecha aparece o desaparece, no en cada paso del desplazamiento.
  bool _backShown = false;
  bool _forwardShown = false;

  void _changed() {
    if (!mounted) return;
    final back = _canGoBack;
    final forward = _canGoForward;
    if (back == _backShown && forward == _forwardShown) return;
    setState(() {
      _backShown = back;
      _forwardShown = forward;
    });
  }

  double get _max =>
      _controller.hasClients ? _controller.position.maxScrollExtent : 0;
  double get _pixels =>
      _controller.hasClients ? _controller.position.pixels : 0;
  bool get _canGoBack => _pixels > 1;
  bool get _canGoForward => _pixels < _max - 1;

  void _animateTo(double offset) {
    if (!_controller.hasClients) return;
    final target = offset.clamp(0.0, _max);
    _target = target;
    _controller
        .animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _target = null);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta;
    // Con la rueda común el movimiento viene vertical; el horizontal (touchpad
    // o Shift) lo maneja la propia lista.
    if (delta.dy == 0 || delta.dy.abs() < delta.dx.abs()) return;
    final from = _target ?? _pixels;
    final next = (from + delta.dy).clamp(0.0, _max);
    if (next == from) return; // en el borde: que siga la página.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _animateTo(next);
    });
  }

  void _page(int direction) {
    if (!_controller.hasClients) return;
    final step = _controller.position.viewportDimension * 0.8;
    _animateTo((_target ?? _pixels) + direction * step);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Shelf.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
              return false;
            },
            child: Stack(
              children: [
                ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.sm,
                    Spacing.lg,
                    Spacing.md,
                  ),
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, _) => const SizedBox(width: Spacing.md),
                  itemBuilder: widget.itemBuilder,
                ),
                _Arrow(
                  alignment: Alignment.centerLeft,
                  icon: Icons.chevron_left,
                  tooltip: 'Ver anteriores',
                  visible: _hovered && _canGoBack,
                  onPressed: () => _page(-1),
                ),
                _Arrow(
                  alignment: Alignment.centerRight,
                  icon: Icons.chevron_right,
                  tooltip: 'Ver más',
                  visible: _hovered && _canGoForward,
                  onPressed: () => _page(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.visible,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.only(bottom: PosterSize.captionHeight),
        child: ExcludeFocus(
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: IconButton.filledTonal(
                tooltip: tooltip,
                icon: Icon(icon),
                onPressed: onPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El lugar de una fila mientras carga: tarjetas grises que no se desplazan.
class ShelfSkeleton extends StatelessWidget {
  const ShelfSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Shelf.height,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          Spacing.md,
        ),
        itemCount: 12,
        separatorBuilder: (_, _) => const SizedBox(width: Spacing.md),
        itemBuilder: (_, _) => const PosterCardSkeleton(),
      ),
    );
  }
}
