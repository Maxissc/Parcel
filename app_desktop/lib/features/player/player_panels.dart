import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../shared/stream_labels.dart';
import 'side_panel.dart';
import 'source_candidates.dart';
import 'source_menu.dart';
import 'subtitle_catalog.dart';
import 'track_labels.dart';

/// Cuál de los paneles laterales del reproductor está abierto.
enum PlayerPanel { source, audio, subtitles }

/// Lo que el panel de subtítulos necesita del catálogo.
class SubtitleMenuData {
  const SubtitleMenuData({
    required this.entries,
    required this.alignmentOf,
    required this.isSelected,
    this.isLoading = _never,
  });

  /// Arma las opciones ordenadas (embebidas y de addons). Se llama al abrir el
  /// panel y cuando cambia el catálogo, no en cada cuadro.
  final List<SubtitleEntry> Function() entries;
  final SubtitleAlignment? Function(SubtitleEntry entry) alignmentOf;

  /// Si [entry] es la pista que suena ahora.
  final bool Function(SubtitleEntry entry) isSelected;

  /// Si [entry] se está bajando todavía.
  final bool Function(SubtitleEntry entry) isLoading;
}

bool _never(SubtitleEntry entry) => false;

/// Deja cortar [text] entre las partes de un nombre de archivo
/// («Pelicula.2026.2160p-GRUPO»): sin esto, un nombre sin espacios no se parte
/// y queda cortado con puntos suspensivos en la primera línea.
String breakable(String text) =>
    text.replaceAllMapped(RegExp(r'[._\-\[\]()|/]'), (m) => '${m[0]}​');

/// Lista de fuentes: la actual arriba y marcada, y el resto agrupado por
/// addon.
class SourcePanelBody extends StatelessWidget {
  const SourcePanelBody({
    super.key,
    required this.menu,
    required this.position,
    required this.onPick,
  });

  final SourceMenu menu;
  final Duration position;

  /// El usuario eligió una fuente; quien llama cierra el panel.
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final candidates = menu.candidates;
    final addons = <String>[];
    for (var i = 0; i < candidates.length; i++) {
      if (i == menu.current) continue;
      if (!addons.contains(candidates[i].addonName)) {
        addons.add(candidates[i].addonName);
      }
    }
    Widget option(int i) => PanelOption(
      checked: i == menu.current,
      onTap: () {
        if (i != menu.current) menu.onPick(i, position);
        onPick();
      },
      child: SourceOptionBody(candidate: candidates[i]),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        if (menu.current >= 0 && menu.current < candidates.length) ...[
          const PanelHeading('Fuente actual'),
          option(menu.current),
        ],
        for (final addon in addons) ...[
          PanelHeading(addon),
          for (var i = 0; i < candidates.length; i++)
            if (i != menu.current && candidates[i].addonName == addon)
              option(i),
        ],
      ],
    );
  }
}

/// El contenido de una fuente: chips con lo que se sabe, el addon en gris y el
/// título completo en hasta tres líneas.
class SourceOptionBody extends StatelessWidget {
  const SourceOptionBody({super.key, required this.candidate});

  final SourceCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = candidate.signals;
    final chips = <Widget>[
      if (s.resolution != null) _Chip(resolutionLabel(s.resolution!)),
      if (s.dolbyVision) const _Chip('DV'),
      if (s.hdr) const _Chip('HDR'),
      if (s.cached == true) const _Chip('⚡ Cacheado', accent: true),
      if (s.cached == false)
        const Tooltip(
          message: uncachedTooltip,
          child: _Chip(uncachedChip, warning: true),
        ),
      if (s.sizeBytes != null && s.sizeBytes! > 0)
        _Chip(formatSize(s.sizeBytes!)),
      if (s.seeders != null) _Chip('👤 ${s.seeders}'),
    ];
    final title = candidate.displayTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: chips),
        if (chips.isNotEmpty) const SizedBox(height: 6),
        Text(
          candidate.addonName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              breakable(title),
              key: const Key('source-title'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.accent = false, this.warning = false});

  final String text;
  final bool accent;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = warning
        ? scheme.tertiary
        : (accent ? scheme.primary : scheme.onSurface);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Pistas de audio del video.
class AudioPanelBody extends StatelessWidget {
  const AudioPanelBody({
    super.key,
    required this.state,
    required this.onSelected,
  });

  final PlaybackState state;
  final ValueChanged<AudioTrack> onSelected;

  @override
  Widget build(BuildContext context) {
    final tracks = state.audioTracks;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (var i = 0; i < tracks.length; i++)
          PanelOption(
            checked: tracks[i] == state.selectedAudio,
            onTap: () => onSelected(tracks[i]),
            child: Text(trackLabel(tracks[i], i)),
          ),
      ],
    );
  }
}

/// «Desactivados», las pistas del video y los subtítulos de los addons, por
/// idioma.
class SubtitlePanelBody extends StatelessWidget {
  const SubtitlePanelBody({
    super.key,
    required this.state,
    required this.data,
    required this.entries,
    required this.onSelected,
    required this.onSelectedEntry,
    required this.onOpenSync,
  });

  final PlaybackState state;
  final SubtitleMenuData? data;

  /// Las opciones ya armadas y ordenadas (con [data]); se calculan al abrir y
  /// cuando cambia el catálogo, no en cada cuadro.
  final List<SubtitleEntry> entries;

  /// `null` apaga los subtítulos.
  final ValueChanged<SubtitleTrack?> onSelected;
  final ValueChanged<SubtitleEntry>? onSelectedEntry;
  final VoidCallback? onOpenSync;

  static String _groupOf(SubtitleLanguage language) => switch (language) {
    SubtitleLanguage.latam || SubtitleLanguage.spanish => 'Español',
    SubtitleLanguage.english => 'Inglés',
    SubtitleLanguage.other => 'Más idiomas',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = this.data;
    final items = <Widget>[
      PanelOption(
        checked: state.selectedSubtitle == null,
        onTap: () => onSelected(null),
        child: const Text('Desactivados'),
      ),
    ];
    if (data == null) {
      final tracks = state.subtitleTracks;
      for (var i = 0; i < tracks.length; i++) {
        items.add(
          PanelOption(
            checked: tracks[i] == state.selectedSubtitle,
            onTap: () => onSelected(tracks[i]),
            child: Text(
              tracks[i].isExternal
                  ? '${trackLabel(tracks[i], i)} · externo'
                  : trackLabel(tracks[i], i),
            ),
          ),
        );
      }
    } else {
      String? group;
      for (final entry in entries) {
        final next = _groupOf(entry.language);
        if (next != group) {
          group = next;
          items.add(PanelHeading(next));
        }
        final tag = alignmentLabel(data.alignmentOf(entry));
        items.add(
          PanelOption(
            checked: data.isSelected(entry),
            onTap: () => onSelectedEntry?.call(entry),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.external ? entry.label : '${entry.label} · del video',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (data.isLoading(entry))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Descargando…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (tag != null)
                  Text(
                    tag,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }
    if (onOpenSync != null) {
      items
        ..add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: Color(0x1FFFFFFF)),
          ),
        )
        ..add(
          PanelOption(
            checked: false,
            onTap: onOpenSync!,
            child: const Text('Sincronizar subtítulos… (S)'),
          ),
        );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: items,
    );
  }
}
