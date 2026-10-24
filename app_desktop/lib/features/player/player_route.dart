import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/diagnostics/diag_log.dart';
import '../../app/diagnostics/playback_diagnostics.dart';
import '../../app/router.dart';
import '../../data/platform.dart';
import '../../data/progress_providers.dart';
import '../../data/providers.dart';
import '../streams/streams_args.dart';
import 'addon_subtitles.dart';
import 'play_item.dart';
import 'player_screen.dart';
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
}

/// Ruta del reproductor: crea el motor, pone la ventana en pantalla completa
/// mientras dura y arma el diagnóstico si está activo. Si el video ya se había
/// empezado, antes pregunta si continuar.
class PlayerRoute extends ConsumerStatefulWidget {
  const PlayerRoute({super.key, required this.args});

  final PlayerArgs args;

  @override
  ConsumerState<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends ConsumerState<PlayerRoute> {
  late final PlaybackEngine _engine;
  late final WindowService _window;
  late final ProgressSaver _saver;
  late final DiagLog _diag;
  Future<List<Subtitle>>? _addonSubtitles;
  TrackPreferences? _preferences;

  /// Desde dónde arranca; `null` mientras se espera la respuesta del usuario.
  Duration? _start;
  bool _screenBuilt = false;

  PlayerArgs get _args => widget.args;

  @override
  void initState() {
    super.initState();
    _window = ref.read(windowServiceProvider);
    _saver = ref.read(progressSaverProvider);
    _diag = ref.read(diagLogProvider);
    _engine = ref.read(playbackEngineFactoryProvider)();
    final diag = ref.read(diagnosticsConfigProvider);
    if (diag != null) {
      final d = PlaybackDiagnostics(_engine, config: diag)..start();
      if (diag.cycleTracks) d.cycleTracks();
    }
    _window.setFullScreen(true);
    final title = _args.item?.title ?? _args.title;
    if (title != null) unawaited(_window.setTitle('$title · $appName'));

    final item = _args.item;
    if (item != null) {
      final settings = ref.read(appSettingsProvider);
      _preferences = TrackPreferences(
        audioLanguage: settings.audioLanguage,
        subtitleLanguage: settings.subtitleLanguage,
      );
      _addonSubtitles = fetchAddonSubtitles(
        ref.read(addonAggregatorProvider),
        item,
        preferredLanguage: settings.subtitleLanguage,
      );
    }

    final saved = _savedProgress();
    if (saved == null) {
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
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
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
    );
    if (!mounted) return;
    setState(() => _start = choice == true ? saved.position : Duration.zero);
  }

  @override
  void dispose() {
    _window.setFullScreen(false);
    unawaited(_window.setTitle(appName));
    // Si nunca se llegó a armar la pantalla, el motor sigue siendo de la ruta.
    if (!_screenBuilt) unawaited(_engine.dispose());
    super.dispose();
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
    unawaited(_saver.save(progress));
    _diag.log(
      'progreso guardado: ${item.title} '
      '${formatPlaybackTime(position)} / ${formatPlaybackTime(duration)}',
    );
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
        // Cierra el reproductor y cambia la lista de streams anterior por la
        // del episodio que sigue.
        router.pop();
        unawaited(
          router.pushReplacement(
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

  @override
  Widget build(BuildContext context) {
    final start = _start;
    if (start == null) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    _screenBuilt = true;
    final args = _args;
    return PlayerScreen(
      engine: _engine,
      source: PlaybackSource(
        url: args.url,
        headers: args.headers,
        startPosition: start,
      ),
      title: args.item?.title ?? args.title,
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
      preferences: _preferences,
      window: _window,
      onProgress: args.item == null ? null : _saveProgress,
      next: _nextEpisode(),
    );
  }
}
