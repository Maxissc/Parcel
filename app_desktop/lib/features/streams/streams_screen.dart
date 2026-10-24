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
import '../player/play_item.dart';
import '../player/player_route.dart';
import 'stream_info.dart';
import 'streams_args.dart';

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
          for (final group in state.groups)
            _GroupSection(args: args, group: group),
        ],
      ),
    );
  }
}

class _GroupSection extends ConsumerWidget {
  const _GroupSection({required this.args, required this.group});

  final StreamsArgs args;
  final StreamGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = group.result;

    final streams = switch (result) {
      AddonSuccess(:final value) => _ordered(value),
      _ => const <AddonStream>[],
    };
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
                  recommended: _isRecommended(stream),
                ),
              ),
        ],
      ),
    );
  }

  bool _isRecommended(AddonStream stream) {
    final binge = args.preferBingeGroup;
    return binge != null &&
        args.preferAddonUrl == group.addon.transportUrl &&
        stream.behaviorHints.bingeGroup == binge &&
        stream.isPlayable;
  }

  /// Los que coinciden con el stream anterior (mismo addon y `bingeGroup`)
  /// primero; el resto, en el orden del addon.
  List<AddonStream> _ordered(List<AddonStream> streams) {
    final first = [
      for (final s in streams)
        if (_isRecommended(s)) s,
    ];
    if (first.isEmpty) return streams;
    return [
      ...first,
      for (final s in streams)
        if (!first.contains(s)) s,
    ];
  }
}

class _StreamTile extends ConsumerWidget {
  const _StreamTile({
    required this.args,
    required this.group,
    required this.stream,
    required this.recommended,
  });

  final StreamsArgs args;
  final StreamGroup group;
  final AddonStream stream;
  final bool recommended;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final block = blockOf(stream);
    if (block == null) {
      unawaited(
        context.push(
          Routes.player,
          extra: PlayerArgs(
            url: stream.url!,
            headers: stream.behaviorHints.proxyRequestHeaders,
            resume: args.resume,
            item: PlayItem(
              meta: args.meta,
              video: args.video,
              stream: stream,
              addonUrl: group.addon.transportUrl,
            ),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final block = blockOf(stream);
    final chips = detectStreamChips(stream);
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
        autofocus: recommended,
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
                      if (chips.isNotEmpty || recommended) ...[
                        if (body != null) const SizedBox(height: Spacing.sm),
                        Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.xs,
                          children: [
                            if (recommended)
                              const _Chip(
                                label: 'Igual que el anterior',
                                icon: Icons.star_outline,
                                highlighted: true,
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
