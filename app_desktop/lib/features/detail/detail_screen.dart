import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart' hide Video;
import 'package:parcel_core/parcel_core.dart' as core show Video;

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/browse_providers.dart';
import '../../data/platform.dart';
import '../../data/progress_providers.dart';
import '../../data/providers.dart';
import '../../shared/remote_image.dart';
import '../../shared/skeleton.dart';
import '../../shared/state_views.dart';
import '../../shared/urls.dart';
import '../player/play_args.dart';
import '../player/play_item.dart';
import '../streams/streams_args.dart';
import 'cast_section.dart';
import 'detail_utils.dart';
import 'tmdb_enrichment.dart';

/// Detalle de una película o serie: fondo, datos, descripción y elenco, y
/// cómo verla (botón «Ver» o lista de episodios).
///
/// [hint] es el ítem del catálogo desde donde se abrió: se muestra enseguida
/// mientras llega la meta completa.
class DetailScreen extends ConsumerWidget {
  const DetailScreen({
    super.key,
    required this.type,
    required this.id,
    this.hint,
  });

  final String type;
  final String id;
  final Meta? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (type: type, id: id);
    final async = ref.watch(metaProvider(key));
    void retry() => ref.invalidate(metaProvider(key));

    final Widget body = async.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      loading: () => hint == null
          ? const _DetailSkeleton()
          : _DetailBody(meta: hint!, loading: true),
      error: (_, _) =>
          _fallback(message: 'Algo falló al pedir los datos.', onRetry: retry),
      data: (result) => switch (result) {
        AddonSuccess(:final value) => _DetailBody(meta: value),
        AddonFailure(:final error) => _fallback(
          message: _metaFailureMessage(error),
          onRetry: retry,
        ),
        null => _fallback(
          message:
              'Ningún addon instalado ofrece información de este contenido.',
          onRetry: null,
        ),
      },
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            context.canPop() ? context.pop() : context.go(Routes.home),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: body),
              Positioned(
                top: Spacing.md,
                left: Spacing.md,
                child: SafeArea(
                  child: IconButton.filledTonal(
                    tooltip: 'Volver (Esc)',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(Routes.home),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Si la meta completa no llega pero se abrió desde un catálogo, se muestra
  /// lo que ya se sabe, con el aviso y la opción de reintentar.
  Widget _fallback({required String message, required VoidCallback? onRetry}) {
    final item = hint;
    if (item != null) {
      return _DetailBody(meta: item, notice: message, onRetry: onRetry);
    }
    return ErrorState(
      title: 'No pudimos abrir el detalle',
      message: message,
      onRetry: onRetry,
    );
  }
}

/// Frase completa de por qué el addon no pudo dar los datos del contenido.
String _metaFailureMessage(AddonException error) => switch (error.reason) {
  AddonFailureReason.timeout => 'El addon no respondió a tiempo.',
  AddonFailureReason.network => 'No se pudo conectar con el addon.',
  AddonFailureReason.http =>
    error.statusCode == null
        ? 'El addon respondió con un error.'
        : 'El addon respondió con un error (HTTP ${error.statusCode}).',
  AddonFailureReason.parse =>
    'El addon mandó una respuesta que Parcel no entiende.',
  AddonFailureReason.invalidUrl => 'La dirección del addon no es válida.',
  AddonFailureReason.storage => 'No se pudo guardar en disco.',
};

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(Spacing.xl, 96, Spacing.xl, Spacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 180, height: 270, radius: 12),
          SizedBox(width: Spacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 360, height: 36),
                SizedBox(height: Spacing.md),
                Skeleton(width: 240, height: 16),
                SizedBox(height: Spacing.lg),
                Skeleton(height: 14),
                SizedBox(height: Spacing.sm),
                Skeleton(height: 14),
                SizedBox(height: Spacing.sm),
                Skeleton(width: 420, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({
    required this.meta,
    this.loading = false,
    this.notice,
    this.onRetry,
  });

  final Meta meta;

  /// Falta traer la meta completa: se muestran esqueletos donde faltan datos.
  final bool loading;

  /// Aviso de que solo se muestra lo del catálogo.
  final String? notice;
  final VoidCallback? onRetry;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

/// Ancho máximo del contenido del detalle.
const double _detailMaxWidth = 1100;

class _DetailBodyState extends ConsumerState<_DetailBody> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Con la key de TMDB, las fotos del elenco y el idioma original llegan en
    // segundo plano y se mezclan con lo que ya hay.
    final enrichment = ref
        .watch(
          tmdbEnrichmentProvider((type: widget.meta.type, id: widget.meta.id)),
        )
        .value;
    final base = widget.meta;
    final meta = enrichment == null
        ? base
        : base.copyWith(
            originalLanguage:
                base.originalLanguage ?? enrichment.originalLanguage,
            castDetails: mergeCastDetails(base.castDetails, enrichment.cast),
          );
    final loading = widget.loading;
    final notice = widget.notice;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = meta.background ?? meta.poster;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 800;
    // El contenido va centrado con un ancho máximo; el margen se reparte a los
    // costados para que la lista de episodios pueda ser perezosa.
    final side =
        Spacing.xl +
        (width > _detailMaxWidth ? (width - _detailMaxWidth) / 2 : 0);

    return Stack(
      children: [
        // Fondo con degradado hacia el color de la pantalla. Sube junto con el
        // contenido sin estar dentro de la lista.
        ListenableBuilder(
          listenable: _scroll,
          builder: (context, child) => Positioned(
            top: _scroll.hasClients ? -_scroll.offset : 0,
            left: 0,
            right: 0,
            height: 560,
            child: child!,
          ),
          child: RepaintBoundary(
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RemoteImage(
                    background,
                    width: 1280,
                    alignment: Alignment.topCenter,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.surface.withValues(alpha: 0.55),
                          scheme.surface.withValues(alpha: 0.85),
                          scheme.surface,
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          scheme.surface.withValues(alpha: 0.7),
                          scheme.surface.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 96, side, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (wide) ...[
                          _Poster(meta: meta),
                          const SizedBox(width: Spacing.xl),
                        ],
                        Expanded(
                          child: _Info(meta: meta, loading: loading),
                        ),
                      ],
                    ),
                    if (notice != null) ...[
                      const SizedBox(height: Spacing.lg),
                      _Notice(message: notice, onRetry: widget.onRetry),
                    ],
                    if (!loading) ...[
                      const SizedBox(height: Spacing.xl),
                      CastSection(credits: meta.credits),
                    ],
                    const SizedBox(height: Spacing.xl),
                    if (!hasEpisodes(meta))
                      if (loading && meta.type != 'movie')
                        const _EpisodesSkeleton()
                      else if (meta.type == 'series' && notice != null)
                        Text(
                          'No encontramos los episodios.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                  ],
                ),
              ),
            ),
            if (hasEpisodes(meta))
              _Episodes(meta: meta, horizontalPadding: side),
            const SliverToBoxAdapter(child: SizedBox(height: Spacing.xl)),
          ],
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.meta});

  final Meta meta;

  @override
  Widget build(BuildContext context) {
    final landscape = meta.posterShape == 'landscape';
    final width = landscape ? 320.0 : 180.0;
    final height = landscape
        ? 180.0
        : (meta.posterShape == 'square' ? 180.0 : 270.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: height,
          child: RemoteImage(meta.poster, width: width),
        ),
      ),
    );
  }
}

