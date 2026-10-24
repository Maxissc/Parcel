import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/diagnostics/diag_log.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/browse_providers.dart';
import '../../data/platform.dart';
import '../../data/playback_providers.dart';
import '../../data/providers.dart';
import '../../shared/remote_image.dart';
import '../../shared/state_views.dart';
import '../streams/streams_args.dart';
import 'play_args.dart';
import 'play_item.dart';
import 'player_route.dart';
import 'source_candidates.dart';
import 'source_menu.dart';

enum _Phase { searching, playing, exhausted }

/// Ruta `/play`: busca los streams, elige sola el que anda (probando los
/// mejores) y abre el reproductor. Si el reproductor no logra abrirlo, pasa a
/// la siguiente alternativa. Mientras busca muestra una pantalla de carga
/// sobre el fondo del contenido.
class PlayRoute extends ConsumerStatefulWidget {
  const PlayRoute({super.key, required this.args});

  final PlayArgs args;

  /// Cuánto se espera, desde que aparece el primer stream reproducible, a que
  /// respondan los addons que faltan.
  static const Duration streamsGrace = Duration(seconds: 3);

  @override
  ConsumerState<PlayRoute> createState() => _PlayRouteState();
}

class _PlayRouteState extends ConsumerState<PlayRoute> {
  late final WindowService _window;
  late final DiagLog _diag;
  final Completer<void> _cancel = Completer<void>();
  final Completer<void> _resumeAnswered = Completer<void>();
  ProviderSubscription<AsyncValue<StreamsState>>? _streamsSub;
  Timer? _grace;

  _Phase _phase = _Phase.searching;
  String? _notice;
  bool _onlyUncached = false;
  bool _selecting = false;
  bool _auto = true;
  int _attempt = 0;
  ResumeMode _resume = ResumeMode.ask;
  Duration? _startAt;
  SourceCandidate? _current;
  List<SourceCandidate> _candidates = const [];
  List<SourceCandidate> _queue = const [];
  StreamsState? _latest;

  PlayArgs get _args => widget.args;

