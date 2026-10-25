import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Pantallas que quieren atender solas el botón Atrás del mouse (el
/// reproductor: hace lo mismo que Esc). Gana la última que se registró; un
/// manejador devuelve `true` si atendió el botón.
class BackInterceptors {
  final List<bool Function()> _handlers = [];

  void add(bool Function() handler) => _handlers.add(handler);

  void remove(bool Function() handler) => _handlers.remove(handler);

  /// `true` si alguna pantalla atendió el botón.
  bool dispatch() {
    for (final handler in _handlers.reversed) {
      if (handler()) return true;
    }
    return false;
  }
}

/// Da acceso a los [BackInterceptors] desde cualquier pantalla.
class BackScope extends InheritedWidget {
  const BackScope({
    super.key,
    required this.interceptors,
    required super.child,
  });

  final BackInterceptors interceptors;

  static BackInterceptors? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BackScope>()?.interceptors;

  @override
  bool updateShouldNotify(BackScope old) => interceptors != old.interceptors;
}

/// «Atrás» en toda la app: Esc y el botón Atrás del mouse (el botón 4) vuelven
/// a la pantalla anterior.
///
/// Esc solo vuelve si lo que está arriba es una pantalla: un diálogo o un menú
/// lo atienden ellos (se cierran), y el reproductor y el detalle tienen su
/// propio Esc, que corre antes porque está más cerca del foco. El botón del
/// mouse vuelve siempre que haya algo atrás, salvo que una pantalla lo atienda
/// ([BackInterceptors]: el reproductor lo trata como Esc).
class BackNavigation extends StatefulWidget {
  const BackNavigation({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  State<BackNavigation> createState() => _BackNavigationState();
}

class _BackNavigationState extends State<BackNavigation> {
  final BackInterceptors _interceptors = BackInterceptors();

  void _back() {
    if (widget.router.canPop()) widget.router.pop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !widget.router.canPop()) {
      return KeyEventResult.ignored;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final route = focusContext == null ? null : ModalRoute.of(focusContext);
    if (route is! PageRoute) return KeyEventResult.ignored;
    _back();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return BackScope(
      interceptors: _interceptors,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons & kBackMouseButton != 0) {
            if (!_interceptors.dispatch()) _back();
          }
        },
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: widget.child,
        ),
      ),
    );
  }
}
