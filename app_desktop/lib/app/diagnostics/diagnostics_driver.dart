import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/onboarding_controller.dart';
import '../../features/player/player_route.dart';
import '../router.dart';
import 'diag_log.dart';

/// Hace lo que pide el modo de diagnóstico (solo debug) una vez que la app
/// está en pantalla: abrir el reproductor con `PARCEL_DIAG_URL` y cerrar la
/// app con `PARCEL_DIAG_EXIT_SECONDS`.
///
/// Si no hay configuración de diagnóstico, no hace nada.
class DiagnosticsDriver extends ConsumerStatefulWidget {
  const DiagnosticsDriver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DiagnosticsDriver> createState() => _DiagnosticsDriverState();
}

class _DiagnosticsDriverState extends ConsumerState<DiagnosticsDriver> {
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    final config = ref.read(diagnosticsConfigProvider);
    if (config == null) return;
    final exitAfter = config.exitAfter;
    if (exitAfter != null) {
      _exitTimer = Timer(exitAfter, () {
        ref.read(diagLogProvider).log('cierre por PARCEL_DIAG_EXIT_SECONDS');
        exit(0);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final paste = config.paste;
      if (paste != null) unawaited(_runPaste(paste));
      final url = config.url;
      if (url != null) {
        unawaited(
          ref
              .read(routerProvider)
              .push(
                Routes.player,
                extra: PlayerArgs(
                  url: url,
                  subtitleUrl: config.subtitleUrl,
                  title: Uri.tryParse(url)?.pathSegments.lastOrNull,
                ),
              ),
        );
      }
    });
  }

  /// Completa el asistente como si el usuario pegara [text] y confirmara.
  /// El asistente deja el informe en el log (líneas `[diag]`).
  Future<void> _runPaste(String text) async {
    ref.read(diagLogProvider).log('diagnóstico: pega la lista y confirma');
    // Mantiene vivo el estado del asistente mientras corre.
    final keepAlive = ref.listenManual(onboardingProvider, (_, _) {});
    try {
      ref.read(routerProvider).go(Routes.onboarding);
      final controller = ref.read(onboardingProvider.notifier)
        ..chooseSource(OnboardingStep.paste)
        ..submitPaste(text);
      await controller.importSelected();
    } finally {
      keepAlive.close();
    }
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
