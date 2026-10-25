import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:parcel_core/parcel_core.dart';

import 'cache_profile.dart';
import 'playback_errors.dart';
import 'playback_stats_reader.dart';
import 'video_surface.dart';

/// [PlaybackEngine] sobre media_kit (libmpv). Es el único lugar que conoce los
/// tipos de media_kit.
class MediaKitPlaybackEngine implements PlaybackEngine, VideoSurfaceProvider {
  MediaKitPlaybackEngine({
    this.loadTimeout = const Duration(seconds: 20),
    this.onLog,
    CacheProfile? cacheProfile,
  }) : cacheProfile = cacheProfile ?? detectCacheProfile() {
    // libass dibuja los subtítulos (ASS con estilos); con eso activo, media_kit
    // no dibuja su capa de subtítulos de Flutter.
    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'Parcel',
        libass: true,
      ),
    );
    // `auto-safe` evita el crash de NVIDIA con H264 de 10 bits (media_kit #1366).
    _video = mkv.VideoController(
      _player,
      configuration: const mkv.VideoControllerConfiguration(hwdec: 'auto-safe'),
    );
    _listen();
  }

  /// Cuánto espera a que cargue el medio antes de cargar un subtítulo externo.
  final Duration loadTimeout;
  final void Function(String message)? onLog;

  /// Caché que se le pide a mpv, según la RAM del equipo.
  final CacheProfile cacheProfile;

  late final mk.Player _player;
  late final mkv.VideoController _video;
  final List<StreamSubscription<Object?>> _subs = [];
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  final StreamController<PlaybackStats> _statsController =
      StreamController<PlaybackStats>.broadcast();

  final MediaLoadGate _gate = MediaLoadGate();

  PlaybackState _state = const PlaybackState();
  PlaybackStats _stats = PlaybackStats.empty;
  Timer? _statsTimer;
  bool _polling = false;

  // Los capítulos se leen una vez por video, cuando ya se conoce la duración.
  bool _chaptersRead = false;
  Duration? _creditsStart;
  mk.VideoParams? _videoParams;
  mk.AudioParams? _audioParams;
  bool _configured = false;
  bool _disposed = false;

  // Pistas de media_kit por id, para poder elegirlas.
  final Map<String, mk.AudioTrack> _audioById = {};
  final Map<String, mk.SubtitleTrack> _subtitleById = {};
  // Ids de pistas de subtítulos que se cargaron por URL.
  final Set<String> _externalIds = {};
  // Ids que mpv dice que están elegidas (`aid` / `sid`).
  String? _aid;
  String? _sid;
  Completer<void>? _loaded;

  @override
  PlaybackState get state => _state;

  @override
  Stream<PlaybackState> get stream => _controller.stream;

  @override
  PlaybackStats get stats => _stats;

  @override
  Stream<PlaybackStats> get statsStream => _statsController.stream;

  void _log(String message) => onLog?.call(message);

  void _update(PlaybackState Function(PlaybackState s) change) {
    if (_disposed) return;
    final next = change(_state);
    if (next == _state) return;
    _state = next;
    _controller.add(next);
  }

  void _listen() {
    final s = _player.stream;
    _subs.addAll([
      s.position.listen((v) => _update((st) => st.copyWith(position: v))),
      s.duration.listen((v) {
        _gate.onDuration(v);
        _update((st) => st.copyWith(duration: v));
        if (v > Duration.zero) {
          final c = _loaded;
          if (c != null && !c.isCompleted) c.complete();
        }
      }),
      s.playing.listen((v) => _update((st) => st.copyWith(playing: v))),
      s.buffering.listen((v) => _update((st) => st.copyWith(buffering: v))),
      s.completed.listen(
        (v) => _update(
          (st) => st.copyWith(completed: v, playing: v ? false : st.playing),
        ),
      ),
      s.volume.listen(
        (v) => _update((st) => st.copyWith(volume: (v / 100).clamp(0.0, 1.0))),
      ),
      s.tracks.listen(_onTracks),
      s.videoParams.listen((v) => _videoParams = v),
      s.audioParams.listen((v) => _audioParams = v),
      s.error.listen(_onError),
    ]);
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollStats()),
    );
    _observe('aid', (v) {
      _aid = v;
      _update(_withSelection);
    });
    _observe('sid', (v) {
      _sid = v;
      _update(_withSelection);
    });
  }

  Future<void> _observe(String property, void Function(String) onValue) async {
    try {
      final platform = _player.platform;
      if (platform is! mk.NativePlayer) return;
      await platform.observeProperty(property, (v) async => onValue(v));
    } catch (e) {
      _log('No se pudo observar $property: ${redactUrlsInText('$e')}');
    }
  }

  static bool _isReal(String id) => id != 'auto' && id != 'no';

  void _onTracks(mk.Tracks tracks) {
    _gate.onTracks(
      hasAudio: tracks.audio.any((t) => _isReal(t.id)),
      hasVideo: tracks.video.any((t) => _isReal(t.id)),
    );
    _audioById
      ..clear()
      ..addEntries(
        tracks.audio.where((t) => _isReal(t.id)).map((t) => MapEntry(t.id, t)),
      );
    _subtitleById
      ..clear()
      ..addEntries(
        tracks.subtitle
            .where((t) => _isReal(t.id))
            .map((t) => MapEntry(t.id, t)),
      );
    _update((st) {
      final audio = [
        for (final t in _audioById.values)
          AudioTrack(
            id: t.id,
            language: t.language,
            title: t.title,
            isDefault: t.isDefault ?? false,
          ),
      ];
      final subs = [
        for (final t in _subtitleById.values)
          SubtitleTrack(
            id: t.id,
            language: t.language,
            title: t.title,
            isExternal: _externalIds.contains(t.id),
          ),
      ];
      return _withSelection(
        st.copyWith(audioTracks: audio, subtitleTracks: subs),
      );
    });
  }

  PlaybackState _withSelection(PlaybackState st) {
    AudioTrack? audio;
    for (final t in st.audioTracks) {
      if (t.id == _aid) audio = t;
    }
    SubtitleTrack? sub;
    for (final t in st.subtitleTracks) {
      if (t.id == _sid) sub = t;
    }
    return st.copyWith(
      selectedAudio: audio,
      selectedSubtitle: sub,
      clearSelectedSubtitle: sub == null,
    );
  }

  void _onError(String message) {
    // Con el medio ya cargado (pistas o duración), los errores que avisa mpv
    // (un subtítulo que no abre, un cuadro que no decodifica) no cortan la
    // reproducción: solo se anotan.
    final decision = decideEngineError(_gate, message);
    _log(decision.logLine);
    if (decision.fatal) _setError(decision.userMessage);
  }

  /// Deja el error en el estado con un mensaje propio: el texto de mpv puede
  /// llevar la URL del stream (con claves), así que no se guarda ni se muestra.
  void _fail(String raw) {
    _log('Error de reproducción: ${redactUrlsInText(raw)}');
    _setError(playbackErrorMessage(raw));
  }

  void _setError(String userMessage) => _update(
    (st) => st.copyWith(error: userMessage, buffering: false, playing: false),
  );

  @override
  Future<void> open(PlaybackSource source) async {
    if (_disposed) return;
    _loaded = Completer<void>();
    _gate.reset();
    _aid = null;
    _sid = null;
    _externalIds.clear();
    _videoParams = null;
    _audioParams = null;
    _stats = PlaybackStats.empty;
    _chaptersRead = false;
    _creditsStart = null;
    _update(
      (st) => PlaybackState(
        buffering: true,
        position: source.startPosition,
        volume: st.volume,
      ),
    );
    try {
      await _configure();
      await _player.open(
        mk.Media(
          source.url,
          httpHeaders: source.headers.isEmpty ? null : source.headers,
          start: source.startPosition > Duration.zero
              ? source.startPosition
              : null,
        ),
      );
    } catch (e) {
      _fail(e.toString());
    }
  }

  /// Fija la caché de mpv y el retraso de subtítulos en cero. Se hace antes de
  /// abrir el medio.
  Future<void> _configure() async {
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    if (!_configured) {
      // Si una opción de caché no se aplica no es un error de la fuente: se
      // anota y se sigue con el resto.
      for (final option in cacheProfile.mpvOptions.entries) {
        await _setOption(platform, option.key, option.value);
      }
      _log('Caché: ${cacheProfile.label}');
      _configured = true;
    }
    await _setOption(platform, 'sub-delay', '0');
  }

  Future<void> _setOption(
    mk.NativePlayer platform,
    String name,
    String value,
  ) async {
    try {
      await platform.setProperty(name, value);
    } on Object catch (e) {
      _log('No se pudo fijar $name: ${redactUrlsInText('$e')}');
    }
  }

  /// Lee los datos técnicos de mpv y los emite si cambiaron.
  Future<void> _pollStats() async {
    if (_disposed || _polling || _statsController.isClosed) return;
    if (!_gate.loaded) return;
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    _polling = true;
    try {
      Future<String> get(String name) => platform.getProperty(name);
      if (!_chaptersRead && _state.duration > Duration.zero) {
        _chaptersRead = true;
        _creditsStart = creditsStartFromChapters(await get('chapter-list'));
      }
      final fps =
          parseMpvDouble(await get('estimated-vf-fps')) ??
          parseMpvDouble(await get('container-fps'));
      final bitrate = parseMpvDouble(await get('video-bitrate'));
      final buffer = bufferFromCacheState(
        await get('demuxer-cache-state'),
        _state.position,
      );
      final vp = _videoParams;
      final ap = _audioParams;
      final next = PlaybackStats(
        videoWidth: vp?.w,
        videoHeight: vp?.h,
        fps: fps != null && fps > 0 ? fps : null,
        videoCodec: shortCodecName(await get('video-codec')),
        dynamicRange: dynamicRangeOf(
          gamma: vp?.gamma,
          colormatrix: vp?.colormatrix,
        ),
        hardwareDecoder: hardwareDecoderName(await get('hwdec-current')),
        videoBitrate: bitrate != null && bitrate > 0 ? bitrate.round() : null,
        audioCodec: shortCodecName(await get('audio-codec-name')),
        audioChannels: ap?.channelCount,
        bufferAhead: buffer?.ahead ?? Duration.zero,
        bufferBehind: buffer?.behind ?? Duration.zero,
        cacheLevel: cacheProfile.label,
        creditsStart: _creditsStart,
      );
      if (_disposed || next == _stats) return;
      _stats = next;
      _statsController.add(next);
    } on Object catch (e) {
      _log('No se pudieron leer los datos técnicos: ${redactUrlsInText('$e')}');
    } finally {
      _polling = false;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    if (_state.completed) await _player.seek(Duration.zero);
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (!_disposed) await _player.pause();
  }

  @override
  Future<void> playOrPause() => _state.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    final max = _state.duration;
    var target = position.isNegative ? Duration.zero : position;
    if (max > Duration.zero && target > max) target = max;
    await _player.seek(target);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    await _player.setVolume(volume.clamp(0.0, 1.0) * 100);
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    if (_disposed) return;
    final t = _audioById[track.id];
    if (t != null) await _player.setAudioTrack(t);
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    if (_disposed) return;
    if (track == null) {
      await _player.setSubtitleTrack(mk.SubtitleTrack.no());
      return;
    }
    final t = _subtitleById[track.id];
    if (t != null) await _player.setSubtitleTrack(t);
  }

  @override
  Future<void> addExternalSubtitle(
    String url, {
    String? title,
    String? language,
  }) async {
    if (_disposed) return;
    // mpv solo acepta `sub-add` con un medio cargado.
    try {
      await _loaded?.future.timeout(loadTimeout);
    } on TimeoutException {
      _log(
        'No cargó el medio a tiempo; no se agrega el subtítulo de '
        '${redactUrlsInText(url)}',
      );
      return;
    }
    if (_disposed) return;
    final before = _subtitleById.keys.toSet();
    await _player.setSubtitleTrack(
      mk.SubtitleTrack.uri(url, title: title, language: language),
    );
    // mpv suma la pista a la lista un instante después: se espera y se la marca
    // como externa.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline) && !_disposed) {
      final added = _subtitleById.keys.where((id) => !before.contains(id));
      if (added.isNotEmpty) {
        _externalIds.addAll(added);
        _update(
          (st) => st.copyWith(
            subtitleTracks: [
              for (final t in st.subtitleTracks)
                _externalIds.contains(t.id)
                    ? SubtitleTrack(
                        id: t.id,
                        language: t.language,
                        title: t.title,
                        isExternal: true,
                      )
                    : t,
            ],
          ),
        );
        _update(_withSelection);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _log(
      'El subtítulo externo no apareció en la lista de pistas: '
      '${redactUrlsInText(url)}',
    );
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    if (_disposed) return;
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    final seconds = delay.inMicroseconds / Duration.microsecondsPerSecond;
    await platform.setProperty('sub-delay', seconds.toStringAsFixed(3));
  }

  @override
  Widget buildVideoSurface(BuildContext context) => mkv.Video(
    controller: _video,
    controls: mkv.NoVideoControls,
    fill: Colors.black,
    subtitleViewConfiguration: const mkv.SubtitleViewConfiguration(
      visible: false,
    ),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _statsTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _controller.close();
    await _statsController.close();
  }
}
