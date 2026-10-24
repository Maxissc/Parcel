import 'package:flutter/painting.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../playback/media_kit_playback_engine.dart';

/// Crea el motor de reproducción. En la app es [MediaKitPlaybackEngine]; en
/// los tests, un motor falso.
typedef PlaybackEngineFactory = PlaybackEngine Function();

final playbackEngineFactoryProvider = Provider<PlaybackEngineFactory>(
  (ref) => MediaKitPlaybackEngine.new,
);

/// Abre [uri] en el navegador. Devuelve `false` si no se pudo.
typedef UrlOpener = Future<bool> Function(Uri uri);

final urlOpenerProvider = Provider<UrlOpener>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  },
);

/// Lo que la app le pide a la ventana del sistema.
abstract class WindowService {
  /// Pantalla completa para el reproductor; `false` la restaura.
  Future<void> setFullScreen(bool fullScreen);

  /// `true` si la ventana está en pantalla completa.
  Future<bool> isFullScreen();

  /// Título de la ventana (el de la barra y el de la barra de tareas).
  Future<void> setTitle(String title);

  /// Con [beforeClose], cerrar la ventana primero lo espera (por ejemplo, para
  /// guardar el progreso) y recién después cierra. Con `null` se cierra directo.
  Future<void> setCloseHandler(Future<void> Function()? beforeClose);
}

/// No hace nada: es lo que usan los tests.
class NoopWindowService implements WindowService {
  const NoopWindowService();

  @override
  Future<void> setFullScreen(bool fullScreen) async {}

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> setCloseHandler(Future<void> Function()? beforeClose) async {}
}

/// Cuánto se espera, como máximo, a lo que hay que terminar antes de cerrar.
const Duration closeGracePeriod = Duration(seconds: 5);

class _CloseListener with WindowListener {
  Future<void> Function()? beforeClose;
  bool _closing = false;

  @override
  Future<void> onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await beforeClose?.call().timeout(closeGracePeriod);
    } on Object {
      // Si guardar falla o tarda de más, igual se cierra: no se deja la
      // ventana trabada.
    }
    await windowManager.destroy();
  }
}

/// Ventana de escritorio, con `window_manager`.
class DesktopWindowService implements WindowService {
  const DesktopWindowService();

  /// Tamaño mínimo de la ventana.
  static const Size minimumSize = Size(960, 600);

  /// Título, tamaño mínimo y tamaño inicial. Se llama una vez antes de
  /// `runApp`.
  static Future<void> initialize() async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 720),
      minimumSize: minimumSize,
      center: true,
      title: appName,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Future<void> setFullScreen(bool fullScreen) =>
      windowManager.setFullScreen(fullScreen);

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  static final _CloseListener _closeListener = _CloseListener();
  static bool _closeListenerAdded = false;

  @override
  Future<void> setCloseHandler(Future<void> Function()? beforeClose) async {
    _closeListener.beforeClose = beforeClose;
    if (!_closeListenerAdded) {
      windowManager.addListener(_closeListener);
      _closeListenerAdded = true;
    }
    await windowManager.setPreventClose(beforeClose != null);
  }
}

final windowServiceProvider = Provider<WindowService>(
  (ref) => const NoopWindowService(),
);
