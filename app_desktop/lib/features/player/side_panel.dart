import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Panel lateral derecho del reproductor (Fuente, Audio, Subtítulos): fondo
/// translúcido con desenfoque, encabezado con una X y una lista con scroll
/// propio. Entra y sale con un deslizamiento y un fundido.
///
/// Va directo dentro de un `Stack`. Con [open] en `false` hace la animación de
/// salida y al terminar avisa por [onDismissed]; quien lo arma lo saca ahí.
class PlayerSidePanel extends StatefulWidget {
  const PlayerSidePanel({
    super.key,
    required this.title,
    required this.open,
    required this.onClose,
    required this.onDismissed,
    required this.child,
  });

  /// Ancho del panel.
  static const double width = 420;

  /// Margen contra los bordes de la ventana.
  static const double margin = 16;

  /// Cuánto dura la entrada y la salida.
  static const Duration duration = Duration(milliseconds: 220);

  final String title;
  final bool open;
  final VoidCallback onClose;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  State<PlayerSidePanel> createState() => _PlayerSidePanelState();
}

class _PlayerSidePanelState extends State<PlayerSidePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PlayerSidePanel.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0.25, 0),
    end: Offset.zero,
  ).animate(_curve);
  final FocusNode _focus = FocusNode(debugLabel: 'player-side-panel');

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.dismissed) return;
      // Con las animaciones apagadas termina en el mismo cuadro: se avisa
      // después de armarlo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.open) widget.onDismissed();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : PlayerSidePanel.duration;
    if (widget.open && !_controller.isCompleted) _controller.forward();
  }

  @override
  void didUpdateWidget(PlayerSidePanel old) {
    super.didUpdateWidget(old);
    if (old.open == widget.open) return;
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      FocusScope.of(context).nextFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      FocusScope.of(context).previousFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      // El espacio de la pantalla pausa: acá activa el ítem con el foco.
      final focused = FocusManager.instance.primaryFocus?.context;
      if (event is KeyDownEvent && focused != null) {
        Actions.maybeInvoke(focused, const ActivateIntent());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth =
        MediaQuery.sizeOf(context).width - 2 * PlayerSidePanel.margin;
    final width = maxWidth < PlayerSidePanel.width
        ? maxWidth
        : PlayerSidePanel.width;
    return Positioned(
      top: PlayerSidePanel.margin,
      right: PlayerSidePanel.margin,
      bottom: PlayerSidePanel.margin,
      width: width,
      child: IgnorePointer(
        ignoring: !widget.open,
        child: FadeTransition(
          opacity: _curve,
          child: SlideTransition(
            position: _slide,
            child: FocusScope(
              child: Focus(
                autofocus: true,
                focusNode: _focus,
                onKeyEvent: _onKey,
                child: ClipRRect(
                  key: const Key('player-side-panel'),
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xB3101014),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x1FFFFFFF)),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                IconButton(
                                  key: const Key('player-panel-close'),
                                  tooltip: 'Cerrar (Esc)',
                                  icon: const Icon(Icons.close),
                                  onPressed: widget.onClose,
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0x1FFFFFFF)),
                          Expanded(child: widget.child),
                        ],
                      ),
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

/// Un ítem elegible de un panel: marca el elegido con un check y un fondo, se
/// resalta al pasar el mouse y se puede activar con el teclado.
class PanelOption extends StatelessWidget {
  const PanelOption({
    super.key,
    required this.checked,
    required this.onTap,
    required this.child,
  });

  final bool checked;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: checked
            ? scheme.primary.withValues(alpha: 0.22)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: Colors.white.withValues(alpha: 0.09),
          focusColor: Colors.white.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: checked
                      ? Icon(Icons.check, size: 20, color: scheme.primary)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Separador de grupo dentro de un panel («Español», un addon...).
class PanelHeading extends StatelessWidget {
  const PanelHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
