import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../playback/playback_errors.dart';

/// Configuración del modo de diagnóstico del reproductor.
///
/// Solo existe en modo debug. Se activa con la variable de entorno
/// `PARCEL_DIAG=1` y deja un log por stdout (y en el archivo de
/// `PARCEL_DIAG_LOG`, si está). Variables opcionales:
///
/// - `PARCEL_DIAG_URL`: abre esa URL en el reproductor al arrancar.
/// - `PARCEL_DIAG_SUB`: URL de un subtítulo externo para cargar al abrir.
/// - `PARCEL_DIAG_CYCLE_TRACKS=1`: recorre las pistas de audio y de subtítulos.
/// - `PARCEL_DIAG_EXIT_SECONDS`: cierra la app pasados esos segundos.
/// - `PARCEL_DIAG_PASTE`: texto con URLs de addons; completa solo el paso
///   «Pegar lista» del asistente, confirma la importación y deja el informe en
///   el log (líneas `[diag]`).
/// - `PARCEL_DIAG_OPEN`: `tipo/id` (por ejemplo `series/tt0903747`); abre su
///   detalle y pide sus streams, y cuenta lo que cargó en el log.
/// - `PARCEL_DIAG_SEARCH`: texto a buscar; abre Buscar con ese texto y cuenta
///   los resultados.
/// - `PARCEL_DIAG_PLAY_FIRST_STREAM=1`: con `PARCEL_DIAG_OPEN`, reproduce el
///   primer stream reproducible que aparezca.
/// - `PARCEL_DIAG_AUTOPLAY=1`: con `PARCEL_DIAG_OPEN`, hace lo mismo que el
///   botón «Ver» (elige la fuente sola, salteando las rotas).
/// - `PARCEL_DIAG_SYNC_TAPS`: segundos separados por coma (por ejemplo
///   `12.0,35.5`); con el reproductor andando, marca esas posiciones en el
///   asistente de sincronización de subtítulos y deja el resultado en el log.
/// - `PARCEL_DIAG_MIN_PROBE_BYTES`: tamaño mínimo con el que la prueba de
///   fuentes acepta un video (por defecto 20 MB; una muestra chica necesita 0).
class DiagnosticsConfig {
  const DiagnosticsConfig({
    this.url,
    this.subtitleUrl,
    this.cycleTracks = false,
    this.exitAfter,
    this.logPath,
    this.paste,
    this.open,
    this.search,
    this.playFirstStream = false,
    this.autoplay = false,
    this.syncTaps = const [],
    this.probeMinBytes,
  });

  final String? url;
  final String? subtitleUrl;
  final bool cycleTracks;
  final Duration? exitAfter;
  final String? logPath;

  /// Texto a pegar en el asistente de migración; `null` si no hay.
  final String? paste;

  /// `tipo/id` del contenido a abrir; `null` si no hay.
  final String? open;

  /// Texto a buscar; `null` si no hay.
  final String? search;
  final bool playFirstStream;
  final bool autoplay;

  /// Posiciones a marcar en el asistente de sincronización.
  final List<Duration> syncTaps;

  /// Tamaño mínimo de la prueba de fuentes; `null` es el normal.
  final int? probeMinBytes;

  /// `null` si no es debug o no está `PARCEL_DIAG`.
  static DiagnosticsConfig? fromEnvironment([Map<String, String>? env]) {
    if (!kDebugMode) return null;
    final e = env ?? Platform.environment;
    if (e['PARCEL_DIAG'] != '1') return null;
    String? nonEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v;
    final exit = int.tryParse(e['PARCEL_DIAG_EXIT_SECONDS'] ?? '');
    return DiagnosticsConfig(
      url: nonEmpty(e['PARCEL_DIAG_URL']),
      subtitleUrl: nonEmpty(e['PARCEL_DIAG_SUB']),
      cycleTracks: e['PARCEL_DIAG_CYCLE_TRACKS'] == '1',
      exitAfter: exit == null ? null : Duration(seconds: exit),
      logPath: nonEmpty(e['PARCEL_DIAG_LOG']),
      paste: nonEmpty(e['PARCEL_DIAG_PASTE']),
      open: nonEmpty(e['PARCEL_DIAG_OPEN']),
      search: nonEmpty(e['PARCEL_DIAG_SEARCH']),
      playFirstStream: e['PARCEL_DIAG_PLAY_FIRST_STREAM'] == '1',
      autoplay: e['PARCEL_DIAG_AUTOPLAY'] == '1',
      syncTaps: [
        for (final part in (e['PARCEL_DIAG_SYNC_TAPS'] ?? '').split(','))
          if (double.tryParse(part.trim()) case final seconds?)
            Duration(milliseconds: (seconds * 1000).round()),
      ],
      probeMinBytes: int.tryParse(e['PARCEL_DIAG_MIN_PROBE_BYTES'] ?? ''),
    );
  }
}

