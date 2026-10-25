/// Rango dinámico del video (SDR, HDR10, HLG o Dolby Vision).
enum DynamicRange {
  sdr,
  hdr10,
  hlg,
  dolbyVision;

  /// Texto corto para mostrar: «HDR», «HLG» o «DV»; `null` para SDR.
  String? get shortLabel => switch (this) {
    sdr => null,
    hdr10 => 'HDR',
    hlg => 'HLG',
    dolbyVision => 'DV',
  };
}

/// Datos técnicos del video que se está reproduciendo, para el panel de
/// información. Todo lo que no se sabe es `null`.
class PlaybackStats {
  const PlaybackStats({
    this.videoWidth,
    this.videoHeight,
    this.fps,
    this.videoCodec,
    this.dynamicRange = DynamicRange.sdr,
    this.hardwareDecoder,
    this.videoBitrate,
    this.audioCodec,
    this.audioChannels,
    this.bufferAhead = Duration.zero,
    this.bufferBehind = Duration.zero,
    this.cacheLevel,
    this.creditsStart,
  });

  /// Sin datos todavía.
  static const PlaybackStats empty = PlaybackStats();

  final int? videoWidth;
  final int? videoHeight;

  /// Cuadros por segundo.
  final double? fps;

  /// Nombre del códec de video (por ejemplo `hevc`).
  final String? videoCodec;
  final DynamicRange dynamicRange;

  /// Decodificador por hardware en uso (por ejemplo `d3d11va`), o `null` si se
  /// decodifica por software.
  final String? hardwareDecoder;

  /// Bits por segundo del video.
  final int? videoBitrate;
  final String? audioCodec;

  /// Cantidad de canales del audio (2, 6, 8...).
  final int? audioChannels;

  /// Cuánto video ya cargado hay por delante de la posición.
  final Duration bufferAhead;

  /// Cuánto video ya reproducido sigue guardado en la caché.
  final Duration bufferBehind;

  /// Nombre del nivel de caché según la memoria del equipo.
  final String? cacheLevel;

  /// Dónde empiezan los créditos, si el archivo trae un capítulo «Credits».
  final Duration? creditsStart;

  PlaybackStats copyWith({
    int? videoWidth,
    int? videoHeight,
    double? fps,
    String? videoCodec,
    DynamicRange? dynamicRange,
    String? hardwareDecoder,
    int? videoBitrate,
    String? audioCodec,
    int? audioChannels,
    Duration? bufferAhead,
    Duration? bufferBehind,
    String? cacheLevel,
    Duration? creditsStart,
  }) {
    return PlaybackStats(
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      fps: fps ?? this.fps,
      videoCodec: videoCodec ?? this.videoCodec,
      dynamicRange: dynamicRange ?? this.dynamicRange,
      hardwareDecoder: hardwareDecoder ?? this.hardwareDecoder,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      audioCodec: audioCodec ?? this.audioCodec,
      audioChannels: audioChannels ?? this.audioChannels,
      bufferAhead: bufferAhead ?? this.bufferAhead,
      bufferBehind: bufferBehind ?? this.bufferBehind,
      cacheLevel: cacheLevel ?? this.cacheLevel,
      creditsStart: creditsStart ?? this.creditsStart,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackStats &&
      other.videoWidth == videoWidth &&
      other.videoHeight == videoHeight &&
      other.fps == fps &&
      other.videoCodec == videoCodec &&
      other.dynamicRange == dynamicRange &&
      other.hardwareDecoder == hardwareDecoder &&
      other.videoBitrate == videoBitrate &&
      other.audioCodec == audioCodec &&
      other.audioChannels == audioChannels &&
      other.bufferAhead == bufferAhead &&
      other.bufferBehind == bufferBehind &&
      other.cacheLevel == cacheLevel &&
      other.creditsStart == creditsStart;

  @override
  int get hashCode => Object.hash(
    videoWidth,
    videoHeight,
    fps,
    videoCodec,
    dynamicRange,
    hardwareDecoder,
    videoBitrate,
    audioCodec,
    audioChannels,
    bufferAhead,
    bufferBehind,
    cacheLevel,
    creditsStart,
  );

  @override
  String toString() =>
      'PlaybackStats(${videoWidth ?? '?'}x${videoHeight ?? '?'} '
      '${fps?.toStringAsFixed(2) ?? '?'}fps $videoCodec ${dynamicRange.name} '
      'hw=$hardwareDecoder vbr=$videoBitrate audio=$audioCodec '
      'ch=$audioChannels ahead=${bufferAhead.inSeconds}s '
      'behind=${bufferBehind.inSeconds}s cache=$cacheLevel)';
}
