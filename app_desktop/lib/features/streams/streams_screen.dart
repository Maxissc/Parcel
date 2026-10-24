import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/browse_providers.dart';
import '../../data/platform.dart';
import '../../shared/addon_logo.dart';
import '../../shared/media_labels.dart';
import '../../shared/skeleton.dart';
import '../../shared/state_views.dart';
import '../../shared/urls.dart';
import '../../data/providers.dart';
import '../../shared/stream_labels.dart';
import '../player/play_args.dart';
import '../player/play_item.dart';
import '../player/source_candidates.dart';
import 'stream_info.dart';
import 'streams_args.dart';
import 'streams_order.dart';

/// Los streams de un video, agrupados por addon (en el orden de los addons).
/// Cada grupo muestra su propio estado: buscando, con error o vacío.
class StreamsScreen extends ConsumerWidget {
  const StreamsScreen({super.key, required this.args});

  final StreamsArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(streamsProvider(args.key));
    final theme = Theme.of(context);
    final episode = args.video;
    final subtitle = episode == null
        ? null
        : [
            ?episodeTagOf(episode),
            if (episode.title.trim().isNotEmpty) episode.title.trim(),
          ].join(' · ');

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            context.canPop() ? context.pop() : null,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(onPressed: () => context.pop()),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  args.meta.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Buscar de nuevo',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(streamsProvider(args.key)),
              ),
              const SizedBox(width: Spacing.sm),
            ],
          ),
          body: switch (async) {
            AsyncError() => ErrorState(
              message: 'No pudimos buscar los streams.',
              onRetry: () => ref.invalidate(streamsProvider(args.key)),
            ),
            AsyncData(:final value) when value.groups.isEmpty =>
              _NoStreamAddons(),
            AsyncData(:final value) => _Groups(args: args, state: value),
            _ => const _GroupsLoading(),
          },
        ),
      ),
    );
  }
}

class _NoStreamAddons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.movie_filter_outlined,
      title: 'Ningún addon instalado ofrece streams para esto',
      message:
          'Para ver algo necesitás un addon que traiga streams. Podés '
          'importar los de tu cuenta de Stremio o Nuvio, o agregar uno por '
          'su URL.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go(Routes.addons),
          icon: const Icon(Icons.extension_outlined),
          label: const Text('Ir a Addons'),
        ),
      ],
    );
  }
}

class _GroupsLoading extends StatelessWidget {
  const _GroupsLoading();

  @override
  Widget build(BuildContext context) =>
      const _Centered(child: _TileSkeleton(count: 3));
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth),
        child: Padding(padding: const EdgeInsets.all(Spacing.lg), child: child),
      ),
    );
  }
}

class _Groups extends ConsumerWidget {
  const _Groups({required this.args, required this.state});

  final StreamsArgs args;
  final StreamsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final waiting = state.groups.where((g) => g.loading).length;
    final groups = orderGroups(state.groups, args.preferAddonUrl);
    // El orden del ranking (el mismo que usa la elección automática).
    final ranked = rankCandidates(
      state.groups,
      quality: ref.watch(appSettingsProvider.select((s) => s.quality)),
    );
    return _Centered(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Text(
              waiting > 0
                  ? 'Buscando en ${state.groups.length} '
                        '${state.groups.length == 1 ? 'addon' : 'addons'}… '
                        '(faltan $waiting)'
                  : 'Elegí de dónde verlo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final group in groups)
            _GroupSection(args: args, group: group, ranked: ranked),
        ],
      ),
    );
  }
}

class _GroupSection extends ConsumerWidget {
  const _GroupSection({
    required this.args,
    required this.group,
    required this.ranked,
  });

  final StreamsArgs args;
  final StreamGroup group;

  /// Todos los streams reproducibles, del mejor al peor.
  final List<SourceCandidate> ranked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = group.result;

    // Con el episodio anterior visto en un addon, ese addon sugiere uno.
    final samePrevious = args.preferAddonUrl == group.addon.transportUrl;
    final binge = args.preferBingeGroup;
    final streams = switch (result) {
      AddonSuccess(:final value) when samePrevious => orderStreams(
        _byRank(value, ranked),
        binge,
      ),
      AddonSuccess(:final value) => _byRank(value, ranked),
      _ => const <AddonStream>[],
    };
    final recommended = samePrevious && result is AddonSuccess
        ? recommendedStream(streams, binge)
        : null;
    final status = switch (result) {
      null => 'Buscando…',
      AddonFailure(:final error) => 'No se pudo cargar · ${failureText(error)}',
      AddonSuccess(:final value) when value.isEmpty => 'Sin streams',
      AddonSuccess(:final value) =>
        '${value.length} ${value.length == 1 ? 'stream' : 'streams'}',
    };
    final statusColor = result is AddonFailure
        ? scheme.error
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AddonLogo(group.addon.manifest.logo, size: 28),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(
                    group.addon.manifest.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              if (result == null)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (result == null) const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (result == null)
            const _TileSkeleton(count: 2)
          else
            for (final stream in streams)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: _StreamTile(
                  args: args,
                  group: group,
                  stream: stream,
                  ranked: ranked,
                  recommended: identical(stream, recommended),
                  // «Igual que el anterior» solo si coincide el bingeGroup.
                  sameBingeGroup:
                      binge != null && stream.behaviorHints.bingeGroup == binge,
                ),
              ),
        ],
      ),
    );
  }
}

