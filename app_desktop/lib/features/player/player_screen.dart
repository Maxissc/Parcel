import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/back_navigation.dart';
import '../../app/theme.dart';
import '../../data/platform.dart';
import '../../playback/playback_errors.dart';
import '../../playback/video_surface.dart';
import 'player_controls.dart';
import 'player_info.dart';
import 'source_menu.dart';
import 'subtitle_catalog.dart';
import 'subtitle_delay.dart';
import 'subtitle_sync_overlay.dart';
import 'track_preferences.dart';

/// `true` si la fuente ya arrancó: la posición avanzó al menos medio segundo
/// desde [from] (también un stream en vivo, sin duración), o hay duración y
/// ya no está cargando.
bool playbackStarted(PlaybackState s, {Duration from = Duration.zero}) =>
    s.position - from >= const Duration(milliseconds: 500) ||
    (s.duration > Duration.zero && !s.buffering);

/// El episodio que sigue, para ofrecerlo al terminar el actual.
class NextEpisode {
  const NextEpisode({required this.label, required this.onOpen});

  /// Por ejemplo «T1 E4 · Título».
  final String label;
  final void Function(BuildContext context) onOpen;
}

/// Pantalla del reproductor: video a pantalla completa de la ventana y
/// controles propios encima.
///
/// Recibe el [PlaybackEngine] ya armado (así se prueba con el motor falso). Por
/// defecto la pantalla toma posesión del motor y lo libera al cerrarse.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.engine,
    required this.source,
    this.subtitles = const [],
    this.lateSubtitles,
    this.catalog,
    this.preferences,
    this.window,
    this.onProgress,
    this.next,
    this.title,
    this.disposeEngine = true,
    this.info,
    this.sourceMenu,
    this.onOpenFailed,
    this.openTimeout = const Duration(seconds: 20),
    this.manualOpenTimeout = const Duration(seconds: 30),
    this.initialSubtitleDelay = Duration.zero,
    this.onSubtitleDelayChanged,
    this.onDecision,
    this.syncTaps = const [],
    this.autoOpenNext = false,
    this.autoNext = false,
  });

  final PlaybackEngine engine;
  final PlaybackSource source;

  /// Subtítulos externos que se cargan al abrir. Si hay más de uno queda
  /// elegido el último.
  final List<Subtitle> subtitles;

  /// Subtítulos que llegan después (de los addons): van al [catalog], que los
  /// ordena y analiza. No se cargan al video hasta que se eligen.
  final Future<List<Subtitle>>? lateSubtitles;

  /// Orden y análisis de los subtítulos. Sin él solo se usan las pistas del
  /// archivo.
  final SubtitleCatalog? catalog;

  /// Idiomas preferidos para elegir pistas solo al abrir. Con `null` no se
  /// toca la elección del motor.
  final TrackPreferences? preferences;

  /// Para pantalla completa (tecla F, doble clic, Esc). Con `null` no hay.
  final WindowService? window;

  /// Se llama con la posición y la duración cada 10 s, al pausar, al terminar
  /// y al salir. Con `null` no se guarda progreso.
  final void Function(Duration position, Duration duration)? onProgress;

  /// Si hay, al terminar el video se ofrece pasar al episodio que sigue.
  final NextEpisode? next;

  /// Con [next], en los créditos arranca una cuenta regresiva de
  /// [nextCountdown] y al llegar a cero abre el episodio que sigue («Pasar solo
  /// al siguiente episodio»). Apagado, solo se ofrece el botón.
  final bool autoNext;
  static const int nextCountdown = 10;

  /// Cuánto antes del final se consideran créditos si el archivo no trae un
  /// capítulo «Credits».
  static const Duration creditsWindow = Duration(seconds: 30);
  final String? title;

  /// Si es `true`, libera [engine] al cerrar la pantalla.
  final bool disposeEngine;

  /// Fuente y contenido para el panel de datos (tecla I).
  final PlayerInfo? info;

  /// Menú «Fuente»; con `null` no se muestra.
  final SourceMenu? sourceMenu;

  /// Si está, un fallo al abrir (error antes del primer cuadro, o más de
  /// [openTimeout] sin arrancar) se avisa por acá en vez de mostrar la pantalla
  /// de error, para que quien llama pruebe otra fuente.
  final VoidCallback? onOpenFailed;
  final Duration openTimeout;

  /// Sin [onOpenFailed] (fuente elegida a mano), a los [manualOpenTimeout] sin
  /// arrancar se muestra el error con Â«ReintentarÂ» y Â«Elegir otra fuenteÂ».
  final Duration manualOpenTimeout;

  /// Retraso de subtítulos con el que arranca (el que el usuario ya fijó para
  /// este contenido) y aviso cada vez que cambia.
  final Duration initialSubtitleDelay;
  final ValueChanged<Duration>? onSubtitleDelayChanged;

  /// Recibe en una línea las decisiones automáticas (pistas elegidas...). Sin
  /// URLs.
  final ValueChanged<String>? onDecision;

  /// Marcas que se aplican solas en el asistente de sincronización (solo para
  /// el diagnóstico).
  final List<Duration> syncTaps;

  /// Diagnóstico: al terminar abre solo el episodio que sigue.
  final bool autoOpenNext;

  /// Segundos sin mover el mouse hasta que se ocultan los controles.
  static const Duration hideAfter = Duration(seconds: 3);

  /// Cada cuánto se guarda el progreso mientras se reproduce.
  static const Duration progressEvery = Duration(seconds: 10);

  /// Antes de este punto no se guarda progreso: abrir y salir enseguida no
  /// tiene que pisar lo que ya se había visto.
  static const Duration minProgress = Duration(seconds: 5);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const _seekStep = Duration(seconds: 10);
  static const _volumeStep = 0.05;
  static const _doubleTap = Duration(milliseconds: 300);
  static const _subtitleDelay = Duration(seconds: 2);

  final FocusNode _focus = FocusNode(debugLabel: 'player');

  /// El foco del asistente de sincronización, mientras está abierto.
  final FocusNode _syncFocus = FocusNode(debugLabel: 'sync-overlay');
  late final SubtitleCatalog _catalog;
  Timer? _hideTimer;
  Timer? _osdTimer;
  Timer? _progressTimer;
  Timer? _tapTimer;
  Timer? _openTimer;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<PlaybackStats>? _statsSub;
  PlaybackStats _stats = PlaybackStats.empty;
  bool _controlsVisible = true;
  bool _menuOpen = false;
  bool _fullScreen = false;
  bool _wasPlaying = false;
  bool _wasCompleted = false;
  bool _nextDismissed = false;

  /// El usuario canceló la cuenta (o cerró la tarjeta) en estos créditos: no
  /// vuelve a arrancar hasta que se salga de ellos.
  bool _countdownCancelled = false;

  /// La ventana está en primer plano (la cuenta no corre si no).
  bool _appActive = true;
  Timer? _countdownTimer;
  int? _countdown;
  SubtitleEntry? _loadingEntry;
  bool _userPickedAudio = false;
  bool _userPickedSubtitle = false;
  bool _started = false;
  bool _failedOver = false;
  bool _stalled = false;

  /// Ya arrancó la elección automática de subtítulos (pasa una vez por
  /// contenido, no por intento).
  bool _autoStarted = false;
  bool _infoOpen = false;
  bool _syncOpen = false;

  /// `true` cuando llegaron (o no hay) los subtítulos de los addons.
  bool _lateLoaded = false;

  /// Dónde estaba el video al abrir: «arrancó» se mide desde ahí.
  Duration _openedAt = Duration.zero;
  final List<Duration> _syncMarks = [];
  final Map<String, SubtitleTrack> _loadedExternal = {};

  /// Retraso de cada pista que el usuario cambió, por clave de pista.
  final Map<String, Duration> _trackDelays = {};
  late Duration _delay = widget.initialSubtitleDelay;
  double? _dragValue;
  double _volumeBeforeMute = 0.5;
  String? _osd;

  PlaybackEngine get _engine => widget.engine;

  BackInterceptors? _backInterceptors;

  /// El botón Atrás del mouse hace lo que Esc: cierra el asistente de
  /// sincronización o el panel de datos, sale de pantalla completa y recién
  /// después vuelve. Solo si el reproductor es la pantalla de arriba.
  bool _onMouseBack() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    unawaited(_escape());
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
        AppLifecycleState.resumed;
    _backInterceptors = BackScope.maybeOf(context)?..add(_onMouseBack);
    _catalog = widget.catalog ?? SubtitleCatalog();
    _lateLoaded = widget.lateSubtitles == null;
    _catalog.addListener(_onCatalogChanged);
    _scheduleHide();
    _stats = _engine.stats;
    _stateSub = _engine.stream.listen(_onEngineState);
    _statsSub = _engine.statsStream.listen((s) {
      if (mounted) setState(() => _stats = s);
    });
    if (widget.onProgress != null) {
      _progressTimer = Timer.periodic(
        PlayerScreen.progressEvery,
        (_) => _reportProgress(onlyIfPlaying: true),
      );
    }
    unawaited(_syncFullScreen());
    unawaited(_start(widget.source));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backInterceptors?.remove(_onMouseBack);
    _reportProgress();
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _progressTimer?.cancel();
    _tapTimer?.cancel();
    _openTimer?.cancel();
    _countdownTimer?.cancel();
    unawaited(_stateSub?.cancel());
    unawaited(_statsSub?.cancel());
    _catalog.removeListener(_onCatalogChanged);
    if (widget.catalog == null) _catalog.dispose();
    _focus.dispose();
    _syncFocus.dispose();
    if (widget.disposeEngine) unawaited(_engine.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(PlayerScreen old) {
    super.didUpdateWidget(old);
    if (old.autoNext == widget.autoNext) return;
    // El ajuste «Pasar solo al siguiente» se lee en vivo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.autoNext) {
        _stopCountdown();
      } else {
        _updateNextEpisode(_engine.state);
      }
    });
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
  }

  void _decide(String message) =>
      widget.onDecision?.call(redactUrlsInText(message));

  /// Abre [source]. Con [retry] es una reapertura de la misma fuente (botón
  /// «Reintentar»): se vuelve a cargar el subtítulo externo que estaba
  /// elegido ([restore]) en vez de repetir la elección automática y el
  /// análisis, que son del contenido y no del intento.
  Future<void> _start(
    PlaybackSource source, {
    bool retry = false,
    SubtitleEntry? restore,
  }) async {
    _started = false;
    _stalled = false;
    _openedAt = source.startPosition;
    _loadedExternal.clear();
    _openTimer?.cancel();
    if (widget.onOpenFailed != null) {
      _openTimer = Timer(widget.openTimeout, () {
        if (!_started) {
          _failOver('no arrancó en ${widget.openTimeout.inSeconds} s');
        }
      });
    } else {
      _openTimer = Timer(widget.manualOpenTimeout, () {
        if (!_started && mounted) {
          _decide(
            'la fuente elegida no arrancó en '
            '${widget.manualOpenTimeout.inSeconds} s',
          );
          setState(() => _stalled = true);
        }
      });
    }
    await _engine.open(source);
    if (!mounted || _engine.state.error != null) return;
    if (_delay != Duration.zero) await _engine.setSubtitleDelay(_delay);
    for (final s in widget.subtitles) {
      if (!mounted) return;
      await _engine.addExternalSubtitle(
        s.url,
        title: s.label ?? s.lang,
        language: s.lang,
      );
    }
    await _applyPreferences();
    if (retry) {
      if (restore != null && mounted) await _selectEntry(restore);
      return;
    }
    await _chooseAutomaticSubtitle();
  }

  /// Dónde dejar el foco del teclado: el asistente de sincronización si está
  /// abierto, y si no el reproductor.
  void _refocus() => (_syncOpen ? _syncFocus : _focus).requestFocus();

  /// La fuente no anduvo: se avisa una sola vez a quien eligió la fuente.
  void _failOver(String reason) {
    if (_failedOver || !mounted) return;
    final callback = widget.onOpenFailed;
    if (callback == null) return;
    _failedOver = true;
    _openTimer?.cancel();
    _decide('la fuente no abrió ($reason)');
    callback();
  }

  // --- Pistas ----------------------------------------------------------------

  /// Espera a que el motor informe las pistas del archivo (llegan un rato
  /// después de abrirlo).
  Future<void> _waitForTracks() async {
    if (_engine.state.audioTracks.isNotEmpty) return;
    try {
      await _engine.stream
          .firstWhere((s) => s.audioTracks.isNotEmpty || s.error != null)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Un video sin audio informable: se sigue con lo que haya.
    } on StateError {
      // El motor se cerró.
    }
  }

  /// Elige el audio según el idioma preferido y deja puesto el subtítulo
  /// embebido que corresponda, una sola vez.
  Future<void> _applyPreferences() async {
    final prefs = widget.preferences;
    if (prefs == null) return;
    await _waitForTracks();
    if (!mounted) return;
    final audio = prefs.pickAudio(_engine.state.audioTracks);
    if (!_userPickedAudio &&
        audio != null &&
        audio != _engine.state.selectedAudio) {
      await _engine.setAudioTrack(audio);
    }
    _decide(
      'audio por defecto: ${_engine.state.selectedAudio ?? audio ?? 'ninguno'}'
      ' (preferencia ${prefs.audioLanguage ?? 'ninguna'}, '
      'original ${prefs.originalLanguage ?? 'desconocido'})',
    );
    final embedded = _catalog.pickAutomatic(
      prefs.subtitleLanguage,
      _engine.state.subtitleTracks.where((t) => !t.isExternal).toList(),
      includeExternal: false,
    );
    final embeddedTarget = embedded?.embedded ?? _embeddedSelection();
    await _chooseSubtitle(embeddedTarget, explicit: embedded != null);
    _decide(
      'subtítulo por defecto (del video): '
      '${embeddedTarget ?? 'ninguno'} '
      '(preferencia ${prefs.subtitleLanguage ?? 'ninguna'})',
    );
  }

  /// La pista de subtítulos elegida si es del archivo; una externa cargada por
  /// nosotros no cuenta como elección del usuario.
  SubtitleTrack? _embeddedSelection() {
    final selected = _engine.state.selectedSubtitle;
    return selected != null && !selected.isExternal ? selected : null;
  }

  Future<void> _chooseSubtitle(
    SubtitleTrack? target, {
    required bool explicit,
  }) async {
    if (_userPickedSubtitle && !explicit) return;
    if (target == _engine.state.selectedSubtitle) return;
    await _engine.setSubtitleTrack(target);
  }

  /// Espera a que el video avance un par de segundos: cargar un subtítulo por
  /// red frena un instante la reproducción y es mejor que no sea al arrancar.
  Future<void> _waitForPlayback() async {
    final from = _engine.state.position;
    try {
      await _engine.stream
          .firstWhere(
            (s) => s.error != null || s.position - from >= _subtitleDelay,
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // El video no avanza (pausado): se cargan igual.
    } on StateError {
      // El motor se cerró.
    }
  }

  /// Cuando llegan y se analizan los subtítulos de los addons, elige el mejor
  /// del idioma preferido (si el usuario todavía no eligió uno).
  Future<void> _chooseAutomaticSubtitle() async {
    _autoStarted = true;
    final late = widget.lateSubtitles;
    if (late != null) {
      final subtitles = await late;
      if (!mounted) return;
      _catalog.setExternal(subtitles);
    }
    _lateLoaded = true;
    if (_catalog.externals.isEmpty) {
      await _maybeRunSyncTaps();
      return;
    }
    // La alineación necesita la duración del video.
    if (_engine.state.duration <= Duration.zero) {
      try {
        await _engine.stream
            .firstWhere((s) => s.duration > Duration.zero || s.error != null)
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        // Sin duración no hay etiquetas: se elige igual.
      } on StateError {
        return;
      }
    }
    if (!mounted) return;
    _catalog.videoDuration = _engine.state.duration;
    try {
      await _catalog.analysisDone.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Se elige con lo que ya se analizó.
    }
    if (!mounted) return;
    final likely = _catalog.externals
        .where((e) => _catalog.alignmentOf(e) == SubtitleAlignment.likely)
        .length;
    final analyzed = _catalog.externals.where((e) => e.cues != null).length;
    _decide(
      'subtítulos de addons: ${_catalog.externals.length}, '
      '$analyzed analizados, $likely probablemente sincronizados',
    );
    final prefs = widget.preferences;
    if (prefs != null && !_userPickedSubtitle) {
      final entry = _catalog.pickAutomatic(
        prefs.subtitleLanguage,
        _engine.state.subtitleTracks.where((t) => !t.isExternal).toList(),
      );
      if (entry != null) {
        _decide(
          'subtítulo por defecto: ${entry.label} '
          '(${entry.external ? 'de un addon' : 'del video'}, '
          '${_catalog.alignmentOf(entry)?.name ?? 'sin analizar'})',
        );
        if (entry.external) {
          await _waitForPlayback();
          if (!mounted || _userPickedSubtitle) return;
        }
        await _selectEntry(entry);
      } else {
        _decide('subtítulo por defecto: ninguno');
      }
    }
    await _maybeRunSyncTaps();
  }

  /// Número de la última elección de subtítulo (cada elección suma uno). Una
  /// descarga vieja que termina cuando ya hubo otra elección no pisa la nueva.
  int _pickToken = 0;
  int _resolvedToken = 0;

  /// La pista que dejó la última elección ya resuelta (`null` si apagó los
  /// subtítulos).
  SubtitleTrack? _pickedTrack;

  void _resolvePick(int token) {
    if (token != _pickToken) return;
    _resolvedToken = token;
    _pickedTrack = _engine.state.selectedSubtitle;
  }

  Future<void> _selectEntry(SubtitleEntry entry) async {
    final token = ++_pickToken;
    final embedded = entry.embedded;
    if (embedded != null) {
      await _engine.setSubtitleTrack(embedded);
      _resolvePick(token);
      return;
    }
    final known = _loadedExternal[entry.id];
    if (known != null) {
      await _engine.setSubtitleTrack(known);
      _resolvePick(token);
      return;
    }
    final before = _engine.state.subtitleTracks.map((t) => t.id).toSet();
    // Mientras se baja, el menú lo marca «Descargando…» y la elección queda.
    if (mounted) setState(() => _loadingEntry = entry);
    try {
      await _engine.addExternalSubtitle(
        entry.subtitle.url,
        title: entry.label,
        language: entry.subtitle.lang,
      );
    } finally {
      if (mounted && token == _pickToken && _loadingEntry?.id == entry.id) {
        setState(() => _loadingEntry = null);
      }
    }
    // La pista que se sumó para esta entrada: una externa nueva que no es de
    // ninguna otra (con dos bajadas en curso, la del medio no es de esta).
    final owned = _loadedExternal.values.toSet();
    final added = _engine.state.subtitleTracks
        .where(
          (t) => t.isExternal && !before.contains(t.id) && !owned.contains(t),
        )
        .lastOrNull;
    if (added != null) _loadedExternal[entry.id] = added;
    if (token != _pickToken) {
      // Hubo otra elección mientras bajaba: el motor eligió esta pista al
      // terminar, y se vuelve a la elección más nueva (si ya se resolvió).
      if (added != null &&
          _resolvedToken > token &&
          _engine.state.selectedSubtitle == added) {
        await _engine.setSubtitleTrack(_pickedTrack);
      }
      return;
    }
    if (added == null && mounted) {
      // No se pudo bajar: queda el subtítulo que había.
      _showOsd('No se pudo cargar el subtítulo');
    }
    _resolvePick(token);
    if (_delay != Duration.zero) await _engine.setSubtitleDelay(_delay);
  }

  /// Clave de la pista de subtítulos que suena ahora (para recordar su
  /// retraso), o `null` si no hay ninguna.
  String? _selectedSubtitleKey() {
    final selected = _engine.state.selectedSubtitle;
    if (selected == null) return null;
    if (!selected.isExternal) return 'emb:${selected.id}';
    for (final e in _loadedExternal.entries) {
      if (e.value == selected) return e.key;
    }
    return 'trk:${selected.id}';
  }

  /// El usuario cambió de subtítulo con [change] a la pista [nextKey] (`null`
  /// si los apaga): el retraso del que dejó queda guardado con él y el nuevo
  /// arranca con el suyo (o en cero). El retraso es de cada subtítulo.
  Future<void> _changeSubtitle(
    String? nextKey,
    Future<void> Function() change,
  ) async {
    _userPickedSubtitle = true;
    final previous = _selectedSubtitleKey();
    if (previous != null) _trackDelays[previous] = _delay;
    // Elegir otra cosa cancela el «Descargando…» de una elección anterior.
    final token = ++_pickToken;
    if (_loadingEntry != null && mounted) setState(() => _loadingEntry = null);
    await change();
    _resolvePick(token);
    if (!mounted || nextKey == null || nextKey == previous) return;
    final delay = _trackDelays[nextKey] ?? Duration.zero;
    if (delay != _delay) _setDelay(delay);
  }

  SubtitleMenuData? _subtitleMenu(PlaybackState state) {
    if (widget.catalog == null && widget.lateSubtitles == null) return null;
    return SubtitleMenuData(
      // Las entradas se arman al abrir el menú, no en cada cuadro.
      entries: () => _catalog.menuEntries(
        state.subtitleTracks.where((t) => !t.isExternal).toList(),
      ),
      alignmentOf: _catalog.alignmentOf,
      isLoading: (entry) => _loadingEntry?.id == entry.id,
      isSelected: (entry) {
        // Bajando una, la que queda tildada es esa y ninguna otra.
        final loading = _loadingEntry;
        if (loading != null) return loading.id == entry.id;
        final selected = state.selectedSubtitle;
        if (selected == null) return false;
        return entry.embedded != null
            ? entry.embedded == selected
            : _loadedExternal[entry.id] == selected;
      },
    );
  }

  // --- Retraso y asistente de sincronización -----------------------------------

  void _setDelay(Duration delay, {bool osd = true}) {
    _delay = delay;
    unawaited(_engine.setSubtitleDelay(delay));
    widget.onSubtitleDelayChanged?.call(delay);
    if (osd) _showOsd('Subtítulos ${formatDelay(delay)}');
  }

  bool get _syncAvailable => _catalog.externals.isNotEmpty;

  /// S (o el menú): abre el asistente. Si ya está abierto no borra las marcas,
  /// solo le devuelve el foco. Sin subtítulos de addons avisa en vez de abrir.
  void _openSync() {
    if (_syncOpen) {
      _refocus();
      return;
    }
    if (!_syncAvailable) {
      _showOsd(
        _lateLoaded
            ? 'No hay subtítulos de addons para sincronizar'
            : 'Buscando subtítulos de addons…',
      );
      return;
    }
    setState(() {
      _syncOpen = true;
      _syncMarks.clear();
      _infoOpen = false;
    });
    _poke();
  }

  void _closeSync() {
    setState(() => _syncOpen = false);
    _focus.requestFocus();
  }

  void _addMark() {
    setState(() => _syncMarks.add(_engine.state.position));
  }

  /// I (o el botón): el panel de datos y el asistente no van juntos.
  void _toggleInfo() {
    setState(() {
      _infoOpen = !_infoOpen;
      if (_infoOpen) _syncOpen = false;
    });
    _refocus();
  }

  Future<void> _applyMatch(SyncMatch match) async {
    final entry = _catalog.entryFor(match.subtitle);
    if (entry != null) {
      await _changeSubtitle(entry.id, () => _selectEntry(entry));
    }
    if (!mounted) return;
    _setDelay(match.suggestedDelay ?? Duration.zero);
    _closeSync();
  }

  /// Diagnóstico: aplica las marcas de `PARCEL_DIAG_SYNC_TAPS` y cuenta qué
  /// quedó.
  Future<void> _maybeRunSyncTaps() async {
    if (widget.syncTaps.isEmpty || !mounted) return;
    final result = SubtitleSyncMatcher.match(
      candidates: _catalog.syncCandidates(),
      marks: widget.syncTaps,
      videoDuration: _engine.state.duration,
      priority: _catalog.priority,
    );
    _decide(
      'sincronización con ${widget.syncTaps.length} marcas: quedan '
      '${result.matches.length} de '
      '${result.matches.length + result.discarded.length} subtítulos'
      '${result.matches.isEmpty ? '' : '; el mejor: ${_labelOf(result.matches.first.subtitle)}, retraso ${result.matches.first.suggestedDelay == null ? 'sin dato' : formatDelay(result.matches.first.suggestedDelay!)}'}',
    );
    if (result.matches.isNotEmpty) await _applyMatch(result.matches.first);
  }

  String _labelOf(Subtitle subtitle) =>
      _catalog.entryFor(subtitle)?.label ?? subtitle.lang;

  // --- Siguiente episodio -------------------------------------------------------

  /// `true` en los créditos (los últimos 30 s, o desde el capítulo «Credits» si
  /// el archivo lo trae) y al terminar.
  bool _inCredits(PlaybackState s) {
    if (widget.next == null) return false;
    if (s.completed) return true;
    final duration = s.duration;
    if (duration <= Duration.zero) return false;
    final start = _stats.creditsStart;
    if (start != null) return s.position >= start;
    // Un video muy corto no tiene créditos aparte.
    if (duration < PlayerScreen.creditsWindow * 2) return false;
    return s.position >= duration - PlayerScreen.creditsWindow;
  }

  bool _nextVisible(PlaybackState s) => !_nextDismissed && _inCredits(s);

  void _updateNextEpisode(PlaybackState s) {
    if (!mounted) return;
    if (!_inCredits(s)) {
      // Salió de los créditos (volvió atrás en el video): se rearma todo.
      _stopCountdown();
      _countdownCancelled = false;
      if (_nextDismissed) setState(() => _nextDismissed = false);
      return;
    }
    if (widget.autoNext &&
        !_nextDismissed &&
        !_countdownCancelled &&
        _countdownTimer == null) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    setState(() => _countdown = PlayerScreen.nextCountdown);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Con el video en pausa o la ventana sin foco la cuenta espera (al
      // terminar el video ya no hay nada que esperar).
      final state = _engine.state;
      if (!_appActive || (!state.playing && !state.completed)) return;
      final left = (_countdown ?? 1) - 1;
      if (left > 0) {
        setState(() => _countdown = left);
        return;
      }
      timer.cancel();
      _countdownTimer = null;
      setState(() => _countdown = 0);
      _decide('siguiente episodio: lo abre solo al terminar la cuenta');
      widget.next?.onOpen(context);
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdown != null && mounted) setState(() => _countdown = null);
  }

  /// «Cancelar» (o cerrar la tarjeta): no abre solo y la tarjeta se va hasta
  /// que se salga de los créditos.
  void _dismissNext() {
    _stopCountdown();
    _countdownCancelled = true;
    setState(() => _nextDismissed = true);
  }

  // --- Progreso ----------------------------------------------------------------

  void _onEngineState(PlaybackState s) {
    if (!_started && playbackStarted(s, from: _openedAt)) {
      _started = true;
      _openTimer?.cancel();
      if (_stalled && mounted) setState(() => _stalled = false);
    }
    if (!_started && s.error != null) _failOver('error al abrir');
    final paused = _wasPlaying && !s.playing;
    final finished = s.completed && !_wasCompleted;
    _wasPlaying = s.playing;
    _wasCompleted = s.completed;
    if (paused || finished) _reportProgress();
    // Al terminar el video la tarjeta vuelve (sin cuenta, si se la canceló).
    if (finished && _nextDismissed) setState(() => _nextDismissed = false);
    _updateNextEpisode(s);
    if (finished && widget.autoOpenNext && widget.next != null) {
      _decide('siguiente episodio: lo abre solo (diagnóstico)');
      unawaited(
        Future<void>.delayed(const Duration(seconds: 1), () {
          if (mounted) widget.next!.onOpen(context);
        }),
      );
    }
  }

  void _reportProgress({bool onlyIfPlaying = false}) {
    final report = widget.onProgress;
    if (report == null) return;
    final s = _engine.state;
    if (onlyIfPlaying && !s.playing) return;
    if (s.error != null || s.duration <= Duration.zero) return;
    if (s.position < PlayerScreen.minProgress) return;
    report(s.position, s.duration);
  }

  // --- Pantalla completa --------------------------------------------------------

  Future<void> _syncFullScreen() async {
    final window = widget.window;
    if (window == null) return;
    final value = await window.isFullScreen();
    if (mounted) setState(() => _fullScreen = value);
  }

  Future<void> _toggleFullScreen() async {
    final window = widget.window;
    if (window == null) return;
    final next = !await window.isFullScreen();
    await window.setFullScreen(next);
    if (mounted) setState(() => _fullScreen = next);
    // Al cambiar de modo la ventana puede quedarse con el foco: se recupera
    // para que el teclado siga andando (en el asistente, si está abierto).
    if (mounted) _refocus();
  }

  /// Esc: cierra el asistente de sincronización o el panel de datos; si no,
  /// sale de pantalla completa; si no, vuelve.
  Future<void> _escape() async {
    if (_syncOpen) {
      _closeSync();
      return;
    }
    if (_infoOpen) {
      setState(() => _infoOpen = false);
      return;
    }
    final window = widget.window;
    if (window != null && await window.isFullScreen()) {
      await window.setFullScreen(false);
      if (mounted) {
        setState(() => _fullScreen = false);
        _refocus();
      }
      return;
    }
    if (mounted) _back();
  }

  /// Un clic pausa o reanuda; dos seguidos pasan a pantalla completa (y
  /// deshacen la pausa del primero).
  void _onSurfaceTap() {
    if (widget.window == null) {
      _playOrPause();
      return;
    }
    if (_tapTimer?.isActive ?? false) {
      _tapTimer!.cancel();
      unawaited(_toggleFullScreen());
      _playOrPause();
    } else {
      _playOrPause();
      _tapTimer = Timer(_doubleTap, () {});
    }
  }

  void _retry() {
    final position = _engine.state.position;
    final source = position > Duration.zero
        ? PlaybackSource(
            url: widget.source.url,
            headers: widget.source.headers,
            startPosition: position,
          )
        : widget.source;
    // Las pistas externas se pierden al reabrir: si había una elegida se
    // vuelve a cargar, sin tocar el catálogo ni rehacer su análisis.
    SubtitleEntry? restore;
    final selected = _engine.state.selectedSubtitle;
    if (selected != null && selected.isExternal) {
      final id = _selectedSubtitleKey();
      for (final e in _catalog.externals) {
        if (e.id == id) restore = e;
      }
    }
    unawaited(_start(source, retry: _autoStarted, restore: restore));
    _poke();
  }

  /// Elegir otra fuente cuando la actual no arranca: con el menú «Fuente» se
  /// elige ahí mismo; si no hay, se vuelve a la lista.
  Future<void> _chooseOtherSource() async {
    final menu = widget.sourceMenu;
    if (menu == null || menu.candidates.length < 2) {
      _back();
      return;
    }
    final index = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Elegir otra fuente'),
        children: [
          for (var i = 0; i < menu.candidates.length; i++)
            if (i != menu.current)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(i),
                child: Text(menu.candidates[i].label),
              ),
        ],
      ),
    );
    if (index != null && mounted) {
      menu.onPick(index, _engine.state.position);
    }
  }

  // --- Controles que se ocultan ---------------------------------------------

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(PlayerScreen.hideAfter, () {
      if (!mounted || _menuOpen || _dragValue != null) return;
      if (_engine.state.error != null) return;
      setState(() => _controlsVisible = false);
    });
  }

  /// Muestra los controles y reinicia la cuenta para ocultarlos.
  void _poke() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _showOsd(String text) {
    _osdTimer?.cancel();
    setState(() => _osd = text);
    _osdTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _osd = null);
    });
  }

  void _menuOpened() {
    _menuOpen = true;
    _hideTimer?.cancel();
  }

  void _menuClosed() {
    _menuOpen = false;
    _refocus();
    _poke();
  }

  // --- Acciones --------------------------------------------------------------

  void _back() => Navigator.of(context).maybePop();

  void _playOrPause() {
    unawaited(_engine.playOrPause());
    _poke();
  }

  void _seekBy(Duration delta) {
    final s = _engine.state;
    if (s.duration <= Duration.zero) return;
    var target = s.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > s.duration) target = s.duration;
    unawaited(_engine.seek(target));
    _showOsd(
      '${delta.isNegative ? '−' : '+'}${delta.inSeconds.abs()} s · '
      '${formatPlaybackTime(target)}',
    );
    _poke();
  }

  void _changeVolume(double volume) {
    final v = volume.clamp(0.0, 1.0);
    unawaited(_engine.setVolume(v));
    _showOsd('Volumen ${(v * 100).round()} %');
    _poke();
  }

  void _toggleMute() {
    final v = _engine.state.volume;
    if (v > 0) {
      _volumeBeforeMute = v;
      _changeVolume(0);
    } else {
      _changeVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 0.5);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.escape && !isRepeat) {
      unawaited(_escape());
    } else if (key == LogicalKeyboardKey.keyF && !isRepeat) {
      unawaited(_toggleFullScreen());
    } else if (key == LogicalKeyboardKey.keyI && !isRepeat) {
      _toggleInfo();
    } else if (key == LogicalKeyboardKey.keyS && !isRepeat) {
      // Con el asistente abierto S marca; nunca lo reabre ni borra las marcas.
      if (_syncOpen) {
        _addMark();
      } else {
        _openSync();
      }
    } else if (key == LogicalKeyboardKey.keyG) {
      _setDelay(_delay - subtitleDelayStep);
    } else if (key == LogicalKeyboardKey.keyH) {
      _setDelay(_delay + subtitleDelayStep);
    } else if (key == LogicalKeyboardKey.enter &&
        !isRepeat &&
        widget.next != null &&
        _nextVisible(_engine.state)) {
      widget.next!.onOpen(context);
    } else if (key == LogicalKeyboardKey.space && !isRepeat) {
      _playOrPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-_seekStep);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(_seekStep);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _changeVolume(_engine.state.volume + _volumeStep);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _changeVolume(_engine.state.volume - _volumeStep);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- Dibujo ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: StreamBuilder<PlaybackState>(
            stream: engine.stream,
            initialData: engine.state,
            builder: (context, snapshot) {
              final state = snapshot.data ?? engine.state;
              return _buildBody(context, state);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PlaybackState state) {
    final engine = _engine;
    // Con quien prueba otras fuentes, un error antes de arrancar no muestra la
    // pantalla de error: se está cambiando de fuente.
    final switching = widget.onOpenFailed != null && !_started;
    final hasError = (state.error != null && !switching) || _stalled;
    final atmos = isAtmosTrack(state.selectedAudio);
    // El overlay dura hasta el primer cuadro real (la regla `playbackStarted`)
    // y vuelve si el video se queda cargando después.
    final started = _started || playbackStarted(state, from: _openedAt);
    final loading = !hasError && (!started || state.buffering || switching);
    final showControls = _controlsVisible && !hasError;

    return MouseRegion(
      cursor: showControls || hasError
          ? MouseCursor.defer
          : SystemMouseCursors.none,
      onHover: (_) => _poke(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const Key('player-surface'),
            behavior: HitTestBehavior.opaque,
            onTap: hasError ? null : _onSurfaceTap,
            child: engine is VideoSurfaceProvider
                ? (engine as VideoSurfaceProvider).buildVideoSurface(context)
                : const ColoredBox(color: Colors.black),
          ),
          if (loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(key: Key('player-loading')),
                  if (state.duration <= Duration.zero) ...[
                    const SizedBox(height: 16),
                    const Text('Cargando…'),
                  ],
                ],
              ),
            ),
          if (_osd != null)
            Positioned(
              top: 72,
              right: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(_osd!, key: const Key('player-osd')),
                ),
              ),
            ),
          IgnorePointer(
            ignoring: !showControls,
            child: AnimatedOpacity(
              key: const Key('player-controls'),
              opacity: showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: PlayerControls(
                state: state,
                stats: _stats,
                title: widget.title,
                dragValue: _dragValue,
                onBack: _back,
                onPlayOrPause: _playOrPause,
                onSeekChanged: (v) => setState(() => _dragValue = v),
                onSeekEnd: (v) {
                  setState(() => _dragValue = null);
                  unawaited(_engine.seek(Duration(milliseconds: v.round())));
                  _poke();
                },
                onVolumeChanged: _changeVolume,
                onToggleMute: _toggleMute,
                onSelectAudio: (t) {
                  _userPickedAudio = true;
                  unawaited(_engine.setAudioTrack(t));
                },
                onSelectSubtitle: (t) => unawaited(
                  _changeSubtitle(
                    t == null
                        ? null
                        : (t.isExternal ? 'trk:${t.id}' : 'emb:${t.id}'),
                    () => _engine.setSubtitleTrack(t),
                  ),
                ),
                subtitles: _subtitleMenu(state),
                onSelectSubtitleEntry: (entry) => unawaited(
                  _changeSubtitle(entry.id, () => _selectEntry(entry)),
                ),
                onOpenSync: _syncAvailable ? _openSync : null,
                sourceMenu: widget.sourceMenu,
                atmos: atmos,
                onToggleInfo: _toggleInfo,
                onMenuOpened: _menuOpened,
                onMenuClosed: _menuClosed,
                isFullScreen: _fullScreen,
                onToggleFullScreen: widget.window == null
                    ? null
                    : () => unawaited(_toggleFullScreen()),
              ),
            ),
          ),
          if (_infoOpen)
            Positioned(
              top: 64,
              right: 0,
              bottom: 112,
              child: InfoPanel(
                stats: _stats,
                info: widget.info,
                atmos: atmos,
                onClose: () {
                  setState(() => _infoOpen = false);
                  _refocus();
                },
              ),
            ),
          if (_syncOpen)
            Positioned(
              left: Spacing.lg,
              bottom: 112,
              child: LayoutBuilder(
                builder: (context, _) => SubtitleSyncOverlay(
                  candidates: _catalog.syncCandidates(),
                  marks: List.unmodifiable(_syncMarks),
                  videoDuration: state.duration,
                  priority: _catalog.priority,
                  labelOf: _labelOf,
                  onMark: _addMark,
                  onApply: (m) => unawaited(_applyMatch(m)),
                  onClose: _closeSync,
                  focusNode: _syncFocus,
                  analyzing: _catalog.analyzing,
                ),
              ),
            ),
          if (widget.next != null && _nextVisible(state))
            Positioned(
              // Con el panel de datos abierto la tarjeta se corre para no pisarlo.
              right: _infoOpen ? InfoPanel.width + Spacing.md : Spacing.lg,
              bottom: 128,
              child: _NextEpisodeCard(
                next: widget.next!,
                countdown: _countdown,
                onDismiss: _dismissNext,
              ),
            ),
          if (hasError)
            _ErrorOverlay(
              message: _stalled && state.error == null
                  ? 'La fuente no empezó a reproducirse.'
                  : redactUrlsInText(state.error ?? ''),
              onRetry: _retry,
              onBack: _back,
              onChooseSource: _chooseOtherSource,
            ),
        ],
      ),
    );
  }
}

