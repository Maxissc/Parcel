import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/diagnostics/diag_log.dart';
import '../../app/diagnostics/playback_diagnostics.dart';
import '../../app/router.dart';
import '../../data/platform.dart';
import '../../data/playback_providers.dart';
import '../../data/progress_providers.dart';
import '../../data/providers.dart';
import '../../playback/playback_errors.dart';
import '../streams/streams_args.dart';
import 'addon_subtitles.dart';
import 'play_args.dart';
import 'play_item.dart';
import 'player_info.dart';
import 'player_screen.dart';
import 'source_menu.dart';
import 'subtitle_catalog.dart';
import 'track_preferences.dart';

/// Qué reproducir en la ruta `/player`.
class PlayerArgs {
  const PlayerArgs({
    required this.url,
    this.subtitleUrl,
    this.title,
    this.headers = const {},
    this.item,
    this.resume = ResumeMode.ask,
    this.startAt,
  });

  final String url;
  final String? subtitleUrl;
  final String? title;

  /// Headers HTTP para pedir [url] (`proxyRequestHeaders` del stream).
  final Map<String, String> headers;

  /// Qué es lo que se reproduce. Con esto el reproductor guarda el progreso,
  /// busca subtítulos en los addons y ofrece el episodio siguiente; sin esto
  /// (una URL de prueba) no hace nada de eso.
  final PlayItem? item;
  final ResumeMode resume;

  /// Desde dónde arrancar, si ya se sabe (por ejemplo, al cambiar de fuente a
  /// mitad del video). Gana sobre [resume].
  final Duration? startAt;
}

/// Pregunta «Continuar desde…» o «Desde el principio». Devuelve `true` para
/// continuar, `false` para empezar de cero y `null` si el usuario se arrepintió
/// (Esc).
Future<bool?> askResume(BuildContext context, PlaybackProgress saved) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => CallbackShortcuts(
      // Esc es «volver»: cierra la pregunta y el reproductor, sin reproducir.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        title: const Text('Ya empezaste esto'),
        content: Text(
          'Lo dejaste en ${formatPlaybackTime(saved.position)} de '
          '${formatPlaybackTime(saved.duration)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Desde el principio'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Continuar desde ${formatPlaybackTime(saved.position)}',
            ),
          ),
        ],
      ),
    ),
  );
}

/// Ruta del reproductor: crea el motor, pone la ventana en pantalla completa
/// (si el ajuste lo pide) mientras dura y arma el diagnóstico si está activo.
/// Si el video ya se había empezado, antes pregunta si continuar.
///
/// Dentro de la ruta `/play` la maneja [PlayRoute] (que elige y cambia de
/// fuente): le pasa [sourceMenu] y [onOpenFailed] y se queda con la ventana
/// ([manageWindow] en `false`).
class PlayerRoute extends ConsumerStatefulWidget {
  const PlayerRoute({
    super.key,
    required this.args,
    this.sourceMenu,
    this.onOpenFailed,
    this.manageWindow = true,
    this.popBeforeNext = true,
    this.content,
  });

  final PlayerArgs args;
  final SourceMenu? sourceMenu;
  final VoidCallback? onOpenFailed;
  final bool manageWindow;

  /// Los subtítulos del contenido, si quien llama los comparte entre varios
  /// intentos (y se ocupa de cerrarlos). Sin esto la ruta arma los suyos.
  final ContentSubtitles? content;

  /// Al pasar al episodio que sigue, primero cierra esta ruta (porque debajo
  /// está la pantalla de streams del episodio anterior, que se reemplaza).
  final bool popBeforeNext;

