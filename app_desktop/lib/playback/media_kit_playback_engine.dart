import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:parcel_core/parcel_core.dart';

import 'video_surface.dart';

/// [PlaybackEngine] sobre media_kit (libmpv). Es el único lugar que conoce los
/// tipos de media_kit.
class MediaKitPlaybackEngine implements PlaybackEngine, VideoSurfaceProvider {
  MediaKitPlaybackEngine({
    this.loadTimeout = const Duration(seconds: 20),
    this.onLog,
  }) {
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

  late final mk.Player _player;
  late final mkv.VideoController _video;
  final List<StreamSubscription<Object?>> _subs = [];
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _state = const PlaybackState();
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
      s.error.listen(_onError),
    ]);
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
      _log('No se pudo observar $property: $e');
    }
  }

  static bool _isReal(String id) => id != 'auto' && id != 'no';

  void _onTracks(mk.Tracks tracks) {
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
          AudioTrack(id: t.id, language: t.language, title: t.title),
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
    // Con el medio ya cargado, los errores que avisa mpv (un subtítulo que no
    // abre, un frame que no decodifica) no cortan la reproducción.
    if (_state.duration > Duration.zero) {
      _log('Aviso de reproducción: $message');
      return;
    }
    _update(
      (st) => st.copyWith(error: message, buffering: false, playing: false),
    );
  }

  @override
  Future<void> open(PlaybackSource source) async {
    if (_disposed) return;
    _loaded = Completer<void>();
    _aid = null;
    _sid = null;
    _externalIds.clear();
    _update(
      (st) => PlaybackState(
        buffering: true,
        position: source.startPosition,
        volume: st.volume,
      ),
    );
    try {
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
      _update(
        (st) =>
            st.copyWith(error: e.toString(), buffering: false, playing: false),
      );
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
      _log('No cargó el medio a tiempo; no se agrega el subtítulo $url');
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
    _log('El subtítulo externo no apareció en la lista de pistas: $url');
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
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _controller.close();
  }
}
