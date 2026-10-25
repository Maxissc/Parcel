import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../data/platform.dart';
import '../data/progress_providers.dart';
import '../data/providers.dart';
import '../shared/state_views.dart';
import 'back_navigation.dart';
import 'diagnostics/diagnostics_driver.dart';
import 'router.dart';
import 'theme.dart';

/// La app. Muestra una pantalla de carga mientras se abren los datos y
/// después el router.
class ParcelApp extends ConsumerStatefulWidget {
  const ParcelApp({super.key});

  @override
  ConsumerState<ParcelApp> createState() => _ParcelAppState();
}

class _ParcelAppState extends ConsumerState<ParcelApp> {
  late final AppLifecycleListener _lifecycle;
  late final WindowService _window;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    _window = ref.read(windowServiceProvider);
    unawaited(_window.setCloseHandler(_saveBeforeClose));
  }

  @override
  void dispose() {
    unawaited(_window.setCloseHandler(null));
    _lifecycle.dispose();
    super.dispose();
  }

  /// Al cerrar la ventana: guarda dónde va el video abierto (si hay) y espera
  /// a que termine de escribirse todo lo pendiente.
  Future<void> _saveBeforeClose() async {
    ref.read(activePlayerProvider).saveNow();
    await ref.read(appDataProvider).value?.flush();
  }

  /// Al salir se espera lo pendiente y se cierra el cliente HTTP y el
  /// repositorio de addons.
  Future<AppExitResponse> _onExitRequested() async {
    final data = ref.read(appDataProvider).value;
    await data?.flush();
    ref.read(httpClientProvider).close();
    await data?.dispose();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    // El aviso a la consola va aparte, para que dibujar no tenga efectos.
    ref.listen(appDataProvider, (_, next) {
      if (next.hasError) {
        debugPrint('No se pudieron abrir los datos: ${next.error}');
      }
    });
    final data = ref.watch(appDataProvider);
    if (data.isLoading) {
      return _bootApp(const LoadingState(label: 'Abriendo Parcel…'));
    }
    if (data.hasError) {
      return _bootApp(
        ErrorState(
          title: 'No pudimos abrir tus datos',
          message:
              'Revisá que la carpeta de datos de Parcel exista y se pueda '
              'escribir, y probá de nuevo.',
          onRetry: () => ref.invalidate(appDataProvider),
        ),
      );
    }
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: appName,
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) => BackNavigation(
        router: router,
        child: DiagnosticsDriver(child: child ?? const SizedBox.shrink()),
      ),
    );
  }

  Widget _bootApp(Widget body) => MaterialApp(
    title: appName,
    theme: buildDarkTheme(),
    themeMode: ThemeMode.dark,
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: body),
  );
}
