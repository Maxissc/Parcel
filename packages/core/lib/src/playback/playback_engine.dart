import 'playback_source.dart';
import 'playback_state.dart';
import 'playback_track.dart';

/// Reproductor de video, sin atarse a una librería concreta.
///
/// El estado se lee con [state] y se escucha con [stream]. Después de
/// [dispose] el motor no se puede volver a usar.
abstract interface class PlaybackEngine {
  PlaybackState get state;

  /// Emite el estado nuevo cada vez que cambia. Es un stream broadcast.
  Stream<PlaybackState> get stream;

  /// Abre [source] y empieza a reproducir. Un fallo no lanza: queda en
  /// `state.error`. Volver a llamar reintenta o cambia de video.
  Future<void> open(PlaybackSource source);

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);

  /// [volume] va de 0 a 1.
  Future<void> setVolume(double volume);

  Future<void> setAudioTrack(AudioTrack track);

  /// `null` desactiva los subtítulos.
  Future<void> setSubtitleTrack(SubtitleTrack? track);

  /// Carga un subtítulo externo y lo elige. Aparece en `state.subtitleTracks`
  /// con `isExternal`.
  Future<void> addExternalSubtitle(
    String url, {
    String? title,
    String? language,
  });

  Future<void> dispose();
}