class _Info extends ConsumerWidget {
  const _Info({required this.meta, required this.loading});

  final Meta meta;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final facts = <String>[
      ?(meta.releaseInfo ??
          (meta.released == null ? null : '${meta.released!.year}')),
      ?meta.runtime,
      ?meta.country,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleBlock(meta: meta),
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.md,
          runSpacing: Spacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final fact in facts)
              Text(
                fact,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (meta.imdbRating != null)
              DecoratedBox(
                key: const Key('detail-imdb'),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C518),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'IMDb',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        meta.imdbRating!,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final genre in meta.genres.take(5))
              Chip(
                label: Text(genre),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        if (meta.description != null)
          Text(
            meta.description!,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
          )
        else if (loading) ...const [
          Skeleton(height: 14),
          SizedBox(height: Spacing.sm),
          Skeleton(height: 14),
          SizedBox(height: Spacing.sm),
          Skeleton(width: 360, height: 14),
        ],
        if (meta.awards != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.md),
            child: Row(
              key: const Key('detail-awards'),
              children: [
                const Icon(
                  Icons.emoji_events_outlined,
                  size: 18,
                  color: Colors.amber,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    meta.awards!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Spacing.lg),
        if (!loading) _Actions(meta: meta),
      ],
    );
  }
}

/// El logo del contenido si lo hay y carga; si no, su nombre.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.meta});

  final Meta meta;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      meta.name,
      style: Theme.of(context).textTheme.displaySmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
    final logo = meta.logo;
    return Semantics(
      header: true,
      label: meta.name,
      child: logo != null && isHttpUrl(logo)
          ? ExcludeSemantics(
              child: Image.network(
                logo,
                height: 90,
                cacheHeight: (90 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (_, _, _) => title,
              ),
            )
          : title,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: scheme.error),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text('Solo tenemos los datos del catálogo. $message'),
            ),
            if (onRetry != null)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Los botones para empezar a ver.
