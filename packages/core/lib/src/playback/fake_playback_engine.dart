import 'dart:async';

import 'playback_engine.dart';
import 'playback_source.dart';
import 'playback_state.dart';
import 'playback_stats.dart';
import 'playback_track.dart';

/// [PlaybackEngine] en memoria para tests: simula el estado sin reproducir.
///
/// Los métodos `tick` y `fail` y el campo `openError` dejan simular lo que
/// haría un reproductor real.
class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine({
    this.mediaDuration = const Duration(minutes: 1),
    this.audioTracks = const [],
    this.subtitleTracks = const [],
  });

  /// Duración que informa al abrir.
  final Duration mediaDuration;

  /// Pistas que informa al abrir.
  final List<AudioTrack> audioTracks;
  final List<SubtitleTrack> subtitleTracks;

  /// Si no es `null`, el próximo [open] termina en error con este mensaje.
  String? openError;

  /// Si es `true`, [open] deja el video cargando para siempre (sin duración
  /// ni primer cuadro), como una fuente que no responde.
  bool stallOnOpen = false;

  /// Última fuente que se abrió.
  PlaybackSource? lastSource;

  /// Cuántas veces se llamó a [open].
  int openCount = 0;

  /// Último retraso de subtítulos pedido con [setSubtitleDelay].
  Duration subtitleDelay = Duration.zero;

  PlaybackState _state = const PlaybackState();
  PlaybackStats _stats = PlaybackStats.empty;
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackStats> _statsController =
      StreamController<PlaybackStats>.broadcast();
  bool _disposed = false;
  int _externalCount = 0;

  @override
  PlaybackState get state => _state;

  @override
  Stream<PlaybackState> get stream => _controller.stream;

  @override
  PlaybackStats get stats => _stats;

  @override
  Stream<PlaybackStats> get statsStream => _statsController.stream;

  void _emit(PlaybackState next) {
    if (_disposed) return;
    _state = next;
    _controller.add(next);
  }

  @override
  Future<void> open(PlaybackSource source) async {
    if (_disposed) return;
    lastSource = source;
    openCount++;
    _externalCount = 0;
    subtitleDelay = Duration.zero;
    if (stallOnOpen) {
      _emit(
        PlaybackState(
          buffering: true,
          position: source.startPosition,
          volume: _state.volume,
        ),
      );
      return;
    }
    final error = openError;
    if (error != null) {
      _emit(
        const PlaybackState().copyWith(error: error, volume: _state.volume),
      );
      return;
    }
    _emit(
      PlaybackState(
        position: source.startPosition,
        duration: mediaDuration,
        playing: true,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        selectedAudio: audioTracks.isEmpty ? null : audioTracks.first,
        volume: _state.volume,
      ),
    );
  }

  @override
  Future<void> play() async =>
      _emit(_state.copyWith(playing: true, completed: false));

  @override
  Future<void> pause() async => _emit(_state.copyWith(playing: false));

  @override
  Future<void> playOrPause() => _state.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    final max = _state.duration;
    final clamped = position.isNegative
        ? Duration.zero
        : (position > max ? max : position);
    _emit(_state.copyWith(position: clamped, completed: false));
  }

  @override
  Future<void> setVolume(double volume) async =>
      _emit(_state.copyWith(volume: volume.clamp(0.0, 1.0)));

  @override
  Future<void> setAudioTrack(AudioTrack track) async =>
      _emit(_state.copyWith(selectedAudio: track));

  @override
  Future<void> setSubtitleTrack(SubtitleTrack? track) async => _emit(
    track == null
        ? _state.copyWith(clearSelectedSubtitle: true)
        : _state.copyWith(selectedSubtitle: track),
  );

  @override
  Future<void> addExternalSubtitle(
    String url, {
    String? title,
    String? language,
  }) async {
    final track = SubtitleTrack(
      id: 'external-${++_externalCount}',
      title: title,
      language: language,
      isExternal: true,
    );
    _emit(
      _state.copyWith(
        subtitleTracks: [..._state.subtitleTracks, track],
        selectedSubtitle: track,
      ),
    );
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    subtitleDelay = delay;
  }

  /// Simula que el reproductor informa [stats].
  void emitStats(PlaybackStats stats) {
    if (_disposed) return;
    _stats = stats;
    _statsController.add(stats);
  }

  /// Avanza la posición [by]; al llegar al final marca `completed` y pausa.
  void tick(Duration by) {
    final end = _state.duration;
    final next = _state.position + by;
    if (end > Duration.zero && next >= end) {
      _emit(_state.copyWith(position: end, completed: true, playing: false));
    } else {
      _emit(_state.copyWith(position: next));
    }
  }

  /// Simula un error de reproducción.
  void fail(String message) =>
      _emit(_state.copyWith(error: message, playing: false, buffering: false));

  /// Simula que se está cargando (o que dejó de cargar).
  void setBuffering(bool value) => _emit(_state.copyWith(buffering: value));

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.close();
    await _statsController.close();
  }
}
