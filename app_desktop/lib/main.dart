import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:parcel_core/parcel_core.dart';

import 'app/diagnostics/playback_diagnostics.dart';
import 'features/home/home_screen.dart';
import 'playback/media_kit_playback_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(ParcelApp(diagnostics: DiagnosticsConfig.fromEnvironment()));
}

class ParcelApp extends StatelessWidget {
  const ParcelApp({super.key, this.engineFactory, this.diagnostics});

  /// Crea el motor de reproducción; por defecto, el de media_kit.
  final PlaybackEngineFactory? engineFactory;

  /// Modo de diagnóstico (solo debug).
  final DiagnosticsConfig? diagnostics;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: HomeScreen(
        engineFactory: engineFactory ?? MediaKitPlaybackEngine.new,
        diagnostics: diagnostics,
      ),
    );
  }
}
