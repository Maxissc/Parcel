import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'app/diagnostics/diag_log.dart';
import 'app/diagnostics/playback_diagnostics.dart';
import 'data/platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await DesktopWindowService.initialize();
  runApp(
    ProviderScope(
      // Si un proveedor falla (por ejemplo, al abrir los datos), la pantalla
      // de error ofrece «Reintentar»; no se reintenta solo.
      retry: (_, _) => null,
      overrides: [
        windowServiceProvider.overrideWithValue(const DesktopWindowService()),
        diagnosticsConfigProvider.overrideWithValue(
          DiagnosticsConfig.fromEnvironment(),
        ),
      ],
      child: const ParcelApp(),
    ),
  );
}
