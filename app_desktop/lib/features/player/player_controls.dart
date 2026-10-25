import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import 'player_info.dart';
import 'player_panels.dart';
import 'source_menu.dart';

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
    required this.onOpenPanel,
    this.openPanel,
    this.sourceMenu,
    this.atmos = false,
    this.onToggleInfo,
    this.isFullScreen = false,
    this.onToggleFullScreen,
  });

  final PlaybackState state;
  final PlaybackStats stats;
  final String? title;

  /// Abre el panel lateral de Fuente, Audio o Subtítulos (o lo cierra si ya
  /// es el que está abierto).
  final ValueChanged<PlayerPanel> onOpenPanel;

  /// El panel lateral que está abierto, si hay uno (marca su botón).
  final PlayerPanel? openPanel;

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
                  // Todo el espacio que sobra es de este tramo: los chips
                  // quedan a la izquierda y las opciones contra el borde.
                  Expanded(
                    child: chips.isEmpty
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              chips.join(' · '),
                              key: const Key('player-stats-chips'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                  ),
                  if (parent.sourceMenu != null)
                    _PanelButton(
                      key: const Key('player-source-menu'),
                      tooltip: 'Fuente',
                      icon: Icons.swap_horiz,
                      active: parent.openPanel == PlayerPanel.source,
                      onPressed: () => parent.onOpenPanel(PlayerPanel.source),
                    ),
                  _PanelButton(
                    key: const Key('player-audio-menu'),
                    tooltip: 'Audio',
                    icon: Icons.audiotrack,
                    active: parent.openPanel == PlayerPanel.audio,
                    onPressed: state.audioTracks.isEmpty
                        ? null
                        : () => parent.onOpenPanel(PlayerPanel.audio),
                  ),
                  _PanelButton(
                    key: const Key('player-subtitle-menu'),
                    tooltip: 'Subtítulos',
                    icon: Icons.subtitles,
                    active: parent.openPanel == PlayerPanel.subtitles,
                    onPressed: () => parent.onOpenPanel(PlayerPanel.subtitles),
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

/// Botón que abre un panel lateral; marcado si ese panel es el que está
/// abierto.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      isSelected: active,
      selectedIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
      onPressed: onPressed,
    );
  }
}
