import 'playback_track.dart';

/// Foto del estado del reproductor.
class PlaybackState {
  const PlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.playing = false,
    this.completed = false,
    this.error,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.selectedAudio,
    this.selectedSubtitle,
    this.volume = 1.0,
  });

  final Duration position;

  /// Cero mientras no se conoce.
  final Duration duration;
  final bool buffering;
  final bool playing;
  final bool completed;

  /// Mensaje del último error, o `null` si no hay.
  final String? error;
  final List<AudioTrack> audioTracks;
  final List<SubtitleTrack> subtitleTracks;
  final AudioTrack? selectedAudio;

  /// `null` si los subtítulos están desactivados.
  final SubtitleTrack? selectedSubtitle;

  /// De 0 (silencio) a 1 (volumen completo).
  final double volume;

  /// Copia con cambios. Para dejar [error] o [selectedSubtitle] en `null` hay
  /// que pasar [clearError] o [clearSelectedSubtitle].
  PlaybackState copyWith({
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? playing,
    bool? completed,
    String? error,
    bool clearError = false,
    List<AudioTrack>? audioTracks,
    List<SubtitleTrack>? subtitleTracks,
    AudioTrack? selectedAudio,
    SubtitleTrack? selectedSubtitle,
    bool clearSelectedSubtitle = false,
    double? volume,
  }) {
    return PlaybackState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffering: buffering ?? this.buffering,
      playing: playing ?? this.playing,
      completed: completed ?? this.completed,
      error: clearError ? null : (error ?? this.error),
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      selectedAudio: selectedAudio ?? this.selectedAudio,
      selectedSubtitle: clearSelectedSubtitle
          ? null
          : (selectedSubtitle ?? this.selectedSubtitle),
      volume: volume ?? this.volume,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackState &&
      other.position == position &&
      other.duration == duration &&
      other.buffering == buffering &&
      other.playing == playing &&
      other.completed == completed &&
      other.error == error &&
      _listEquals(other.audioTracks, audioTracks) &&
      _listEquals(other.subtitleTracks, subtitleTracks) &&
      other.selectedAudio == selectedAudio &&
      other.selectedSubtitle == selectedSubtitle &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(
    position,
    duration,
    buffering,
    playing,
    completed,
    error,
    Object.hashAll(audioTracks),
    Object.hashAll(subtitleTracks),
    selectedAudio,
    selectedSubtitle,
    volume,
  );

  @override
  String toString() =>
      'PlaybackState(pos=$position dur=$duration playing=$playing '
      'buffering=$buffering completed=$completed error=$error '
      'audio=${audioTracks.length} subs=${subtitleTracks.length} '
      'selAudio=${selectedAudio?.id} selSub=${selectedSubtitle?.id} '
      'vol=$volume)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
