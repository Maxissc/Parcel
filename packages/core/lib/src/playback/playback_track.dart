/// Pista de un video (audio o subtítulos), con datos que sirven para mostrarla.
abstract class PlaybackTrack {
  const PlaybackTrack({required this.id, this.language, this.title});

  /// Identificador dentro del reproductor; no cambia mientras dura el video.
  final String id;

  /// Código de idioma tal como lo informa el archivo (por ejemplo `spa` o `es`).
  final String? language;

  /// Título que puso quien armó el archivo (por ejemplo «Castellano 5.1»).
  final String? title;
}

/// Pista de audio.
class AudioTrack extends PlaybackTrack {
  const AudioTrack({
    required super.id,
    super.language,
    super.title,
    this.isDefault = false,
  });

  /// `true` si el archivo la marca como pista por defecto.
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      other is AudioTrack &&
      other.id == id &&
      other.language == language &&
      other.title == title &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(id, language, title, isDefault);

  @override
  String toString() => 'AudioTrack($id $language $title)';
}

/// Pista de subtítulos, interna del archivo o externa (cargada por URL).
class SubtitleTrack extends PlaybackTrack {
  const SubtitleTrack({
    required super.id,
    super.language,
    super.title,
    this.isExternal = false,
  });

  final bool isExternal;

  @override
  bool operator ==(Object other) =>
      other is SubtitleTrack &&
      other.id == id &&
      other.language == language &&
      other.title == title &&
      other.isExternal == isExternal;

  @override
  int get hashCode => Object.hash(id, language, title, isExternal);

  @override
  String toString() =>
      'SubtitleTrack($id $language $title'
      '${isExternal ? ' externa' : ''})';
}
