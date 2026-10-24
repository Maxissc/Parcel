import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/diagnostics/diag_log.dart';
import '../../app/diagnostics/playback_diagnostics.dart';
import '../../data/platform.dart';
import 'player_screen.dart';

/// Qué reproducir en la ruta `/player`.
class PlayerArgs {
  const PlayerArgs({required this.url, this.subtitleUrl, this.title});

  final String url;
  final String? subtitleUrl;
  final String? title;
}

/// Ruta del reproductor: crea el motor, pone la ventana en pantalla completa
/// mientras dura y arma el diagnóstico si está activo.
class PlayerRoute extends ConsumerStatefulWidget {
  const PlayerRoute({super.key, required this.args});

  final PlayerArgs args;

  @override
  ConsumerState<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends ConsumerState<PlayerRoute> {
  late final PlaybackEngine _engine;
  late final WindowService _window;

  @override
  void initState() {
    super.initState();
    _window = ref.read(windowServiceProvider);
    _engine = ref.read(playbackEngineFactoryProvider)();
    final diag = ref.read(diagnosticsConfigProvider);
    if (diag != null) {
      final d = PlaybackDiagnostics(_engine, config: diag)..start();
      if (diag.cycleTracks) d.cycleTracks();
    }
    _window.setFullScreen(true);
  }

  @override
  void dispose() {
    _window.setFullScreen(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    return PlayerScreen(
      engine: _engine,
      source: PlaybackSource(url: args.url),
      title: args.title,
      subtitles: [
        if (args.subtitleUrl != null)
          Subtitle(
            id: args.subtitleUrl!,
            url: args.subtitleUrl!,
            lang: 'und',
            label: 'Subtítulo externo',
          ),
      ],
    );
  }
}
