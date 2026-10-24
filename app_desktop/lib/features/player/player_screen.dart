import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import '../../data/platform.dart';
import '../../playback/playback_errors.dart';
import '../../playback/video_surface.dart';
import 'player_controls.dart';
import 'track_preferences.dart';

/// El episodio que sigue, para ofrecerlo al terminar el actual.
class NextEpisode {
  const NextEpisode({required this.label, required this.onOpen});

  /// Por ejemplo «T1 E4 · Título».
  final String label;
  final void Function(BuildContext context) onOpen;
}

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
    this.lateSubtitles,
    this.preferences,
    this.window,
    this.onProgress,
    this.next,
    this.title,
    this.disposeEngine = true,
  });

  final PlaybackEngine engine;
  final PlaybackSource source;

  /// Subtítulos externos que se cargan al abrir. Si hay más de uno queda
  /// elegido el último.
  final List<Subtitle> subtitles;

  /// Subtítulos que llegan después (de los addons): se suman cuando el video
  /// ya está andando.
  final Future<List<Subtitle>>? lateSubtitles;

  /// Idiomas preferidos para elegir pistas solo al abrir. Con `null` no se
  /// toca la elección del motor.
  final TrackPreferences? preferences;

  /// Para pantalla completa (tecla F, doble clic, Esc). Con `null` no hay.
  final WindowService? window;

  /// Se llama con la posición y la duración cada 10 s, al pausar, al terminar
  /// y al salir. Con `null` no se guarda progreso.
  final void Function(Duration position, Duration duration)? onProgress;

  /// Si hay, al terminar el video se ofrece pasar al episodio que sigue.
  final NextEpisode? next;
  final String? title;

  /// Si es `true`, libera [engine] al cerrar la pantalla.
  final bool disposeEngine;

  /// Segundos sin mover el mouse hasta que se ocultan los controles.
  static const Duration hideAfter = Duration(seconds: 3);

  /// Cada cuánto se guarda el progreso mientras se reproduce.
  static const Duration progressEvery = Duration(seconds: 10);

  /// Antes de este punto no se guarda progreso: abrir y salir enseguida no
  /// tiene que pisar lo que ya se había visto.
  static const Duration minProgress = Duration(seconds: 5);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _seekStep = Duration(seconds: 10);
  static const _volumeStep = 0.05;
  static const _doubleTap = Duration(milliseconds: 300);
  static const _subtitleDelay = Duration(seconds: 2);

  final FocusNode _focus = FocusNode(debugLabel: 'player');
  Timer? _hideTimer;
  Timer? _osdTimer;
  Timer? _progressTimer;
  Timer? _tapTimer;
  StreamSubscription<PlaybackState>? _stateSub;
  bool _controlsVisible = true;
  bool _menuOpen = false;
  bool _fullScreen = false;
  bool _wasPlaying = false;
  bool _wasCompleted = false;
  bool _nextDismissed = false;
  bool _userPickedAudio = false;
  bool _userPickedSubtitle = false;
  double? _dragValue;
  double _volumeBeforeMute = 0.5;
  String? _osd;

  PlaybackEngine get _engine => widget.engine;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
    _stateSub = _engine.stream.listen(_onEngineState);
    if (widget.onProgress != null) {
      _progressTimer = Timer.periodic(
        PlayerScreen.progressEvery,
        (_) => _reportProgress(onlyIfPlaying: true),
      );
    }
    unawaited(_syncFullScreen());
    unawaited(_start(widget.source));
  }

  @override
  void dispose() {
    _reportProgress();
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _progressTimer?.cancel();
    _tapTimer?.cancel();
    unawaited(_stateSub?.cancel());
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
    await _applyPreferences();
    await _addLateSubtitles();
  }

  // --- Pistas ----------------------------------------------------------------

  /// Espera a que el motor informe las pistas del archivo (llegan un rato
  /// después de abrirlo).
  Future<void> _waitForTracks() async {
    if (_engine.state.audioTracks.isNotEmpty) return;
    try {
      await _engine.stream
          .firstWhere((s) => s.audioTracks.isNotEmpty || s.error != null)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Un video sin audio informable: se sigue con lo que haya.
    } on StateError {
      // El motor se cerró.
    }
  }

  /// Elige audio y subtítulos según los idiomas preferidos, una sola vez.
  Future<void> _applyPreferences() async {
    final prefs = widget.preferences;
    if (prefs == null) return;
    await _waitForTracks();
    if (!mounted) return;
    final audio = prefs.pickAudio(_engine.state.audioTracks);
    if (!_userPickedAudio &&
        audio != null &&
        audio != _engine.state.selectedAudio) {
      await _engine.setAudioTrack(audio);
    }
    await _chooseSubtitle(fallback: _embeddedSelection());
  }

  /// La pista de subtítulos elegida si es del archivo; una externa cargada por
  /// nosotros no cuenta como elección del usuario.
  SubtitleTrack? _embeddedSelection() {
    final selected = _engine.state.selectedSubtitle;
    return selected != null && !selected.isExternal ? selected : null;
  }

  /// Deja puesta la pista del idioma preferido o, si no hay, [fallback]
  /// (`null` es sin subtítulos). Si el usuario ya eligió una, la respeta.
  Future<void> _chooseSubtitle({required SubtitleTrack? fallback}) async {
    final state = _engine.state;
    final target = _userPickedSubtitle
        ? fallback
        : (widget.preferences?.pickSubtitle(state.subtitleTracks) ?? fallback);
    if (target == state.selectedSubtitle) return;
    await _engine.setSubtitleTrack(target);
  }

  /// Espera a que el video avance un par de segundos: cargar un subtítulo por
  /// red frena un instante la reproducción y es mejor que no sea al arrancar.
  Future<void> _waitForPlayback() async {
    final from = _engine.state.position;
    try {
      await _engine.stream
          .firstWhere(
            (s) => s.error != null || s.position - from >= _subtitleDelay,
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // El video no avanza (pausado): se cargan igual.
    } on StateError {
      // El motor se cerró.
    }
  }

  /// Suma los subtítulos de los addons cuando llegan. Cada pista nueva el
  /// motor la elige sola, así que después de cada una se vuelve a la elección
  /// que corresponde.
  Future<void> _addLateSubtitles() async {
    final late = widget.lateSubtitles;
    if (late == null) return;
    final subtitles = await late;
    if (!mounted || subtitles.isEmpty) return;
    await _waitForPlayback();
    if (!mounted) return;
    final before = _userPickedSubtitle
        ? _engine.state.selectedSubtitle
        : _embeddedSelection();
    for (final s in subtitles) {
      if (!mounted) return;
      await _engine.addExternalSubtitle(
        s.url,
        title: s.label ?? s.lang,
        language: s.lang,
      );
      if (!mounted) return;
      await _chooseSubtitle(fallback: before);
    }
  }

  // --- Progreso ----------------------------------------------------------------

  void _onEngineState(PlaybackState s) {
    final paused = _wasPlaying && !s.playing;
    final finished = s.completed && !_wasCompleted;
    _wasPlaying = s.playing;
    _wasCompleted = s.completed;
    if (paused || finished) _reportProgress();
    if (finished && mounted) setState(() => _nextDismissed = false);
  }

  void _reportProgress({bool onlyIfPlaying = false}) {
    final report = widget.onProgress;
    if (report == null) return;
    final s = _engine.state;
    if (onlyIfPlaying && !s.playing) return;
    if (s.error != null || s.duration <= Duration.zero) return;
    if (s.position < PlayerScreen.minProgress) return;
    report(s.position, s.duration);
  }

  // --- Pantalla completa --------------------------------------------------------

  Future<void> _syncFullScreen() async {
    final window = widget.window;
    if (window == null) return;
    final value = await window.isFullScreen();
    if (mounted) setState(() => _fullScreen = value);
  }

  Future<void> _toggleFullScreen() async {
    final window = widget.window;
    if (window == null) return;
    final next = !await window.isFullScreen();
    await window.setFullScreen(next);
    if (mounted) setState(() => _fullScreen = next);
  }

  /// Esc: si la ventana está en pantalla completa sale de ella; si no, vuelve.
  Future<void> _escape() async {
    final window = widget.window;
    if (window != null && await window.isFullScreen()) {
      await window.setFullScreen(false);
      if (mounted) setState(() => _fullScreen = false);
      return;
    }
    if (mounted) _back();
  }

  /// Un clic pausa o reanuda; dos seguidos pasan a pantalla completa (y
  /// deshacen la pausa del primero).
  void _onSurfaceTap() {
    if (widget.window == null) {
      _playOrPause();
      return;
    }
    if (_tapTimer?.isActive ?? false) {
      _tapTimer!.cancel();
      unawaited(_toggleFullScreen());
      _playOrPause();
    } else {
      _playOrPause();
      _tapTimer = Timer(_doubleTap, () {});
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
      unawaited(_escape());
    } else if (key == LogicalKeyboardKey.keyF && !isRepeat) {
      unawaited(_toggleFullScreen());
    } else if (key == LogicalKeyboardKey.enter &&
        !isRepeat &&
        _engine.state.completed &&
        widget.next != null &&
        !_nextDismissed) {
      widget.next!.onOpen(context);
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
            onTap: hasError ? null : _onSurfaceTap,
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
                onSelectAudio: (t) {
                  _userPickedAudio = true;
                  unawaited(_engine.setAudioTrack(t));
                },
                onSelectSubtitle: (t) {
                  _userPickedSubtitle = true;
                  unawaited(_engine.setSubtitleTrack(t));
                },
                onMenuOpened: _menuOpened,
                onMenuClosed: _menuClosed,
                isFullScreen: _fullScreen,
                onToggleFullScreen: widget.window == null
                    ? null
                    : () => unawaited(_toggleFullScreen()),
              ),
            ),
          ),
          if (state.completed && widget.next != null && !_nextDismissed)
            Positioned(
              right: Spacing.lg,
              bottom: 128,
              child: _NextEpisodeCard(
                next: widget.next!,
                onDismiss: () => setState(() => _nextDismissed = true),
              ),
            ),
          if (hasError)
            _ErrorOverlay(
              message: redactUrlsInText(state.error!),
              onRetry: _retry,
              onBack: _back,
            ),
        ],
      ),
    );
  }
}

/// Tarjeta que aparece al terminar un episodio con el que sigue.
class _NextEpisodeCard extends StatelessWidget {
  const _NextEpisodeCard({required this.next, required this.onDismiss});

  final NextEpisode next;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('player-next-card'),
      color: Colors.black.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.sm,
          Spacing.md,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Siguiente episodio',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onDismiss,
                  ),
                ],
              ),
              Text(
                next.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.icon(
                key: const Key('player-next'),
                onPressed: () => next.onOpen(context),
                icon: const Icon(Icons.skip_next),
                label: const Text('Ver siguiente episodio'),
              ),
            ],
          ),
        ),
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