/// Escribe una línea por cada cambio relevante del [PlaybackEngine]: pistas
/// detectadas, pista elegida, posición cada 5 s y errores.
class PlaybackDiagnostics {
  PlaybackDiagnostics(
    this.engine, {
    required this.config,
    void Function(String line)? sink,
  }) : _sink = sink ?? _defaultSink(config.logPath);

  final PlaybackEngine engine;
  final DiagnosticsConfig config;
  final void Function(String line) _sink;

  StreamSubscription<PlaybackState>? _sub;
  Timer? _positionTimer;
  PlaybackState _last = const PlaybackState();

  static void Function(String) _defaultSink(String? path) {
    return (line) {
      stdout.writeln(line);
      if (path != null) {
        File(path).writeAsStringSync('$line\n', mode: FileMode.append);
      }
    };
  }

  void _write(String message) {
    final ts = DateTime.now().toIso8601String();
    // Ninguna línea del diagnóstico puede llevar una URL completa.
    _sink('[parcel-diag $ts] ${redactUrlsInText(message)}');
  }

  /// Empieza a escuchar. Se detiene solo cuando el motor se libera.
  void start() {
    _write('inicio del diagnóstico');
    _sub = engine.stream.listen(_onState, onDone: stop);
    _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final s = engine.state;
      _write(
        'POS ${formatPlaybackTime(s.position)} / '
        '${formatPlaybackTime(s.duration)} playing=${s.playing} '
        'buffering=${s.buffering} volumen=${s.volume.toStringAsFixed(2)}',
      );
    });
    final exitAfter = config.exitAfter;
    if (exitAfter != null) {
      Timer(exitAfter, () {
        _write('cierre por PARCEL_DIAG_EXIT_SECONDS');
        exit(0);
      });
    }
  }

  void stop() {
    _positionTimer?.cancel();
    _positionTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }

  String _tracks(List<PlaybackTrack> tracks) => tracks
      .map(
        (t) =>
            '[${t.id} ${t.language ?? '-'} ${t.title ?? '-'}'
            '${t is SubtitleTrack && t.isExternal ? ' externa' : ''}]',
      )
      .join(' ');

  void _onState(PlaybackState s) {
    final p = _last;
    if (s.duration != p.duration && s.duration > Duration.zero) {
      _write('DURACION ${formatPlaybackTime(s.duration)}');
    }
    if (!_sameIds(s.audioTracks, p.audioTracks)) {
      _write('PISTAS_AUDIO ${s.audioTracks.length}: ${_tracks(s.audioTracks)}');
    }
    if (!_sameIds(s.subtitleTracks, p.subtitleTracks) ||
        _externalCount(s) != _externalCount(p)) {
      _write(
        'PISTAS_SUBTITULOS ${s.subtitleTracks.length}: '
        '${_tracks(s.subtitleTracks)}',
      );
    }
    if (s.selectedAudio != p.selectedAudio) {
      _write('AUDIO_ELEGIDO ${s.selectedAudio ?? 'ninguno'}');
    }
    if (s.selectedSubtitle != p.selectedSubtitle) {
      _write('SUBTITULO_ELEGIDO ${s.selectedSubtitle ?? 'desactivado'}');
    }
    if (s.playing != p.playing) _write('PLAYING ${s.playing}');
    if (s.buffering != p.buffering) _write('BUFFERING ${s.buffering}');
    if (s.completed != p.completed) _write('COMPLETADO ${s.completed}');
    if (s.error != p.error && s.error != null) _write('ERROR ${s.error}');
    _last = s;
  }

  int _externalCount(PlaybackState s) =>
      s.subtitleTracks.where((t) => t.isExternal).length;

  bool _sameIds(List<PlaybackTrack> a, List<PlaybackTrack> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// Recorre cada pista de audio y de subtítulos, esperando [step] entre una y
  /// otra, y deja los subtítulos desactivados al final. Espera a que el medio
  /// tenga pistas y duración.
  Future<void> cycleTracks({Duration step = const Duration(seconds: 4)}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (engine.state.audioTracks.isEmpty &&
        engine.state.error == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await Future<void>.delayed(step);
    _write('RECORRIDO de pistas: audio');
    for (final t in List.of(engine.state.audioTracks)) {
      _write('RECORRIDO audio -> $t');
      await engine.setAudioTrack(t);
      await Future<void>.delayed(step);
    }
    _write('RECORRIDO de pistas: subtítulos');
    for (final t in List.of(engine.state.subtitleTracks)) {
      _write('RECORRIDO subtitulo -> $t');
      await engine.setSubtitleTrack(t);
      await Future<void>.delayed(step);
    }
    _write('RECORRIDO subtitulo -> desactivado');
    await engine.setSubtitleTrack(null);
    await Future<void>.delayed(step);
    _write('RECORRIDO terminado');
  }
}
