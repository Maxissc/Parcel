import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart' hide Video;

import '../../data/browse_providers.dart';
import '../../data/progress_providers.dart';
import '../../data/providers.dart';
import '../../features/detail/detail_utils.dart';
import '../../features/onboarding/onboarding_controller.dart';
import '../../features/player/play_item.dart';
import '../../features/player/player_route.dart';
import '../../features/streams/streams_args.dart';
import '../../shared/media_labels.dart';
import '../router.dart';
import 'diag_log.dart';
import 'playback_diagnostics.dart';

/// Hace lo que pide el modo de diagnóstico (solo debug) una vez que la app
/// está en pantalla: abrir el reproductor con `PARCEL_DIAG_URL`, importar
/// addons con `PARCEL_DIAG_PASTE`, recorrer la navegación (inicio, búsqueda,
/// detalle, streams, reproducción) con `PARCEL_DIAG_OPEN`,
/// `PARCEL_DIAG_SEARCH` y `PARCEL_DIAG_PLAY_FIRST_STREAM`, y cerrar la app con
/// `PARCEL_DIAG_EXIT_SECONDS`. Cuenta lo que cargó con líneas `[diag]`.
///
/// Si no hay configuración de diagnóstico, no hace nada.
class DiagnosticsDriver extends ConsumerStatefulWidget {
  const DiagnosticsDriver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DiagnosticsDriver> createState() => _DiagnosticsDriverState();
}

class _DiagnosticsDriverState extends ConsumerState<DiagnosticsDriver> {
  Timer? _exitTimer;

  DiagLog get _log => ref.read(diagLogProvider);

