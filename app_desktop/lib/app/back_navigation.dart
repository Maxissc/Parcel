import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// «Atrás» en toda la app: Esc y el botón Atrás del mouse (el botón 4) vuelven
/// a la pantalla anterior.
///
/// Esc solo vuelve si lo que está arriba es una pantalla: un diálogo o un menú
/// lo atienden ellos (se cierran), y el reproductor y el detalle tienen su
/// propio Esc, que corre antes porque está más cerca del foco. El botón del
/// mouse vuelve siempre que haya algo atrás.
class BackNavigation extends StatelessWidget {
  const BackNavigation({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  void _back() {
    if (router.canPop()) router.pop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !router.canPop()) {
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons & kBackMouseButton != 0) {
          _back();
        }
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: child,
      ),
    );
  }
}