class _Actions extends ConsumerWidget {
  const _Actions({required this.meta});

  final Meta meta;

  /// Reproduce: con la fuente automática (por defecto) abre el reproductor
  /// directo; si no, la lista de streams.
  void _open(
    BuildContext context,
    WidgetRef ref, {
    core.Video? video,
    ResumeMode resume = ResumeMode.ask,
  }) {
    if (ref.read(appSettingsProvider).autoSelectSource) {
      context.push(
        Routes.play,
        extra: PlayArgs(meta: meta, video: video, resume: resume),
      );
    } else {
      _chooseSource(context, video: video, resume: resume);
    }
  }

  void _chooseSource(
    BuildContext context, {
    core.Video? video,
    ResumeMode resume = ResumeMode.ask,
  }) {
    context.push(
      Routes.streams,
      extra: StreamsArgs(meta: meta, video: video, resume: resume),
    );
  }

  Widget _trailer(BuildContext context, WidgetRef ref) {
    final trailers = meta.trailerStreams;
    if (trailers.isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const Key('detail-trailer'),
      onPressed: () => unawaited(
        ref.read(urlOpenerProvider)(
          Uri.https('www.youtube.com', '/watch', {'v': trailers.first.ytId}),
        ),
      ),
      icon: const Icon(Icons.smart_display_outlined),
      label: const Text('Tráiler'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(progressRevisionProvider);
    final repository = ref.watch(progressRepositoryProvider);

    if (hasEpisodes(meta)) {
      final last = lastWatched(
        meta,
        (videoId) => repository.get(meta.type, meta.id, videoId),
      );
      if (last == null || !last.isInProgress) return _trailer(context, ref);
      final video = meta.videos.firstWhere((v) => v.id == last.videoId);
      final tag = episodeTagOf(video);
      return Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.sm,
        children: [
          FilledButton.icon(
            key: const Key('detail-continue'),
            onPressed: () =>
                _open(context, ref, video: video, resume: ResumeMode.resume),
            icon: const Icon(Icons.play_arrow),
            label: Text(
              'Continuar${tag == null ? '' : ' $tag'} desde '
              '${formatPlaybackTime(last.position)}',
            ),
          ),
          OutlinedButton(
            key: const Key('detail-choose-source'),
            onPressed: () =>
                _chooseSource(context, video: video, resume: ResumeMode.resume),
            child: const Text('Elegir fuente'),
          ),
          _trailer(context, ref),
        ],
      );
    }

    final saved = repository.get(meta.type, meta.id, meta.id);
    final resumable = saved != null && saved.isInProgress ? saved : null;
    final watch = resumable == null
        ? FilledButton.icon(
            key: const Key('detail-watch'),
            onPressed: () => _open(context, ref),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Ver'),
          )
        : OutlinedButton.icon(
            key: const Key('detail-watch'),
            onPressed: () => _open(context, ref),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Ver'),
          );
    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      children: [
        if (resumable != null)
          FilledButton.icon(
            key: const Key('detail-continue'),
            onPressed: () => _open(context, ref, resume: ResumeMode.resume),
            icon: const Icon(Icons.play_arrow),
            label: Text(
              'Continuar desde ${formatPlaybackTime(resumable.position)}',
            ),
          ),
        watch,
        OutlinedButton(
          key: const Key('detail-choose-source'),
          onPressed: () => _chooseSource(context),
          child: const Text('Elegir fuente'),
        ),
        _trailer(context, ref),
      ],
    );
  }
}

