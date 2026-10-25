import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// «Atrás» en toda la app: Esc y el botón Atrás del mouse (el botón 4) vuelven
/// a la pantalla anterior.
///
/// Esc entra como `DismissIntent`, que solo llega acá si nadie más lo atendió
/// (un diálogo, un menú o el reproductor lo atienden antes). El botón del
/// mouse vuelve siempre que haya algo atrás.
class BackNavigation extends StatelessWidget {
  const BackNavigation({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  void _back() {
    if (router.canPop()) router.pop();
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
      child: Actions(
        actions: {DismissIntent: _BackAction(router.canPop, _back)},
        child: child,
      ),
    );
  }
}

class _BackAction extends Action<DismissIntent> {
  _BackAction(this._canPop, this._back);

  final bool Function() _canPop;
  final VoidCallback _back;

  @override
  bool isEnabled(DismissIntent intent) => _canPop();

  @override
  Object? invoke(DismissIntent intent) {
    _back();
    return null;
  }
}