/// Los streams de un grupo en el orden del ranking; los que no se pueden
/// reproducir quedan al final, como vinieron.
List<AddonStream> _byRank(
  List<AddonStream> streams,
  List<SourceCandidate> ranked,
) {
  final position = Map<AddonStream, int>.identity();
  for (var i = 0; i < ranked.length; i++) {
    position[ranked[i].stream] = i;
  }
  final playable = [
    for (final s in streams)
      if (position.containsKey(s)) s,
  ]..sort((a, b) => position[a]!.compareTo(position[b]!));
  return [
    ...playable,
    for (final s in streams)
      if (!position.containsKey(s)) s,
  ];
}

class _StreamTile extends ConsumerStatefulWidget {
  const _StreamTile({
    required this.args,
    required this.group,
    required this.stream,
    required this.ranked,
    required this.recommended,
    required this.sameBingeGroup,
  });

  final StreamsArgs args;
  final StreamGroup group;
  final AddonStream stream;
  final List<SourceCandidate> ranked;

  /// Es el que se sugiere: tiene el foco, así Enter lo reproduce.
  final bool recommended;
  final bool sameBingeGroup;

  @override
  ConsumerState<_StreamTile> createState() => _StreamTileState();
}

class _StreamTileState extends ConsumerState<_StreamTile> {
  final FocusNode _focus = FocusNode(debugLabel: 'stream-recomendado');

  StreamsArgs get args => widget.args;
  StreamGroup get group => widget.group;
  AddonStream get stream => widget.stream;
  bool get recommended => widget.recommended;

  @override
  void initState() {
    super.initState();
    if (recommended) _focusSoon();
  }

  @override
  void didUpdateWidget(_StreamTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (recommended && !oldWidget.recommended) _focusSoon();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// El sugerido aparece cuando responde el addon, con la pantalla ya
  /// enfocada: `autofocus` no alcanza, hay que pedir el foco.
  void _focusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final block = blockOf(stream);
    if (block == null) {
      final candidate = widget.ranked.firstWhere(
        (c) => identical(c.stream, stream),
        orElse: () => SourceCandidate(
          stream: stream,
          addonUrl: group.addon.transportUrl,
          addonName: group.addon.manifest.name,
        ),
      );
      unawaited(
        context.push(
          Routes.play,
          extra: PlayArgs(
            meta: args.meta,
            video: args.video,
            resume: args.resume,
            chosen: candidate,
            candidates: widget.ranked,
            fromStreams: true,
          ),
        ),
      );
      return;
    }
    if (block == StreamBlock.external && isHttpUrl(stream.externalUrl)) {
      final opened = await ref.read(urlOpenerProvider)(
        Uri.parse(stream.externalUrl!),
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el enlace.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final block = blockOf(stream);
    final chips = detectStreamChips(stream);
    final signals = StreamSignals.of(stream);
    final isBest =
        widget.ranked.isNotEmpty &&
        identical(widget.ranked.first.stream, stream);
    final body = stream.description ?? stream.title;
    final canOpen =
        block == null ||
        (block == StreamBlock.external && isHttpUrl(stream.externalUrl));
    final tooltip = switch (block) {
      null => null,
      StreamBlock.torrent => 'Los torrents todavía no están soportados',
      StreamBlock.external => 'Se abre fuera de Parcel',
      StreamBlock.unsupported =>
        'Este tipo de fuente todavía no está soportado',
    };

    final tile = Card(
      clipBehavior: Clip.antiAlias,
      color: recommended
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: recommended ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        focusNode: _focus,
        onTap: canOpen ? () => unawaited(_open(context, ref)) : null,
        child: Opacity(
          opacity: block == null ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    stream.name ?? group.addon.manifest.name,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (body != null)
                        Text(
                          body,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      if (chips.isNotEmpty ||
                          recommended ||
                          isBest ||
                          (block == null && signals.cached != null)) ...[
                        if (body != null) const SizedBox(height: Spacing.sm),
                        Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.xs,
                          children: [
                            if (recommended)
                              _Chip(
                                label: widget.sameBingeGroup
                                    ? 'Igual que el anterior'
                                    : 'Del mismo addon',
                                icon: Icons.star_outline,
                                highlighted: true,
                              ),
                            if (isBest)
                              const _Chip(
                                label: 'Mejor fuente',
                                icon: Icons.thumb_up_alt_outlined,
                                highlighted: true,
                              ),
                            if (signals.cached == true)
                              const _Chip(label: '⚡ Cacheado'),
                            if (signals.cached == false)
                              const Tooltip(
                                message: uncachedTooltip,
                                child: _Chip(label: uncachedChip),
                              ),
                            for (final chip in chips) _Chip(label: chip),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Icon(switch (block) {
                  null => Icons.play_circle_outline,
                  StreamBlock.torrent => Icons.block,
                  StreamBlock.external => Icons.open_in_new,
                  StreamBlock.unsupported => Icons.block,
                }, color: block == null ? scheme.primary : null),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip, child: tile);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.highlighted = false});

  final String label;
  final IconData? icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primary.withValues(alpha: 0.2)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: Spacing.sm),
            child: Skeleton(height: 72, radius: 12),
          ),
      ],
    );
  }
}
