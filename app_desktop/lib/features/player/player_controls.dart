import 'package:flutter/material.dart';
import 'package:parcel_core/parcel_core.dart';

import 'track_labels.dart';

/// Barras de controles que se dibujan encima del video. No guarda estado del
/// reproductor: todo entra por parámetros y sale por callbacks.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.state,
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
    this.isFullScreen = false,
    this.onToggleFullScreen,
  });

  final PlaybackState state;
  final String? title;

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
          _BottomBar(
            state: state,
            dragValue: dragValue,
            onPlayOrPause: onPlayOrPause,
            onSeekChanged: onSeekChanged,
            onSeekEnd: onSeekEnd,
            onVolumeChanged: onVolumeChanged,
            onToggleMute: onToggleMute,
            onSelectAudio: onSelectAudio,
            onSelectSubtitle: onSelectSubtitle,
            onMenuOpened: onMenuOpened,
            onMenuClosed: onMenuClosed,
            isFullScreen: isFullScreen,
            onToggleFullScreen: onToggleFullScreen,
          ),
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
  const _BottomBar({
    required this.state,
    required this.dragValue,
    required this.onPlayOrPause,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onVolumeChanged,
    required this.onToggleMute,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onMenuOpened,
    required this.onMenuClosed,
    required this.isFullScreen,
    required this.onToggleFullScreen,
  });

  final PlaybackState state;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final double? dragValue;
  final VoidCallback onPlayOrPause;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final ValueChanged<AudioTrack> onSelectAudio;
  final ValueChanged<SubtitleTrack?> onSelectSubtitle;
  final VoidCallback onMenuOpened;
  final VoidCallback onMenuClosed;

  @override
  Widget build(BuildContext context) {
    final durationMs = state.duration.inMilliseconds.toDouble();
    final positionMs = (dragValue ?? state.position.inMilliseconds.toDouble())
        .clamp(0.0, durationMs > 0 ? durationMs : 1.0);
    final canSeek = durationMs > 0;
    final playIcon = state.completed
        ? Icons.replay
        : (state.playing ? Icons.pause : Icons.play_arrow);
    final playTooltip = state.completed
        ? 'Volver a ver'
        : (state.playing ? 'Pausar' : 'Reproducir');
    final volumeIcon = state.volume <= 0
        ? Icons.volume_off
        : (state.volume < 0.5 ? Icons.volume_down : Icons.volume_up);

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
                    child: Slider(
                      key: const Key('player-seek'),
                      value: positionMs,
                      max: canSeek ? durationMs : 1.0,
                      onChanged: canSeek ? onSeekChanged : null,
                      onChangeEnd: canSeek ? onSeekEnd : null,
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
                    onPressed: onPlayOrPause,
                  ),
                  IconButton(
                    tooltip: state.volume <= 0 ? 'Activar sonido' : 'Silenciar',
                    icon: Icon(volumeIcon),
                    onPressed: onToggleMute,
                  ),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      key: const Key('player-volume'),
                      value: state.volume.clamp(0.0, 1.0),
                      onChanged: onVolumeChanged,
                    ),
                  ),
                  const Spacer(),
                  _AudioMenu(
                    state: state,
                    onSelected: onSelectAudio,
                    onOpened: onMenuOpened,
                    onClosed: onMenuClosed,
                  ),
                  _SubtitleMenu(
                    state: state,
                    onSelected: onSelectSubtitle,
                    onOpened: onMenuOpened,
                    onClosed: onMenuClosed,
                  ),
                  if (onToggleFullScreen != null)
                    IconButton(
                      key: const Key('player-fullscreen'),
                      tooltip: isFullScreen
                          ? 'Salir de pantalla completa (F)'
                          : 'Pantalla completa (F)',
                      icon: Icon(
                        isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      ),
                      onPressed: onToggleFullScreen,
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
    required this.onSelected,
    required this.onOpened,
    required this.onClosed,
  });

  final PlaybackState state;
  final ValueChanged<SubtitleTrack?> onSelected;
  final VoidCallback onOpened;
  final VoidCallback onClosed;

  // Valor del ítem «Desactivados»: un popup no informa una selección `null`.
  static const _off = SubtitleTrack(id: '__off__');

  @override
  Widget build(BuildContext context) {
    final tracks = state.subtitleTracks;
    return PopupMenuButton<SubtitleTrack>(
      key: const Key('player-subtitle-menu'),
      tooltip: 'Subtítulos',
      icon: const Icon(Icons.subtitles),
      onOpened: onOpened,
      onCanceled: onClosed,
      onSelected: (t) {
        onSelected(t == _off ? null : t);
        onClosed();
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem<SubtitleTrack>(
          value: _off,
          checked: state.selectedSubtitle == null,
          child: const Text('Desactivados'),
        ),
        for (var i = 0; i < tracks.length; i++)
          CheckedPopupMenuItem<SubtitleTrack>(
            value: tracks[i],
            checked: tracks[i] == state.selectedSubtitle,
            child: Text(
              tracks[i].isExternal
                  ? '${trackLabel(tracks[i], i)} · externo'
                  : trackLabel(tracks[i], i),
            ),
          ),
      ],
    );
  }
}