/// Tarjeta que aparece al terminar un episodio con el que sigue.
class _NextEpisodeCard extends StatelessWidget {
  const _NextEpisodeCard({
    required this.next,
    required this.onDismiss,
    this.countdown,
  });

  final NextEpisode next;
  final VoidCallback onDismiss;

  /// Segundos que faltan para que arranque solo; `null` si no hay cuenta.
  final int? countdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('player-next-card'),
      color: Colors.black.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.sm,
          Spacing.sm,
          Spacing.md,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Siguiente episodio',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onDismiss,
                  ),
                ],
              ),
              Text(
                next.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              if (countdown != null)
                Text(
                  'Empieza en $countdown s',
                  key: const Key('player-next-countdown'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  FilledButton.icon(
                    key: const Key('player-next'),
                    onPressed: () => next.onOpen(context),
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Ver siguiente episodio'),
                  ),
                  if (countdown != null)
                    OutlinedButton(
                      key: const Key('player-next-cancel'),
                      onPressed: onDismiss,
                      child: const Text('Cancelar'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({
    required this.message,
    required this.onRetry,
    required this.onBack,
    required this.onChooseSource,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback onChooseSource;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const Key('player-error'),
      color: Colors.black87,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                'No se pudo reproducir el video',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                  OutlinedButton(
                    key: const Key('player-choose-source'),
                    onPressed: onChooseSource,
                    child: const Text('Elegir otra fuente'),
                  ),
                  TextButton(onPressed: onBack, child: const Text('Volver')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
