import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'poster_card.dart';

/// Título de una fila: el nombre y, en gris al lado, de dónde viene. Con
/// [onSeeAll], el título se puede tocar y a la derecha aparece «Ver todo ›».
class RowHeader extends StatelessWidget {
  const RowHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onSeeAll,
  });

  final String title;
  final String? subtitle;

  /// Algo a la derecha del título (por ejemplo «Reintentar»).
  final Widget? trailing;

  /// Abre el catálogo entero.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    if (onSeeAll != null) {
      titleText = InkWell(
        key: const Key('row-title'),
        onTap: onSeeAll,
        // Con el teclado se llega por «Ver todo ›»; si el título también
        // tomara el foco, ↓ desde una tarjeta pararía en él.
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(6),
        child: titleText,
      );
    }
    final labels = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: Semantics(header: true, child: titleText)),
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
        if (trailing != null) ...[const SizedBox(width: Spacing.sm), trailing!],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: onSeeAll == null
          ? labels
          : Row(
              children: [
                // El título y el addon a la izquierda; «Ver todo ›» pegado al
                // borde derecho.
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: labels),
                ),
                TextButton(
                  key: const Key('row-see-all'),
                  onPressed: onSeeAll,
                  child: const Text('Ver todo ›'),
                ),
              ],
            ),
    );
  }
}

/// Fila horizontal de tarjetas.
///
/// La rueda vertical sigue de largo y mueve la página; la fila se mueve con
/// Shift + rueda, con el desplazamiento horizontal del trackpad, arrastrando
/// con el mouse y con las flechas ‹ › que aparecen al pasar el mouse.
class Shelf extends StatefulWidget {
  const Shelf({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.height = defaultHeight,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;

  /// Alto de una fila de pósters.
  static const double defaultHeight =
      210 + PosterSize.captionHeight + Spacing.sm + Spacing.md;

  /// Cuánto del ancho visible avanza una flecha.
  static const double pageFraction = 0.85;
  static const Duration pageDuration = Duration(milliseconds: 380);

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  final ScrollController _controller = ScrollController();
  // Estado de las flechas aparte, para no reconstruir las tarjetas: solo las
  // flechas escuchan estos avisos.
  final ValueNotifier<bool> _hovered = ValueNotifier(false);
  final ValueNotifier<bool> _canBack = ValueNotifier(false);
  final ValueNotifier<bool> _canForward = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    _hovered.dispose();
    _canBack.dispose();
    _canForward.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    _canBack.value = position.pixels > 1;
    _canForward.value = position.pixels < position.maxScrollExtent - 1;
  }

  void _page(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target =
        (position.pixels +
                direction * position.viewportDimension * Shelf.pageFraction)
            .clamp(0.0, position.maxScrollExtent);
    unawaited(
      _controller.animateTo(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Shelf.pageDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fade = Theme.of(context).scaffoldBackgroundColor;
    final behavior = ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
    );
    return SizedBox(
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => _hovered.value = true,
        onExit: (_) => _hovered.value = false,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
            return false;
          },
          child: Stack(
            children: [
              ScrollConfiguration(
                behavior: behavior,
                child: ListView.separated(
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
              ),
              _Arrow(
                forward: false,
                fade: fade,
                hovered: _hovered,
                can: _canBack,
                onPressed: () => _page(-1),
              ),
              _Arrow(
                forward: true,
                fade: fade,
                hovered: _hovered,
                can: _canForward,
                onPressed: () => _page(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.forward,
    required this.fade,
    required this.hovered,
    required this.can,
    required this.onPressed,
  });

  final bool forward;
  final Color fade;
  final ValueNotifier<bool> hovered;
  final ValueNotifier<bool> can;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final side = forward ? Alignment.centerRight : Alignment.centerLeft;
    final other = forward ? Alignment.centerLeft : Alignment.centerRight;
    return Positioned(
      top: 0,
      bottom: 0,
      left: forward ? null : 0,
      right: forward ? 0 : null,
      width: 72,
      child: ListenableBuilder(
        listenable: Listenable.merge([hovered, can]),
        builder: (context, _) {
          final show = hovered.value && can.value;
          return ExcludeFocus(
            child: IgnorePointer(
              ignoring: !show,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: side,
                      end: other,
                      colors: [fade, fade.withValues(alpha: 0)],
                    ),
                  ),
                  child: Align(
                    alignment: side,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: PosterSize.captionHeight,
                        left: Spacing.sm,
                        right: Spacing.sm,
                      ),
                      child: IconButton.filledTonal(
                        tooltip: forward ? 'Ver más' : 'Ver anteriores',
                        iconSize: 32,
                        icon: Icon(
                          forward ? Icons.chevron_right : Icons.chevron_left,
                        ),
                        onPressed: onPressed,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
      height: Shelf.defaultHeight,
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