  @override
  void initState() {
    super.initState();
    final config = ref.read(diagnosticsConfigProvider);
    if (config == null) return;
    final exitAfter = config.exitAfter;
    if (exitAfter != null) {
      _exitTimer = Timer(exitAfter, () {
        ref.read(diagLogProvider).log('cierre por PARCEL_DIAG_EXIT_SECONDS');
        exit(0);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final paste = config.paste;
      final pasted = paste == null ? Future<void>.value() : _runPaste(paste);
      final url = config.url;
      if (url != null) {
        unawaited(
          ref
              .read(routerProvider)
              .push(
                Routes.player,
                extra: PlayerArgs(
                  url: url,
                  subtitleUrl: config.subtitleUrl,
                  title: Uri.tryParse(url)?.pathSegments.lastOrNull,
                ),
              ),
        );
        return;
      }
      unawaited(pasted.then((_) => _browse(config)));
    });
  }

  /// Completa el asistente como si el usuario pegara [text] y confirmara.
  /// El asistente deja el informe en el log (líneas `[diag]`).
  Future<void> _runPaste(String text) async {
    _log.log('diagnóstico: pega la lista y confirma');
    // Mantiene vivo el estado del asistente mientras corre.
    final keepAlive = ref.listenManual(onboardingProvider, (_, _) {});
    try {
      ref.read(routerProvider).go(Routes.onboarding);
      final controller = ref.read(onboardingProvider.notifier)
        ..chooseSource(OnboardingStep.paste)
        ..submitPaste(text);
      await controller.importSelected();
    } finally {
      keepAlive.close();
    }
  }

  // --- Recorrido de la navegación -------------------------------------------

  /// Espera un `FutureProvider` manteniéndolo vivo mientras tanto (los de
  /// búsqueda, detalle y streams se sueltan solos si nadie los mira).
  Future<T> _await<T>(FutureProvider<T> provider) async {
    final hold = ref.listenManual(provider, (_, _) {});
    try {
      return await ref.read(provider.future);
    } finally {
      hold.close();
    }
  }

  Future<void> _browse(DiagnosticsConfig config) async {
    if (!mounted) return;
    if (ref.read(addonRepositoryProvider).addons.isEmpty) {
      _log.log('diagnóstico: no hay addons instalados; no se recorre nada');
      return;
    }
    // Con un recorrido pedido se parte desde el inicio; si no, la pantalla
    // queda donde estaba (por ejemplo, el informe del asistente).
    if (config.open != null || config.search != null) {
      ref.read(routerProvider).go(Routes.home);
    }
    try {
      await _logHome();
      final search = config.search;
      if (search != null) await _logSearch(search);
      final open = config.open;
      if (open != null) await _logOpen(open, config.playFirstStream);
    } on Object catch (e) {
      _log.log('diagnóstico: el recorrido falló: ${e.runtimeType}');
    }
  }

  Future<void> _logHome() async {
    final catalogs = ref.read(addonAggregatorProvider).homeCatalogs();
    final results = await Future.wait([
      for (final catalog in catalogs)
        _await(catalogItemsProvider((catalog: catalog, search: null))),
    ]);
    var withItems = 0;
    for (var i = 0; i < catalogs.length; i++) {
      final c = catalogs[i];
      final name =
          '«${c.catalog.name} · ${typeLabel(c.catalog.type)}» '
          '(${c.addon.manifest.name})';
      switch (results[i]) {
        case AddonFailure(:final error):
          _log.log('home fila $name: no se pudo cargar (${error.reason.name})');
        case AddonSuccess(:final value) when value.isEmpty:
          _log.log('home fila $name: vacía, se oculta');
        case AddonSuccess(:final value):
          withItems++;
          _log.log('home fila $name: ${value.length} ítems');
      }
    }
    _log.log('home: $withItems de ${catalogs.length} catálogos con ítems');
    final watching = ref.read(continueWatchingProvider);
    _log.log('seguir viendo: ${watching.length} ítems');
    for (final p in watching) {
      final tag = p.type == 'movie'
          ? ''
          : ' ${episodeLabelFromVideoId(p.videoId) ?? ''}';
      _log.log(
        'seguir viendo: «${p.name}»$tag ${(p.fraction * 100).round()} % '
        '(${formatPlaybackTime(p.position)} de ${formatPlaybackTime(p.duration)})',
      );
    }
  }

  Future<void> _logSearch(String query) async {
    ref.read(routerProvider).go(Routes.search);
    final catalogs = ref.read(addonAggregatorProvider).searchCatalogs();
    final results = await Future.wait([
      for (final catalog in catalogs)
        _await(catalogItemsProvider((catalog: catalog, search: query))),
    ]);
    final parts = <String>[];
    for (var i = 0; i < catalogs.length; i++) {
      final name =
          '«${catalogs[i].catalog.name} · ${typeLabel(catalogs[i].catalog.type)}»';
      parts.add(switch (results[i]) {
        AddonFailure(:final error) => '$name falló (${error.reason.name})',
        AddonSuccess(:final value) => '$name ${value.length} resultados',
      });
    }
    _log.log(
      'búsqueda «$query»: ${catalogs.length} catálogos con búsqueda'
      '${parts.isEmpty ? '' : '; ${parts.join('; ')}'}',
    );
  }

  Future<void> _logOpen(String open, bool playFirstStream) async {
    final slash = open.indexOf('/');
    if (slash <= 0 || slash == open.length - 1) {
      _log.log('diagnóstico: PARCEL_DIAG_OPEN tiene que ser tipo/id');
      return;
    }
    final type = open.substring(0, slash);
    final id = open.substring(slash + 1);
    final router = ref.read(routerProvider);
    unawaited(router.push(Routes.detailPath(type, id)));

    final metaResult = await _await(metaProvider((type: type, id: id)));
    final Meta meta;
    switch (metaResult) {
      case null:
        _log.log('detalle $open: ningún addon ofrece la meta');
        return;
      case AddonFailure(:final error):
        _log.log('detalle $open: falló (${error.reason.name})');
        return;
      case AddonSuccess(:final value):
        meta = value;
    }
    final seasons = hasEpisodes(meta) ? seasonsOf(meta) : const <int>[];
    _log.log(
      'detalle $open: «${meta.name}» · ${meta.videos.length} episodios · '
      '${seasons.length} temporadas $seasons · '
      'fondo=${meta.background != null ? 'sí' : 'no'} '
      'logo=${meta.logo != null ? 'sí' : 'no'} '
      'géneros=${meta.genres.length} elenco=${meta.cast.length}',
    );

    final video = hasEpisodes(meta) ? orderedEpisodes(meta).first : null;
    final args = StreamsArgs(meta: meta, video: video);
    final label = video == null ? meta.id : video.id;
    final hold = ref.listenManual(streamsProvider(args.key), (_, _) {});
    final state = await _streams(args.key);
    hold.close();
    if (state.groups.isEmpty) {
      _log.log(
        'streams ${args.key.type} $label: ningún addon instalado ofrece '
        'streams para esto',
      );
    }
    final playable = <(StreamGroup, AddonStream)>[];
    for (final group in state.groups) {
      switch (group.result) {
        case AddonFailure(:final error):
          _log.log(
            'streams ${args.key.type} $label: ${group.addon.manifest.name}: '
            'falló (${error.reason.name})',
          );
        case AddonSuccess<List<AddonStream>>(:final value):
          final ok = value.where((s) => s.isPlayable).toList();
          _log.log(
            'streams ${args.key.type} $label: ${group.addon.manifest.name}: '
            '${value.length} streams (${ok.length} reproducibles)',
          );
          playable.addAll([for (final s in ok) (group, s)]);
        case null:
          break;
      }
    }

    if (!playFirstStream) return;
    if (playable.isEmpty) {
      _log.log('diagnóstico: no hay ningún stream reproducible');
      return;
    }
    final (group, stream) = playable.first;
    unawaited(router.push(Routes.streams, extra: args));
    await Future<void>.delayed(const Duration(seconds: 1));
    _log.log(
      'reproducción: abre el primer stream reproducible de '
      '${group.addon.manifest.name} para «${meta.name}»',
    );
    unawaited(
      router.push(
        Routes.player,
        extra: PlayerArgs(
          url: stream.url!,
          headers: stream.behaviorHints.proxyRequestHeaders,
          item: PlayItem(
            meta: meta,
            video: video,
            stream: stream,
            addonUrl: group.addon.transportUrl,
          ),
        ),
      ),
    );
  }

  /// Espera a que todos los addons de streams hayan respondido (o fallado).
  Future<StreamsState> _streams(StreamsKey key) {
    final done = Completer<StreamsState>();
    final sub = ref.listenManual(streamsProvider(key), (_, next) {
      final value = next.value;
      if (value != null && !value.loading && !done.isCompleted) {
        done.complete(value);
      }
    }, fireImmediately: true);
    return done.future
        .timeout(
          const Duration(seconds: 40),
          onTimeout: () => const StreamsState([]),
        )
        .whenComplete(sub.close);
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
