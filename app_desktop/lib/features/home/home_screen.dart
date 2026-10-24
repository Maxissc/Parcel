import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/diagnostics/playback_diagnostics.dart';
import '../player/player_screen.dart';
import '../settings/try_player_dialog.dart';

/// Crea el motor de reproducción. En la app es [MediaKitPlaybackEngine]; en
/// los tests, un motor falso.
typedef PlaybackEngineFactory = PlaybackEngine Function();

/// Pantalla de inicio (provisoria): el botón de prueba del reproductor.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.engineFactory, this.diagnostics});

  final PlaybackEngineFactory engineFactory;

  /// Modo de diagnóstico (solo debug); si trae URL, abre el reproductor al
  /// arrancar.
  final DiagnosticsConfig? diagnostics;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final url = widget.diagnostics?.url;
    if (url != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openPlayer(url: url, subtitleUrl: widget.diagnostics?.subtitleUrl);
        }
      });
    }
  }

  Future<void> _askAndOpen() async {
    final request = await showTryPlayerDialog(context);
    if (request == null || !mounted) return;
    _openPlayer(url: request.url, subtitleUrl: request.subtitleUrl);
  }

  void _openPlayer({required String url, String? subtitleUrl}) {
    final engine = widget.engineFactory();
    final diag = widget.diagnostics;
    if (diag != null) {
      final d = PlaybackDiagnostics(engine, config: diag)..start();
      if (diag.cycleTracks) d.cycleTracks();
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          engine: engine,
          source: PlaybackSource(url: url),
          title: Uri.tryParse(url)?.pathSegments.lastOrNull,
          subtitles: [
            if (subtitleUrl != null)
              Subtitle(
                id: subtitleUrl,
                url: subtitleUrl,
                lang: 'und',
                label: 'Subtítulo externo',
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(appName, style: textTheme.displayMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _askAndOpen,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Probar reproductor'),
            ),
          ],
        ),
      ),
    );
  }
}
