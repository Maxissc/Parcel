import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/diagnostics/diag_log.dart';
import '../../app/router.dart';
import '../../data/browse_providers.dart';
import '../../data/platform.dart';
import '../../data/playback_providers.dart';
import '../../data/providers.dart';
import '../../shared/state_views.dart';
import '../streams/streams_args.dart';
import 'play_args.dart';
import 'addon_subtitles.dart';
import 'loading_view.dart';
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
  late final FullScreenOwners _fullScreen;
  late final ContentSubtitles _content;
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
    _fullScreen = ref.read(fullScreenOwnersProvider);
    _diag = ref.read(diagLogProvider);
    _content = newContentSubtitles(ref, _cancel.future);
    _resume = _args.resume;
    unawaited(
      _fullScreen.acquire(
        fullScreen: ref.read(appSettingsProvider).openFullScreen,
      ),
    );
    if (ref.read(diagnosticsConfigProvider)?.cycleFullscreen ?? false) {
      unawaited(_diagFullscreenCycle());
    }
    if (ref.read(diagnosticsConfigProvider)?.autoNext ?? false) {
      unawaited(_diagFullscreenState());
    }
    final chosen = _args.chosen;
    if (chosen != null) {
      _auto = false;
      _candidates = _args.candidates.isEmpty ? [chosen] : _args.candidates;
    } else {
      _diag.log('autoplay: buscando la mejor fuente');
    }
    // Nada que cambie el estado corre dentro de `initState`: la pregunta de
    // continuar, la elección de la fuente y el primer aviso del proveedor
    // esperan al primer cuadro.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_resolveResume());
      if (chosen != null) {
        unawaited(_playWhenResumeKnown(chosen));
      } else {
        _streamsSub = ref.listenManual(
          streamsProvider(_args.key),
          _onStreams,
          fireImmediately: true,
        );
      }
    });
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

  /// Diagnóstico: entra y sale de pantalla completa de verdad y cuenta en qué
  /// estado queda la ventana, también al cerrar el reproductor.
  Future<void> _diagFullscreenCycle() async {
    final window = _window;
    final diag = _diag;
    Future<void> report(String when) async => diag.log(
      'pantalla completa $when: ${await window.isFullScreen() ? 'sí' : 'no'}',
    );
    Future<void> pause(int ms) =>
        Future<void>.delayed(Duration(milliseconds: ms));
    await pause(9000);
    if (!mounted) return;
    await report('con el video andando');
    await window.setFullScreen(false);
    await pause(1200);
    await report('después de salir');
    await window.setFullScreen(true);
    await pause(1200);
    await report('después de volver a entrar');
    if (!mounted) return;
    _leave();
    await pause(1500);
    await report('con el reproductor cerrado');
  }

  /// Diagnóstico: a los 4 s de abrir anota si la ventana está en pantalla
  /// completa (para comprobar que «siguiente episodio» no la saca).
  Future<void> _diagFullscreenState() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    _diag.log(
      'pantalla completa con ${_args.video?.id ?? _args.meta.id}: '
      '${await _window.isFullScreen() ? 'sí' : 'no'}',
    );
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
    unawaited(_fullScreen.release());
    _content.dispose();
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
    // Las que no están ni elegidas ni entre las alternativas fallaron la
    // prueba (o son las que no se probaron porque ya había una buena).
    _diag.log(
      'autoplay: elegida la fuente de ${result.$1.addonName} '
      '(${result.$3} pruebas, ${ready.length - 1 - _queue.length} '
      'descartadas por no responder)',
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
    // Estado terminal: ni el proveedor ni la gracia vuelven a elegir.
    _selecting = true;
    _grace?.cancel();
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
      // El mismo contenido comparte catálogo (y lo ya analizado) entre todos
      // los intentos de fuente.
      content: _content,
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

/// «Buscando la mejor fuente…» sobre el fondo del contenido, con el logo
/// respirando.
class _SearchingView extends StatelessWidget {
  const _SearchingView({
    required this.meta,
    required this.notice,
    required this.onBack,
  });

  final Meta meta;

  /// Si hay, se está probando otra fuente.
  final String? notice;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onBack},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: PlayerLoadingView(
            key: const Key('play-searching'),
            art: LoadingArt.fromMeta(meta),
            status: notice == null
                ? 'Buscando la mejor fuente…'
                : 'Probando otra fuente…',
            onBack: onBack,
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
