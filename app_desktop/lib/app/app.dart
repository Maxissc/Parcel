import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../data/providers.dart';
import '../shared/state_views.dart';
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

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Al salir se cierra el cliente HTTP y el repositorio de addons.
  Future<AppExitResponse> _onExitRequested() async {
    ref.read(httpClientProvider).close();
    await ref.read(appDataProvider).value?.dispose();
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
    return MaterialApp.router(
      title: appName,
      theme: buildDarkTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          DiagnosticsDriver(child: child ?? const SizedBox.shrink()),
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
