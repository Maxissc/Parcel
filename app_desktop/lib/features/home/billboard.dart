import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/theme.dart';
import '../../data/browse_providers.dart';
import '../../data/progress_providers.dart';
import '../../shared/media_labels.dart';
import '../../shared/remote_image.dart';
import '../../shared/urls.dart';
import '../player/play_item.dart';
import 'home_rows.dart';
import 'meta_actions.dart';

/// Un destacado del billboard: la meta y, si viene de «Seguir viendo», lo que
/// quedó a medias.
class BillboardItem {
  const BillboardItem(this.meta, {this.progress});

  final Meta meta;
  final PlaybackProgress? progress;

  /// Texto del botón principal: «Ver» o «Continuar T1 E3».
  String get playLabel {
    final p = progress;
    if (p == null) return 'Ver';
    final tag = p.type == 'movie' ? null : episodeLabelFromVideoId(p.videoId);
    return tag == null ? 'Continuar' : 'Continuar $tag';
  }
}

/// Cuántos destacados rota el billboard como máximo.
const int billboardMax = 4;

/// Los destacados: el primero de «Seguir viendo» si hay; después los primeros
/// de los catálogos de la home (en el orden elegido) hasta [billboardMax].
final billboardItemsProvider = Provider.autoDispose<List<BillboardItem>>((ref) {
  final items = <BillboardItem>[];
  final seen = <String>{};
  final watching = ref.watch(continueWatchingProvider);
  if (watching.isNotEmpty) {
    final p = watching.first;
    seen.add('${p.type}/${p.metaId}');
    items.add(
      BillboardItem(
        Meta(
          id: p.metaId,
          type: p.type,
          name: p.name,
          poster: p.poster,
          background: p.thumbnail,
        ),
        progress: p,
      ),
    );
  }
  // Se miran pocas filas: el destacado no tiene que pedir toda la home.
  for (final catalog in ref.watch(homeRowsProvider).take(3)) {
    if (items.length >= billboardMax) break;
    final result = ref
        .watch(catalogItemsProvider((catalog: catalog, search: null)))
        .value;
    // Si una fila anterior todavía carga se espera: así el destacado no salta
    // de una fila a otra cuando llega la primera.
    if (result == null) break;
    if (result is! AddonSuccess<List<Meta>>) continue;
    for (final meta in result.value) {
      if (items.length >= billboardMax) break;
      if (meta.background == null && meta.poster == null) continue;
      if (seen.add('${meta.type}/${meta.id}')) items.add(BillboardItem(meta));
    }
    // Con los de la primera fila que carga ya alcanza para mostrar algo.
    if (items.isNotEmpty) break;
  }
  return items;
});

/// Cómo se precarga una imagen en la caché (se reemplaza en los tests).
typedef ImagePrecache = Future<void> Function(
  ImageProvider image,
  BuildContext context,
);

final billboardPrecacheProvider = Provider<ImagePrecache>(
  (ref) =>
      (image, context) => precacheImage(image, context, onError: (_, _) {}),
);

/// El destacado de arriba de la home: rota solo, se frena con el mouse
/// encima o con la ventana sin foco.
class Billboard extends ConsumerStatefulWidget {
  const Billboard({super.key, this.interval = const Duration(seconds: 9)});

  final Duration interval;

  @override
  ConsumerState<Billboard> createState() => _BillboardState();
}

