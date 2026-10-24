import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../playback/video_surface.dart';
import 'player_controls.dart';

/// Pantalla del reproductor: video a pantalla completa de la ventana y
/// controles propios encima.
///
/// Recibe el [PlaybackEngine] ya armado (así se prueba con el motor falso). Por
/// defecto la pantalla toma posesión del motor y lo libera al cerrarse.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.engine,
    required this.source,
    this.subtitles = const [],
    this.title,
    this.disposeEngine = true,
  });

  final PlaybackEngine engine;
  final PlaybackSource source;

  /// Subtítulos externos que se cargan al abrir. Si hay más de uno queda
  /// elegido el último.
  final List<Subtitle> subtitles;
  final String? title;

  /// Si es `true`, libera [engine] al cerrar la pantalla.
  final bool disposeEngine;

  /// Segundos sin mover el mouse hasta que se ocultan los controles.
  static const Duration hideAfter = Duration(seconds: 3);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _seekStep = Duration(seconds: 10);
  static const _volumeStep = 0.05;

  final FocusNode _focus = FocusNode(debugLabel: 'player');
  Timer? _hideTimer;
  Timer? _osdTimer;
  bool _controlsVisible = true;
  bool _menuOpen = false;
  double? _dragValue;
  double _volumeBeforeMute = 0.5;
  String? _osd;

  PlaybackEngine get _engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
    unawaited(_start(widget.source));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _focus.dispose();
    if (widget.disposeEngine) unawaited(_engine.dispose());
    super.dispose();
  }

  Future<void> _start(PlaybackSource source) async {
    await _engine.open(source);
    if (!mounted || _engine.state.error != null) return;
    for (final s in widget.subtitles) {
      if (!mounted) return;
      await _engine.addExternalSubtitle(
        s.url,
        title: s.label ?? s.lang,
        language: s.lang,
      );
    }
  }

  void _retry() {
    final position = _engine.state.position;
    final source = position > Duration.zero
        ? PlaybackSource(
            url: widget.source.url,
            headers: widget.source.headers,
            startPosition: position,
          )
        : widget.source;
    unawaited(_start(source));
    _poke();
  }

  // --- Controles que se ocultan ---------------------------------------------

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(PlayerScreen.hideAfter, () {
      if (!mounted || _menuOpen || _dragValue != null) return;
      if (_engine.state.error != null) return;
      setState(() => _controlsVisible = false);
    });
  }

  /// Muestra los controles y reinicia la cuenta para ocultarlos.
  void _poke() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _showOsd(String text) {
    _osdTimer?.cancel();
    setState(() => _osd = text);
    _osdTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _osd = null);
    });
  }

  void _menuOpened() {
    _menuOpen = true;
    _hideTimer?.cancel();
  }

  void _menuClosed() {
    _menuOpen = false;
    _focus.requestFocus();
    _poke();
  }

  // --- Acciones --------------------------------------------------------------

  void _back() => Navigator.of(context).maybePop();

  void _playOrPause() {
    unawaited(_engine.playOrPause());
    _poke();
  }

  void _seekBy(Duration delta) {
    final s = _engine.state;
    if (s.duration <= Duration.zero) return;
    var target = s.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > s.duration) target = s.duration;
    unawaited(_engine.seek(target));
    _showOsd(
      '${delta.isNegative ? '−' : '+'}${delta.inSeconds.abs()} s · '
      '${formatPlaybackTime(target)}',
    );
    _poke();
  }

  void _changeVolume(double volume) {
    final v = volume.clamp(0.0, 1.0);
    unawaited(_engine.setVolume(v));
    _showOsd('Volumen ${(v * 100).round()} %');
    _poke();
  }

  void _toggleMute() {
    final v = _engine.state.volume;
    if (v > 0) {
      _volumeBeforeMute = v;
      _changeVolume(0);
    } else {
      _changeVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 0.5);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.escape && !isRepeat) {
      _back();
    } else if (key == LogicalKeyboardKey.space && !isRepeat) {
      _playOrPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-_seekStep);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(_seekStep);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _changeVolume(_engine.state.volume + _volumeStep);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _changeVolume(_engine.state.volume - _volumeStep);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- Dibujo ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: StreamBuilder<PlaybackState>(
            stream: engine.stream,
            initialData: engine.state,
            builder: (context, snapshot) {
              final state = snapshot.data ?? engine.state;
              return _buildBody(context, state);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PlaybackState state) {
    final engine = _engine;
    final hasError = state.error != null;
    final loading =
        !hasError && (state.buffering || state.duration <= Duration.zero);
    final showControls = _controlsVisible && !hasError;

    return MouseRegion(
      cursor: showControls || hasError
          ? MouseCursor.defer
          : SystemMouseCursors.none,
      onHover: (_) => _poke(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const Key('player-surface'),
            behavior: HitTestBehavior.opaque,
            onTap: hasError ? null : _playOrPause,
            child: engine is VideoSurfaceProvider
                ? (engine as VideoSurfaceProvider).buildVideoSurface(context)
                : const ColoredBox(color: Colors.black),
          ),
          if (loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(key: Key('player-loading')),
                  if (state.duration <= Duration.zero) ...[
                    const SizedBox(height: 16),
                    const Text('Cargando…'),
                  ],
                ],
              ),
            ),
          if (_osd != null)
            Positioned(
              top: 72,
              right: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(_osd!, key: const Key('player-osd')),
                ),
              ),
            ),
          IgnorePointer(
            ignoring: !showControls,
            child: AnimatedOpacity(
              key: const Key('player-controls'),
              opacity: showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: PlayerControls(
                state: state,
                title: widget.title,
                dragValue: _dragValue,
                onBack: _back,
                onPlayOrPause: _playOrPause,
                onSeekChanged: (v) => setState(() => _dragValue = v),
                onSeekEnd: (v) {
                  setState(() => _dragValue = null);
                  unawaited(_engine.seek(Duration(milliseconds: v.round())));
                  _poke();
                },
                onVolumeChanged: _changeVolume,
                onToggleMute: _toggleMute,
                onSelectAudio: (t) => unawaited(_engine.setAudioTrack(t)),
                onSelectSubtitle: (t) => unawaited(_engine.setSubtitleTrack(t)),
                onMenuOpened: _menuOpened,
                onMenuClosed: _menuClosed,
              ),
            ),
          ),
          if (hasError)
            _ErrorOverlay(
              message: state.error!,
              onRetry: _retry,
              onBack: _back,
            ),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const Key('player-error'),
      color: Colors.black87,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                'No se pudo reproducir el video',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(onPressed: onBack, child: const Text('Volver')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
