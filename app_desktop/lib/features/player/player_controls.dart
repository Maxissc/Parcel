import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import '../../shared/stream_labels.dart';
import 'player_info.dart';
import 'source_menu.dart';
import 'subtitle_catalog.dart';
import 'track_labels.dart';

/// Lo que el menú de subtítulos necesita del catálogo.
class SubtitleMenuData {
  const SubtitleMenuData({
    required this.entries,
    required this.alignmentOf,
    required this.isSelected,
    this.isLoading = _never,
  });

  /// Arma las opciones ordenadas (embebidas y de addons). Se llama al abrir el
  /// menú, no en cada cuadro.
  final List<SubtitleEntry> Function() entries;
  final SubtitleAlignment? Function(SubtitleEntry entry) alignmentOf;

  /// Si [entry] es la pista que suena ahora.
  final bool Function(SubtitleEntry entry) isSelected;

  /// Si [entry] se está bajando todavía.
  final bool Function(SubtitleEntry entry) isLoading;
}

bool _never(SubtitleEntry entry) => false;

/// Barras de controles que se dibujan encima del video. No guarda estado del
/// reproductor: todo entra por parámetros y sale por callbacks.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.state,
    required this.stats,
    required this.title,
    required this.dragValue,
    required this.onBack,
    required this.onPlayOrPause,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onVolumeChanged,
    required this.onToggleMute,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onMenuOpened,
    required this.onMenuClosed,
    this.subtitles,
    this.onSelectSubtitleEntry,
    this.onOpenSync,
    this.sourceMenu,
    this.atmos = false,
    this.onToggleInfo,
    this.isFullScreen = false,
    this.onToggleFullScreen,
  });

  final PlaybackState state;
  final PlaybackStats stats;
  final String? title;

  /// Datos del menú de subtítulos; con `null` el menú lista las pistas del
  /// motor, sin más.
  final SubtitleMenuData? subtitles;
  final ValueChanged<SubtitleEntry>? onSelectSubtitleEntry;

  /// Abre el asistente de sincronización; con `null` no se ofrece.
  final VoidCallback? onOpenSync;

  /// Menú «Fuente»; con `null` no se muestra.
  final SourceMenu? sourceMenu;
  final bool atmos;

  /// Muestra u oculta el panel de datos; con `null` no hay botón.
  final VoidCallback? onToggleInfo;

  /// Si la ventana está en pantalla completa (cambia el ícono del botón).
  final bool isFullScreen;

  /// Alterna la pantalla completa; con `null` no se muestra el botón.
  final VoidCallback? onToggleFullScreen;

  /// Posición (ms) mientras el usuario arrastra la barra; `null` si no arrastra.
  final double? dragValue;
  final VoidCallback onBack;
  final VoidCallback onPlayOrPause;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final ValueChanged<AudioTrack> onSelectAudio;

  /// `null` desactiva los subtítulos.
  final ValueChanged<SubtitleTrack?> onSelectSubtitle;
  final VoidCallback onMenuOpened;
  final VoidCallback onMenuClosed;

  @override
  Widget build(BuildContext context) {
    // Los controles no toman el foco: el teclado lo maneja la pantalla, así
    // espacio y flechas no activan por error un botón o mueven un slider.
    return ExcludeFocus(
      child: Column(
        children: [
          _TopBar(title: title, onBack: onBack),
          const Spacer(),
          _BottomBar(parent: this),
        ],
      ),
    );
  }
}

const _scrimTop = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xCC000000), Color(0x00000000)],
  ),
);