class _BillboardState extends ConsumerState<Billboard>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _index = 0;
  bool _hovered = false;
  bool _focused = true;

  /// `false` cuando otra pantalla tapa la home (por ejemplo el reproductor):
  /// no rota ni gasta cuadros.
  ValueListenable<TickerModeData>? _visible;

  /// Qué destacado y a qué ancho ya se precargó el siguiente.
  String? _precached;
  double _width = 0;

  bool get _paused => _hovered || !_focused || _visible?.value.enabled == false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _focused = state == null || state == AppLifecycleState.resumed;
    _restart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.getValuesNotifier(context);
    if (visible == _visible) return;
    _visible?.removeListener(_onVisibleChanged);
    _visible = visible..addListener(_onVisibleChanged);
  }

  void _onVisibleChanged() {
    // Al volver a verse, la cuenta arranca de nuevo.
    if (mounted && _visible?.value.enabled == true) _restart();
  }

  @override
  void dispose() {
    _visible?.removeListener(_onVisibleChanged);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final focused = state == AppLifecycleState.resumed;
    if (focused && !_focused) _restart();
    _focused = focused;
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (_paused || !mounted) return;
      final count = ref.read(billboardItemsProvider).length;
      if (count < 2) return;
      setState(() => _index = (_index + 1) % count);
    });
  }

  /// Baja de antemano el fondo del destacado que sigue, para que al rotar ya
  /// esté en la caché y no haya un destello de fondo vacío.
  void _precacheNext() {
    if (!mounted || _width <= 0) return;
    final items = ref.read(billboardItemsProvider);
    if (items.length < 2) return;
    final next = items[(_index + 1) % items.length].meta;
    final url = next.background ?? next.poster;
    if (url == null || !isHttpUrl(url)) return;
    final provider = remoteImageProvider(
      url,
      _width,
      MediaQuery.devicePixelRatioOf(context),
    );
    unawaited(ref.read(billboardPrecacheProvider)(provider, context));
  }

  void _select(int index) {
    setState(() => _index = index);
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(billboardItemsProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, items.length - 1);
    final item = items[index];
    final reduce = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final key =
            '$index|${items.length}|${items[(index + 1) % items.length].meta.id}|$_width';
        if (key != _precached) {
          _precached = key;
          WidgetsBinding.instance.addPostFrameCallback((_) => _precacheNext());
        }
        final height = (constraints.maxWidth * 0.34).clamp(260.0, 420.0);
        return MouseRegion(
          onEnter: (_) => _hovered = true,
          onExit: (_) {
            _hovered = false;
            // Al salir el mouse, el destacado se queda un intervalo entero.
            _restart();
          },
          child: SizedBox(
            key: const Key('billboard'),
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _Slide(
                    key: ValueKey('${item.meta.type}/${item.meta.id}'),
                    item: item,
                    width: constraints.maxWidth,
                  ),
                ),
                Positioned(
                  right: Spacing.lg,
                  bottom: Spacing.md,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _Dot(
                          key: Key('billboard-dot-$i'),
                          selected: i == index,
                          label: 'Destacado ${i + 1}',
                          onTap: () => _select(i),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: selected ? 30 : 20,
            height: 4,
            decoration: BoxDecoration(
              color: selected ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un destacado: fondo con degradado, logo o título, datos, sinopsis y
/// botones.
class _Slide extends ConsumerWidget {
  const _Slide({super.key, required this.item, required this.width});

  final BillboardItem item;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fade = theme.scaffoldBackgroundColor;
    final actions = MetaActions(context, ref);
    // Un ítem de «Seguir viendo» no trae sinopsis ni logo: se completa con la
    // meta del addon cuando llega.
    final full = item.progress == null
        ? null
        : ref
              .watch(metaProvider((type: item.meta.type, id: item.meta.id)))
              .value;
    final fullMeta = full is AddonSuccess<Meta> ? full.value : null;
    final meta = fullMeta ?? item.meta;
    final facts = [
      if (meta.imdbRating != null) 'IMDb ${meta.imdbRating}',
      ?(meta.releaseInfo ?? meta.released?.year.toString()),
      ...meta.genres.take(3),
    ];
    final image = meta.background ?? item.meta.background ?? meta.poster;

    return Stack(
      fit: StackFit.expand,
      children: [
        RemoteImage(image, width: width, alignment: Alignment.topCenter),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [fade, fade.withValues(alpha: 0.55), Colors.transparent],
              stops: const [0.08, 0.45, 0.8],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [fade, Colors.transparent],
              stops: const [0, 0.5],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.lg,
            Spacing.lg + Spacing.md,
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meta.logo != null)
                    SizedBox(
                      key: const Key('billboard-logo'),
                      height: 64,
                      width: 260,
                      child: RemoteImage(
                        meta.logo,
                        width: 260,
                        showPlaceholder: false,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                      ),
                    )
                  else
                    Text(
                      meta.name,
                      key: const Key('billboard-title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(height: Spacing.sm),
                  if (facts.isNotEmpty)
                    Text(
                      facts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (meta.description != null) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(
                      meta.description!,
                      key: const Key('billboard-synopsis'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: Spacing.md),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Spacing.sm,
                    children: [
                      FilledButton.icon(
                        key: const Key('billboard-play'),
                        onPressed: () => unawaited(
                          actions.play(
                            item.meta,
                            videoId: item.progress?.videoId,
                            resume: item.progress == null
                                ? ResumeMode.ask
                                : ResumeMode.resume,
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(item.playLabel),
                      ),
                      OutlinedButton.icon(
                        key: const Key('billboard-info'),
                        onPressed: () => actions.info(item.meta),
                        icon: const Icon(Icons.info_outline),
                        label: const Text('Más info'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