  @override
  ConsumerState<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends ConsumerState<PlayerRoute> {
  late final PlaybackEngine _engine;
  late final WindowService _window;
  late final FullScreenOwners _fullScreen;
  ContentSubtitles? _ownContent;
  Completer<void>? _cancelSubtitles;
  late final ProgressSaver _saver;
  late final DiagLog _diag;
  late final ActivePlayer _active;
  late final Map<String, Duration> _delays;
  Future<List<Subtitle>>? _addonSubtitles;
  SubtitleCatalog? _catalog;
  TrackPreferences? _preferences;
  List<Duration> _syncTaps = const [];
  Timer? _statsLog;

  /// Desde dónde arranca; `null` mientras se espera la respuesta del usuario.
  Duration? _start;
  bool _screenBuilt = false;

  PlayerArgs get _args => widget.args;

  @override
  void initState() {
    super.initState();
    _window = ref.read(windowServiceProvider);
    _fullScreen = ref.read(fullScreenOwnersProvider);
    _saver = ref.read(progressSaverProvider);
    _diag = ref.read(diagLogProvider);
    _delays = ref.read(subtitleDelaysProvider);
    _active = ref.read(activePlayerProvider)..register(_saveNow);
    _engine = ref.read(playbackEngineFactoryProvider)();
    final diag = ref.read(diagnosticsConfigProvider);
    if (diag != null) {
      final d = PlaybackDiagnostics(_engine, config: diag)..start();
      if (diag.cycleTracks) d.cycleTracks();
      _syncTaps = diag.syncTaps;
    }
    if (_diag.enabled) {
      // Cada 5 s, los datos técnicos del video (sin URLs).
      _statsLog = Timer.periodic(const Duration(seconds: 5), (_) {
        final s = _engine.stats;
        final st = _engine.state;
        _diag.log(
          'stats: ${s.videoWidth ?? '?'}x${s.videoHeight ?? '?'} '
          '${s.fps?.toStringAsFixed(2) ?? '?'} fps '
          'video=${s.videoCodec ?? '?'} audio=${s.audioCodec ?? '?'} '
          '${s.audioChannels ?? '?'} canales ${s.dynamicRange.name} '
          'hw=${s.hardwareDecoder ?? 'no'} '
          'bitrate=${s.videoBitrate ?? '?'} '
          'buffer adelante=${s.bufferAhead.inSeconds} s '
          'atrás=${s.bufferBehind.inSeconds} s '
          'caché=${s.cacheLevel ?? '?'} '
          'pos=${formatPlaybackTime(st.position)}',
        );
      });
    }
    final settings = ref.read(appSettingsProvider);
    if (widget.manageWindow) {
      unawaited(_fullScreen.acquire(fullScreen: settings.openFullScreen));
    }
    final title = _args.item?.title ?? _args.title;
    if (title != null) unawaited(_window.setTitle('$title · $appName'));

    final item = _args.item;
    if (item != null) {
      _preferences = TrackPreferences(
        audioLanguage: settings.audioLanguage,
        subtitleLanguage: settings.subtitleLanguage,
        originalLanguage: inferOriginalLanguage(item.meta),
      );
      var content = widget.content;
      if (content == null) {
        final cancel = _cancelSubtitles = Completer<void>();
        content = _ownContent = newContentSubtitles(ref, cancel.future);
      }
      _catalog = content.catalog;
      _addonSubtitles = content.forItem(item);
    }

    final saved = _savedProgress();
    if (_args.startAt != null) {
      _start = _args.startAt;
    } else if (_args.resume == ResumeMode.fromStart) {
      _start = Duration.zero;
    } else if (saved == null) {
      _start = Duration.zero;
    } else if (_args.resume == ResumeMode.resume) {
      _start = saved.position;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_askResume(saved));
      });
    }
  }

  /// El progreso guardado de este video, si quedó a medias.
  PlaybackProgress? _savedProgress() {
    final item = _args.item;
    if (item == null) return null;
    final saved = ref
        .read(progressRepositoryProvider)
        .get(item.type, item.meta.id, item.videoId);
    return saved != null && saved.isInProgress ? saved : null;
  }

  Future<void> _askResume(PlaybackProgress saved) async {
    final choice = await askResume(context, saved);
    if (!mounted) return;
    if (choice == null) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.home);
      }
      return;
    }
    setState(() => _start = choice ? saved.position : Duration.zero);
  }

  @override
  void dispose() {
    _statsLog?.cancel();
    _active.unregister(_saveNow);
    if (widget.manageWindow) unawaited(_fullScreen.release());
    unawaited(_window.setTitle(appName));
    if (_cancelSubtitles?.isCompleted == false) _cancelSubtitles!.complete();
    _ownContent?.dispose();
    // Si nunca se llegó a armar la pantalla, el motor sigue siendo de la ruta.
    if (!_screenBuilt) unawaited(_engine.dispose());
    super.dispose();
  }

  /// Guarda dónde va el video ahora (al cerrar la ventana). Con las mismas
  /// reglas que la pantalla: sin error, con duración y pasados unos segundos.
  void _saveNow() {
    if (!_screenBuilt) return;
    final s = _engine.state;
    if (s.error != null || s.duration <= Duration.zero) return;
    if (s.position < PlayerScreen.minProgress) return;
    _saveProgress(s.position, s.duration);
  }

  void _saveProgress(Duration position, Duration duration) {
    final item = _args.item;
    if (item == null) return;
    final progress = PlaybackProgress(
      type: item.type,
      metaId: item.meta.id,
      videoId: item.videoId,
      position: position,
      duration: duration,
      name: item.meta.name,
      poster: item.meta.poster,
      updatedAt: DateTime.now(),
    );
    unawaited(_write(progress));
    _diag.log(
      'progreso guardado: ${item.title} '
      '${formatPlaybackTime(position)} / ${formatPlaybackTime(duration)}',
    );
  }

  /// Guarda en disco. Si falla (disco lleno, sin permisos) no rompe la
  /// reproducción: queda anotado en el diagnóstico y se vuelve a intentar con
  /// el próximo guardado.
  Future<void> _write(PlaybackProgress progress) async {
    try {
      await _saver.save(progress);
    } on Object catch (e) {
      _diag.log('progreso no guardado: ${e.runtimeType}');
    }
  }

  NextEpisode? _nextEpisode() {
    final item = _args.item;
    final next = item?.nextEpisode;
    if (item == null || next == null) return null;
    final tag = episodeTagOf(next);
    final label = [
      ?tag,
      if (next.title.trim().isNotEmpty) next.title.trim(),
    ].join(' · ');
    return NextEpisode(
      label: label.isEmpty ? 'Siguiente episodio' : label,
      onOpen: (context) {
        final router = GoRouter.of(context);
        final auto = ref.read(appSettingsProvider).autoSelectSource;
        // Cierra el reproductor y cambia la pantalla anterior (la lista de
        // streams del episodio que terminó) por la del que sigue.
        if (widget.popBeforeNext) router.pop();
        unawaited(
          auto
              ? router.pushReplacement(
                  Routes.play,
                  extra: PlayArgs(
                    meta: item.meta,
                    video: next,
                    preferAddonUrl: item.addonUrl,
                    preferBingeGroup: item.stream.behaviorHints.bingeGroup,
                  ),
                )
              : router.pushReplacement(
                  Routes.streams,
                  extra: StreamsArgs(
                    meta: item.meta,
                    video: next,
                    preferAddonUrl: item.addonUrl,
                    preferBingeGroup: item.stream.behaviorHints.bingeGroup,
                  ),
                ),
        );
      },
    );
  }

  PlayerInfo? _info() {
    final item = _args.item;
    if (item == null) return null;
    final meta = item.meta;
    final year = meta.releaseInfo ?? meta.released?.year.toString();
    final name = item.stream.name
        ?.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join(' · ');
    return PlayerInfo(
      addonName: item.addonName,
      streamName: name == null ? null : redactUrlsInText(name),
      imdbRating: meta.imdbRating,
      year: year,
      runtime: meta.runtime,
      genres: meta.genres,
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    if (start == null) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    _screenBuilt = true;
    final args = _args;
    final item = args.item;
    final delayKey = item == null ? null : '${item.type}:${item.videoId}';
    return PlayerScreen(
      engine: _engine,
      source: PlaybackSource(
        url: args.url,
        headers: args.headers,
        startPosition: start,
      ),
      title: item?.title ?? args.title,
      subtitles: [
        if (args.subtitleUrl != null)
          Subtitle(
            id: args.subtitleUrl!,
            url: args.subtitleUrl!,
            lang: 'und',
            label: 'Subtítulo externo',
          ),
      ],
      lateSubtitles: _addonSubtitles,
      catalog: _catalog,
      preferences: _preferences,
      window: _window,
      onProgress: item == null ? null : _saveProgress,
      next: _nextEpisode(),
      info: _info(),
      sourceMenu: widget.sourceMenu,
      onOpenFailed: widget.onOpenFailed,
      initialSubtitleDelay: _delays[delayKey] ?? Duration.zero,
      onSubtitleDelayChanged: delayKey == null
          ? null
          : (d) => _delays[delayKey] = d,
      onDecision: (message) => _diag.log('reproductor: $message'),
      syncTaps: _syncTaps,
      autoOpenNext: ref.read(diagnosticsConfigProvider)?.autoNext ?? false,
    );
  }
}