/// Selector de temporada y lista de episodios.
///
/// Es un sliver: los episodios se arman a medida que se ven, porque una serie
/// puede tener cientos.
class _Episodes extends ConsumerStatefulWidget {
  const _Episodes({required this.meta, required this.horizontalPadding});

  final Meta meta;
  final double horizontalPadding;

  @override
  ConsumerState<_Episodes> createState() => _EpisodesState();
}

class _EpisodesState extends ConsumerState<_Episodes> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final theme = Theme.of(context);
    ref.watch(progressRevisionProvider);
    final repository = ref.watch(progressRepositoryProvider);
    PlaybackProgress? progressOf(String videoId) =>
        repository.get(meta.type, meta.id, videoId);

    final seasons = seasonsOf(meta);
    final selected =
        _season ??
        defaultSeason(meta, lastWatched(meta, progressOf)) ??
        seasons.first;
    final episodes = episodesOf(meta, selected);

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Episodios',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (seasons.length > 1)
              DropdownButton<int>(
                key: const Key('season-selector'),
                value: selected,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                items: [
                  for (final s in seasons)
                    DropdownMenuItem(value: s, child: Text(seasonName(s))),
                ],
                onChanged: (s) => setState(() => _season = s),
              )
            else
              Text(
                seasonName(selected),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
      ],
    );

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverList.builder(
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final video = episodes[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: _EpisodeTile(
                  video: video,
                  progress: progressOf(video.id),
                  // Con la fuente automática, cada episodio ofrece elegir la
                  // fuente a mano.
                  onChooseSource:
                      ref.watch(appSettingsProvider).autoSelectSource
                      ? () => context.push(
                          Routes.streams,
                          extra: StreamsArgs(meta: meta, video: video),
                        )
                      : null,
                  onTap: () {
                    if (ref.read(appSettingsProvider).autoSelectSource) {
                      context.push(
                        Routes.play,
                        extra: PlayArgs(meta: meta, video: video),
                      );
                    } else {
                      context.push(
                        Routes.streams,
                        extra: StreamsArgs(meta: meta, video: video),
                      );
                    }
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.video,
    required this.progress,
    required this.onTap,
    this.onChooseSource,
  });

  final core.Video video;
  final PlaybackProgress? progress;
  final VoidCallback onTap;

  /// Lleva a la lista de streams de este episodio; con `null` no hay botón.
  final VoidCallback? onChooseSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final released = video.released;
    final upcoming = released != null && released.isAfter(DateTime.now());
    final fraction = progress?.fraction ?? 0;
    final finished =
        progress != null && !progress!.isInProgress && fraction > 0.5;
    final title = video.title.trim();
    final number = video.episode == null ? '' : '${video.episode}. ';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 168,
                height: 94,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RemoteImage(video.thumbnail, width: 168),
                      if (progress != null && progress!.isInProgress)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            key: const Key('episode-progress'),
                            value: fraction.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$number${title.isEmpty ? 'Episodio ${video.episode ?? ''}'.trim() : title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (finished)
                          Tooltip(
                            message: 'Visto',
                            child: Icon(
                              Icons.check_circle,
                              size: 18,
                              color: scheme.primary,
                            ),
                          ),
                      ],
                    ),
                    if (released != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          upcoming
                              ? 'Próximamente · ${formatDate(released)}'
                              : formatDate(released),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (video.overview != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.xs),
                        child: Text(
                          video.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              if (onChooseSource != null)
                IconButton(
                  key: Key('episode-choose-source-${video.id}'),
                  tooltip: 'Elegir fuente',
                  icon: const Icon(Icons.playlist_play),
                  onPressed: onChooseSource,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodesSkeleton extends StatelessWidget {
  const _EpisodesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Skeleton(width: 140, height: 24),
        SizedBox(height: Spacing.md),
        Skeleton(height: 94, radius: 12),
        SizedBox(height: Spacing.sm),
        Skeleton(height: 94, radius: 12),
      ],
    );
  }
}