const _scrimBottom = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xCC000000), Color(0x00000000)],
  ),
);

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String? title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _scrimTop,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 24),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Volver',
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              if (title != null)
                Expanded(
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.parent});

  final PlayerControls parent;

  @override
  Widget build(BuildContext context) {
    final state = parent.state;
    final dragValue = parent.dragValue;
    final durationMs = state.duration.inMilliseconds.toDouble();
    final positionMs = (dragValue ?? state.position.inMilliseconds.toDouble())
        .clamp(0.0, durationMs > 0 ? durationMs : 1.0);
    final canSeek = durationMs > 0;
    final bufferedMs = canSeek
        ? (positionMs + parent.stats.bufferAhead.inMilliseconds).clamp(
            0.0,
            durationMs,
          )
        : 0.0;
    final playIcon = state.completed
        ? Icons.replay
        : (state.playing ? Icons.pause : Icons.play_arrow);
    final playTooltip = state.completed
        ? 'Volver a ver'
        : (state.playing ? 'Pausar' : 'Reproducir');
    final volumeIcon = state.volume <= 0
        ? Icons.volume_off
        : (state.volume < 0.5 ? Icons.volume_down : Icons.volume_up);
    final chips = statsChips(parent.stats, atmos: parent.atmos);

    return DecoratedBox(
      decoration: _scrimBottom,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      formatPlaybackTime(
                        Duration(milliseconds: positionMs.round()),
                      ),
                      key: const Key('player-position'),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    child: _SeekBar(
                      positionMs: positionMs,
                      durationMs: durationMs,
                      bufferedMs: bufferedMs,
                      onChanged: canSeek ? parent.onSeekChanged : null,
                      onChangeEnd: canSeek ? parent.onSeekEnd : null,
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      formatPlaybackTime(state.duration),
                      key: const Key('player-duration'),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    key: const Key('player-play'),
                    tooltip: playTooltip,
                    iconSize: 32,
                    icon: Icon(playIcon),
                    onPressed: parent.onPlayOrPause,
                  ),
                  IconButton(
                    tooltip: state.volume <= 0 ? 'Activar sonido' : 'Silenciar',
                    icon: Icon(volumeIcon),
                    onPressed: parent.onToggleMute,
                  ),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      key: const Key('player-volume'),
                      value: state.volume.clamp(0.0, 1.0),
                      onChanged: parent.onVolumeChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (chips.isNotEmpty)
                    Flexible(
                      child: Text(
                        chips.join(' · '),
                        key: const Key('player-stats-chips'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  const Spacer(),
                  if (parent.sourceMenu != null)
                    _SourceMenuButton(
                      menu: parent.sourceMenu!,
                      position: state.position,
                      onOpened: parent.onMenuOpened,
                      onClosed: parent.onMenuClosed,
                    ),
                  _AudioMenu(
                    state: state,
                    onSelected: parent.onSelectAudio,
                    onOpened: parent.onMenuOpened,
                    onClosed: parent.onMenuClosed,
                  ),
                  _SubtitleMenu(
                    state: state,
                    data: parent.subtitles,
                    onSelected: parent.onSelectSubtitle,
                    onSelectedEntry: parent.onSelectSubtitleEntry,
                    onOpenSync: parent.onOpenSync,
                    onOpened: parent.onMenuOpened,
                    onClosed: parent.onMenuClosed,
                  ),
                  if (parent.onToggleInfo != null)
                    IconButton(
                      key: const Key('player-info-button'),
                      tooltip: 'Información (I)',
                      icon: const Icon(Icons.info_outline),
                      onPressed: parent.onToggleInfo,
                    ),
                  if (parent.onToggleFullScreen != null)
                    IconButton(
                      key: const Key('player-fullscreen'),
                      tooltip: parent.isFullScreen
                          ? 'Salir de pantalla completa (F)'
                          : 'Pantalla completa (F)',
                      icon: Icon(
                        parent.isFullScreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                      ),
                      onPressed: parent.onToggleFullScreen,
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

/// Barra de progreso con el tramo ya cargado hacia adelante por detrás.
class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.positionMs,
    required this.durationMs,
    required this.bufferedMs,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double positionMs;
  final double durationMs;
  final double bufferedMs;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = durationMs > 0 ? bufferedMs / durationMs : 0.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        // El carril del Slider empieza 12 px adentro (radio del pulgar).
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: const Key('player-buffer'),
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.18),
          ),
          child: Slider(
            key: const Key('player-seek'),
            value: positionMs,
            max: durationMs > 0 ? durationMs : 1.0,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _SourceMenuButton extends StatelessWidget {
  const _SourceMenuButton({
    required this.menu,
    required this.position,
    required this.onOpened,
    required this.onClosed,
  });

  final SourceMenu menu;
  final Duration position;
  final VoidCallback onOpened;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      key: const Key('player-source-menu'),
      tooltip: 'Fuente',
      icon: const Icon(Icons.swap_horiz),
      onOpened: onOpened,
      onCanceled: onClosed,
      onSelected: (i) {
        onClosed();
        if (i != menu.current) menu.onPick(i, position);
      },
      itemBuilder: (_) => [
        for (var i = 0; i < menu.candidates.length; i++)
          CheckedPopupMenuItem<int>(
            value: i,
            checked: i == menu.current,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      menu.candidates[i].label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!menu.candidates[i].isReady) ...[
                    const SizedBox(width: 8),
                    const Tooltip(
                      message: uncachedTooltip,
                      child: Chip(
                        label: Text(uncachedChip),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AudioMenu extends StatelessWidget {
  const _AudioMenu({
    required this.state,
    required this.onSelected,
    required this.onOpened,
    required this.onClosed,
  });

  final PlaybackState state;
  final ValueChanged<AudioTrack> onSelected;
  final VoidCallback onOpened;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    final tracks = state.audioTracks;
    return PopupMenuButton<AudioTrack>(
      key: const Key('player-audio-menu'),
      tooltip: 'Audio',
      icon: const Icon(Icons.audiotrack),
      enabled: tracks.isNotEmpty,
      onOpened: onOpened,
      onCanceled: onClosed,
      onSelected: (t) {
        onSelected(t);
        onClosed();
      },
      itemBuilder: (_) => [
        for (var i = 0; i < tracks.length; i++)
          CheckedPopupMenuItem<AudioTrack>(
            value: tracks[i],
            checked: tracks[i] == state.selectedAudio,
            child: Text(trackLabel(tracks[i], i)),
          ),
      ],
    );
  }
}

class _SubtitleMenu extends StatelessWidget {
  const _SubtitleMenu({
    required this.state,
    required this.data,
    required this.onSelected,
    required this.onSelectedEntry,
    required this.onOpenSync,
    required this.onOpened,
    required this.onClosed,
  });

  final PlaybackState state;
  final SubtitleMenuData? data;
  final ValueChanged<SubtitleTrack?> onSelected;
  final ValueChanged<SubtitleEntry>? onSelectedEntry;
  final VoidCallback? onOpenSync;
  final VoidCallback onOpened;
  final VoidCallback onClosed;

  // Valores de los ítems que no son una pista: un popup no informa un `null`.
  static const _off = 'off';
  static const _sync = 'sync';

  @override
  Widget build(BuildContext context) {
    final data = this.data;
    final theme = Theme.of(context);
    return PopupMenuButton<Object>(
      key: const Key('player-subtitle-menu'),
      tooltip: 'Subtítulos',
      icon: const Icon(Icons.subtitles),
      onOpened: onOpened,
      onCanceled: onClosed,
      onSelected: (value) {
        if (value == _off) {
          onSelected(null);
        } else if (value == _sync) {
          onOpenSync?.call();
        } else if (value is SubtitleEntry) {
          onSelectedEntry?.call(value);
        } else if (value is SubtitleTrack) {
          onSelected(value);
        }
        onClosed();
      },
      itemBuilder: (_) {
        final items = <PopupMenuEntry<Object>>[
          CheckedPopupMenuItem<Object>(
            value: _off,
            checked: state.selectedSubtitle == null,
            child: const Text('Desactivados'),
          ),
        ];
        if (data == null) {
          final tracks = state.subtitleTracks;
          for (var i = 0; i < tracks.length; i++) {
            items.add(
              CheckedPopupMenuItem<Object>(
                value: tracks[i],
                checked: tracks[i] == state.selectedSubtitle,
                child: Text(
                  tracks[i].isExternal
                      ? '${trackLabel(tracks[i], i)} · externo'
                      : trackLabel(tracks[i], i),
                ),
              ),
            );
          }
        } else {
          var moreLanguages = false;
          for (final entry in data.entries()) {
            if (entry.language == SubtitleLanguage.other && !moreLanguages) {
              moreLanguages = true;
              items.add(
                PopupMenuItem<Object>(
                  enabled: false,
                  height: 32,
                  child: Text('Más idiomas', style: theme.textTheme.labelLarge),
                ),
              );
            }
            final tag = alignmentLabel(data.alignmentOf(entry));
            items.add(
              CheckedPopupMenuItem<Object>(
                value: entry,
                checked: data.isSelected(entry),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.external
                            ? entry.label
                            : '${entry.label} · del video',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (data.isLoading(entry))
                        Row(
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
              ),
            );
          }
        }
        if (onOpenSync != null) {
          items
            ..add(const PopupMenuDivider())
            ..add(
              const PopupMenuItem<Object>(
                value: _sync,
                child: Text('Sincronizar subtítulos… (S)'),
              ),
            );
        }
        return items;
      },
    );
  }
}