  @override
  void initState() {
    super.initState();
    _window = ref.read(windowServiceProvider);
    _diag = ref.read(diagLogProvider);
    _resume = _args.resume;
    unawaited(
      _window.setFullScreen(ref.read(appSettingsProvider).openFullScreen),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolveResume());
    });
    final chosen = _args.chosen;
    if (chosen != null) {
      _auto = false;
      _candidates = _args.candidates.isEmpty ? [chosen] : _args.candidates;
      unawaited(_playWhenResumeKnown(chosen));
    } else {
      _diag.log('autoplay: buscando la mejor fuente');
      _streamsSub = ref.listenManual(
        streamsProvider(_args.key),
        _onStreams,
        fireImmediately: true,
      );
    }
  }

  /// Si el video ya se había empezado, pregunta antes de seguir (mientras la
  /// búsqueda corre por detrás).
  Future<void> _resolveResume() async {
    if (_resume != ResumeMode.ask) {
      _resumeAnswered.complete();
      return;
    }
    final item = _args;
    final saved = ref
        .read(progressRepositoryProvider)
        .get(item.meta.type, item.meta.id, item.videoId);
    if (saved == null || !saved.isInProgress) {
      _resume = ResumeMode.fromStart;
      _resumeAnswered.complete();
      return;
    }
    final choice = await askResume(context, saved);
    if (!mounted) return;
    if (choice == null) {
      _leave();
      return;
    }
    _resume = choice ? ResumeMode.resume : ResumeMode.fromStart;
    _resumeAnswered.complete();
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  @override
  void dispose() {
    if (!_cancel.isCompleted) _cancel.complete();
    _grace?.cancel();
    _streamsSub?.close();
    unawaited(_window.setFullScreen(false));
    super.dispose();
  }

  // --- Búsqueda ------------------------------------------------------------

  List<SourceCandidate> _rank(StreamsState state) {
    final settings = ref.read(appSettingsProvider);
    return rankCandidates(
      state.groups,
      quality: settings.quality,
      preferAddonUrl: _args.preferAddonUrl,
      preferBingeGroup: _args.preferBingeGroup,
    );
  }

  void _onStreams(
    AsyncValue<StreamsState>? previous,
    AsyncValue<StreamsState> next,
  ) {
    if (_selecting || !mounted) return;
    if (next.hasError) {
      _exhaust();
      return;
    }
    final state = next.value;
    if (state == null) return;
    _latest = state;
    if (!state.loading) {
      unawaited(_selectFromLatest());
    } else if (_grace == null && _rank(state).any((c) => c.isReady)) {
      _grace = Timer(
        PlayRoute.streamsGrace,
        () => unawaited(_selectFromLatest()),
      );
    }
  }

  Future<void> _selectFromLatest() async {
    if (_selecting || !mounted) return;
    final state = _latest;
    if (state == null) return;
    _selecting = true;
    _grace?.cancel();
    final ranked = _rank(state);
    final ready = ranked.where((c) => c.isReady).toList();
    _candidates = ranked;
    _diag.log(
      'autoplay: ${state.groups.length} addons, ${ranked.length} fuentes '
      '(${ready.length} listas)',
    );
    if (ready.isEmpty) {
      _onlyUncached = ranked.isNotEmpty;
      _exhaust();
      return;
    }
    final result = await _probe(ready);
    if (!mounted) return;
    if (result == null) {
      _exhaust();
      return;
    }
    _queue = result.$2;
    _diag.log(
      'autoplay: elegida la fuente de ${result.$1.addonName} '
      '(${result.$3} pruebas)',
    );
    await _resumeAnswered.future;
    _play(result.$1);
  }

  /// Prueba [candidates] (solo los cacheados o sin datos de caché) y devuelve
  /// el elegido, las alternativas que quedan y cuántas pruebas hizo.
  Future<(SourceCandidate, List<SourceCandidate>, int)?> _probe(
    List<SourceCandidate> candidates,
  ) async {
    final byStream = Map<AddonStream, SourceCandidate>.identity();
    for (final c in candidates) {
      byStream[c.stream] = c;
    }
    final selection = await ref.read(autoStreamSelectorProvider).select([
      for (final c in candidates) c.stream,
    ], cancel: _cancel.future);
    final chosen = selection.chosen;
    if (selection.cancelled || chosen == null) return null;
    return (
      byStream[chosen]!,
      [
        for (final s in selection.alternatives)
          if (byStream[s]!.isReady) byStream[s]!,
      ],
      selection.attempts,
    );
  }

  void _exhaust() {
    if (!mounted) return;
    _diag.log('autoplay: no hay una fuente que ande');
    setState(() => _phase = _Phase.exhausted);
  }

  // --- Reproducción ---------------------------------------------------------

  Future<void> _playWhenResumeKnown(SourceCandidate candidate) async {
    await _resumeAnswered.future;
    if (mounted) _play(candidate);
  }

  void _play(SourceCandidate candidate, {Duration? startAt}) {
    if (!mounted) return;
    setState(() {
      _current = candidate;
      _startAt = startAt;
      _attempt++;
      _notice = null;
      _phase = _Phase.playing;
    });
  }

  Future<void> _onOpenFailed() async {
    if (!mounted || _phase != _Phase.playing) return;
    _diag.log(
      'autoplay: la fuente de ${_current?.addonName} no abrió; probando otra',
    );
    setState(() {
      _phase = _Phase.searching;
      _notice = 'Esa fuente no anduvo, probando otra…';
    });
    final result = _queue.isEmpty ? null : await _probe(_queue);
    if (!mounted) return;
    if (result == null) {
      _exhaust();
      return;
    }
    _queue = result.$2;
    _diag.log('autoplay: ahora la fuente de ${result.$1.addonName}');
    _play(result.$1);
  }

  void _pick(int index, Duration position) {
    _auto = false;
    _diag.log('autoplay: el usuario eligió otra fuente');
    _play(_candidates[index], startAt: position);
  }

  void _toManual() {
    final args = _args;
    final router = GoRouter.of(context);
    unawaited(
      router.pushReplacement(
        Routes.streams,
        extra: StreamsArgs(
          meta: args.meta,
          video: args.video,
          resume: _resume == ResumeMode.ask ? args.resume : _resume,
          preferAddonUrl: args.preferAddonUrl,
          preferBingeGroup: args.preferBingeGroup,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.searching => _SearchingView(
        meta: _args.meta,
        notice: _notice,
        onBack: _leave,
      ),
      _Phase.exhausted => _ExhaustedView(
        onlyUncached: _onlyUncached,
        onManual: _toManual,
        onBack: _leave,
      ),
      _Phase.playing => _buildPlayer(),
    };
  }

  Widget _buildPlayer() {
    final candidate = _current!;
    final args = _args;
    final index = _candidates.indexWhere(
      (c) => identical(c.stream, candidate.stream),
    );
    return PlayerRoute(
      key: ValueKey(_attempt),
      manageWindow: false,
      popBeforeNext: args.fromStreams,
      onOpenFailed: _auto ? () => unawaited(_onOpenFailed()) : null,
      sourceMenu: index < 0 || _candidates.length < 2
          ? null
          : SourceMenu(candidates: _candidates, current: index, onPick: _pick),
      args: PlayerArgs(
        url: candidate.stream.url!,
        headers: candidate.stream.behaviorHints.proxyRequestHeaders,
        resume: _resume == ResumeMode.ask ? ResumeMode.fromStart : _resume,
        startAt: _startAt,
        item: PlayItem(
          meta: args.meta,
          video: args.video,
          stream: candidate.stream,
          addonUrl: candidate.addonUrl,
          addonName: candidate.addonName,
        ),
      ),
    );
  }
}

/// «Buscando la mejor fuente…» sobre el fondo del contenido.
class _SearchingView extends StatelessWidget {
  const _SearchingView({
    required this.meta,
    required this.notice,
    required this.onBack,
  });

  final Meta meta;
  final String? notice;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onBack},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              RemoteImage(meta.background ?? meta.poster, width: 1280),
              ColoredBox(color: Colors.black.withValues(alpha: 0.75)),
              Positioned(
                top: Spacing.md,
                left: Spacing.md,
                child: SafeArea(
                  child: IconButton.filledTonal(
                    tooltip: 'Volver (Esc)',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onBack,
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(key: Key('play-searching')),
                    const SizedBox(height: Spacing.md),
                    Text(
                      meta.name,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.sm),
                    const Text('Buscando la mejor fuente…'),
                    if (notice != null) ...[
                      const SizedBox(height: Spacing.sm),
                      Text(
                        notice!,
                        key: const Key('play-notice'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExhaustedView extends StatelessWidget {
  const _ExhaustedView({
    required this.onlyUncached,
    required this.onManual,
    required this.onBack,
  });

  final bool onlyUncached;
  final VoidCallback onManual;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onBack},
      child: Scaffold(
        body: EmptyState(
          icon: Icons.sentiment_dissatisfied_outlined,
          title: onlyUncached
              ? 'No encontramos una fuente lista'
              : 'No encontramos una fuente que funcione',
          message: onlyUncached
              ? 'Las que hay todavía las tiene que descargar el debrid y '
                    'pueden tardar en empezar. Podés elegir una a mano.'
              : 'Ninguna de las fuentes respondió bien. Podés elegir una a '
                    'mano o probar más tarde.',
          actions: [
            FilledButton(
              key: const Key('play-manual'),
              autofocus: true,
              onPressed: onManual,
              child: const Text('Elegir a mano'),
            ),
            TextButton(onPressed: onBack, child: const Text('Volver')),
          ],
        ),
      ),
    );
  }
}
