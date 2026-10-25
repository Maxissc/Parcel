/// Cambia cada dirección `http(s)://…` de [text] por solo su host. Las URLs de
/// los streams pueden llevar claves de debrid o tokens: no se muestran ni se
/// escriben en ningún log.
String redactUrlsInText(String text) {
  return text.replaceAllMapped(_urlPattern, (m) {
    final uri = Uri.tryParse(m.group(0)!);
    final host = uri?.host ?? '';
    if (host.isEmpty) return '[dirección]';
    return uri!.hasPort ? '$host:${uri.port}' : host;
  });
}

final RegExp _urlPattern = RegExp(
  r'''(?:https?|ftp|rtmp|rtsp|mms|file)://[^\s"'<>()]+''',
  caseSensitive: false,
);

/// Mensaje en español para un error del motor de reproducción. Nunca incluye
/// el texto original: puede traer la URL del stream.
String playbackErrorMessage(String raw) {
  final text = raw.toLowerCase();
  bool has(Pattern p) => text.contains(p);
  bool http(String code) => RegExp('\\b$code\\b').hasMatch(text);

  if (http('401') || http('403') || has('forbidden') || has('unauthorized')) {
    return 'El servidor no dejó abrir el video. Puede que el enlace haya '
        'vencido o que falte tu clave.';
  }
  if (http('404') || http('410') || has('not found')) {
    return 'No se encontró el video en el servidor.';
  }
  if (RegExp(r'\b5\d\d\b').hasMatch(text) || has('server error')) {
    return 'El servidor respondió con un error.';
  }
  if (has('timed out') || has('timeout')) {
    return 'El servidor tardó demasiado en responder.';
  }
  if (has('resolve') ||
      has('refused') ||
      has('unreachable') ||
      has('connection') ||
      has('network') ||
      has('ssl') ||
      has('tls')) {
    return 'No se pudo conectar con el servidor.';
  }
  if (has('recognize file format') ||
      has('unsupported') ||
      has('invalid data')) {
    return 'Parcel no reconoce el formato de este video.';
  }
  return 'No se pudo abrir el video.';
}

/// Qué hacer con un error que avisa mpv: si corta la reproducción, el mensaje
/// para el usuario y la línea para el log (ambos sin URLs).
class EngineErrorDecision {
  const EngineErrorDecision({
    required this.fatal,
    required this.userMessage,
    required this.logLine,
  });

  final bool fatal;
  final String userMessage;
  final String logLine;
}

/// Decide con [gate] si el error [raw] de mpv es fatal.
EngineErrorDecision decideEngineError(MediaLoadGate gate, String raw) {
  final fatal = gate.isFatalError;
  return EngineErrorDecision(
    fatal: fatal,
    userMessage: playbackErrorMessage(raw),
    logLine:
        '${fatal ? 'Error de reproducción' : 'Aviso de reproducción'}: '
        '${redactUrlsInText(raw)}',
  );
}

/// Sabe si el medio ya cargó, para decidir si un error de mpv es fatal.
///
/// Los avisos de mpv con el medio cargado (un subtítulo que no abre, un cuadro
/// que no decodifica) no cortan la reproducción. Un error es fatal solo si el
/// medio no cargó: no hubo pistas de audio o video ni duración.
class MediaLoadGate {
  bool _tracks = false;
  bool _duration = false;

  /// Las pistas que informó el motor: cuenta si hay de audio o de video.
  void onTracks({required bool hasAudio, required bool hasVideo}) {
    if (hasAudio || hasVideo) _tracks = true;
  }

  void onDuration(Duration duration) {
    if (duration > Duration.zero) _duration = true;
  }

  bool get loaded => _tracks || _duration;

  /// `true` si un error que llega ahora tiene que cortar la reproducción.
  bool get isFatalError => !loaded;

  /// Al abrir otro medio.
  void reset() {
    _tracks = false;
    _duration = false;
  }
}
